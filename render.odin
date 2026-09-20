package nuppu

import "gpu"

import "base:runtime"

import "core:math"
import "core:slice"
import "core:log"

_ :: log

// Resolves a mesh handle from the index stored in a draw sort key.
@(require_results)
get_mesh_by_index :: proc(index: uint) -> (handle: Mesh_Handle, ok: bool) #optional_ok #no_bounds_check {
    if index == 0 || u64(index) >= u64(MAX_MESHES) { return {}, false }
    if _, mesh_ok := resource_table_get(&_state.mesh_library.table, int(index)); !mesh_ok { return {}, false }
    return Mesh_Handle { handle = u16(index) }, true
}

INSTANCE_SIZE_ALIGN :: 16

// ============================================================================
// Instance layout
// ============================================================================
#assert(size_of(Mesh_Instance) == 64)
Mesh_Instance :: struct #all_or_none #align(INSTANCE_SIZE_ALIGN) {
    position: [3]f32,
    color: [4]u8,

    matrix_x: [3]f32,
    mesh_data_1: [2]u16,
    

    matrix_y: [3]f32,
    mesh_data_2: [2]u16,

    mesh_matrix_z: [3]f32,

    material_and_flags: u32,
}

#assert(size_of(Sprite_Instance) == 64)
Sprite_Instance :: struct #all_or_none #align(INSTANCE_SIZE_ALIGN) {
    position: [3]f32,
    color: [4]u8,

    matrix_x: [3]f32,
    uv_min: [2]u16,

    matrix_y: [3]f32,
    uv_size: [2]u16,

    _unused: [3]f32,
    material_and_flags: u32,
}


// ============================================================================
// Draw batcher
//
// Pipeline:
//   cull_entities(T): frustum-test a type into a Cull_Set
//   submit_<X>/_submit: pack each survivor into its layout's bucket + sort key
//   flush_culled_instances(frame): globally sort all layouts by draw_sort_key,
//     stage + copy each layout's records into its own double-buffered device
//     buffer, emit Draw_Command runs
//   draw_all_instances(frame): bind shader + layout buffer, one draw per run
// ============================================================================


Draw_Command :: struct {
    mesh:           Mesh_Handle,
    shader:         Shader_Handle,
    material:       Material_Handle,
    draw_state:     Draw_State,
    buffer:         gpu.ptr, // this layout's instance buffer
    base_instance:  uint,     // element index into `buffer`
    instance_count: uint,
}

// One staging bucket per instance layout. `data` is `count * size` packed
// instance bytes; `keys` is the parallel, index-aligned list of sort keys.
// `buffer` is that layout's own device-local instance buffer, holding
// `FRAMES_IN_FLIGHT` slots of `capacity` records each.
Submission :: struct {
    data:     [dynamic]u8,           // instance bytes
    keys:     [dynamic]Draw_Sort_Key, // parallel, index-aligned draw sort keys
    size:     int,                   // size_t
    buffer:   gpu.ptr,      // device-local instance buffer
    capacity: uint,          // max instances
    active:   bool,         // has this layout been submitted this frame?
}

// A resolved reference into a Submission. Building one flat list of these and
// sorting it gives a single ordering across every instance type.
Global_Entry :: struct {
    key:  Draw_Sort_Key,
    type: uint, // index into Draw_Batcher.submission_order
    item: uint, // index into Submission.keys / Submission.data
}

// A single 64-bit ordering value for every submitted instance. Kept distinct so
// it cannot be confused with other u64s in the batch pipeline, and so the width
// is explicit (plain `uint` is 32-bit on the wasm target).
Draw_Sort_Key :: distinct u64

Draw_Batcher :: struct {
    draw_commands:    [dynamic]Draw_Command,
    submissions:      map[typeid]Submission,
    submission_order: [dynamic]typeid,
    entries:          [dynamic]Global_Entry,

    instance_count: int,

    allocator: runtime.Allocator,
    is_init:   bool,
}

Cull_Set :: struct {
    entities: [dynamic]^Entity,
}

