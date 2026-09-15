package main

import nuppu "../.."
import gpu "../../gpu"

state: ^State

State :: struct {
    mesh: nuppu.Mesh_Handle,
}

Object_Params :: struct {
    color: [4]f32,
}

Triangle_Entity :: struct {
    using e: ^nuppu.Entity,
}

_init :: proc() {
    nuppu.update_camera({0, 0, 2}, {}, 0.1, 1_000, 80)

    nuppu.register_entity(Triangle_Entity, 8, {.Interpolate, .Has_Mesh})

    state.mesh = nuppu.mesh_upload(
         {
            nuppu.pack_vertex(position = {-0.8, -0.8, 0}, color = {255,   0,   0, 255}),
            nuppu.pack_vertex(position = { 0.8, -0.8, 0}, color = {  0, 255,   0, 255}),
            nuppu.pack_vertex(position = { 0.0,  0.8, 0}, color = {  0,   0, 255, 255}),
        },
        { 0, 1, 2 },
        "triangle",
    )

    vertex_code: []u8
    fragment_code: []u8
    when ODIN_OS == .Darwin {
        vertex_code   = #load("triangle.vs.metal", []u8)
        fragment_code = #load("triangle.ps.metal", []u8)
    } else when ODIN_OS == .JS {
        vertex_code   = #load("triangle.wgsl", []u8)
        fragment_code = vertex_code
    }

    shader, shader_ok := nuppu.shader_register({
        vertex_code    = string(vertex_code),
        vertex_entry   = "vertexMain",
        fragment_code  = string(fragment_code),
        fragment_entry = "fragmentMain",
        color_format   = .BGRA8Unorm,
        depth_format   = .Depth32Float,
        blend          = gpu.BLEND_NONE,
        multisample    = { count = 1, mask = 0xFFFFFFFF },
        topology       = .Triangle,
    }, "unlit_vertex_color")
    assert(shader_ok, "1-Primitive: failed to register shader")

    params := Object_Params {
        color = {1, 1, 1, 1},
    }
    mat_scope := nuppu.material_upload_scope(1)
    mat, mat_ok := nuppu.material_upload(&mat_scope, shader, nuppu.DEFAULT_DRAW_STATE, &params, name = "unlit")
    assert(mat_ok, "1-Primitive: failed to upload material")

    triangle := nuppu.entity_add(Triangle_Entity, "triangle")
    triangle.mesh         = state.mesh
    triangle.materials[0] = mat
    triangle.scale        = {1, 1, 1}
}

_update :: proc() {}

_render :: proc(current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    nuppu.update_constants(frame)
    defer nuppu.end_frame(frame)

    nuppu.cull(frame)
    nuppu.finish_instance_upload(frame)

    gpu.barrier(.Transfer, .All)

    swapchain := nuppu.acquire_next_swapchain()
    nuppu.begin_render_pass({
        clear_color  = {12, 12, 12, 255},
        load_action  = .Clear,
        store_action = .Store,
        texture      = swapchain,
    }, {
        load_action  = .Clear,
        store_action = .Store,
        texture      = nuppu.depth(),
    })

    nuppu.draw_all_instances(frame)
    nuppu.end_render_pass()
}

desc := nuppu.App_Desc(State) {
    state       = &state,
    window_size = {1000, 1000},
    init        = _init,
    update      = _update,
    render      = _render,
}

main :: proc() {
    nuppu.run(desc)
}
