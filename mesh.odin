#+vet unused shadowing using-param style semicolon cast explicit-allocators

package nuppu

import "gpu"
import "bit_array"
import "base:intrinsics"
import "core:log"
import "core:mem"

_ :: log

Mesh_Handle     :: Handle(bit_array.Handle)
Mesh_Handle_Nil :: Mesh_Handle{}

VERTEX_BLOB_SIZE :: 16 * mem.Megabyte
GLOBAL_INDEX_COUNT_MAX :: (1 << 16) - 1

#assert(size_of(Vertex) == 32)
Vertex :: struct #align(16) {
    position: [3]f32,
    uv:       [2]u16,
    color:    [4]u8,
    normal:   [3]f32,
}

// Currently forcing u16
Vertex_Index :: u16

Mesh :: struct #all_or_none {
    vertex_count: u32,
    index_count:  u32,
    vertex_base:  u32, // offset into the global buffer 
    index_base:   u32, // offset into the global buffer
    
    verts:        gpu.ptr, // view into global
    indices:      gpu.ptr, // view into global
}

Built_In_Mesh :: enum u8 {
    Quad,
    Cube,
}

Mesh_Library :: struct {
    vertex_arena: gpu.Arena,
    index_arena:  gpu.Arena,

    built_in_lookup: [Built_In_Mesh]Mesh_Handle,

    meshes: bit_array.Bit_Array(Resource(Mesh, Mesh_Handle), u64(CONFIG.max_meshes), Mesh_Handle),
}

mesh_library_init :: proc(lib: ^Mesh_Library) {
    bit_array.init(&lib.meshes)

    lib.vertex_arena, _ = gpu.arena_init(VERTEX_BLOB_SIZE, 256, flags = .Default)
    lib.index_arena, _ = gpu.arena_init(size_of(Vertex_Index) * GLOBAL_INDEX_COUNT_MAX, flags = .Index)

    create_built_in_meshes()
}

@(require_results)
register_mesh :: proc(lib: ^Mesh_Library, vertex_count: u32, index_count: u32, name: string = "", loc := #caller_location) -> Mesh_Handle {
    verts_view   := gpu.arena_alloc(&lib.vertex_arena, Vertex, uint(vertex_count))
    indices_view := gpu.arena_alloc_raw(&lib.index_arena, size_of(Vertex_Index), uint(index_count), 4)

    handle := add_resource(&lib.meshes, Mesh {
        vertex_count = vertex_count,
        index_count  = index_count,
        vertex_base  = verts_view.byte_offset / size_of(Vertex),
        index_base   = indices_view.byte_offset / size_of(Vertex_Index),
        verts        = verts_view,
        indices      = indices_view,
    }, name, loc)

    return handle
}

// Registers a mesh and uploads its vertex + index data in one call. The data is
// staged through a temporary host-visible arena and copied into the global
// device-local mesh arenas.
@(require_results)
mesh_upload :: proc(
    vertices: []Vertex,
    indices:  []Vertex_Index,
    name:     string = "",
    loc := #caller_location,
) -> Mesh_Handle {
    lib := &_state.mesh_library

    handle := register_mesh(lib, u32(len(vertices)), u32(len(indices)), name, loc)
    mesh, ok := get_resource(&lib.meshes, handle)
    assert(ok, "mesh_upload: failed to resolve registered mesh")

    upload, _ := gpu.arena_init(
        u32(size_of(Vertex) * len(vertices) + size_of(Vertex_Index) * len(indices)),
    )

    verts := gpu.arena_alloc(&upload, Vertex, uint(len(vertices)))
    intrinsics.mem_copy_non_overlapping(verts.cpu, raw_data(vertices), size_of(Vertex) * len(vertices))
    idx := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), uint(len(indices)), 4)
    intrinsics.mem_copy_non_overlapping(idx.cpu, raw_data(indices), size_of(Vertex_Index) * len(indices))

    gpu.begin_commands()
    gpu.copy(mesh.verts, verts)
    gpu.copy(mesh.indices, idx)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()

    gpu.release_ptr(&upload.ptr)

    return handle
}