// ----------------------------------------------------------------------------
// Draw sort key
//
// A single u64 orders every submitted instance across all types:
//
//   bits  0..7   extra_sort      user override (tie-break)
//   bits  8..23  material        full 16-bit Material_Handle raw value
//   bits 24..33  mesh index      u16 handle index
//   bits 34..41  shader index    u16 handle index
//   bits 42..61  depth           far-first for Transparent, 0 for Opaque
//   bits 62..63  render queue    Opaque < Transparent < UI
//
// Sorting is pure u64 comparison: the material and mesh are recovered from the
// key after sorting (shader/draw_state are derived from the material). The
// material index is stored whole in its 16-bit field.
// ----------------------------------------------------------------------------

SORT_EXTRA_SHIFT    :: 0
SORT_MATERIAL_SHIFT :: 8
SORT_MESH_SHIFT     :: 24
SORT_SHADER_SHIFT   :: 34
SORT_DEPTH_SHIFT    :: 42
SORT_QUEUE_SHIFT    :: 62

SORT_MATERIAL_BITS  :: 16
SORT_MESH_BITS      :: 10
SORT_SHADER_BITS    :: 8
SORT_DEPTH_BITS     :: 20

SORT_MATERIAL_MASK :: (1 << SORT_MATERIAL_BITS) - 1
SORT_MESH_MASK     :: (1 << SORT_MESH_BITS) - 1
SORT_DEPTH_MAX     :: u64((1 << SORT_DEPTH_BITS) - 1)

#assert(MAX_MESHES  <= 1 << SORT_MESH_BITS,   "mesh index does not fit the sort key")
#assert(MAX_SHADERS <= 1 << SORT_SHADER_BITS, "shader index does not fit the sort key")
#assert(u16(gpu.Front_Face.CW)           <= 0b1,   "Front_Face does not fit draw_state_pack")
#assert(u16(gpu.Cull_Mode.Back)          <= 0b11,  "Cull_Mode does not fit draw_state_pack")
#assert(u16(gpu.Compare_Function.Always) <= 0b111, "Compare_Function does not fit draw_state_pack")

// 7 valid bits: depth_write | front_face<<1 | cull_mode<<2 | depth_compare<<4.
draw_state_pack :: proc "contextless" (state: Draw_State) -> u8 {
    return u8(state.depth_write)        |
           u8(state.front_face)    << 1 |
           u8(state.cull_mode)     << 2 |
           u8(state.depth_compare) << 4
}

draw_sort_key :: proc "contextless" (
    queue:      Render_Queue,
    depth:      u64,
    shader:     Shader_Handle,
    mesh:       Mesh_Handle,
    material:   Material_Handle,
    extra_sort: u8,
) -> Draw_Sort_Key {
    return Draw_Sort_Key(
        u64(extra_sort)          << SORT_EXTRA_SHIFT    |
        u64(material.handle)     << SORT_MATERIAL_SHIFT |
        u64(mesh.handle)         << SORT_MESH_SHIFT     |
        u64(shader.handle)       << SORT_SHADER_SHIFT   |
        (depth & SORT_DEPTH_MAX) << SORT_DEPTH_SHIFT    |
        u64(queue)               << SORT_QUEUE_SHIFT,
    )
}

// Recover the material handle from a sort key.
_sort_key_material :: #force_inline proc "contextless" (key: Draw_Sort_Key) -> Material_Handle {
    return Material_Handle { handle = MATERIAL_HANDLE_RAW((u64(key) >> SORT_MATERIAL_SHIFT) & SORT_MATERIAL_MASK) }
}

// Recover the mesh handle index from a sort key.
_sort_key_mesh_index :: #force_inline proc "contextless" (key: Draw_Sort_Key) -> uint {
    return uint((u64(key) >> SORT_MESH_SHIFT) & SORT_MESH_MASK)
}

