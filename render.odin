package nuppu

import "core:math"
import "core:mem"
import "gpu"
import "bit_array"
import "base:intrinsics"
import "base:runtime"
import "core:slice"
import "core:log"

#assert(size_of(Vertex) == 32)
Vertex :: struct #align(16) {
    position: [3]f32,
    uv:       [2]u16,

    color:    [4]u8,
    normal:   [3]f32,
}

Vertex_Index :: u16

Mesh :: struct #all_or_none {
    vertex_count: u32,
    index_count:  u32,
    vertex_base:  u32,
    index_base:   u32,
    verts:        gpu.ptr,
    indices:      gpu.ptr,
}

Built_in_mesh :: enum u32 {
    Quad,
    Cube,
}

Built_in_texture :: enum u32 {
    Depth,
    Swapchain,
}

@(require_results)
push_mesh_zeroed :: proc(
    vertex_count: u32,
    index_count: u32,
    loc := #caller_location,
) -> Mesh_Handle {

    verts_view   := gpu.arena_alloc(&_state.vertex, Vertex, uint(vertex_count))
    indices_view := gpu.arena_alloc_raw(&_state.index, size_of(Vertex_Index), uint(index_count), 4)

    handle := add_resource(&_state.meshes, Mesh {
        vertex_count = vertex_count,
        index_count  = index_count,
        vertex_base  = verts_view.byte_offset / size_of(Vertex),
        index_base   = indices_view.byte_offset / size_of(Vertex_Index),
        verts        = verts_view,
        indices      = indices_view,
        })

    return handle
}

get_built_in_mesh :: proc(built_in_mesh: Built_in_mesh) -> (^Mesh, bool) #optional_ok {
    return get_mesh(_state.built_in_meshes[built_in_mesh])
}

get_mesh :: proc(handle: Mesh_Handle) -> (^Mesh, bool) { return get_resource(&_state.meshes, handle) }

draw_sprite :: proc(
    frame: Frame,
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    uv_min:       [2]f32 = {0, 0},
    uv_size:      [2]f32 = {1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [2]f32 = {1, 1},
    material_idx: u32    = 0,
) {
    sprite_instance := pack_sprite_instance(position, color, uv_min, uv_size, rotation, scale, material_idx)

    push_instance(frame, &_state.draw_batcher, Instance{.Sprite, .Default, {}}, sprite_instance)
}

draw_cube :: proc(
    frame: Frame,
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [3]f32 = {1, 1, 1},
    material_idx: u32    = 0,
) {

    mesh_instance := pack_mesh_instance(position, color, rotation, scale, material_idx)

    push_instance(frame, &_state.draw_batcher, Instance{.Mesh, .Default, {}}, mesh_instance)
}

Instance_Kind :: enum u16 {
    Sprite = 0,
    Mesh,
}

Material_Kind :: enum u16 {
    Default = 0,
}

#assert(size_of(Instance) == 8)
Instance :: struct #align(8) {
    kind: Instance_Kind,
    material_idx: Material_Kind,

    _extra_data: u32,
}

#assert(size_of(Mesh_Instance) == 32)
Mesh_Instance :: struct #all_or_none #align(16) {
    position: [3]f32,
    color:    [4]u8,

    scale: [3]u16,
    turns: [3]u8,
    material_index: u8,
    _pad: [3]u8,
}

Instance_Batch :: struct {
    base_instances   : gpu.ptr,
    variant_instances: gpu.ptr,
    variant_byte_offset: u32, // byte offset of variant start in the batcher's blob
    
    cap              : i32, // how many instances of a given variant buffer can fit into single slice, NOT the cap of the buffer
    top              : [FRAMES_IN_FLIGHT]i32, // the amount of instance + instance data
}

Draw_Batcher :: struct {
    types               : [dynamic]typeid,
    sizes               : [dynamic]i64,
    instances           : [dynamic]Instance_Batch,
    meshes              : [dynamic]Mesh_Handle,

    instance_base_buffer: gpu.ptr,
    instance_data_buffer: gpu.ptr,

    instances_total: i64,

    base_watermark: u32,
    data_watermark: u32,
    allocator: runtime.Allocator,
    is_init: bool,
}

