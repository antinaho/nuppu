package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:mem"

State :: struct {
    angle: f32,

    pso: gpu.Pipeline_Handle,

    pos_gpu:   gpu.ptr,
    color_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    angle_buf: gpu.ptr,
}

Position :: [3]f32
Color :: [3]f32

// 16 bytes to match Metal `constant FrameData&` layout (pad to vec4 alignment).
FrameData :: struct #align(16) {
    angle: f32,
    _pad:  [3]f32,
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

    // Staging arena for one-time vertex upload + initial angle.
    upload := gpu.arena()

    positions := gpu.arena_alloc(&upload, Position, NUM_VERTICES)
    mem.copy_non_overlapping(positions.cpu, &[3]Position{
        { -0.8,  0.8, 0.0 },
        {  0.0, -0.8, 0.0 },
        { +0.8,  0.8, 0.0 },
    }, 3 * size_of(Position))

    colors := gpu.arena_alloc(&upload, Color, NUM_VERTICES)
    mem.copy_non_overlapping(colors.cpu, &[3]Color{
        { 1, 0, 0 },
        { 0, 1, 0 },
        { 0, 0, 1 },
    }, 3 * size_of(Color))

    indices := gpu.arena_alloc(&upload, u32, NUM_VERTICES)
    mem.copy_non_overlapping(indices.cpu, &[3]u32{ 0, 1, 2 }, 3 * size_of(u32))

    // Initial angle = 0.
    initial_fd := gpu.arena_alloc(&upload, FrameData, 1)
    (^FrameData)(initial_fd.cpu)^ = FrameData{angle = 0}

    gpu.unmap(&upload.ptr)

    // Allocate GPU buffers.
    state.pos_gpu   = gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Position), align_of(Position), "Positions")
    state.color_gpu = gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Color),    align_of(Color),    "Colors")
    state.index_gpu = gpu.malloc_index(NUM_VERTICES, .Uint32, "Indices")
    state.angle_buf = gpu.malloc(.GPU_Constant, 1, size_of(FrameData), align_of(FrameData), "Angle")

    // Upload all staging data in one command buffer.
    gpu.begin_frame_or_commands()
    gpu.copy(state.pos_gpu,   positions)
    gpu.copy(state.color_gpu, colors)
    gpu.copy(state.index_gpu, indices)
    gpu.copy(state.angle_buf, initial_fd)
    gpu.barrier(.Transfer, .All)
    gpu.commit()
}

_update :: proc() {
    state.angle += 0.0005
}

_render :: proc(previous, current: ^State, alpha: f32) {
    gpu.begin_frame_or_commands()
    frame_arena := gpu.frame_arena()

    fd := gpu.arena_alloc(frame_arena, FrameData, 1)
    (^FrameData)(fd.cpu)^ = FrameData{angle = current.angle}
    gpu.unmap(&frame_arena.ptr)
    gpu.copy(current.angle_buf, fd)
    
    gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })

    gpu.set_pipeline(current.pso)
    gpu.set_buffers({current.pos_gpu, current.color_gpu, current.angle_buf}, {0, 3}, .Vertex)
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
