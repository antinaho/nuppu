package main

import nuppu "../../"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:time"
import "core:path/filepath"
import "core:slice"
import "core:os"

window_app: ^Window

Window :: struct {
    number: [2]f32,

    v_shader: nuppu.Shader,
    f_shader: nuppu.Shader,

    vertex_gpu: nuppu.ptr,
    index_gpu: nuppu.ptr,
    instance_gpu: nuppu.ptr,

    pipeline: nuppu.Pipeline,
}

init :: proc() {
    window_app.v_shader = nuppu.shader_init(#load("4-instancing.metal", []u8), "vertexMain", .Vertex)
    window_app.f_shader = nuppu.shader_init(#load("4-instancing.metal", []u8), "fragmentMain", .Fragment)

    window_app.pipeline = nuppu.pipeline_init(window_app.v_shader, window_app.f_shader, {.BGRA8Unorm_sRGB}, .Invalid)

    upload_arena := nuppu.gpu_arena_init()
    defer nuppu.gpu_arena_deinit(&upload_arena)

    s :: f32(0.5)
    VERT_COUNT :: 4
    INDEX_COUNT :: 6

    verts := nuppu.gpu_arena_alloc_T(&upload_arena, [3]f32, VERT_COUNT)
    verts_array := ([^]([3]f32))(verts.cpu)
    verts_array[0] = { -s, -s, +s }
    verts_array[1] = { +s, -s, +s }
    verts_array[2] = { +s, +s, +s }
    verts_array[3] = { -s, +s, +s }

    indices := nuppu.gpu_arena_alloc_T(&upload_arena, u32, INDEX_COUNT)
    indices_array := ([^](u32))(indices.cpu)
    indices_array[0] = 0
    indices_array[1] = 1
    indices_array[2] = 2
    indices_array[3] = 2
    indices_array[4] = 3
    indices_array[5] = 0

    window_app.vertex_gpu = nuppu.gpu_malloc(size_of([3]f32) * VERT_COUNT, align_of([3]f32), .GPU_Only)
    window_app.index_gpu = nuppu.gpu_malloc(size_of(u32) * INDEX_COUNT, 16, .GPU_Only)
    window_app.instance_gpu = nuppu.gpu_malloc(INSTANCE_COUNT * size_of(Instance_Data), align_of(Instance_Data), .GPU_Only)

    cmds := nuppu.begin_commands()
    nuppu.cmd_mem_copy(cmds, window_app.vertex_gpu, verts, size_of([3]f32) * VERT_COUNT)
    nuppu.cmd_mem_copy(cmds, window_app.index_gpu, indices, size_of(u32) * INDEX_COUNT)
    nuppu.cmd_barrier(cmds, .Transfer, .All)
    nuppu.end_commands(cmds, {})
}

INSTANCE_COUNT :: 64
Instance_Data :: struct #align(16) {
    transform: matrix[4, 4]f32,
    color: [4]f32
}

deinit :: proc() {
    nuppu.shader_deinit(window_app.v_shader)
    nuppu.shader_deinit(window_app.f_shader)

    nuppu.pipeline_deinit(window_app.pipeline)

    nuppu.gpu_free(window_app.vertex_gpu)
    nuppu.gpu_free(window_app.index_gpu)
    nuppu.gpu_free(window_app.instance_gpu)
}

render :: proc(prev, curr: Window, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {

    @static angle: f32
    angle += nuppu.delta_time_f32() * 0.5

    instances := nuppu.gpu_arena_alloc_T(arena, Instance_Data, INSTANCE_COUNT)
    instances_array := slice.from_ptr((^Instance_Data)(instances.cpu), INSTANCE_COUNT)
    scl :: 0.12
    for &data, idx in instances_array {
        i := f32(idx) / f32(INSTANCE_COUNT)
        x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
        y_off := math.sin((i + angle) * 2 * math.PI)
        data.transform = linalg.transpose(matrix[4, 4]f32{
            scl * math.sin(angle), scl * math.cos(angle), 0, 0,
            scl * math.cos(angle), -scl * math.sin(angle), 0, 0,
            0, 0, scl, 0,
            x_off, y_off, 0, 1
        })
        data.color = [4]f32{i, 1 - i, math.sin(math.PI * i), 1}
    }

    cmds := nuppu.begin_commands()

    nuppu.cmd_mem_copy(cmds, curr.instance_gpu, instances, size_of(Instance_Data) * INSTANCE_COUNT)
    nuppu.cmd_barrier(cmds, .Transfer, .All)

    swapchain := nuppu.acquire_next_swapchain(cmds)

    nuppu.cmd_begin_render_pass(cmds, {
        {
            load_action = .Clear,
            store_action = .Store,
            texture = swapchain,
        }
    })

    nuppu.cmd_set_pipeline(cmds, window_app.pipeline)

    nuppu.cmd_draw_indiced_primitives(cmds, {
        {window_app.vertex_gpu, 0},
        {curr.instance_gpu, 1}
    },
    .Triangle,
    window_app.index_gpu,
    INSTANCE_COUNT)

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