package lo

import nuppu "../../.."
import gpu "../../../gpu"
import "core:mem"
import "core:fmt"
import "core:slice"

State :: struct {
    pso: gpu.Pipeline,

    index_gpu: gpu.ptr,
    vertices: gpu.ptr,
}

Vertex :: struct #align(16) {
    pos: [4]f32,
    color: [4]f32,
}

state: ^State

_init :: proc() {
when ODIN_OS == .Darwin {
    vertex_code := #load("triangle.vs.metal", []u8)
    fragment_code := #load("triangle.ps.metal", []u8)
}
when ODIN_OS == .JS {
    vertex_code := #load("triangle.wgsl", []u8)
    fragment_code := vertex_code 
}

    // Init resources
    shader_vs := gpu.shader_init("my_vert_shader", vertex_code)
    shader_ps := gpu.shader_init("my_frag_shader", fragment_code)

    vertex_shader := gpu.Shader_IR {
        shader = shader_vs,
        entry_point = "vertexMain",
    }

    fragment_shader := gpu.Shader_IR {
        shader = shader_ps,
        entry_point = "fragmentMain",
    }

    state.pso = gpu.pipeline_init(vertex_shader, fragment_shader, {
        color_format = .BGRA8Unorm,
    })

    NUM_VERTICES :: 3

    // Allocates single CPU writable buffer for staging
    upload := gpu.arena()
    //defer gpu.destroy_arena(&upload)

    // Moves upload scope's offset and returns CPU modifiable slice to put data into
    vertices := gpu.arena_alloc(&upload, Vertex, NUM_VERTICES)
    mem.copy_non_overlapping(vertices.cpu, &[NUM_VERTICES]Vertex{
        { pos = { -0.8,  0.8, 0.0, 1.0 }, color = { 1, 0, 0, 1 } },
        { pos = {  0.0, -0.8, 0.0, 1.0 }, color = { 0, 1, 0, 1 } },
        { pos = { +0.8,  0.8, 0.0, 1.0 }, color = { 0, 0, 1, 1 } },
    }, NUM_VERTICES * size_of(Vertex))

    indices := gpu.arena_alloc(&upload, u32, NUM_VERTICES)
    mem.copy_non_overlapping(indices.cpu, &[NUM_VERTICES]u32{ 0, 1, 2 }, NUM_VERTICES * size_of(u32))

    gpu.unmap(&upload.ptr)

    state.vertices = gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Vertex), align_of(Vertex), "Vertices buffer")
    state.index_gpu = gpu.malloc_index(NUM_VERTICES, .Uint32, "Indices buffer")

    gpu.begin_commands()
    gpu.copy(state.vertices, vertices)
    gpu.copy(state.index_gpu, indices)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()
    //

}

_update :: proc() {}

_render :: proc(previous, current: ^State, alpha: f32) {
    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })

    gpu.set_pipeline(current.pso)

    block := gpu.Parameter_Block {
        constants = {},
        read_resources = {0 = current.vertices},
        read_write_resources = {},
        samplers = {},
    }
    gpu.use_parameter_block(&block)

    gpu.draw_indiced_primitives(.Triangle, current.index_gpu, 3, 0, 1, 0, 0)

    gpu.end_render_pass()

    gpu.end_frame()
}

desc := nuppu.App_Desc(State) {
    state = &state,
    window_size = {1000, 1000},
    init = _init,
    update = _update,
    render = _render,
}

main :: proc() {
    nuppu.run(desc)
}
