package nuppu

import "core:container/handle_map"

Default_Renderer :: struct {
    mesh_data: GPU_Arena,
    
    vertex_positions_data: GPU_Arena,
    vertex_normals_data: GPU_Arena,
    vertex_uvs_data: GPU_Arena,
    
    instance_arena: GPU_Arena,
    instances_gpu: []ptr,
    
    index_data: GPU_Arena,

    meshes: Resource_Library(128, Mesh_Impl, Mesh_Handle),
    slot_to_mesh: [128]Mesh,

    instances_dirty: bool,
}

Mesh_Impl :: struct {
    slot_in_buffer: u32,
    mesh: Mesh,
}
Mesh_Handle :: handle_map.Handle16

dr: ^Default_Renderer
MAX_INSTANCES :: 10_000

dr_init :: proc() {
    dr = new(Default_Renderer)

    resource_library_init(&dr.meshes)
    // Later take in T and count instead of bytes + align, but currently not API for that
    dr.mesh_data = gpu_arena_init(align=align_of(Mesh), mem=Memory.GPU_Only)
    
    dr.vertex_positions_data = gpu_arena_init(mem=Memory.GPU_Only)
    dr.vertex_uvs_data = gpu_arena_init(mem=Memory.GPU_Only)
    dr.vertex_normals_data = gpu_arena_init(mem=Memory.GPU_Only)

    dr.index_data = gpu_arena_init(mem=Memory.GPU_Only)

    dr.instance_arena = gpu_arena_init(align=align_of(Instance), mem=Memory.GPU_Only)
    dr.instances_gpu = make([]ptr, len=RENDER_FRAMES_IN_FLIGHT)
    for I in 0 ..< RENDER_FRAMES_IN_FLIGHT {
        dr.instances_gpu[I] = gpu_arena_alloc(&dr.instance_arena, Instance, MAX_INSTANCES) 
    }
}

dr_deinit :: proc() {
    gpu_arena_deinit(&dr.mesh_data)
    
    gpu_arena_deinit(&dr.vertex_positions_data)
    gpu_arena_deinit(&dr.vertex_uvs_data)
    gpu_arena_deinit(&dr.vertex_normals_data)

    gpu_arena_deinit(&dr.index_data)
    
    gpu_arena_deinit(&dr.instance_arena)
    
    delete(dr.instances_gpu)
    free(dr)
}

