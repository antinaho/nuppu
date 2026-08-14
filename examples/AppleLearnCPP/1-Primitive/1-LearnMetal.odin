package main

import nuppu "../../../"
import "core:fmt"
import "core:log"
import "core:math"
import "core:time"
import "core:path/filepath"
import "core:os"

basic_app: ^Basic

Basic :: struct {
    v_shader: nuppu.Shader,
    f_shader: nuppu.Shader,

    positions_gpu: nuppu.ptr,
    colors_gpu: nuppu.ptr,

    pipeline: nuppu.Pipeline,
}

init :: proc() {
    basic_app.v_shader = nuppu.shader_init(#load("1-primitive.metal", []u8), "vertexMain", .Vertex)
    basic_app.f_shader = nuppu.shader_init(#load("1-primitive.metal", []u8), "fragmentMain", .Fragment)

    basic_app.pipeline = nuppu.pipeline_init(basic_app.v_shader, basic_app.f_shader, {.BGRA8Unorm_sRGB}, .Invalid)

    upload_arena := nuppu.gpu_arena_init()
    defer nuppu.gpu_arena_deinit(&upload_arena)

    NUM_VERTICES :: 3
    Position :: [3]f32
    Color :: [3]f32

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

    basic_app.positions_gpu = nuppu.__gpu_malloc_bytes(size_of(Position) * NUM_VERTICES, align_of(Position), .GPU_Only)
    basic_app.colors_gpu = nuppu.__gpu_malloc_bytes(size_of(Color) * NUM_VERTICES, align_of(Color), .GPU_Only)

    cmds := nuppu.begin_commands()
    nuppu.cmd_mem_copy(cmds, basic_app.positions_gpu, positions, size_of(Position) * NUM_VERTICES)
    nuppu.cmd_mem_copy(cmds, basic_app.colors_gpu, colors, size_of(Color) * NUM_VERTICES)
    nuppu.cmd_barrier(cmds, .Transfer, .All)
    nuppu.end_commands(cmds, {})
}

deinit :: proc() {
    nuppu.shader_deinit(basic_app.v_shader)
    nuppu.shader_deinit(basic_app.f_shader)

    nuppu.pipeline_deinit(basic_app.pipeline)

    nuppu.gpu_free(basic_app.positions_gpu)
    nuppu.gpu_free(basic_app.colors_gpu)
}

render :: proc(prev, curr: Basic, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {

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

    nuppu.cmd_set_pipeline(cmds, basic_app.pipeline)

    nuppu.cmd_set_buffers(cmds, {basic_app.positions_gpu, basic_app.colors_gpu}, {0, 0}, {0, 2}, .Vertex)
    nuppu.cmd_draw_primitives(cmds, .Triangle, 3)

    nuppu.cmd_end_render_pass(cmds)
    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc(Basic) {
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
        &basic_app,
        config
    )
}