package nuppu

Default_Renderer :: struct {
    mesh_data: GPU_Arena,
    vertex_data: GPU_Arena,
    index_data: GPU_Arena,
    instances_gpu: []ptr,
}

dr: ^Default_Renderer
MAX_INSTANCES :: 100

dr_init :: proc(frames_in_flight: int = 3) {
    dr = new(Default_Renderer)

    // Later take in T and count instead of bytes + align, but currently not API for that
    dr.mesh_data = gpu_arena_init(align=align_of(Mesh), mem=Memory.GPU_Only)
    dr.vertex_data = gpu_arena_init(mem=Memory.GPU_Only)
    dr.index_data = gpu_arena_init(mem=Memory.GPU_Only)

    dr.instances_gpu = make([]ptr, len=frames_in_flight)
    for I in 0 ..< frames_in_flight {
        dr.instances_gpu[I] = gpu_malloc(size_of(Instance), MAX_INSTANCES, Memory.GPU_Only)
    }
}

dr_deinit :: proc() {
    gpu_arena_deinit(&dr.mesh_data)
    gpu_arena_deinit(&dr.vertex_data)
    gpu_arena_deinit(&dr.index_data)
    for inst_buf in dr.instances_gpu {
        gpu_free(inst_buf)
    }
    delete(dr.instances_gpu)
    free(dr)
}

dr_push_mesh :: proc(verts: [][3]f32, indices: []u32) -> uint {
    vertex_gpu := gpu_arena_alloc(&dr.vertex_data, [3]f32, len(verts))
    index_gpu := gpu_arena_alloc(&dr.index_data, u32, len(indices))

    vertex_upload := gpu_malloc([3]f32, len(verts), Memory.CPU_GPU)
    index_upload := gpu_malloc(u32, len(indices), Memory.CPU_GPU)
    
    gpu_ptr_fill_slice(vertex_upload, verts)
    gpu_ptr_fill_slice(index_upload, indices)

    cmds := begin_commands()
    cmd_mem_copy(cmds, vertex_gpu, vertex_upload, u64(size_of([3]f32) * len(verts)))
    cmd_mem_copy(cmds, index_gpu, index_upload, u64(size_of(u32) * len(indices)))
    cmd_barrier(cmds, .Transfer, .All)
    end_commands(cmds, {})

    vertex_delta := vertex_gpu._buffer_offset - dr.vertex_data._buffer_offset
    index_delta := index_gpu._buffer_offset - dr.index_data._buffer_offset

    result := Mesh {
        vertex_range = {vertex_delta / size_of([3]f32), len(verts)},
        index_range = {index_delta / size_of(u32), len(indices)},
    }

    mesh_idx := dr.mesh_data.offset / size_of(Mesh)
    mesh_gpu := gpu_arena_alloc(&dr.mesh_data, Mesh, 1)
    mesh_upload := gpu_malloc(Mesh, 1, Memory.CPU_GPU)
    gpu_ptr_fill_slice(mesh_upload, []Mesh{result})

    cmds = begin_commands()
    cmd_mem_copy(cmds, mesh_gpu, mesh_upload, u64(size_of(Mesh)))
    cmd_barrier(cmds, .Transfer, .All)
    end_commands(cmds, {})
    
    return mesh_idx
}


Shader_Data :: struct {
    instances: ^Instance,
    meshes: ^Mesh,
    vertices: ^[3]f32,
}

Instance :: struct {
    transform: matrix[4, 4]f32,
    color: [4]f32,
    mesh_id: u32,
}

Mesh :: struct {
    vertex_range: Range,
    index_range: Range,
}
