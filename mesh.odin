#+vet unused shadowing using-param style semicolon cast explicit-allocators

package nuppu

import "gpu"
import "base:runtime"
import "base:intrinsics"
import "core:log"
import "core:fmt"

_ :: fmt
_ :: log


MESH_HANDLE_RAW :: u16
Mesh_Handle :: distinct Handle(MESH_HANDLE_RAW)
Mesh_Handle_Nil :: Mesh_Handle{}

MESH_INDEX_MASK :: (1 << 16) - 1

#assert(size_of(Vertex) == 32)
Vertex :: struct #align(16) {
    position: [3]f32,
    uv:       [2]u16,
    color:    [4]u8,
    normal:   [3]f32,
}

Vertex_Index :: u16

Mesh :: struct #all_or_none {
    vertex_count: uint,
    index_count:  uint,
    vertex_base:  uint, // offset into the global buffer 
    index_base:   uint, // offset into the global buffer
    
    verts:        gpu.ptr, // view into global
    indices:      gpu.ptr, // view into global
}

Mesh_Library :: struct {
    vertex_arena: gpu.Arena,
    index_arena:  gpu.Arena,

    built_in_lookup: [Built_In_Mesh]Mesh_Handle,

    table: Resource_Table(Mesh), // slot 0 is the nil sentinel

    __mesh_handles: [dynamic]Mesh_Handle, // debug-only, for leak reports
}

Built_In_Mesh :: enum u8 {
    Quad,
    Cube,
}


#assert(MAX_MESHES <= MESH_INDEX_MASK, "CONFIG.max_meshes must fit the index mask")

get_mesh :: proc(handle: Mesh_Handle) -> (mesh: ^Mesh, ok: bool) #optional_ok {
    idx := mesh_handle_unpack(handle)
    if idx == 0 { return nil, false }
    return resource_table_get(&_state.mesh_library.table, int(idx))
}

mesh_handle_unpack :: proc "contextless" (handle: Mesh_Handle) -> u16 { 
    return handle.handle & MESH_INDEX_MASK 
}

built_in_mesh_handle :: proc "contextless" (built_in_mesh: Built_In_Mesh) -> Mesh_Handle { 
    return _state.mesh_library.built_in_lookup[built_in_mesh] 
}

// Frees the mesh slot. The backing bytes stay in the global vertex/index arenas
// (they are bump-allocated and not reclaimed).
mesh_free :: proc(handle: Mesh_Handle) {
    lib := &_state.mesh_library
    if handle == lib.built_in_lookup[.Quad] || handle == lib.built_in_lookup[.Cube] {
        return
    }
    idx := mesh_handle_unpack(handle)
    if idx == 0 { return }
    mesh, ok := resource_table_get(&lib.table, int(idx))
    if !ok { return }

    mesh^ = {}
    resource_table_release(&lib.table, int(idx))

    when ODIN_DEBUG {
        for h, i in lib.__mesh_handles {
            if h == handle {
                unordered_remove(&lib.__mesh_handles, i)
                break
            }
        }
    }
}

NUPPU_mesh_library_init :: proc(lib: ^Mesh_Library, allocator := context.allocator) -> (err: runtime.Allocator_Error) {
    err = resource_table_init(&lib.table, MAX_MESHES, allocator)
    if err != nil { return }

    success: bool
    lib.vertex_arena, success = gpu.arena_init(VERTEX_STORAGE_BYTES, 256, usage = .Default)
    assert(success, "mesh_library_init: failed to init vertex arena")
    lib.index_arena, success = gpu.arena_init(INDEX_STORAGE_BYTES, usage = .Index)
    assert(success, "mesh_library_init: failed to init index arena")

    when ODIN_DEBUG {
        lib.__mesh_handles = make([dynamic]Mesh_Handle, 0, 64, context.allocator)
    }

    create_built_in_meshes()

    return
}

NUPPU_mesh_library_deinit :: proc(lib: ^Mesh_Library) {
    gpu.release_ptr(&lib.vertex_arena.ptr)
    gpu.release_ptr(&lib.index_arena.ptr)
    resource_table_destroy(&lib.table)

    when ODIN_DEBUG {
        delete(lib.__mesh_handles)
    }
    lib^ = {}
}

@(require_results)
register_mesh :: proc(lib: ^Mesh_Library, #any_int vertex_count: uint, #any_int index_count: uint, name: string = "", loc := #caller_location) -> Mesh_Handle {
    verts_view   := gpu.arena_alloc(&lib.vertex_arena, Vertex, uint(vertex_count))
    indices_view := gpu.arena_alloc_raw(&lib.index_arena, size_of(Vertex_Index), uint(index_count), 4)

    index, ok := resource_table_acquire(&lib.table)
    assert(ok, "register_mesh: out of mesh slots, raise CONFIG.max_meshes")

    lib.table.items[index] = Mesh {
        vertex_count = vertex_count,
        index_count  = index_count,
        vertex_base  = verts_view.byte_offset / size_of(Vertex),
        index_base   = indices_view.byte_offset / size_of(Vertex_Index),
        verts        = verts_view,
        indices      = indices_view,
    }

    handle := Mesh_Handle { handle = u16(index) }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
        append(&lib.__mesh_handles, handle)
    }

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
    mesh, mesh_ok := get_mesh(handle)
    assert(mesh_ok, "mesh_upload: registered mesh is not retrievable")

    upload, upload_ok := gpu.arena_init(
        u32(size_of(Vertex) * len(vertices) + size_of(Vertex_Index) * len(indices)),
    )
    assert(upload_ok, "mesh_upload: failed to allocate staging arena")

    verts := gpu.arena_alloc(&upload, Vertex, uint(len(vertices)))
    intrinsics.mem_copy_non_overlapping(verts.cpu, raw_data(vertices), size_of(Vertex) * len(vertices))
    idx := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), uint(len(indices)), 4)
    intrinsics.mem_copy_non_overlapping(idx.cpu, raw_data(indices), size_of(Vertex_Index) * len(indices))

    gpu.begin_commands()
    gpu.copy(mesh.verts, verts)
    gpu.copy(mesh.indices, idx)
    gpu.transfer_submit(&upload.ptr)

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

    upload, upload_ok := gpu.arena_init(4 * 1024 * 1024)
    assert(upload_ok, "create_built_in_meshes: failed to allocate staging arena")
    gpu.begin_commands()
    
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
        
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        
        indices := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), INDEX_COUNT, 4)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))
        
        quad_handle := register_mesh(&_state.mesh_library, VERTEX_COUNT, INDEX_COUNT, "builtin_quad")

        _state.mesh_library.built_in_lookup[.Quad] = quad_handle
        quad_mesh, quad_ok := get_mesh(quad_handle)
        assert(quad_ok, "create_built_in_meshes: quad mesh is not retrievable")

        gpu.copy(quad_mesh.verts, verts)
        gpu.copy(quad_mesh.indices, indices)
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

        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        
        indices := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), INDEX_COUNT, 4)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))

        cube_handle := register_mesh(&_state.mesh_library, VERTEX_COUNT, INDEX_COUNT, "builtin_cube")
        _state.mesh_library.built_in_lookup[.Cube] = cube_handle
        cube_mesh, cube_ok := get_mesh(cube_handle)
        assert(cube_ok, "create_built_in_meshes: cube mesh is not retrievable")

        gpu.copy(cube_mesh.verts, verts)
        gpu.copy(cube_mesh.indices, indices)
    }

    gpu.transfer_submit(&upload.ptr)

    return
}