init_draw_batcher :: proc(batcher: ^Draw_Batcher, max_instances: u32, max_instance_data_size: u32, allocator := context.allocator) {
    batcher.instance_base_buffer, _ = gpu.malloc(size_of(Instance) * max_instances * FRAMES_IN_FLIGHT, align_of(Instance), .Staging)
    batcher.instance_data_buffer, _ = gpu.malloc(max_instance_data_size * FRAMES_IN_FLIGHT, 16, .Staging)

    INITIAL_CAPACITY :: 16
    batcher.allocator = allocator
    batcher.instances_total = i64(max_instances)

    batcher.types = make([dynamic]typeid, len=0, cap = INITIAL_CAPACITY, allocator = allocator)
    batcher.sizes = make([dynamic]i64, len=0, cap = INITIAL_CAPACITY, allocator = allocator)
    batcher.instances = make([dynamic]Instance_Batch, len=0, cap = INITIAL_CAPACITY, allocator = allocator)
    batcher.meshes = make([dynamic]Mesh_Handle, len=0, cap = INITIAL_CAPACITY, allocator = allocator)

    batcher.is_init = true
}

draw_batcher_add_variant :: proc(batcher: ^Draw_Batcher, $T: typeid, mesh: Mesh_Handle, capacity: int = 1024) {
    assert(batcher.is_init)

    if slice.contains(batcher.types[:], T) {
        return // already added
    }

    append(&batcher.meshes, mesh)
    append(&batcher.types, T)
    size_t := size_of(T)
    append(&batcher.sizes, i64(size_t))
    
    assert(align_of(T) % 16 == 0)

    batch := Instance_Batch {
        base_instances = gpu.sub_alloc(batcher.instance_base_buffer, batcher.base_watermark, u32(FRAMES_IN_FLIGHT * capacity * size_of(Instance))),
        variant_instances = gpu.sub_alloc(batcher.instance_data_buffer, batcher.data_watermark, u32(FRAMES_IN_FLIGHT * capacity * size_t)),
        cap = i32(capacity),
        top = {},
    }
    batch.variant_byte_offset = u32(uintptr(batch.variant_instances.cpu) - uintptr(batcher.instance_data_buffer.cpu))

    append(&batcher.instances, batch)

    batcher.base_watermark += u32(FRAMES_IN_FLIGHT * capacity * size_of(Instance))
    batcher.data_watermark += u32(FRAMES_IN_FLIGHT * capacity * size_t)
}

batcher_reset :: proc(frame: Frame, batcher: ^Draw_Batcher) {
    for &data in batcher.instances {
        data.top[frame.n % FRAMES_IN_FLIGHT] = 0
    }
}

push_instance :: proc(frame: Frame, batcher: ^Draw_Batcher, instance: Instance, instance_data: $T) {
    assert(batcher.is_init)
    variant_idx, found := slice.linear_search(batcher.types[:], T)
    assert(found, "push_instance: type not registered")

    data := &batcher.instances[variant_idx] // data
    size := batcher.sizes[variant_idx] // size of variant instance
    frame_n := frame.n // current frame
    top := &data.top[frame_n % FRAMES_IN_FLIGHT]
    top_idx := top^ // how many instances pushed this frame
    if top_idx >= data.cap {
        log.error("push_instance: out of capacity")
        return
    }
    
    base_instance_ptr := \
    uintptr(data.base_instances.cpu) \
    + uintptr( (frame_n % FRAMES_IN_FLIGHT) * size_of(Instance) * u64(data.cap)) \
    + uintptr(top_idx * size_of(Instance))
    
    base_data_ptr := \ 
    uintptr(data.variant_instances.cpu) \
    + uintptr( (frame_n % FRAMES_IN_FLIGHT) * u64(size) * u64(data.cap)) \
    + uintptr(u64(top_idx) * u64(size))
    
    // Hardcode for now
    _instance := Instance {
        kind = instance.kind,
        material_idx = instance.material_idx,
        _extra_data = u32(u64(data.variant_byte_offset) \
        + (frame_n % FRAMES_IN_FLIGHT) * u64(size) * u64(data.cap) \
        + u64(top_idx) * u64(size)),
    }

    // Write
    ([^]Instance)(rawptr(base_instance_ptr))[0] = _instance
    
    dest := ([^]u8)(rawptr(base_data_ptr))
    i := instance_data
    mem.copy(&dest[0], &i, int(size))

    top^ += 1
}

