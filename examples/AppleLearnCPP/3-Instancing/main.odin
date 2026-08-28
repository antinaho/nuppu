package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/linalg"

State :: struct {
    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,

    angle: f32,

    pso: gpu.Pipeline,
}

Vertex :: struct #align(16) {
    pos: [4]f32,
}

INSTANCE_COUNT :: 32
Instance_Data :: struct #align(16) {
    transform: matrix[4, 4]f32,
    color: [4]f32
}

state: ^State
import "core:mem"

_init :: proc() {
when ODIN_OS == .Darwin {
    vertex_code := #load("instancing.vs.metal", []u8)
    fragment_code := #load("instancing.ps.metal", []u8)
}
when ODIN_OS == .JS {
    // WGSL uses same shader for vertex and fragment
    vertex_code := #load("instancing.wgsl", []u8)
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
    NUM_VERTICES :: 4
    NUM_INDICES :: 6
    s :: 0.5
//
    upload := gpu.arena()

    vertices := gpu.arena_alloc(&upload, Vertex, NUM_VERTICES)
    mem.copy_non_overlapping(vertices.cpu, &[NUM_VERTICES]Vertex{
        {{ -s, -s, +s, 1.0 }},
        {{ +s, -s, +s, 1.0 }},
        {{ +s, +s, +s, 1.0 }},
        {{ -s, +s, +s, 1.0 }},    
    }, NUM_VERTICES * size_of(Vertex))
    
    indices := gpu.arena_alloc(&upload, u32, NUM_INDICES)
    mem.copy_non_overlapping(indices.cpu, &[NUM_INDICES]u32{
        0, 1, 2, 2, 3, 0    
    }, NUM_INDICES * size_of(u32))
    
    gpu.unmap(&upload.ptr)    
//
    state.vertex_gpu = gpu.malloc(.GPU_Storage, NUM_VERTICES, size_of(Vertex), align_of(Vertex), "Positions")
    state.index_gpu = gpu.malloc_index(NUM_INDICES, .Uint32, "Indices")    
    state.instance_gpu = gpu.malloc(.GPU_Storage, INSTANCE_COUNT, size_of(Instance_Data), align_of(Instance_Data), "Instances")

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
    scl :: 0.12
    angle := math.lerp(previous.angle, current.angle, alpha)
    
    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    instances := gpu.arena_alloc(frame_arena, Instance_Data, INSTANCE_COUNT)
    for &isnt, idx in ([^]Instance_Data)(instances.cpu)[:INSTANCE_COUNT] {
        i := f32(idx) / f32(INSTANCE_COUNT)
        x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
        y_off := math.sin((i + angle) * 2 * math.PI)
        isnt.transform = linalg.transpose(matrix[4, 4]f32{
            scl * math.sin(angle), scl * math.cos(angle), 0, 0,
            scl * math.cos(angle), -scl * math.sin(angle), 0, 0,
            0, 0, scl, 0,
            x_off, y_off, 0, 1
        })
        isnt.color = [4]f32{i, 1 - i, math.sin(math.PI * i), 1}
    }
    gpu.unmap(&frame_arena.ptr)

    gpu.copy(current.instance_gpu, instances)
    gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    }, {})

    gpu.set_pipeline(current.pso)

    block := gpu.Parameter_Block {
        constants = {},
        read_resources = {
            0 = current.vertex_gpu,
            1 = current.instance_gpu,
        },
        read_write_resources = {},
        samplers = {},
    }

    gpu.use_parameter_block(&block)
    //gpu.set_buffers({current.pos_gpu, current.instance_gpu}, {0, 2}, .Vertex)

    gpu.draw_indiced_primitives(
    .Triangle,
    current.index_gpu,
    6, 0,
    INSTANCE_COUNT,
    0, 0)

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
