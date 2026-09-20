package main

import nuppu "../.."
import gpu "../../gpu"
import "../../platform"
import "core:image"
import _ "core:image/png"

State :: struct {
    angle: f32,

    tex_browser: nuppu.Texture_Handle,
    tex_peach:   nuppu.Texture_Handle,
    sampler:     nuppu.Sampler_Handle,

    m_browser: nuppu.Material_Handle,
    m_peach:   nuppu.Material_Handle,
    shader:    nuppu.Shader_Handle,
}

INSTANCE_COUNT :: 4
ATLAS_COLS :: 2
ATLAS_ROWS :: 2

state: ^State

_init :: proc() {

    // MATERIALS
    // 1. Malloc per material gpu space
    // 2. Upload data to that gpu space

    // Malloc gpu space for materials different variants
    tex_browser := nuppu.texture_2D( {63, 63}, .RGBA8Unorm, {.Sampled}, name = "Browser tex" )
    tex_peach := nuppu.texture_2D( {63, 63}, .RGBA8Unorm, {.Sampled}, name = "Peach tex" )

    // Load texture data from disk
    tex_bowser_data, tex_bowser_load_err := image.load_from_bytes(#load("bowser.png", []u8), {.alpha_add_if_missing}, context.temp_allocator)
    assert(tex_bowser_load_err == nil, "3-Instancing: failed to decode bowser.png")
    defer image.destroy(tex_bowser_data, context.temp_allocator)

    tex_peach_data, tex_peach_load_err := image.load_from_bytes(#load("peach.png", []u8), {.alpha_add_if_missing}, context.temp_allocator)
    assert(tex_peach_load_err == nil, "3-Instancing: failed to decode peach.png")
    defer image.destroy(tex_peach_data, context.temp_allocator)

    tex_upload_scope := nuppu.texture_upload_scope(2 * nuppu.texture_upload_image_bytes(63, 63, .RGBA8Unorm))
    nuppu.texture_upload(&tex_upload_scope, tex_browser, .RGBA8Unorm, raw_data(tex_bowser_data.pixels.buf[:]))
    nuppu.texture_upload(&tex_upload_scope, tex_peach, .RGBA8Unorm, raw_data(tex_peach_data.pixels.buf[:]))
    nuppu.texture_upload_scope_end(&tex_upload_scope)

    // Material constants are just scalars; the texture is set-2 per material.
    sprite_params := Sprite_Material_Constants {
        color = {1, 1, 1, 1},
    }

    mat_scope := nuppu.material_upload_scope()
    mat_browser, mat_browser_ok := nuppu.material_upload(&mat_scope, nuppu.DEFAULT_DRAW_STATE, &sprite_params, .Opaque, { nuppu.material_texture(tex_browser) }, "browser mat")
    mat_peach, mat_peach_ok := nuppu.material_upload(&mat_scope, nuppu.DEFAULT_DRAW_STATE, &sprite_params, .Opaque, { nuppu.material_texture(tex_peach) }, "peach mat")
    assert(mat_browser_ok && mat_peach_ok, "3-Instancing: failed to upload materials")
    nuppu.material_upload_scope_end(&mat_scope)

    // SHADER RESOURCES
    // 1. Create shader's constant resources (buffers, textures, samplers)
    shader_sampler := nuppu.sampler_create({
        min_filter = .Nearest,
        mag_filter = .Nearest,
        mip_filter = .Nearest,
        wrap_s     = .ClampToEdge,
        wrap_t     = .ClampToEdge,
        wrap_r     = .ClampToEdge,
    }, "instancing_sampler")

    // SHADER
    vertex_code: []u8
    fragment_code: []u8
    when ODIN_OS == .Darwin {
        vertex_code   = #load("instancing.vs.metal", []u8)
        fragment_code = #load("instancing.ps.metal", []u8)
    } else when ODIN_OS == .JS {
        vertex_code   = #load("instancing.wgsl", []u8)
        fragment_code = vertex_code
    }

    sprite_shader, sprite_shader_ok := nuppu.shader_register({
        vertex_code    = string(vertex_code),
        vertex_entry   = "vertexMain",
        fragment_code  = string(fragment_code),
        fragment_entry = "fragmentMain",
        color_format   = .BGRA8Unorm,
        depth_format   = .Depth32Float,
        blend          = gpu.BLEND_NONE,
        multisample    = { count = 1, mask = 0xFFFFFFFF },
        topology       = .Triangle,
        shader_resources = {
            samplers = { shader_sampler },
        },
    }, nuppu.Sprite_Instance, mat_browser, "sprite_shader")
    assert(sprite_shader_ok, "3-Instancing: failed to register shader")

    nuppu.connect_materials_to_shader({mat_browser, mat_peach}, sprite_shader)



    state.tex_browser = tex_browser
    state.tex_peach   = tex_peach
    state.sampler     = shader_sampler
    state.m_browser   = mat_browser
    state.m_peach     = mat_peach
    state.shader      = sprite_shader


    // Entities
    nuppu.register_entity(Quad_Entity, 8, {.Interpolate})
    nuppu.register_entity(Cube_Entity, 8, {.Interpolate})

    // Register entities that use browser material
    for idx in 0 ..< INSTANCE_COUNT {
        q := nuppu.entity_add(Quad_Entity, "quad")
        q.mesh     = nuppu.built_in_mesh_handle(.Quad)
        q.material = mat_browser
        q.position = {-1 + f32(idx) * 0.5, 0.5, 0}
        nuppu.sprite_animation_configure(&q.anim, ATLAS_COLS, ATLAS_ROWS, 6.0)
        q.anim.frame_n = u32(idx) % (ATLAS_COLS * ATLAS_ROWS) // phase offset per quad
    }

    // Register entities that use peach material
    for idx in 0 ..< INSTANCE_COUNT {
        q := nuppu.entity_add(Quad_Entity, "quad")
        q.mesh     = nuppu.built_in_mesh_handle(.Quad)
        q.material = mat_peach
        q.scale    = {1, 1, 1}
        q.position = {0.5, -1 + f32(idx) * 0.5, 0}
        nuppu.sprite_animation_configure(&q.anim, ATLAS_COLS, ATLAS_ROWS, 6.0)
        q.anim.frame_n = u32(idx + 2) % (ATLAS_COLS * ATLAS_ROWS)
    }

    nuppu.update_camera({0, 0, 2}, {}, 0.1, 1_000, 80)
    
    // cube_handle := nuppu.built_in_mesh_handle(.Cube)
    // for idx in 0 ..< INSTANCE_COUNT {
    //     c := nuppu.entity_add(Cube_Entity, "cube")
    //     c.mesh     = cube_handle
    //     c.material = mat
    //     c.position = {0, f32(idx) * 0.05 - 0.8, 0}
    // }
}

Sprite_Material_Constants :: struct {
    color: [4]f32,
}

// `anim` is CPU-only sprite-sheet playback; its uv rect is passed to
// submit_sprite each frame.
Quad_Entity :: struct {
    using e: ^nuppu.Entity,
    anim: nuppu.Sprite_Animation,
}

Cube_Entity :: struct {
    using e: ^nuppu.Entity,
}

_deinit :: proc() {
    nuppu.texture_free(state.tex_browser)
    nuppu.texture_free(state.tex_peach)
    nuppu.material_free(state.m_browser)
    nuppu.material_free(state.m_peach)
    nuppu.shader_free(state.shader)
    nuppu.sampler_free(state.sampler)
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
        nuppu.sprite_animation_advance(&e.anim, nuppu.sim_delta_time())
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

    culled_sprites := nuppu.cull_entities(Quad_Entity)
    for q in culled_sprites.entities {
        quad := (^Quad_Entity)(q.v.data)
        uv_min, uv_size := nuppu.sprite_animation_uv(&quad.anim)
        nuppu.submit_sprite(q, uv_min, uv_size)
    }

    culled_meshes := nuppu.cull_entities(Cube_Entity)
    for c in culled_meshes.entities {
        nuppu.submit_mesh(c)
    }

    nuppu.flush_culled_instances(frame)

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


// slangc examples/3-Instancing/instancing.slang \
//   -target metal \
//   -entry vertexMain \
//   -stage vertex \
//   -entry fragmentMain \
//   -stage fragment \
//   -o T.metal