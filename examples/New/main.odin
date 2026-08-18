package lo

import nuppu "../../"
import gpu "../../gpu"
import "core:fmt"

State :: struct {
    pso: gpu.Resource,

    pos_gpu: gpu.ptr,
    color_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
}

state: ^State

_init :: proc() {
when ODIN_OS == .Darwin {
    shader_code := #load("triangle.metal", []u8)
}
when ODIN_OS == .JS {
    shader_code := #load("triangle.wgsl", []u8)
}
    shader := gpu.shader_init("my_vert_shader", shader_code)

    state.pso = gpu.pipeline_init(shader, "vertexMain", shader, "fragmentMain", .BGRA8Unorm)

    upload_arena := gpu.arena_init()

    NUM_VERTICES :: 3
    Position :: [3]f32
    Color :: [3]f32

    positions := gpu.arena_alloc(&upload_arena, Position, NUM_VERTICES)
    ps := []Position {
        { -0.8,  0.8, 0.0 },
        {  0.0, -0.8, 0.0 },
        { +0.8,  0.8, 0.0 },
    }
    gpu.ptr_fill_slice(&positions, ps)

    colors := gpu.arena_alloc(&upload_arena, Color, NUM_VERTICES)
    cs := []Color {
        { 1, 0, 0 },
        { 0, 1, 0 },
        { 0, 0, 1 },
    }
    gpu.ptr_fill_slice(&colors, cs)

    indices := gpu.arena_alloc(&upload_arena, u32, NUM_VERTICES)
    is := []u32 {
        0, 1, 2,
    }
    gpu.ptr_fill_slice(&indices, is)
    
    state.pos_gpu = gpu.buffer_init(size_of(Position) * NUM_VERTICES, align_of(Position), .GPU_Only)
    state.color_gpu = gpu.buffer_init(size_of(Color) * NUM_VERTICES, align_of(Color), .GPU_Only)
    state.index_gpu = gpu.buffer_init(size_of(u32) * NUM_VERTICES, align_of(u32), .GPU_Only)
    
    gpu.upload_one_shot({
        {&state.pos_gpu, positions, size_of(Position) * NUM_VERTICES},
        {&state.color_gpu, colors, size_of(Color) * NUM_VERTICES},
        {&state.index_gpu, indices, size_of(u32) * NUM_VERTICES},
    })
}

_update :: proc() {}

_render :: proc(previous, current: ^State, alpha: f32) {
    gpu.begin_frame()

    // color_rt
    // depth_rt

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color = {120, 10, 10, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })

    gpu.set_pipeline(current.pso)
    gpu.set_buffers({current.pos_gpu, current.color_gpu}, {0, 0}, {0, 2}, .Vertex)
    gpu.draw_primitives(.Triangle, current.index_gpu, 3, 0)

    gpu.end_render_pass()
    gpu.present(swapchain)

    defer gpu.end_frame()
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