package main

import nuppu "../.."
import gpu "../../gpu"
import "../../platform"
import "core:image"
import _ "core:image/png"

State :: struct {
    angle:    f32,
    texture:  nuppu.Texture_Handle,
}

state: ^State

// Mirrors the shader's Material_Data: only the atlas texture is material-local,
// everything else belongs to the engine or the shader.
Object_Params :: struct {
    color: [4]f32,
}

Quad_Entity :: struct {
    using e: ^nuppu.Entity,
}

INSTANCE_COUNT :: 8

_init :: proc() {
    TW :: 63
    TH :: 63

    atlas := nuppu.texture_2D({TW, TH}, .RGBA8Unorm, {.Sampled}, name = "sprite_atlas")

    img, err := image.load_from_bytes(#load("bowser.png", []u8), {.alpha_add_if_missing}, context.temp_allocator)
    assert(err == nil, "8-Sprite: failed to decode bowser.png")
    defer image.destroy(img, context.temp_allocator)

    scope := nuppu.texture_upload_scope(nuppu.texture_upload_image_bytes(TW, TH, .RGBA8Unorm))
    nuppu.texture_upload(&scope, atlas, .RGBA8Unorm, raw_data(img.pixels.buf[:]))
    nuppu.texture_upload_scope_end(&scope)

    nuppu.update_camera({0, 0, 2}, {}, 0.1, 1_000, 80)

    nuppu.register_entity(Quad_Entity, 8, {.Interpolate})

    state.texture  = atlas
    
    quad_handle := nuppu.built_in_mesh_handle(.Quad)

    for idx in 0 ..< INSTANCE_COUNT {
        q := nuppu.entity_add(Quad_Entity, "quad")
        q.mesh     = quad_handle
        q.material = nuppu.get_built_in_material(nuppu.Built_In_Material.Sprite)
        q.position = {-1 + f32(idx) * 0.25, 0.5, 0}
    }
}

_deinit :: proc() {
    nuppu.texture_free(state.texture)
}

_update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.09

    it := nuppu.entities_of(Quad_Entity)
    for e, _ in nuppu.entity_variant_iterator_next(&it, Quad_Entity) {
        e.rotation.z = state.angle
    }
}

_render :: proc(current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    nuppu.update_constants(frame)
    defer nuppu.end_frame(frame)

    culled := nuppu.cull_entities(Quad_Entity)
    for q in culled.entities {
        nuppu.submit_sprite(q, {0, 0}, {1, 1})
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
