package main

import nuppu "../.."
import gpu "../../gpu"
import "core:math"

state: ^State

State :: struct {
    angle:    f32,
    center:   [3]f32,
    material: nuppu.Material_Handle,
    shader:   nuppu.Shader_Handle,
}

Object_Params :: struct {
    color: [4]f32,
}

Cube_Entity :: struct {
    using e: ^nuppu.Entity,
    color: [4]f32,
}

INSTANCE_WIDTH  :: 3
INSTANCE_HEIGHT :: 3
INSTANCE_DEPTH  :: 2
INSTANCE_COUNT  :: INSTANCE_WIDTH * INSTANCE_HEIGHT * INSTANCE_DEPTH

_init :: proc() {
    nuppu.update_camera({0, 0, 0}, {}, 0.03, 500, 45)

    nuppu.register_entity(Cube_Entity, 8, {.Interpolate})

    vertex_code: []u8
    fragment_code: []u8
    when ODIN_OS == .Darwin {
        vertex_code   = #load("perspective.vs.metal", []u8)
        fragment_code = #load("perspective.ps.metal", []u8)
    } else when ODIN_OS == .JS {
        vertex_code   = #load("perspective.wgsl", []u8)
        fragment_code = vertex_code
    }

    params := Object_Params {
        color = {1, 1, 1, 1},
    }
    mat_scope := nuppu.material_upload_scope()
    mat, mat_ok := nuppu.material_upload(&mat_scope, nuppu.DEFAULT_DRAW_STATE, &params, name = "unlit")
    assert(mat_ok, "4-Perspective: failed to upload material")
    nuppu.material_upload_scope_end(&mat_scope)

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
    }, nuppu.Mesh_Instance, mat, "unlit_instance_color")
    assert(shader_ok, "4-Perspective: failed to register shader")
    nuppu.connect_materials_to_shader({mat}, shader)

    state.material = mat
    state.shader   = shader

    cube_handle := nuppu.built_in_mesh_handle(.Cube)

    spacing :: 1.2
    center_sum: [3]f32
    for iz in 0 ..< INSTANCE_DEPTH {
        for iy in 0 ..< INSTANCE_HEIGHT {
            for ix in 0 ..< INSTANCE_WIDTH {
                c := nuppu.entity_add(Cube_Entity, "cube")
                c.mesh         = cube_handle
                c.material = mat
                c.scale        = {0.4, 0.4, 0.4}
                c.position = {
                    (f32(ix) - f32(INSTANCE_WIDTH - 1)  * 0.5) * spacing,
                    (f32(iy) - f32(INSTANCE_HEIGHT - 1) * 0.5) * spacing,
                    -4 - f32(iz) * spacing,
                }
                center_sum += c.position

                t := f32(ix * INSTANCE_HEIGHT * INSTANCE_DEPTH + iy * INSTANCE_DEPTH + iz) / f32(INSTANCE_COUNT)
                c.color = {t, 1 - t, math.sin(math.TAU * t), 1}
            }
        }
    }
    state.center = center_sum / f32(INSTANCE_COUNT)
}

_deinit :: proc() {
    nuppu.material_free(state.material)
    nuppu.shader_free(state.shader)
}

_update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.35

    // Orbit the whole formation around its center instead of only spinning in place.
    step := nuppu.sim_delta_time() * 0.35
    c, s := math.cos(step), math.sin(step)

    it := nuppu.entities_of(Cube_Entity)
    for e, _ in nuppu.advance_entities_of(&it) {
        p := e.position - state.center
        e.position = state.center + [3]f32{p.x * c - p.z * s, p.y, p.x * s + p.z * c}

        e.rotation.x = state.angle * 0.5
        e.rotation.y = state.angle
    }
}

_render :: proc(current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    nuppu.update_constants(frame)
    defer nuppu.end_frame(frame)

    culled := nuppu.cull_entities(Cube_Entity)
    for e in culled.entities {
        cube := (^Cube_Entity)(e.v.data)
        nuppu.submit_mesh(e, cube.color)
    }

    nuppu.flush_culled_instances(frame)

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
    deinit      = _deinit,
    update      = _update,
    render      = _render,
}

main :: proc() {
    nuppu.run(desc)
}
