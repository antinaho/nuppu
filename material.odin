#+vet unused shadowing using-param style semicolon cast explicit-allocators

package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "gpu"
import "core:slice"

_ :: log
_ :: slice


MATERIAL_PARAM_BYTES :: 32

MATERIAL_HANDLE_RAW :: u16
MATERIAL_BASE_BIT   :: 1 << 9
MATERIAL_INDEX_MASK :: MAX_MATERIALS - 1
#assert(MAX_MATERIALS > 0 && (MAX_MATERIALS & (MAX_MATERIALS-1)) == 0, "MAX_MATERIALS must be a power of two")
#assert(MATERIAL_INDEX_MASK < MATERIAL_BASE_BIT, "material index collides with the base-material bit")

Material_Constant :: struct #align(16) {
    params: [MATERIAL_PARAM_BYTES]u8,
}
#assert(size_of(Material_Constant) == MATERIAL_PARAM_BYTES)

Material_Handle :: distinct Handle(MATERIAL_HANDLE_RAW)
MATERIAL_NIL    :: Material_Handle{}

// Resolves an engine texture handle into a material resource.
material_texture :: proc(handle: Texture_Handle) -> gpu.Parameter_Resource {
    tex, ok := get_texture(handle)
    assert(ok, "material_texture: invalid texture handle")
    return tex^
}

// Render order bucket a material belongs to. Opaque draws are batched purely by
// pipeline; Transparent draws are depth-sorted back-to-front.
Render_Queue :: enum u8 {
    Opaque = 0,
    Transparent,
}

Built_In_Material :: enum u8 {
    Sprite,
}

// CPU-side companion to one 32-byte GPU material record.
Material_Record :: struct {
    shader:   Shader_Handle,
    state:    Draw_State,
    queue:    Render_Queue,
    bindings: [dynamic]gpu.Parameter_Resource,
}

get_built_in_material :: proc(mat: Built_In_Material) -> Material_Handle {
    return _state.material_library.built_in[mat]
}

Material_Library :: struct {
    private_material_buffer: gpu.ptr,
    built_in: [Built_In_Material]Material_Handle,

    material_type_set: map[typeid]Material_Handle,
    table: Resource_Table(Material_Record),

    __material_handles: [dynamic]Material_Handle, // debug-only
}

NUPPU_material_lib_init :: proc(lib: ^Material_Library, allocator := context.allocator) -> (err: runtime.Allocator_Error) {
    ok: bool
    lib.private_material_buffer, ok = gpu.malloc(
        u32(MAX_MATERIALS * size_of(Material_Constant)),
        256, .Default, "Material Buffer",
    )
    assert(ok, "material_lib_init: failed to alloc material buffer")

    resource_table_init(&lib.table, MAX_MATERIALS, allocator) or_return
    lib.material_type_set = make(map[typeid]Material_Handle, capacity = MAX_MATERIALS, allocator = allocator) or_return

    when ODIN_DEBUG {
        lib.__material_handles = make([dynamic]Material_Handle, 0, 64, context.allocator)
    }

    return
}

NUPPU_material_lib_deinit :: proc(lib: ^Material_Library) {
    gpu.release_ptr(&lib.private_material_buffer)

    it := bit_mask_array_iterator_init(&lib.table.occupied)
    for index in bit_mask_array_iterator_next(&it) {
        if index == 0 { continue }
        delete(lib.table.items[index].bindings)
    }
    resource_table_destroy(&lib.table)
    delete(lib.material_type_set)

    when ODIN_DEBUG {
        delete(lib.__material_handles)
    }
    lib^ = {}
}

Material_Upload_Scope :: struct {
    staging: gpu.ptr,
    occupied: Bit_Mask_Array,
}

@(require_results)
material_upload_scope :: proc(loc := #caller_location) -> Material_Upload_Scope {
    staging_mat, ok := gpu.malloc(
        size_of(Material_Constant) * MAX_MATERIALS,
        align_of(Material_Constant),
        .Staging,
    )
    assert(ok, "material_upload_scope: failed to alloc material buffer")
    intrinsics.mem_zero(staging_mat.cpu, size_of(Material_Constant) * MAX_MATERIALS)

    lib := &_state.material_library
    scope_occupied := bit_mask_array_init(lib.table.occupied.bit_count, allocator = context.temp_allocator)
    intrinsics.mem_copy_non_overlapping(
        rawptr(scope_occupied.words), rawptr(lib.table.occupied.words),
        lib.table.occupied.word_count * size_of(Bit_Mask64),
    )
    scope_occupied.free_hint = lib.table.occupied.free_hint
    scope_occupied.live      = lib.table.occupied.live

    return {
        staging = staging_mat,
        occupied = scope_occupied,
    }
}

