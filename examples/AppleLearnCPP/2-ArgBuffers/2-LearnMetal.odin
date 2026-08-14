package main

import nuppu "../../../"
import "core:fmt"
import "core:log"
import "core:math"
import "core:time"
import "core:path/filepath"
import "core:os"


window_app: ^Window

Window :: struct {
    number: [2]f32,

    v_shader: nuppu.Shader,
    f_shader: nuppu.Shader,

    positions_gpu: nuppu.ptr,
    colors_gpu: nuppu.ptr,

    pipeline: nuppu.Pipeline,

    argument_buffer: nuppu.ptr,
}

Position :: [3]f32
Color :: [3]f32

init :: proc() {
    window_app.v_shader = nuppu.shader_init(#load("2-argbuffers.metal", []u8), "vertexMain", .Vertex)
    window_app.f_shader = nuppu.shader_init(#load("2-argbuffers.metal", []u8), "fragmentMain", .Fragment)

    window_app.pipeline = nuppu.pipeline_init(window_app.v_shader, window_app.f_shader, {.BGRA8Unorm_sRGB}, .Invalid)

    upload_arena := nuppu.gpu_arena_init()
    defer nuppu.gpu_arena_deinit(&upload_arena)

    NUM_VERTICES :: 3


    positions := nuppu.gpu_arena_alloc(&upload_arena, Position, NUM_VERTICES)
    ps := []Position {
        { -0.8,  0.8, 0.0 },
        {  0.0, -0.8, 0.0 },
        { +0.8,  0.8, 0.0 },
    }
    nuppu.gpu_ptr_fill_slice(positions, ps)

    colors := nuppu.gpu_arena_alloc(&upload_arena, Color, NUM_VERTICES)
    cs := []Color {
        { 1, 0, 0 },
        { 0, 1, 0 },
        { 0, 0, 1 },
    }
    nuppu.gpu_ptr_fill_slice(colors, cs)

    window_app.positions_gpu = nuppu.__gpu_malloc_bytes(size_of(Position) * NUM_VERTICES, align_of(Position), .GPU_Only)
    window_app.colors_gpu = nuppu.__gpu_malloc_bytes(size_of(Color) * NUM_VERTICES, align_of(Color), .GPU_Only)

    cmds := nuppu.begin_commands()
    nuppu.cmd_mem_copy(cmds, window_app.positions_gpu, positions, size_of(Position) * NUM_VERTICES)
    nuppu.cmd_mem_copy(cmds, window_app.colors_gpu, colors, size_of(Color) * NUM_VERTICES)
    nuppu.cmd_barrier(cmds, .Transfer, .All)
    nuppu.end_commands(cmds, {})

    window_app.argument_buffer = nuppu.__gpu_malloc_bytes(size_of(Buffer_Data), align_of(Buffer_Data), .CPU_GPU)
    (^Buffer_Data)(window_app.argument_buffer.cpu)^ = Buffer_Data {
        positions = (^Position)(window_app.positions_gpu.gpu),
        colors = (^Color)(window_app.colors_gpu.gpu),
    }

    // Argument buffer approach without using pointers. Prefer pointer approach if possible.
    // window_app.argument_buffer = nuppu.__MTL_argument_buffer_init(window_app.v_shader, 0, {
    //     {window_app.positions_gpu, 0},
    //     {window_app.colors_gpu, 1}
    // })
}

Buffer_Data :: struct {
    positions: ^Position,
    colors: ^Color,
}

deinit :: proc() {
    nuppu.shader_deinit(window_app.v_shader)
    nuppu.shader_deinit(window_app.f_shader)

    nuppu.pipeline_deinit(window_app.pipeline)

    nuppu.gpu_free(window_app.positions_gpu)
    nuppu.gpu_free(window_app.colors_gpu)
    nuppu.gpu_free(window_app.argument_buffer)
}

render :: proc(prev, curr: Window, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {

    cmds := nuppu.begin_commands()
    swapchain := nuppu.acquire_next_swapchain(cmds)

    nuppu.cmd_begin_render_pass(cmds, {
        {
            clear_color = {64, 128, 255, 255},
            load_action = .Clear,
            store_action = .Store,
            texture = swapchain,
        }
    })

    nuppu.cmd_set_pipeline(cmds, window_app.pipeline)

    nuppu.cmd_use_resources(cmds, {
        {window_app.positions_gpu, {.Read}, {.Vertex}},
        {window_app.colors_gpu, {.Read}, {.Vertex}},
    })
    nuppu.cmd_set_buffer(cmds, window_app.argument_buffer, 0, .Vertex)
    nuppu.cmd_draw_primitives(cmds, 
        .Triangle,
        3
    )

    nuppu.cmd_end_render_pass(cmds)
    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc(Window) {
    init = init,
    deinit = deinit,
    render = render,
}

config :: nuppu.App_Config {
    window_size = [2]i32{1280, 720},
    window_title = "Window",
}

main :: proc() {
    nuppu.app_init(
        _desc,
        &window_app,
        config
    )
}