finish_instance_upload :: proc(frame: Frame) {
    f := u32(frame.n % FRAMES_IN_FLIGHT)

    for &data, I in _state.draw_batcher.instances {
        gpu.unmap(&data.base_instances, 
            i64( i64(frame.n % FRAMES_IN_FLIGHT) * i64(size_of(Instance) ) * i64(data.cap)),
            i64(size_of(Instance) * data.cap))
        gpu.unmap(&data.variant_instances, 
            i64( i64(frame.n % FRAMES_IN_FLIGHT) * i64(_state.draw_batcher.sizes[I]) * i64(data.cap)),
            i64( i64(_state.draw_batcher.sizes[I]) * i64(data.cap)))
    }

    for &data, I in _state.draw_batcher.instances {
        size_t := u32(_state.draw_batcher.sizes[I])
        hdr_slot  := u32(data.cap) * u32(size_of(Instance))
        data_slot := u32(data.cap) * size_t

        src_hdr := gpu.sub_alloc(data.base_instances,    f * hdr_slot,  hdr_slot)
        src_dat := gpu.sub_alloc(data.variant_instances, f * data_slot, data_slot)

        hdr_off  := u32(data.base_instances.byte_offset)  // where headers belong
        data_off := u32(data.variant_byte_offset)         // where payloads belong

        dst_hdr := gpu.sub_alloc(_state.instances,      hdr_off  + f * hdr_slot,  hdr_slot)
        dst_dat := gpu.sub_alloc(_state.instances_data, data_off + f * data_slot, data_slot)

        gpu.copy(dst_hdr, src_hdr)
        gpu.copy(dst_dat, src_dat)
    }

    // TODO: Needed for wgpu to start mapping again
    // gpu.recall(&batcher.instance_buffer)
    // gpu.recall(&batcher.instance_data_buffer_blob)
}

draw_all_instances :: proc(frame: Frame) {
    f := frame.n % FRAMES_IN_FLIGHT
    base_instance :i32= 0
    for batch, i in _state.draw_batcher.instances {
        mesh_handle := _state.draw_batcher.meshes[i]
        mesh, ok := get_mesh(mesh_handle)
        if !ok { continue }

        count := u32(batch.top[f])
        if count == 0 { continue }

        gpu.draw_indiced_primitives(
            &_state.built_in_block,
            _state.index.ptr,
            mesh.index_count,
            mesh.index_base,
            count,
            mesh.vertex_base,
            u32(base_instance),
        )

        base_instance += batch.cap * FRAMES_IN_FLIGHT
    }
}

create_built_in_meshes :: proc() {
    
    {
        // Quad
        s :: 0.5
        VERTEX_COUNT :: 4
        INDEX_COUNT :: 6
        v := [VERTEX_COUNT]Vertex {
            pack_vertex( position = { -s, -s, 0 }, uv = { 0.0, 0.0 } ),
            pack_vertex( position = { +s, -s, 0 }, uv = { 1.0, 0.0 } ),
            pack_vertex( position = { +s, +s, 0 }, uv = { 1.0, 1.0 } ),
            pack_vertex( position = { -s, +s, 0 }, uv = { 0.0, 1.0 } ),
        }
    
        i := [INDEX_COUNT]Vertex_Index {
            0, 1, 2, 2, 3, 0
        }

        upload, _ := gpu.arena_init(4 * 1024 * 1024)
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        indices := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), INDEX_COUNT, 4)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))
    
        quad_handle := push_mesh_zeroed(VERTEX_COUNT, INDEX_COUNT)
    
        _state.built_in_meshes[.Quad] = quad_handle
    
        quad_mesh, _ := get_resource(&_state.meshes, quad_handle)
    
        gpu.unmap(&upload.ptr)
        gpu.begin_commands()
        gpu.copy(quad_mesh.verts, verts)
        gpu.copy(quad_mesh.indices, indices)
        gpu.barrier(.Transfer, .All)
        gpu.commit_commands()
    }

    {
        // Cube
        s :: 0.5
        VERTEX_COUNT :: 24
        INDEX_COUNT :: 36
        v := [VERTEX_COUNT]Vertex {
            // Front (+Z)
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 0, 1 } ),

            // Right (+X)
            pack_vertex( position = { +s, -s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 0, 1 } ),

            // Back (-Z)
            pack_vertex( position = { +s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { -s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 0, 1 } ),

            // Left (-X)
            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 } ),

            // Top (+Y)
            pack_vertex( position = { -s, +s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 } ),

            // Bottom (-Y)
            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 1 } ),
        }

        i := [INDEX_COUNT]Vertex_Index {
            0,  1,  2,  2,  3,  0,    /* front  */
            4,  5,  6,  6,  7,  4,    /* right  */
            8,  9, 10, 10, 11,  8,    /* back   */
            12, 13, 14, 14, 15, 12,   /* left   */
            16, 17, 18, 18, 19, 16,   /* top    */
            20, 21, 22, 22, 23, 20,   /* bottom */
        }

        upload, _ := gpu.arena_init(4 * 1024 * 1024)
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        indices := gpu.arena_alloc(&upload, Vertex_Index, INDEX_COUNT)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))

        cube_handle := push_mesh_zeroed(VERTEX_COUNT, INDEX_COUNT)
    
        _state.built_in_meshes[.Cube] = cube_handle
    
        cube_mesh, _ := get_resource(&_state.meshes, cube_handle)
    
        gpu.unmap(&upload.ptr)
        gpu.begin_commands()
        gpu.copy(cube_mesh.verts, verts)
        gpu.copy(cube_mesh.indices, indices)
        gpu.barrier(.Transfer, .All)
        gpu.commit_commands()
    }
}

