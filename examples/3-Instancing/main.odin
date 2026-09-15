package main

import nuppu "../.."
import gpu "../../gpu"
import "../../platform"
import "core:fmt"
import "core:image"
import _ "core:image/png"

State :: struct {
    angle: f32,

    textures: nuppu.Texture_Handle,
    sampler:  gpu.Sampler,
}

INSTANCE_COUNT :: 4
ATLAS_COLS :: 2
ATLAS_ROWS :: 2

state: ^State

_upload_png_to_array_layer :: proc(texture: gpu.Texture, layer: int, data: []u8, label: string) {
    img, img_err := image.load_from_bytes(data, {.alpha_add_if_missing}, context.temp_allocator)
    if img_err != nil {
        panic(fmt.tprintf("3-Instancing: failed to decode %s: %v", label, img_err))
    }
    defer image.destroy(img, context.temp_allocator)

    gpu.copy_to_texture(texture, {0, 0, u32(layer)}, {u32(img.width), u32(img.height), 1}, 0, raw_data(img.pixels.buf[:]), u32(img.width * 4))
}

_init :: proc() {
    state.textures = nuppu.texture_init_ex({
        dimensions  = {63, 63},
        format      = .RGBA8Unorm,
        type        = ._2D_Array,
        storage     = .Shared,
        usage       = {.Sampled},
        layer_count = 2,
    }, name = "sprite_atlas")

    texture, texture_ok := nuppu.get_texture(state.textures)
    assert(texture_ok, "3-Instancing: failed to get texture")
    _upload_png_to_array_layer(texture^, 0, #load("bowser.png", []u8), "bowser.png")
    _upload_png_to_array_layer(texture^, 1, #load("peach.png", []u8), "peach.png")

    state.sampler = gpu.sampler_init({
        min_filter = .Nearest,
        mag_filter = .Nearest,
        mip_filter = .Nearest,
        wrap_s     = .ClampToEdge,
        wrap_t     = .ClampToEdge,
        wrap_r     = .ClampToEdge,
    })

    nuppu.update_camera({0, 0, 2}, {}, 0.1, 1_000, 80)

    nuppu.register_entity(Quad_Entity, 8, {.Interpolate, .Has_Mesh}, nuppu.Sprite_Instance)
    nuppu.register_entity(Cube_Entity, 8, {.Interpolate, .Has_Mesh})

    vertex_code: []u8
    fragment_code: []u8
    when ODIN_OS == .Darwin {
        vertex_code   = #load("instancing.vs.metal", []u8)
        fragment_code = #load("instancing.ps.metal", []u8)
    } else when ODIN_OS == .JS {
        vertex_code   = #load("instancing.wgsl", []u8)
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
        textures       = []nuppu.Texture_Handle{ state.textures },
        samplers       = []gpu.Sampler{ state.sampler },
    }, "sprite_shader")
    assert(shader_ok, "3-Instancing: failed to register shader")

    sprite_params := Object_Params {
        color = {1, 1, 1, 1},
    }

    mat_scope := nuppu.material_upload_scope(1)
    mat, mat_ok := nuppu.material_upload(&mat_scope, shader, nuppu.DEFAULT_DRAW_STATE, &sprite_params, name = "sprite")
    assert(mat_ok, "3-Instancing: failed to register material")

    quad_handle := nuppu.built_in_mesh_handle(.Quad)
    cube_handle := nuppu.built_in_mesh_handle(.Cube)

    for idx in 0 ..< INSTANCE_COUNT {
        q := nuppu.entity_add(Quad_Entity, "quad")
        q.mesh         = quad_handle
        q.materials[0] = mat
        q.scale        = {1, 1, 1}
        q.position     = {-1 + f32(idx) * 0.5, 0.5, 0}
        nuppu.sprite_animation_configure(&q.gpu_instance, &q.anim, ATLAS_COLS, ATLAS_ROWS, 6.0)
        q.gpu_instance.frame_n = u32(idx) % (ATLAS_COLS * ATLAS_ROWS) // phase offset per quad
        nuppu.sprite_animation_advance(&q.gpu_instance, &q.anim, 0)
    }

    for idx in 0 ..< INSTANCE_COUNT {
        c := nuppu.entity_add(Cube_Entity, "cube")
        c.mesh         = cube_handle
        c.materials[0] = mat
        c.scale        = {1, 1, 1}
        c.position     = {0, f32(idx) * 0.05 - 0.8, 0}
    }

    for idx in 0 ..< INSTANCE_COUNT {
        q := nuppu.entity_add(Quad_Entity, "quad")
        q.mesh         = quad_handle
        q.materials[0] = mat
        q.scale        = {1, 1, 1}
        q.position     = {0.5, -1 + f32(idx) * 0.5, 0}
        nuppu.sprite_animation_configure(&q.gpu_instance, &q.anim, ATLAS_COLS, ATLAS_ROWS, 6.0)
        q.gpu_instance.frame_n = u32(idx + 2) % (ATLAS_COLS * ATLAS_ROWS)
        nuppu.sprite_animation_advance(&q.gpu_instance, &q.anim, 0)
    }
}

Object_Params :: struct {
    color: [4]f32,
}

// The engine uploads the `gpu_instance` field verbatim; `anim` is CPU-only
// playback state.
Quad_Entity :: struct {
    using e: ^nuppu.Entity,
    gpu_instance: nuppu.Sprite_Instance,
    anim: nuppu.Sprite_Animation,
}

Cube_Entity :: struct {
    using e: ^nuppu.Entity,
}

_deinit :: proc() {

}

_update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.09

    MS :: 1.25
    if platform.input_key_held(.KEY_A) {
        nuppu.move(nuppu.camera(), {-nuppu.sim_delta_time() * MS, 0, 0})
    }
    if platform.input_key_held(.KEY_D) {
        nuppu.move(nuppu.camera(), {nuppu.sim_delta_time() * MS, 0, 0})
    }

    if platform.input_key_held(.KEY_W) {
        nuppu.move(nuppu.camera(), {0, nuppu.sim_delta_time() * MS, 0})
    }
    if platform.input_key_held(.KEY_S) {
        nuppu.move(nuppu.camera(), {0, -nuppu.sim_delta_time() * MS, 0})
    }

    angle := state.angle
    qit := nuppu.entities_of(Quad_Entity)
    for e, _ in nuppu.entity_variant_iterator_next(&qit, Quad_Entity) {
        e.rotation.z = angle
        // Advances frame_n and writes uv_min/uv_max; the gather pass uploads them.
        nuppu.sprite_animation_advance(&e.gpu_instance, &e.anim, nuppu.sim_delta_time())
    }

    cit := nuppu.entities_of(Cube_Entity)
    for e, h in nuppu.advance_entities_of(&cit) {
        e.rotation.y = angle
        _ = h
    }
}

_render :: proc(current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    nuppu.update_constants(frame)
    defer nuppu.end_frame(frame)

    nuppu.cull(frame)
    nuppu.finish_instance_upload(frame)

    gpu.barrier(.Transfer, .All)

    swapchain_handle := nuppu.acquire_next_swapchain()
    depth_handle     := nuppu.depth()
    nuppu.begin_render_pass({
        clear_color  = {12, 12, 12, 255},
        load_action  = .Clear,
        store_action = .Store,
        texture      = swapchain_handle,
    }, {
        load_action = .Clear,
        store_action = .Store,
        texture = depth_handle,
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
