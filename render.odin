package nuppu

import "core:math"
import "core:mem"
import "gpu"
import "bit_array"
import "base:intrinsics"
import "base:runtime"
import "core:slice"

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

@(require_results)
push_mesh_zeroed :: proc(
    vertex_count: u32,
    index_count: u32,
    loc := #caller_location,
) -> bit_array.Handle {

    verts_view   := gpu.arena_alloc(&_state.vertex, Vertex, uint(vertex_count))
    indices_view := gpu.arena_alloc_raw(&_state.index, size_of(Vertex_Index), uint(index_count), 4)

    handle := add_resource(&_state.meshes, Mesh {
        vertex_count = vertex_count,
        index_count  = index_count,
        vertex_base  = verts_view.byte_offset / size_of(Vertex),
        index_base   = indices_view.byte_offset / size_of(Vertex_Index),
        verts        = verts_view,
        indices      = indices_view,
        }, {
            name = "Mesh",
            created_at = loc,
        })
        
    return handle
}

get_built_in_mesh :: proc(built_in_mesh: Built_in_mesh) -> (^Mesh, bool) #optional_ok {
    return get_mesh(_state.built_in_meshes[built_in_mesh])
}

get_mesh :: proc(handle: bit_array.Handle) -> (^Mesh, bool) { return get_resource(&_state.meshes, handle) }

draw_sprite :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    uv_min:       [2]f32 = {0, 0},
    uv_size:      [2]f32 = {1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [2]f32 = {1, 1},
    material_idx: u32    = 0,
) {
    sprite_instance := pack_sprite_instance(position, color, uv_min, uv_size, rotation, scale, material_idx)

    push_instance(&_state.instance_batcher, .Sprite, .Default, slice.bytes_from_ptr(&sprite_instance, size_of(Sprite_Instance)))
}

draw_cube :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [3]f32 = {1, 1, 1},
    material_idx: u32    = 0,
) {

    base_instance := Instance {
        kind = .Mesh,
        material_idx = .Default,
        extra_data = {},
    }

    mesh_instance := pack_mesh_instance(position, color, rotation, scale, material_idx)

    push_instance(&_state.instance_batcher, .Mesh, .Default, slice.bytes_from_ptr(&mesh_instance, size_of(Mesh_Instance)))
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

    extra_data: u32,
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

Instance_Batcher :: struct {
    instance_buffer: gpu.ptr,
    instance_data_buffer_blob: gpu.ptr,

    instance_offset:      int,
    instance_data_offset: int,
}

push_instance :: proc(batcher: ^Instance_Batcher, kind: Instance_Kind, material: Material_Kind, instance_data: []u8) {
    if len(instance_data) == 0 {
        return
    }

    batcher.instance_data_offset = runtime.align_forward(batcher.instance_data_offset, 16)

    instance := Instance {
        kind = kind,
        material_idx = material,
        extra_data = u32(batcher.instance_data_offset),
    }

    // Write base instance data
    ([^]Instance)(batcher.instance_buffer.cpu)[batcher.instance_offset] = instance
    batcher.instance_offset += 1

    // Write aligned instance data
    dest := ([^]u8)(batcher.instance_data_buffer_blob.cpu)
    mem.copy(&dest[batcher.instance_data_offset], raw_data(instance_data), len(instance_data))
    batcher.instance_data_offset += len(instance_data)
}

finish_instance_upload :: proc() {
    gpu.unmap(&_state.instance_batcher.instance_buffer)
    gpu.unmap(&_state.instance_batcher.instance_data_buffer_blob)

    gpu.copy(_state._instances, _state.instance_batcher.instance_buffer)
    gpu.copy(_state._instances_data, _state.instance_batcher.instance_data_buffer_blob)

    // Needed for wgpu to start mapping again
    // gpu.recall(&batcher.instance_buffer)
    // gpu.recall(&batcher.instance_data_buffer_blob)
}

reset_batches :: proc(batcher: ^Instance_Batcher) {
    batcher.instance_offset      = 0
    batcher.instance_data_offset = 0
}


draw_instances :: proc() {

}

draw_mesh_builtin :: proc(mesh_type: Built_in_mesh, instance_count: u32 = 1, base_instance: u32 = 0) {

    mesh := get_built_in_mesh(mesh_type)

    gpu.draw_indiced_primitives(
        &_state.built_in_block,
        _state.index.ptr,
        mesh.index_count,
        mesh.index_base,
        instance_count,
        mesh.vertex_base,
        base_instance
    )
}

draw_mesh_ex :: proc(mesh: ^Mesh, parameter_block: ^gpu.Parameter_Block, instance_count: u32) {
    base_instance :u32= 0

    gpu.draw_indiced_primitives(
        parameter_block,
        _state.index.ptr,
        mesh.index_count,
        mesh.index_base,
        instance_count,
        mesh.vertex_base,
        base_instance
    )
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