@(require_results)
material_upload :: proc(
    scope: ^Material_Upload_Scope,
    state: Draw_State,
    data: ^$M,
    queue: Render_Queue = .Opaque,
    bindings: []gpu.Parameter_Resource = nil,
    name: string = "",
    loc := #caller_location,
) -> (Material_Handle, bool) #optional_ok {
    assert(size_of(M) <= MATERIAL_PARAM_BYTES, "material_upload: parameter payload exceeds MATERIAL_PARAM_BYTES", loc = loc)

    lib := &_state.material_library
    free_idx, ok := bit_mask_array_flip_first_zero(&scope.occupied)
    assert(ok, "material_upload: Ran out of space, increase max materials")
    
    handle_raw := u16(free_idx)
    mat_slot := &([^]Material_Constant)(scope.staging.cpu)[free_idx]
    intrinsics.mem_copy_non_overlapping(mat_slot, rawptr(data), size_of(M))

    rec := &lib.table.items[free_idx]
    rec.state = state
    rec.queue = queue
    if len(bindings) > 0 {
        clear(&rec.bindings)
        append(&rec.bindings, ..bindings)
    }

    handle := Material_Handle { handle = handle_raw }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
    }

    if M not_in lib.material_type_set {
        handle.handle |= MATERIAL_BASE_BIT
        lib.material_type_set[M] = handle
    }

    when ODIN_DEBUG {
        append(&lib.__material_handles, handle)
    }

    return handle, true
}

material_upload_scope_end :: proc(scope: ^Material_Upload_Scope) {
    lib := &_state.material_library

    gpu.begin_commands()
    ranges := bit_mask_array_diff_ranges(&scope.occupied, &lib.table.occupied, context.temp_allocator) 
    for r in ranges {
        gpu.copy(
            lib.private_material_buffer,
            scope.staging,
            dst_offset      = r.start * size_of(Material_Constant),
            src_offset      = r.start * size_of(Material_Constant),
            length_override = size_of(Material_Constant) * r.length,
        )
    }
    gpu.transfer_submit(&scope.staging)

    // update to the new state
    lib.table.occupied.free_hint = scope.occupied.free_hint
    lib.table.occupied.live      = scope.occupied.live
    intrinsics.mem_copy_non_overlapping(
        rawptr(lib.table.occupied.words), rawptr(scope.occupied.words),
        scope.occupied.word_count * size_of(Bit_Mask64),
    )
}

material_free :: proc(handle: Material_Handle) {
    lib := &_state.material_library
    idx, ok := material_handle_unpack(handle)
    if !ok { return }
    rec, got := resource_table_get(&lib.table, int(idx))
    if !got { return }

    // Drop the base-material registration pointing at this slot, if any.
    base_type: typeid
    is_base: bool
    for t, base in lib.material_type_set {
        if base == handle {
            base_type = t
            is_base = true
            break
        }
    }
    if is_base {
        delete_key(&lib.material_type_set, base_type)
    }

    delete(rec.bindings)
    rec^ = {}
    resource_table_release(&lib.table, int(idx))

    when ODIN_DEBUG {
        i, found := slice.linear_search(lib.__material_handles[:], handle)
        if found {
            unordered_remove(&lib.__material_handles, i)
        }
    }
}

material_handle_unpack :: proc "contextless" (handle: Material_Handle) -> (idx: MATERIAL_HANDLE_RAW, ok: bool) #optional_ok { 
    idx = handle.handle & MATERIAL_INDEX_MASK
    if idx == 0 || idx >= MAX_MATERIALS { return 0, false }
    return idx, true
}

is_base_material :: proc "contextless" (handle: Material_Handle) -> bool {
    return (handle.handle & MATERIAL_BASE_BIT) != 0
}

material_shader_of     :: proc "contextless" (handle: Material_Handle) -> Shader_Handle {
    idx, ok := material_handle_unpack(handle)
    if !ok { return {} }
    return _state.material_library.table.items[int(idx)].shader
}

material_draw_state_of :: proc "contextless" (handle: Material_Handle) -> Draw_State {
    idx, ok := material_handle_unpack(handle)
    if !ok { return DEFAULT_DRAW_STATE }
    return _state.material_library.table.items[int(idx)].state
}

material_queue_of      :: proc "contextless" (handle: Material_Handle) -> Render_Queue {
    idx, ok := material_handle_unpack(handle)
    if !ok { return .Opaque }
    return _state.material_library.table.items[int(idx)].queue
}

material_bindings_of :: proc "contextless" (handle: Material_Handle) -> []gpu.Parameter_Resource {
    idx, ok := material_handle_unpack(handle)
    if !ok { return nil }
    return _state.material_library.table.items[int(idx)].bindings[:]
}
