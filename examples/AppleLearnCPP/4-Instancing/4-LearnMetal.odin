package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/linalg"

State :: struct {
    pso: gpu.Resource,

    pos_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,

    angle: f32,
}

Position :: [3]f32

INSTANCE_COUNT :: 32
Instance_Data :: struct #align(16) {
    transform: matrix[4, 4]f32,
    color: [4]f32
}

state: ^State

_init :: proc() {
when ODIN_OS == .Darwin {
    shader_code := #load("instancing.metal", []u8)
}
when ODIN_OS == .JS {
    shader_code := #load("instancing.wgsl", []u8)
}
    shader := gpu.shader_init("my_vert_shader", shader_code)

    state.pso = gpu.pipeline_init(shader, "vertexMain", shader, "fragmentMain", .BGRA8Unorm)

    NUM_VERTICES :: 4
    NUM_INDICES :: 6
    s :: 0.5

    upload_arena := gpu.arena_init()
    defer gpu.arena_deinit(&upload_arena)

    positions := gpu.arena_alloc(&upload_arena, Position, NUM_VERTICES)
    gpu.arena_copy(positions, []Position{
        { -s, -s, +s },
        { +s, -s, +s },
        { +s, +s, +s },
        { -s, +s, +s },
    })
    
    indices := gpu.arena_alloc(&upload_arena, u32, NUM_INDICES)
    gpu.arena_copy(indices, []u32{
        0, 1, 2, 
        2, 3, 0,
    })
    
    gpu.arena_upload_stop(&upload_arena)
    
    state.pos_gpu = gpu.buffer_init(size_of(Position) * NUM_VERTICES, align_of(Position), .GPU_Only)
    state.index_gpu = gpu.buffer_init(size_of(u32) * NUM_INDICES, align_of(u32), .GPU_Only)
    
    state.instance_gpu = gpu.buffer_init(INSTANCE_COUNT * size_of(Instance_Data), align_of(Instance_Data), .GPU_Only)

    gpu.begin_frame_or_commands()
    gpu.mem_copy(state.pos_gpu, positions, size_of(Position) * NUM_VERTICES)
    gpu.mem_copy(state.index_gpu, indices, size_of(u32) * NUM_INDICES)
    gpu.barrier(.Transfer, .All)
    gpu.commit()
}

_update :: proc() {
    state.angle += 0.0019
}

_render :: proc(previous, current: ^State, alpha: f32) {
    gpu.begin_frame_or_commands()
    scl :: 0.12


when gpu.GPU_BACKEND == gpu.GPU_BACKEND_WGPU {
    frame_arena := gpu.frame_arena()
     defer gpu.frame_arena_deinit(frame_arena) 
    instances := gpu.arena_alloc(frame_arena, Instance_Data, INSTANCE_COUNT)

    for &isnt, idx in ([^]Instance_Data)(instances.cpu)[:INSTANCE_COUNT] {
        i := f32(idx) / f32(INSTANCE_COUNT)
        x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
        y_off := math.sin((i + current.angle) * 2 * math.PI)
        isnt.transform = linalg.transpose(matrix[4, 4]f32{
            scl * math.sin(current.angle), scl * math.cos(current.angle), 0, 0,
            scl * math.cos(current.angle), -scl * math.sin(current.angle), 0, 0,
            0, 0, scl, 0,
            x_off, y_off, 0, 1
        })
        isnt.color = [4]f32{i, 1 - i, math.sin(math.PI * i), 1}
    }

    gpu.arena_upload_stop(frame_arena)
   

    gpu.mem_copy(current.instance_gpu, instances, size_of(Instance_Data) * INSTANCE_COUNT)
}

    // instances_staging := gpu.buffer_init(size_of(Instance_Data) * INSTANCE_COUNT, align_of(Instance_Data), .CPU_GPU)
    // instances_array := slice.from_ptr((^Instance_Data)(instances_staging.cpu), INSTANCE_COUNT)
    // 
    // for &isnt, idx in instances_array {
    //     i := f32(idx) / f32(INSTANCE_COUNT)
    //     x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
    //     y_off := math.sin((i + current.angle) * 2 * math.PI)
    //     isnt.transform = linalg.transpose(matrix[4, 4]f32{
    //         scl * math.sin(current.angle), scl * math.cos(current.angle), 0, 0,
    //         scl * math.cos(current.angle), -scl * math.sin(current.angle), 0, 0,
    //         0, 0, scl, 0,
    //         x_off, y_off, 0, 1
    //     })
    //     isnt.color = [4]f32{i, 1 - i, math.sin(math.PI * i), 1}
    // }

    // gpu.mem_copy(current.instance_gpu, instances_staging, size_of(Instance_Data) * INSTANCE_COUNT)
    // gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })

    gpu.set_pipeline(current.pso)

    gpu.set_buffers({current.pos_gpu, current.instance_gpu}, {0, 0}, {0, 2}, .Vertex)

    gpu.draw_indiced_primitives(
    .Triangle,
    current.index_gpu,
    6, 0,
    INSTANCE_COUNT,
    0, 0)

    gpu.end_render_pass()
    gpu.commit()

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