// Back-to-front key: far instances get a smaller value so they draw first.
_depth_sort_value :: proc "contextless" (position: [3]f32) -> u64 {
    cam := _state.camera_position
    dx  := position.x - cam.x
    dy  := position.y - cam.y
    dz  := position.z - cam.z
    dist  := math.sqrt(dx*dx + dy*dy + dz*dz)
    far   := max(_state.camera_far, 0.0001)
    near  := math.clamp(dist / far, 0.0, 1.0)
    return u64((1.0 - near) * f32(SORT_DEPTH_MAX))
}

// Rows of rotation * scale, matching the TRS the instance shaders expect. The
// scale is applied per column; `z` is the third row.
_trs_rows :: proc "contextless" (rotation, scale: [3]f32) -> (x, y, z: [3]f32) {
    cx, sx := math.cos(rotation.x), math.sin(rotation.x)
    cy, sy := math.cos(rotation.y), math.sin(rotation.y)
    cz, sz := math.cos(rotation.z), math.sin(rotation.z)

    x = { cz*cy, cz*sy*sx - sz*cx, cz*sy*cx + sz*sx }
    y = { sz*cy, sz*sy*sx + cz*cx, sz*sy*cx - cz*sx }
    z = { -sy,   cy*sx,            cy*cx            }

    x *= scale
    y *= scale
    z *= scale
    return
}

init_draw_batcher :: proc(batcher: ^Draw_Batcher, allocator := context.allocator) {
    if batcher.is_init { return }
    batcher.is_init   = true
    batcher.allocator = allocator

    INITIAL_CAP :: 16
    batcher.submissions      = make(map[typeid]Submission, INITIAL_CAP, allocator)
    batcher.draw_commands    = make([dynamic]Draw_Command, 0, INITIAL_CAP, allocator)
    batcher.submission_order = make([dynamic]typeid, 0, INITIAL_CAP, allocator)
    batcher.entries          = make([dynamic]Global_Entry, 0, INITIAL_CAP, allocator)
}

destroy_draw_batcher :: proc(batcher: ^Draw_Batcher) {
    if !batcher.is_init { return }

    for _, &submission in batcher.submissions {
        gpu.release_ptr(&submission.buffer)
        delete(submission.data)
        delete(submission.keys)
    }
    delete(batcher.submissions)
    delete(batcher.draw_commands)
    delete(batcher.submission_order)
    delete(batcher.entries)
    batcher^ = {}
}

batcher_reset :: proc(batcher: ^Draw_Batcher) {
    for _, &submission in batcher.submissions {
        clear(&submission.data)
        clear(&submission.keys)
        submission.active = false
    }
    clear(&batcher.draw_commands)
    clear(&batcher.submission_order)
    clear(&batcher.entries)
    batcher.instance_count = 0
}

// ----------------------------------------------------------------------------
// Entity gather
// ----------------------------------------------------------------------------

// Trailing word of both instance layouts. Bits 0..15 carry the material index;
// bit 16 marks data0/data1 as a uv rect (sprites) rather than mesh data.
INSTANCE_FLAG_ATLAS_UV :: u32(1) << 16

instance_tail :: #force_inline proc "contextless" (material_index: u16, atlas: bool) -> u32 {
    return u32(material_index) | (INSTANCE_FLAG_ATLAS_UV if atlas else 0)
}



// Ensures the instance buffer for layout `I` exists and returns it. Called from
// `shader_register` so WGPU has a concrete instance resource to build the
// graphics block from, and from `_submit` on first use.
@(require_results)
_batcher_layout_buffer :: proc($I: typeid) -> gpu.ptr {
    #assert(size_of(I) > 0, "instance layout must not be zero-sized")
    #assert(size_of(I) % INSTANCE_SIZE_ALIGN == 0, "instance layout size must be a multiple of 16")

    batcher := &_state.draw_batcher

    submission, found := batcher.submissions[I]
    if !found {
        capacity := uint(MAX_INSTANCES_PER_TYPE)
        bytes    := uint(FRAMES_IN_FLIGHT) * capacity * size_of(I)
        buffer, ok := gpu.malloc(bytes, 256, .Default, "Instance")
        assert(ok, "_batcher_layout_buffer: failed to alloc instance buffer")

        submission = Submission {
            data     = make([dynamic]u8, 0, allocator = batcher.allocator),
            keys     = make([dynamic]Draw_Sort_Key, 0, allocator = batcher.allocator),
            size     = size_of(I),
            buffer   = buffer,
            capacity = capacity,
        }
        batcher.submissions[I] = submission
    }

    return submission.buffer
}