@(require_results)
pack_vertex :: proc(
    position: [3]f32,
    uv:       [2]f32 = {0, 0},
    normal:   [3]f32 = {0, 1, 0},
    color:    [4]u8  = {255, 255, 255, 255},
) -> Vertex {
    return Vertex {
        position = position,
        uv =       [2]u16{pack_float01(uv.x), pack_float01(uv.y)},
        color =    color,
        normal =   normal,
    }
}


create_built_in_meshes :: proc() {
    // Quad
    {
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
            0, 1, 2, 2, 3, 0,
        }

        upload, _ := gpu.arena_init(size_of(Vertex) * VERTEX_COUNT + size_of(Vertex_Index) * INDEX_COUNT)
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        indices := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), INDEX_COUNT, 4)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))

        quad_handle := register_mesh(&_state.mesh_library, VERTEX_COUNT, INDEX_COUNT, "builtin_quad")
        _state.mesh_library.built_in_lookup[.Quad] = quad_handle
        quad_mesh, _ := get_resource(&_state.mesh_library.meshes, quad_handle)

        gpu.begin_commands()
        gpu.copy(quad_mesh.verts, verts)
        gpu.copy(quad_mesh.indices, indices)
        gpu.barrier(.Transfer, .All)
        gpu.commit_commands()
        gpu.release_ptr(&upload.ptr)
    }

    // Cube
    {
        s :: 0.5
        VERTEX_COUNT :: 24
        INDEX_COUNT :: 36
        v := [VERTEX_COUNT]Vertex {
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 0 }, normal = {  0,  0, +1 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 0 }, normal = {  0,  0, +1 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 1 }, normal = {  0,  0, +1 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 0, 1 }, normal = {  0,  0, +1 } ),

            pack_vertex( position = { +s, -s, +s }, uv = { 0, 0 }, normal = { +1,  0,  0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 }, normal = { +1,  0,  0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 }, normal = { +1,  0,  0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 0, 1 }, normal = { +1,  0,  0 } ),

            pack_vertex( position = { +s, -s, -s }, uv = { 0, 0 }, normal = {  0,  0, -1 } ),
            pack_vertex( position = { -s, -s, -s }, uv = { 1, 0 }, normal = {  0,  0, -1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 1, 1 }, normal = {  0,  0, -1 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 0, 1 }, normal = {  0,  0, -1 } ),

            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 }, normal = { -1,  0,  0 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 1, 0 }, normal = { -1,  0,  0 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 1, 1 }, normal = { -1,  0,  0 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 }, normal = { -1,  0,  0 } ),

            pack_vertex( position = { -s, +s, +s }, uv = { 0, 0 }, normal = {  0, +1,  0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 0 }, normal = {  0, +1,  0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 }, normal = {  0, +1,  0 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 }, normal = {  0, +1,  0 } ),

            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 }, normal = {  0, -1,  0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 }, normal = {  0, -1,  0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 1 }, normal = {  0, -1,  0 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 1 }, normal = {  0, -1,  0 } ),
        }

        i := [INDEX_COUNT]Vertex_Index {
              0,  1,  2,  2,  3,  0,
              4,  5,  6,  6,  7,  4,
              8,  9, 10, 10, 11,  8,
             12, 13, 14, 14, 15, 12,
             16, 17, 18, 18, 19, 16,
             20, 21, 22, 22, 23, 20,
        }

        upload, _ := gpu.arena_init(size_of(Vertex) * VERTEX_COUNT + size_of(Vertex_Index) * INDEX_COUNT)
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        
        indices := gpu.arena_alloc(&upload, Vertex_Index, INDEX_COUNT)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))

        cube_handle := register_mesh(&_state.mesh_library, VERTEX_COUNT, INDEX_COUNT, "builtin_cube")
        _state.mesh_library.built_in_lookup[.Cube] = cube_handle
        cube_mesh, _ := get_resource(&_state.mesh_library.meshes, cube_handle)

        gpu.begin_commands()
        gpu.copy(cube_mesh.verts, verts)
        gpu.copy(cube_mesh.indices, indices)
        gpu.barrier(.Transfer, .All)
        gpu.commit_commands()
        gpu.release_ptr(&upload.ptr)
    }
}