package lo

import nuppu "../../.."
import gpu "../../../gpu"
import "core:mem"

State :: struct {
    pso: gpu.Pipeline_Handle,

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

    // Init resources
    shader := gpu.shader_init("my_vert_shader", shader_code)
    state.pso = gpu.pipeline_init(shader, "vertexMain", shader, "fragmentMain", .BGRA8Unorm)

    NUM_VERTICES :: 3
    Position :: [3]f32
    Color :: [3]f32

    // Allocates single CPU writable buffer for staging
    upload := gpu.arena()
    //defer gpu.destroy_arena(&upload)

    // Moves upload scope's offset and returns CPU modifiable slice to put data into
    positions := gpu.arena_alloc(&upload, Position, NUM_VERTICES) 
    mem.copy_non_overlapping(positions.cpu, &[3]Position {
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

    gpu.unmap(&upload.ptr)

    state.pos_gpu   = gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Position), align_of(Position), "Positions buffer")
    state.color_gpu = gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Color),    align_of(Color),    "Colors buffer")
    state.index_gpu = gpu.malloc_index(NUM_VERTICES, .Uint32, "Indices buffer")

    gpu.begin_commands()
    gpu.copy(state.pos_gpu, positions)
    gpu.copy(state.color_gpu, colors)
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
    gpu.set_buffers({current.pos_gpu, current.color_gpu}, {0, 2}, .Vertex)
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