// Packs one instance of layout `I` and enqueues it under that layout's bucket.
// Shared by the engine `submit_<X>` wrappers and user-defined ones.
_submit :: proc(instance: $I, key: Draw_Sort_Key) {
    batcher := &_state.draw_batcher

    _ = _batcher_layout_buffer(I)
    submission := batcher.submissions[I]

    if !submission.active {
        submission.active = true
        append(&batcher.submission_order, I)
    }

    assert(len(submission.keys) < int(submission.capacity), "submit: per-type instance capacity exceeded; raise CONFIG.max_instances_per_type")

    local := instance
    bytes := slice.bytes_from_ptr(&local, size_of(I))
    append(&submission.data, ..bytes)
    append(&submission.keys, key)
    batcher.submissions[I] = submission

    batcher.instance_count += 1
}

// Builds the draw sort key for an entity's material + mesh.
_entity_sort_key :: proc(e: ^Entity, position: [3]f32, extra_sort: u8) -> Draw_Sort_Key {
    shader := material_shader_of(e.material)
    queue := material_queue_of(e.material)
    depth := queue == .Transparent ? _depth_sort_value(position) : 0
    return draw_sort_key(queue, depth, shader, e.mesh, e.material, extra_sort)
}

// Public entry point for user-defined instance layouts. `instance` is any
// struct whose size is a multiple of 16; its type is the layout. The draw key,
// queue and depth come from the entity's material.
submit_instance :: proc(e: ^Entity, instance: $I, extra_sort: u8 = 0) {
    position, _, _ := transform(e, _render_alpha())
    _submit(instance, _entity_sort_key(e, position, extra_sort))
}

submit_sprite :: proc(e: ^Entity, uv_min, uv_size: [2]f32, color := [4]f32{1,1,1,1}, extra_sort: u8 = 0) {
    position, rotation, scale := transform(e, _render_alpha())
    matrix_x, matrix_y, _ := _trs_rows(rotation, scale)

    inst := Sprite_Instance {
        position = position,
        color    = pack_color(color),

        matrix_x = matrix_x,
        uv_min   = pack_uv_to_u16x2(uv_min),

        matrix_y = matrix_y,
        uv_size  = pack_uv_to_u16x2(uv_size),

        _unused  = {},
        material_and_flags = instance_tail(material_handle_unpack(e.material), true),
    }

    _submit(inst, _entity_sort_key(e, position, extra_sort))
}

submit_mesh :: proc(e: ^Entity, color := [4]f32{1,1,1,1}, mesh_data := [4]u16{}, extra_sort: u8 = 0) {
    position, rotation, scale := transform(e, _render_alpha())
    matrix_x, matrix_y, matrix_z := _trs_rows(rotation, scale)

    inst := Mesh_Instance {
        position = position,
        color    = pack_color(color),

        matrix_x     = matrix_x,
        mesh_data_1  = {mesh_data[0], mesh_data[1]},

        matrix_y     = matrix_y,
        mesh_data_2  = {mesh_data[2], mesh_data[3]},

        mesh_matrix_z = matrix_z,

        material_and_flags = instance_tail(material_handle_unpack(e.material), false),
    }

    _submit(inst, _entity_sort_key(e, position, extra_sort))
}

cull_entities :: proc($T: typeid) -> Cull_Set {
    return _cull_entities(_state.entity_manager, T)
}

