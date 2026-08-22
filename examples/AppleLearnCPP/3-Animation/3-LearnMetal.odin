package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:slice"
import "core:fmt"

State :: struct {
    angle: f32,

    pso: gpu.Resource,

    pos_gpu: gpu.ptr,
    color_gpu: gpu.ptr,
    index_gpu: gpu.ptr,

    // Metal
    by_ptr_buffer: gpu.ptr,

    // WGPU
    angle_buffer: gpu.ptr,
}

Position :: [3]f32
Color :: [3]f32
Buffer_Data :: struct {
    positions: ^Position,
    colors: ^Color,
}
FrameData :: struct {
    angle: f32,
}

state: ^State

_init :: proc() {
when ODIN_OS == .Darwin {
    shader_code := #load("animation.metal", []u8)
}
when ODIN_OS == .JS {
    shader_code := #load("animation.wgsl", []u8)
}

    shader := gpu.shader_init("my_vert_shader", shader_code)
    state.pso = gpu.pipeline_init(shader, "vertexMain", shader, "fragmentMain", .BGRA8Unorm)

    NUM_VERTICES :: 3

    upload := gpu.upload_arena() 
    defer gpu.destroy_arena(&upload)

    // Moves upload scope's offset and returns CPU modifiable slice to put data into
    positions := gpu.arena_alloc(&upload, Position, NUM_VERTICES) 
    copy(positions, []Position {
        { -0.8,  0.8, 0.0 },
        {  0.0, -0.8, 0.0 },
        { +0.8,  0.8, 0.0 },
    })

    colors := gpu.arena_alloc(&upload, Color, NUM_VERTICES)
    copy(colors, []Color{
        { 1, 0, 0 },
        { 0, 1, 0 },
        { 0, 0, 1 },
    })

    indices := gpu.arena_alloc(&upload, u32, NUM_VERTICES)
    copy(indices, []u32{ 0, 1, 2 })

    
    gpu.begin_frame_or_commands()
    state.pos_gpu   = gpu.promote(&upload, positions) 
    state.color_gpu = gpu.promote(&upload, colors)
    state.index_gpu = gpu.promote(&upload, indices, .Index)
    gpu.barrier(.Transfer, .All)
    gpu.commit()
    
    // WGPU constant buffer creation, on Metal we can use temp_malloc
    state.angle_buffer = gpu.buffer(f32, 1, .GPU, .Constant)

    // METAL
    state.by_ptr_buffer = gpu.buffer(Buffer_Data, 1, .Default, .Default)
    (^Buffer_Data)(state.by_ptr_buffer.cpu)^ = Buffer_Data {
        positions = (^Position)(state.pos_gpu.gpu),
        colors = (^Color)(state.color_gpu.gpu),
    }
}

_update :: proc() {
    state.angle += 0.0005
}

_render :: proc(previous, current: ^State, alpha: f32) {
    gpu.begin_frame_or_commands()
    frame_arena := gpu.frame_arena()

    swapchain := gpu.acquire_next_swapchain()
    
when gpu.GPU_BACKEND == gpu.GPU_BACKEND_WGPU {
    angle := gpu.arena_alloc(frame_arena, [4]f32, 1)
    copy(angle, [][4]f32{
        {current.angle, 0, 0, 0},
    }
    )

    gpu.move(frame_arena, angle, current.angle_buffer, 0)

    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })
    
    gpu.set_buffers({current.pos_gpu, current.color_gpu, current.angle_buffer}, {0, 0, 0}, {0, 3}, .Vertex)
}
else when gpu.GPU_BACKEND == gpu.GPU_BACKEND_METAL {
    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })

    frame_data := FrameData { angle = current.angle }

    gpu.temp_malloc(slice.bytes_from_ptr(&frame_data, size_of(FrameData)), 1, .Vertex)

    gpu.use_resources({
        {current.pos_gpu, {.Read}, {.Vertex}},
        {current.color_gpu, {.Read}, {.Vertex}},
    })

    gpu.set_buffers({current.by_ptr_buffer}, {0}, {0, 1}, .Vertex)
}

    gpu.set_pipeline(current.pso)
    gpu.draw_indiced_primitives(.Triangle, current.index_gpu, 3, 0, 1, 0, 0)

    gpu.end_render_pass()
    gpu.commit()

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
