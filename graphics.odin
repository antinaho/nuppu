package nuppu

import "core:math"
import "gpu"
import "bit_array"
import "base:intrinsics"
import "base:runtime"

#assert(size_of(Vertex) == 32)
Vertex :: struct #align(16) {
    position: [3]f32,
    uv:       [2]u16,

    color:    [4]u8,
    normal:   [3]f32,
}

Vertex_Index :: u16

Mesh :: struct #all_or_none {
    vertex_count:   u32,
    index_count:    u32,
    verts:          gpu.ptr,
    indices:        gpu.ptr,
}

Built_in_mesh :: enum {
    Quad,
    Cube,
}


@(require_results)
push_mesh_zeroed :: proc(
    vertex_count: u32,
    index_count: u32,
    loc := #caller_location,
) -> bit_array.Handle {

    handle := add_resource(&_state.meshes, Mesh {
        vertex_count = vertex_count,
        index_count = index_count,
        verts = gpu.arena_alloc(&_state.vertex, Vertex, uint(vertex_count)),
        indices = gpu.arena_alloc_raw(&_state.index, size_of(Vertex_Index), uint(index_count), 4)
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

draw_mesh :: proc(mesh: ^Mesh, instance_count: u32) {
    base_vertex := u32(mesh.verts.offset / size_of(Vertex))
    first_index := u32(mesh.indices.offset / size_of(Vertex_Index))

    gpu.draw_indiced_primitives(
    .Triangle,
    _state.index.ptr,
    mesh.index_count, first_index,
    instance_count,
    base_vertex, 0)
}

create_built_in_meshes :: proc() {
    
    {
        // Quad
        s :: 0.5
        VERTEX_COUNT :: 4
        INDEX_COUNT :: 6
        v := [VERTEX_COUNT]Vertex {
            pack_vertex( position = { -s, -s, 0 }),
            pack_vertex( position = { +s, -s, 0 }),
            pack_vertex( position = { +s, +s, 0 }),
            pack_vertex( position = { -s, +s, 0 }),    
        }
    
        i := [INDEX_COUNT]Vertex_Index {
            0, 1, 2, 2, 3, 0
        }

        upload := gpu.arena_init()
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
        VERTEX_COUNT :: 8
        INDEX_COUNT :: 36
        v := [VERTEX_COUNT]Vertex {
            pack_vertex( position = { -s, -s, +s }),
            pack_vertex( position = { +s, -s, +s }),
            pack_vertex( position = { +s, +s, +s }),
            pack_vertex( position = { -s, +s, +s }),
            pack_vertex( position = { -s, -s, -s }),
            pack_vertex( position = { -s, +s, -s }),
            pack_vertex( position = { +s, +s, -s }),
            pack_vertex( position = { +s, -s, -s }),    
        }

        i := [INDEX_COUNT]Vertex_Index {
            0, 1, 2, /* front */
            2, 3, 0,

            1, 7, 6, /* right */
            6, 2, 1,


            7, 4, 5, /* back */
            5, 6, 7,

            4, 0, 3, /* left */
            3, 5, 4,

            3, 2, 6, /* top */
            6, 5, 3,

            4, 7, 1, /* bottom */
            1, 0, 4  
        }

        upload := gpu.arena_init()
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
    _pad: u8,
}

pack_sprite_instance :: proc(
    position: [3]f32,
    color:    [4]f32,
    uv_min:   [2]f32,
    uv_size:  [2]f32,
    rotation: [3]f32,
    scale:    [2]f32,
) -> Sprite_Instance {
    return Sprite_Instance {
        position = position,
        color    = pack_color(color),
        uv_min   = {pack_float01(uv_min.x), pack_float01(uv_min.y)},
        uv_size  = {pack_float01(uv_size.x), pack_float01(uv_size.y)},
        scale    = {pack_scale_f32(scale.x), pack_scale_f32(scale.y)},
        turns    = {
            pack_radians_turn(rotation.x),
            pack_radians_turn(rotation.y),
            pack_radians_turn(rotation.z),
        },
        _pad     = 0,
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