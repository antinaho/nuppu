#+vet unused shadowing using-param style semicolon cast explicit-allocators

/*


*/

package nuppu

#assert(CONFIG.max_materials <= MATERIAL_INDEX_MASK, "CONFIG.max_materials must be <= MATERIAL_INDEX_MASK")

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "gpu"

_ :: log

MATERIAL_HANDLE_RAW       :: u16
MATERIAL_INDEX_MASK       :: (1 << 15) - 1
MATERIAL_EMBED_BIT        ::  1 << 15

MATERIAL_EMBED_DATA_BYTES :: 6

Material_Handle :: Handle(MATERIAL_HANDLE_RAW)
MATERIAL_NIL    :: Material_Handle{}

when !ODIN_DEBUG {
    #assert(size_of(Material_Handle) == size_of(MATERIAL_HANDLE_RAW))
}

#assert(size_of(GPU_Material_Instance) == 8)
GPU_Material_Instance :: struct #align(8) {
    handle     : MATERIAL_HANDLE_RAW,
    user_data_1: u16,
    user_data_2: u32,                 // extra inline data or byte offset into the parameter buffer
}

Material_Library :: struct {
    private_material_buffer: gpu.ptr, // [CONFIG.max_materials]GPU_Material
    private_params_buffer  : gpu.ptr, // [CONFIG.material_param_bytes]u8 variable-size params

    material_types         : [dynamic]typeid,
    material_shaders       : [dynamic]Shader_Handle,
    material_draw_states   : [dynamic]Draw_State,

    occupied               : Bit_Mask_Array,

    allocator              : runtime.Allocator,
    is_init                : bool,

    material_handles       : [dynamic]Material_Handle, // debug-only
}

Material_Upload_Scope :: struct {
    staging_mat   : gpu.ptr,
    staging_params: gpu.Arena,
    active        : bool,
}

@(require_results, deferred_out_by_ptr = __material_upload_scope_end)
material_upload_scope :: proc(count: int) -> Material_Upload_Scope {
    // `material_upload` writes each material at its global library index, and
    // the scope-end blit copies the whole staging buffer to the private buffer
    // at offset 0. Size the staging buffer to the full library so both stay in
    // bounds and aligned.
    assert(count > 0 && count <= CONFIG.max_materials, "material_upload_scope: bad count")
    staging_mat, ok := gpu.malloc(
        size_of(GPU_Material_Instance) * CONFIG.max_materials,
        u32(align_of(GPU_Material_Instance)), .Staging,
    )
    assert(ok, "material_upload_scope: failed to alloc material buffer")
    staging_params, ok_par := gpu.arena_init(CONFIG.material_param_bytes, 16, .Staging)
    assert(ok_par, "material_upload_scope: failed to alloc material params buffer")
    
    return Material_Upload_Scope {
        staging_mat = staging_mat,
        staging_params = staging_params,
        active = true,
    }
}

@(require_results)
material_upload :: proc(scope: ^Material_Upload_Scope, shader: Shader_Handle, state: Draw_State, data: ^$M, is_embed: bool = false, name: string = "", loc := #caller_location) -> (Material_Handle, bool) #optional_ok {
    lib := &_state.material_library
    assert(lib.is_init, "material_upload: material library not initialized")
    assert(scope.active, "material_upload: scope is not active, call material_upload_scope() first")
    free_idx, ok := bit_mask_array_flip_first_zero(&_state.material_library.occupied)
    assert(ok, "material_upload: Ran out of space, increase max materials in config")
    handle_raw := u16(free_idx)

    if is_embed {
        if size_of(M) > MATERIAL_EMBED_DATA_BYTES {
            log.error("material_register: embed data size is too large", location = loc)
            return MATERIAL_NIL, false
        }
        handle_raw |= MATERIAL_EMBED_BIT
    }

    mat := &([^]GPU_Material_Instance)(scope.staging_mat.cpu)[free_idx]
    mat.handle = handle_raw
    mat.user_data_1 = 0
    mat.user_data_2 = 0

    size_t := size_of(M)
    if size_t <= MATERIAL_EMBED_DATA_BYTES && is_embed {
        intrinsics.mem_copy_non_overlapping(&mat.user_data_1, rawptr(data), size_t)
    } else {
        view := gpu.arena_alloc_raw(&scope.staging_params, uint(size_t), 1, 16)
        intrinsics.mem_zero(view.cpu, size_t)
        intrinsics.mem_copy_non_overlapping(view.cpu, rawptr(data), size_t)
        mat.user_data_2 = view.byte_offset
    }

    handle := Material_Handle { handle = handle_raw }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
        append(&lib.material_handles, handle)
    }

    append(&lib.material_types, M)
    append(&lib.material_shaders, shader)
    append(&lib.material_draw_states, state)

    return handle, true
}