dr_push_mesh :: proc(verts: []Vertex_Position, indices: []u32, uvs: []Vertex_UV, normals: []Vertex_Normal) -> Mesh_Handle {
    dr.instances_dirty = true

    vertex_pos_gpu := gpu_arena_alloc(&dr.vertex_positions_data, Vertex_Position, len(verts))
    vertex_pos_upload := gpu_malloc(Vertex_Position, len(verts), Memory.CPU_GPU)
    gpu_ptr_fill_slice(vertex_pos_upload, verts)

    vertex_uv_gpu := gpu_arena_alloc(&dr.vertex_uvs_data, Vertex_UV, len(uvs))
    vertex_uv_upload := gpu_malloc(Vertex_UV, len(uvs), Memory.CPU_GPU)
    gpu_ptr_fill_slice(vertex_uv_upload, uvs)

    index_gpu := gpu_arena_alloc(&dr.index_data, u32, len(indices))
    index_upload := gpu_malloc(u32, len(indices), Memory.CPU_GPU)
    gpu_ptr_fill_slice(index_upload, indices)

    normal_gpu := gpu_arena_alloc(&dr.vertex_normals_data, Vertex_Normal, len(normals))
    normal_upload := gpu_malloc(Vertex_Normal, len(normals), Memory.CPU_GPU)
    gpu_ptr_fill_slice(normal_upload, normals)

    cmds := begin_commands()
    cmd_mem_copy(cmds, vertex_pos_gpu, vertex_pos_upload, u64(size_of(Vertex_Position) * len(verts)))
    cmd_mem_copy(cmds, vertex_uv_gpu, vertex_uv_upload, u64(size_of(Vertex_UV) * len(uvs)))
    cmd_mem_copy(cmds, index_gpu, index_upload, u64(size_of(u32) * len(indices)))
    cmd_mem_copy(cmds, normal_gpu, normal_upload, u64(size_of(Vertex_Normal) * len(normals)))
    cmd_barrier(cmds, .Transfer, .All)
    end_commands(cmds, {})

    vertex_pos_delta := vertex_pos_gpu._buffer_offset - dr.vertex_positions_data._buffer_offset
    vertex_uv_delta := vertex_uv_gpu._buffer_offset - dr.vertex_uvs_data._buffer_offset
    vertex_normal_delta := normal_gpu._buffer_offset - dr.vertex_normals_data._buffer_offset
    index_delta := index_gpu._buffer_offset - dr.index_data._buffer_offset

    result := Mesh {
        vertex_position_range = {u32(vertex_pos_delta / size_of(Vertex_Position)), u32(len(verts))},
        vertex_uv_range = {u32(vertex_uv_delta / size_of(Vertex_UV)), u32(len(uvs))},
        vertex_normal_range = {u32(vertex_normal_delta / size_of(Vertex_Normal)), u32(len(normals))},
        index_range = {u32(index_delta / size_of(u32)), u32(len(indices))},
    }

    gpu_slot := dr.mesh_data.offset / size_of(Mesh)
    dr.slot_to_mesh[gpu_slot] = result

    mesh_gpu := gpu_arena_alloc(&dr.mesh_data, Mesh, 1)
    mesh_upload := gpu_malloc(Mesh, 1, Memory.CPU_GPU)
    gpu_ptr_fill_slice(mesh_upload, []Mesh{result})

    handle := resource_library_add(&dr.meshes, Mesh_Impl {
        slot_in_buffer = u32(gpu_slot),
        mesh = result,
    }, {})

    cmds = begin_commands()
    cmd_mem_copy(cmds, mesh_gpu, mesh_upload, u64(size_of(Mesh)))
    cmd_barrier(cmds, .Transfer, .All)
    end_commands(cmds, {})

    return handle
}

random_array :: proc(N: int, rng: proc() -> $T, allocator := context.temp_allocator) -> []T {
    arr := make([]T, len=N, allocator=allocator)
    for i in 0..<N {
        arr[i] = rng()
    }
    return arr
}

_pack_color :: proc(c: Color) -> u32 {
    return u32(c.r) << 24 | u32(c.g) << 16 | u32(c.b) << 8 | u32(c.a)
}

pack_color :: proc(r, g, b, a: f32) -> u32 {
    return u32(f32(r) * 255) << 24 | u32(f32(g) * 255) << 16 | u32(f32(b) * 255) << 8 | u32(f32(a) * 255)
}

_depack_color :: proc(c: u32) -> Color {
    return Color {
        u8(c >> 24 & 0xFF),
        u8(c >> 16 & 0xFF),
        u8(c >> 8 & 0xFF),
        u8(c & 0xFF),
    }
}

depack_color :: proc(c: u32) -> [4]f32 {
    return [4]f32 {
        f32(c >> 24 & 0xFF) / 255,
        f32(c >> 16 & 0xFF) / 255,
        f32(c >> 8 & 0xFF) / 255,
        f32(c & 0xFF) / 255,
    }
}

Vertex_Position :: [3]f32
Vertex_UV :: [2]f32
Vertex_Normal :: [3]f32

Shader_Data :: struct #align(16) #all_or_none {
    instances: ^Instance,
    meshes: ^Mesh,
    vertex_positions: ^Vertex_Position,
    vertex_uvs: ^Vertex_UV,
    vertex_normals: ^Vertex_Normal,
}

Instance :: struct #align(16) {
    transform: matrix[4, 4]f32,
    mesh_id: u32,
}

Mesh :: struct #align(16) {
    vertex_position_range: Range,
    vertex_normal_range: Range,
    vertex_uv_range: Range,
    index_range: Range,
}
