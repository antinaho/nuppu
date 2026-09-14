package main

import nuppu "../.."
import gpu "../../gpu"
import "core:math"

state: ^State

State :: struct {
    angle:   f32,
    center:  [3]f32,
    texture: nuppu.Texture_Handle,
}

Object_Params :: struct {
    color: [4]f32,
}

// Per-entity data uploaded every frame through the `gpu_instance` field.
Color_Instance :: struct {
    color: [4]f32,
}

Cube_Entity :: struct {
    using e: ^nuppu.Entity,
    gpu_instance: Color_Instance,
}

TEXTURE_WIDTH  :: 128
TEXTURE_HEIGHT :: 128

INSTANCE_WIDTH  :: 10
INSTANCE_HEIGHT :: 10
INSTANCE_DEPTH  :: 10
INSTANCE_COUNT  :: INSTANCE_WIDTH * INSTANCE_HEIGHT * INSTANCE_DEPTH

_init :: proc() {
    nuppu.update_camera({0, 0, 0}, {}, 0.03, 500, 45)

    nuppu.register_entity(Cube_Entity, 8, {.Interpolate, .Has_Mesh}, Color_Instance)

    // A storage texture the compute pass writes into and the render pass samples.
    state.texture = nuppu.texture_init_ex({
        dimensions  = {TEXTURE_WIDTH, TEXTURE_HEIGHT},
        format      = .RGBA8Unorm,
        type        = ._2D,
        storage     = .Shared,
        usage       = {.Write, .Sampled},
        layer_count = 1,
    }, name = "mandelbrot")

    // Compute the Mandelbrot set once, before the render loop starts.
    {
        compute_code: []u8
        when ODIN_OS == .Darwin {
            compute_code = #load("mandelbrot.metal", []u8)
        } else when ODIN_OS == .JS {
            compute_code = #load("mandelbrot.wgsl", []u8)
        }

        kernel      := gpu.shader_module_init("mandelbrot", compute_code)
        compute_pso := gpu.compute_pipeline_init(kernel, "mandelbrot_set")

        tex, tex_ok := nuppu.get_texture(state.texture)
        assert(tex_ok, "6-Compute: failed to get compute texture")

        gpu.begin_commands()
        gpu.set_compute_pipeline(compute_pso)
        block := gpu.Parameter_Block {
            read_write_resources = { 0 = tex^ },
        }
        gpu.use_parameter_block(&block, .Compute)
        gpu.compute_dispatch({TEXTURE_WIDTH, TEXTURE_HEIGHT, 1}, {128, 1, 1})
        gpu.barrier(.Compute, .All)
        gpu.commit_commands()
    }

    sampler := gpu.sampler_init({
        min_filter = .Linear,
        mag_filter = .Linear,
        mip_filter = .Linear,
        wrap_s     = .Repeat,
        wrap_t     = .Repeat,
        wrap_r     = .Repeat,
    })

    vertex_code: []u8
    fragment_code: []u8
    when ODIN_OS == .Darwin {
        vertex_code   = #load("compute.vs.metal", []u8)
        fragment_code = #load("compute.ps.metal", []u8)
    } else when ODIN_OS == .JS {
        vertex_code   = #load("compute.wgsl", []u8)
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
        textures       = []nuppu.Texture_Handle{ state.texture },
        samplers       = []gpu.Sampler{ sampler },
    }, "lit_textured")
    assert(shader_ok, "6-Compute: failed to register shader")

    params := Object_Params {
        color = {1, 1, 1, 1},
    }
    mat_scope := nuppu.material_upload_scope(1)
    mat, mat_ok := nuppu.material_upload(&mat_scope, shader, nuppu.DEFAULT_DRAW_STATE, &params, name = "mandelbrot")
    assert(mat_ok, "6-Compute: failed to upload material")

    cube_handle := nuppu.built_in_mesh_handle(.Cube)

    scl :: 0.2
    center_sum: [3]f32
    for iz in 0 ..< INSTANCE_DEPTH {
        for iy in 0 ..< INSTANCE_HEIGHT {
            for ix in 0 ..< INSTANCE_WIDTH {
                c := nuppu.entity_add(Cube_Entity, "cube")
                c.mesh         = cube_handle
                c.materials[0] = mat
                c.scale        = {scl, scl, scl}
                c.position = {
                    (f32(ix) - f32(INSTANCE_WIDTH)  * 0.5) * 2 * scl + scl,
                    (f32(iy) - f32(INSTANCE_HEIGHT) * 0.5) * 2 * scl + scl,
                    -7 + (f32(iz) - f32(INSTANCE_DEPTH) * 0.5) * 2 * scl,
                }
                center_sum += c.position

                t := f32(ix * INSTANCE_HEIGHT * INSTANCE_DEPTH + iy * INSTANCE_DEPTH + iz) / f32(INSTANCE_COUNT)
                c.gpu_instance.color = {t, 1 - t, math.sin(math.TAU * t), 1}
            }
        }
    }
    state.center = center_sum / f32(INSTANCE_COUNT)
}

_update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.45

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
    nuppu.update_constants()
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
