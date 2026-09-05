package lo

import nuppu "../../.."
import R "../../../render"
import "core:mem"
import "core:fmt"
import "core:slice"

State :: struct {
    pso: gpu.Pipeline,

    mesh: nuppu.Mesh,
}

state: ^State

_init :: proc() {
when ODIN_OS == .Darwin {
    vertex_code := #load("triangle.vs.metal", []u8)
    fragment_code := #load("triangle.ps.metal", []u8)
}
when ODIN_OS == .JS {
    vertex_code := #load("triangle.wgsl", []u8)
    fragment_code := vertex_code 
}

     

    // Init resources
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

    // Allocates single CPU writable buffer for staging
    upload := gpu.arena_init()
    //defer gpu.destroy_arena(&upload)

    // Moves upload scope's offset and returns CPU modifiable slice to put data into
    vertices := gpu.arena_alloc(&upload, nuppu.Vertex, NUM_VERTICES)
    mem.copy_non_overlapping(vertices.cpu, &[NUM_VERTICES]nuppu.Vertex{
        nuppu.pack_vertex( position = { -0.8, +0.8, 0.0 }, color = { 255, 0, 0, 255 }),
        nuppu.pack_vertex( position = {  0.0, -0.8, 0.0 }, color = { 0, 255, 0, 255 }),
        nuppu.pack_vertex( position = { +0.8, +0.8, 0.0 }, color = { 0, 0, 255, 255 }),
    }, NUM_VERTICES * size_of(nuppu.Vertex))

    indices := gpu.arena_alloc_raw(&upload, size_of(nuppu.Vertex_Index), NUM_VERTICES, 4)
    mem.copy_non_overlapping(indices.cpu, &[NUM_VERTICES]nuppu.Vertex_Index{ 0, 1, 2 }, NUM_VERTICES * size_of(nuppu.Vertex_Index))

    gpu.unmap(&upload.ptr)

    state.mesh = nuppu.push_mesh_zeroed(
        vertex_count = NUM_VERTICES,
        index_count = NUM_VERTICES,
    )

    gpu.begin_commands()
    gpu.copy(state.mesh.verts, vertices)
    gpu.copy(state.mesh.indices, indices)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()
    //

}

_update :: proc() {}

_render :: proc(previous, current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    defer nuppu.end_frame(frame)
    frame_arena := nuppu.frame_arena(frame)

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color = {12, 12, 12, 255},
        load_action = .Clear,
        store_action = .Store,
        texture = swapchain,
    })

    gpu.set_pipeline(current.pso)

    block := gpu.Parameter_Block {
        constants = {},
        read_resources = {0 = current.mesh.verts},
        read_write_resources = {},
        samplers = {},
    }

    gpu.use_parameter_block(&block)

    gpu.draw_indiced_primitives(.Triangle, current.mesh.indices, current.mesh.index_count, 0, 1, 0, 0)

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