/////////////////////////////////////////////////////

#assert(size_of(Engine_Uniform) == 208)
Engine_Uniform :: struct #all_or_none #align(16) {
    cam_perspective_transform: matrix[4, 4]f32,
    cam_ortho_transform: matrix[4, 4]f32,
    cam_view_transform: matrix[4, 4]f32,
    cam_position: [3]f32,
    _pad: f32,
}

SCALE_MAX :: 100.0

#assert(size_of(Sprite_Instance) == 32)
Sprite_Instance :: struct #all_or_none #align(16) {
    position: [3]f32,
    color:    [4]u8,
    // [4]f32

    uv_min: [2]u16,
    uv_size: [2]u16,
    // [2]f32

    scale: [2]u16,
    turns: [3]u8,
    material_index: u8,
}

#assert(size_of(Material) == 8)
Material :: struct {
    id: u16,
    user_data_1: u16,
    user_data_2: u32,
}

pack_mesh_instance :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [3]f32 = {1, 1, 1},
    material_idx: u32    = 0,
) -> Mesh_Instance {
    assert(material_idx < u32(max(u8) - 1))

    return Mesh_Instance {
        position = position,
        color    = pack_color(color),
        scale    = { pack_scale_f32(scale.x), pack_scale_f32(scale.y), pack_scale_f32(scale.z) },
        turns    = {
            pack_radians_turn(rotation.x),
            pack_radians_turn(rotation.y),
            pack_radians_turn(rotation.z),
        },
        material_index = u8(material_idx),
        _pad = {},
    }
} 

pack_sprite_instance :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    uv_min:       [2]f32 = {0, 0},
    uv_size:      [2]f32 = {1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [2]f32 = {1, 1},
    material_idx: u32    = 0,
) -> Sprite_Instance {
    assert(material_idx < u32(max(u8) - 1))
    
    return Sprite_Instance {
        position = position,
        color    = pack_color(color),
        uv_min   = { pack_float01(uv_min.x), pack_float01(uv_min.y) },
        uv_size  = { pack_float01(uv_size.x), pack_float01(uv_size.y) },
        scale    = { pack_scale_f32(scale.x), pack_scale_f32(scale.y) },
        turns    = {
            pack_radians_turn(rotation.x),
            pack_radians_turn(rotation.y),
            pack_radians_turn(rotation.z),
        },
        material_index = u8(material_idx),
    }
}

pack_color :: proc(value: [4]f32) -> [4]u8 {
    return [4]u8{
        u8(math.round(value[0] * 255)),
        u8(math.round(value[1] * 255)),
        u8(math.round(value[2] * 255)),
        u8(math.round(value[3] * 255)),
    }
}

pack_scale_f32 :: proc(value: f32) -> u16 {
    c := math.clamp(value, 0.0, SCALE_MAX)
    return u16(math.round(c / SCALE_MAX * 65535))
}

pack_radians_turn :: proc(radians: f32) -> u8 {
    turns := math.mod(radians / (2 * math.PI), 1.0)
    if turns < 0 do turns += 1.0
    return u8(math.round(turns * 255))
}

/////////////////////////////////////////////////////

pack_float01 :: proc(value: f32) -> u16 {
    result := math.clamp(value, 0.0, 1.0)
    return u16(math.round(result * (1 << 16 - 1)))
}

pack_vertex :: proc(
    position: [3]f32,
    uv:       [2]f32 = {0, 0},
    color:    [4]u8  = {255, 255, 255, 255},
    normal:   [3]f32 = {0, 1, 0},
) -> Vertex {
    return Vertex {
        position = position,
        uv =       [2]u16{pack_float01(uv.x), pack_float01(uv.y)},
        color =    color,
        normal =   normal,
    }
}
