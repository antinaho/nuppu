package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:mem"
import "core:math"

State :: struct {
    angle: f32,

    pso: gpu.Pipeline,

    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    angle_buf: gpu.ptr,
}

Vertex :: struct #align(16) {
    pos: [4]f32,
    color: [4]f32,
}

Animation :: struct #align(16) {
    angle: f32,
    _pad: [3]u32,
}

state: ^State

_init :: proc() {
when ODIN_OS == .Darwin {
    vertex_code := #load("animation.vs.metal", []u8)
    fragment_code := #load("animation.ps.metal", []u8)
}
when ODIN_OS == .JS {
    // WGSL uses same shader for vertex and fragment
    vertex_code := #load("animation.wgsl", []u8)
    fragment_code := vertex_code 
}

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

    // Staging arena for one-time vertex upload + initial angle.
    upload := gpu.arena_init()

    vertices := gpu.arena_alloc(&upload, Vertex, NUM_VERTICES)
    mem.copy_non_overlapping(vertices.cpu, &[NUM_VERTICES]Vertex{
        {{ -0.8,  0.8, 0.0, 1.0 }, { 1, 0, 0, 1 }},
        {{  0.0, -0.8, 0.0, 1.0 }, { 0, 1, 0, 1 }},
        {{ +0.8,  0.8, 0.0, 1.0 }, { 0, 0, 1, 1 }},
    }, NUM_VERTICES * size_of(Vertex))

    indices := gpu.arena_alloc(&upload, u32, NUM_VERTICES)
    mem.copy_non_overlapping(indices.cpu, &[3]u32{ 0, 1, 2 }, 3 * size_of(u32))

    gpu.unmap(&upload.ptr)

    // Allocate GPU buffers.
    state.vertex_gpu= gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Vertex), align_of(Vertex), "Positions")
    state.index_gpu = gpu.malloc_index(NUM_VERTICES, .Uint32, "Indices")
    state.angle_buf = gpu.malloc(.GPU_Constant, 1, size_of(Animation), align_of(Animation), "Animation")

    // Upload all staging data in one command buffer.
    gpu.begin_commands()
    gpu.copy(state.vertex_gpu, vertices)
    gpu.copy(state.index_gpu, indices)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()
}

_update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.5
}

_render :: proc(previous, current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    defer nuppu.end_frame(frame)
    frame_arena := nuppu.frame_arena(frame)

    angle := math.lerp(previous.angle, current.angle, alpha)

    fd := gpu.arena_alloc(frame_arena, Animation, 1)
    (^Animation)(fd.cpu)^ = Animation{angle = angle}

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

    block := gpu.Parameter_Block {
        constants = {0 = current.angle_buf},
        read_resources = {0 = current.vertex_gpu},
        read_write_resources = {},
        samplers = {},
    }

    gpu.use_parameter_block(&block)

    //gpu.set_buffers({current.pos_gpu, current.color_gpu, current.angle_buf}, {0, 3}, .Vertex)
    gpu.draw_indiced_primitives(.Triangle, current.index_gpu, 3, 0, 1, 0, 0)

    gpu.end_render_pass()
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