_cull_entities :: proc(em: ^Entity_Manager, $T: typeid) -> Cull_Set {

    cull_set := Cull_Set {
        entities = make([dynamic]^Entity, 0, 512, allocator = context.temp_allocator),
    }

    cam, ok := entity_get_typed(em, _state.main_camera, Camera)
    if !ok { return cull_set }

    idx := -1
    for type, IDX in em.types {
        if T != type { continue }
        idx = IDX
        break
    }
    if idx == -1 { return cull_set }

    iter := Entity_Iterator {
        manager     = em,
        variant_idx = ENTITY_VARIANT(idx),
    }

    for entity in iter_next_entity(&iter) {
        center := entity.position
        radius := 0.5 * math.sqrt(entity.scale.x * entity.scale.x + entity.scale.y * entity.scale.y + entity.scale.z * entity.scale.z)
        if _sphere_in_frustum(cam.frustum, center, radius) {
            append(&cull_set.entities, entity)
        }
    }

    return cull_set
}

// ----------------------------------------------------------------------------
// Sort + upload
// ----------------------------------------------------------------------------

_global_entry_less :: proc(a, b: Global_Entry) -> bool {
    return a.key < b.key
}

// Sorts every submitted instance across all layouts by draw_sort_key and emits
// one Draw_Command per contiguous run of identical draw state. A global sort is
// what lets opaque/transparent ordering span instance types. Each layout's
// records are staged into the frame arena and copied into that layout's own
// device buffer for the current frame-in-flight.
flush_culled_instances :: proc(frame: Frame) {
    batcher := &_state.draw_batcher
    f := frame.n % FRAMES_IN_FLIGHT

    total := batcher.instance_count
    if total == 0 { return }

    ntypes := len(batcher.submission_order)
    views   := make([]gpu.ptr, ntypes, context.temp_allocator)
    cursors := make([]uint, ntypes, context.temp_allocator)

    arena        := frame.arena
    staged_bytes := uint(0)

    // One contiguous staging region per active layout.
    for layout, type_idx in batcher.submission_order {
        submission := batcher.submissions[layout]
        count := len(submission.keys)
        if count == 0 { continue }

        views[type_idx]   = gpu.arena_alloc_raw(arena, uint(submission.size), uint(count), INSTANCE_SIZE_ALIGN)
        cursors[type_idx] = 0
        staged_bytes += uint(count) * uint(submission.size)
    }

    assert(
        staged_bytes + size_of(Engine_Uniform) + 64 <= FRAME_ARENA_BYTES,
        "flush_culled_instances: staged instances exceed CONFIG.frame_upload_bytes",
    )

    // Resolve and globally sort every submitted record for cross-type ordering.
    clear(&batcher.entries)
    for layout, type_idx in batcher.submission_order {
        submission := batcher.submissions[layout]
        for key, key_idx in submission.keys {
            append(&batcher.entries, Global_Entry {
                key  = key,
                type = uint(type_idx),
                item = uint(key_idx),
            })
        }
    }
    slice.sort_by(batcher.entries[:], _global_entry_less)

    run_start_cursor  := uint(0)
    prev_type         := max(uint)
    prev_mesh_index   := max(uint)
    prev_material     := Material_Handle { handle = max(MATERIAL_HANDLE_RAW) }

    for entry, i in batcher.entries {
        submission := batcher.submissions[batcher.submission_order[entry.type]]
        cursor     := cursors[entry.type]

        src := submission.data[int(entry.item) * submission.size:][:submission.size]
        dst := ([^]u8)(views[entry.type].cpu)[int(cursor) * submission.size:][:submission.size]
        copy(dst, src)

        // Runs split on the draw identity, which the key fully determines:
        // material implies shader + draw_state.
        material   := _sort_key_material(entry.key)
        mesh_index := _sort_key_mesh_index(entry.key)

        same_as_prev := entry.type == prev_type &&
            mesh_index         == prev_mesh_index &&
            material.handle    == prev_material.handle
        if !same_as_prev {
            run_start_cursor = cursor
        }

        cursors[entry.type] = cursor + 1

        is_last  := i == total - 1
        same_run := false
        if !is_last {
            next_entry   := batcher.entries[i + 1]
            next_key     := next_entry.key
            next_material := _sort_key_material(next_key)
            same_run = next_entry.type == entry.type &&
                _sort_key_mesh_index(next_key) == mesh_index &&
                next_material.handle           == material.handle
        }

        if is_last || !same_run {
            shader := material_shader_of(material)
            draw_state := material_draw_state_of(material)
            mesh_handle, mesh_ok := get_mesh_by_index(mesh_index)
            if mesh_ok {
                append(&batcher.draw_commands, Draw_Command {
                    mesh           = mesh_handle,
                    shader         = shader,
                    material       = material,
                    draw_state     = draw_state,
                    buffer         = submission.buffer,
                    base_instance  = uint(f) * submission.capacity + run_start_cursor,
                    instance_count = cursor - run_start_cursor + 1,
                })
            }
        }

        prev_type       = entry.type
        prev_mesh_index = mesh_index
        prev_material   = material
    }

    // Upload each layout's staged records into its device buffer region.
    for layout, type_idx in batcher.submission_order {
        submission := batcher.submissions[layout]
        count := len(submission.keys)
        if count == 0 { continue }

        bytes := count * submission.size
        gpu.copy(
            gpu.sub_alloc(submission.buffer, uint(f) * submission.capacity * uint(submission.size), uint(bytes)),
            views[type_idx],
        )
    }

    gpu.barrier(.Transfer, .All)
}