__material_upload_scope_end :: proc(scope: ^Material_Upload_Scope) {
    lib := &_state.material_library
    gpu.unmap(&scope.staging_mat)
    gpu.unmap(&scope.staging_params.ptr)
    gpu.begin_commands()
    gpu.copy(lib.private_material_buffer, scope.staging_mat)
    gpu.copy(lib.private_params_buffer, scope.staging_params.ptr)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()

    gpu.release_ptr(&scope.staging_mat)
    gpu.release_ptr(&scope.staging_params.ptr)
    scope.active = false
}


@(require_results)
material_shader_of :: proc(handle: Material_Handle) -> (Shader_Handle, Draw_State) {
    lib := &_state.material_library
    index := _material_handle_unpack(handle)
    return lib.material_shaders[index], lib.material_draw_states[index]
}

_material_lib_init :: proc(lib: ^Material_Library, allocator := context.allocator) {
    if lib.is_init { return }
    lib.is_init = true
    lib.allocator = allocator

    lib.occupied = bit_mask_array_init(CONFIG.max_materials, allocator = context.allocator)

    ok: bool
    lib.private_material_buffer, ok = gpu.malloc(
        u32(CONFIG.max_materials * size_of(GPU_Material_Instance)),
        u32(align_of(GPU_Material_Instance)), .Default, "Material Buffer",
    )
    assert(ok, "material_lib_init: failed to alloc material buffer")

    lib.private_params_buffer, ok = gpu.malloc(CONFIG.material_param_bytes, 16, .Default, "Material params") 
    assert(ok, "material_lib_init: failed to alloc material params buffer")

    lib.material_types       = make([dynamic]typeid, 0, 64, allocator)
    lib.material_shaders     = make([dynamic]Shader_Handle, 0, 64, allocator)
    lib.material_draw_states = make([dynamic]Draw_State, 0, 64, allocator)

    // Slot 0 is MATERIAL_NIL; keep the per-index arrays aligned with `top`.
    append(&lib.material_types, typeid_of(int))
    append(&lib.material_shaders, Shader_Handle_Nil)
    append(&lib.material_draw_states, DEFAULT_DRAW_STATE)
    bit_mask_array_flip_first_zero(&lib.occupied)

    when ODIN_DEBUG {
        lib.material_handles = make([dynamic]Material_Handle, 0, 64, allocator)
        append(&lib.material_handles, Material_Handle{})
    }
}

_material_lib_deinit :: proc(lib: ^Material_Library) {
    gpu.release_ptr(&lib.private_material_buffer)
    gpu.release_ptr(&lib.private_params_buffer)
    bit_mask_array_destroy(&lib.occupied)
    delete(lib.material_types)
    delete(lib.material_shaders)
    delete(lib.material_draw_states)
    when ODIN_DEBUG {
        delete(lib.material_handles)
    }
    lib^ = {}
}

_material_handle_unpack :: proc(handle: Material_Handle) -> u16 {
    return handle.handle & MATERIAL_INDEX_MASK
}