// ----------------------------------------------------------------------------
// Draw
// ----------------------------------------------------------------------------

draw_all_instances :: proc(frame: Frame) {
    for cmd in _state.draw_batcher.draw_commands {
        if cmd.mesh == Mesh_Handle_Nil { continue }
        mesh, mesh_ok := get_mesh(cmd.mesh)
        if !mesh_ok { continue }
        if cmd.instance_count == 0 { continue }

        shader, shader_ok := get_shader(cmd.shader)
        if !shader_ok { continue }

        // Swap this draw's instance buffer into the shader's graphics block
        // (set 1) and bind the material's resources (set 3). The engine block
        // (set 0) is static; both setters no-op when unchanged.
        graphics_resources := [2]gpu.Parameter_Resource {
            cmd.buffer,
            _state.material_library.private_material_buffer,
        }
        gpu.update_parameter_block(&shader.desc.binding_blocks[SHADER_BLOCK_GRAPHICS], graphics_resources[:])
        gpu.update_parameter_block(&shader.desc.binding_blocks[SHADER_BLOCK_MATERIAL], material_bindings_of(cmd.material))
        gpu.set_shader(shader)

        gpu.set_draw_state(cmd.draw_state)

        gpu.draw_indexed(
            _state.mesh_library.index_arena.ptr,
            mesh.index_count,
            mesh.index_base,
            cmd.instance_count,
            mesh.vertex_base,
            cmd.base_instance,
        )
    }
}

// ============================================================================
// Frame uniforms
// ============================================================================

Engine_Uniform :: struct #all_or_none #align(16) {
    cam_perspective_transform: matrix[4, 4]f32,
    cam_ortho_transform:       matrix[4, 4]f32,
    cam_world_transform:       matrix[4, 4]f32, // entity-world → camera-view in the current shader contract
    cam_position: [3]f32,
    _pad: f32,
}
#assert(size_of(Engine_Uniform) == 208)

// ============================================================================
// Pack helpers
// ============================================================================
@(require_results)
pack_color :: proc "contextless" (value: [4]f32) -> [4]u8 {
    return [4]u8{
        u8(math.round(value[0] * 255)),
        u8(math.round(value[1] * 255)),
        u8(math.round(value[2] * 255)),
        u8(math.round(value[3] * 255)),
    }
}

// Pack a [2]f32 uv into two u16s (x, y).
@(require_results)
pack_uv_to_u16x2 :: proc "contextless" (uv: [2]f32) -> [2]u16 {
    return {u16(pack_float01(uv.x)), u16(pack_float01(uv.y))} 
}

@(require_results)
pack_float01 :: proc "contextless" (value: f32) -> u16 {
    result := math.clamp(value, 0.0, 1.0)
    return u16(math.round(result * (1 << 16 - 1)))
}

