package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:image"
import "core:image/png"
import glm "core:math/linalg/glsl"

State :: struct {
    angle: f32,

    pso:      gpu.Pipeline,
    textures: gpu.Texture,
    sampler:  gpu.Sampler,

    camera_pos: [3]f32,
}

INSTANCE_COUNT :: 32

state: ^State

_upload_png_to_array_layer :: proc(texture: gpu.Texture, layer: int, data: []u8, label: string) {
    img, img_err := image.load_from_bytes(data, {.alpha_add_if_missing}, context.temp_allocator)
    if img_err != nil {
        panic(fmt.tprintf("3-Instancing_camera: failed to decode %s: %v", label, img_err))
    }
    defer image.destroy(img, context.temp_allocator)

    gpu.copy_to_texture(texture, {0, 0, layer}, {img.width, img.height, 1}, 0, raw_data(img.pixels.buf[:]), u32(img.width * 4))
}

_init :: proc() {
    vertex_code   := #load("instancing.vs.metal", []u8)
    fragment_code := #load("instancing.ps.metal", []u8)

    shader_vs := gpu.shader_init("ia_vert", vertex_code)
    shader_ps := gpu.shader_init("ia_frag", fragment_code)

    vertex_shader := gpu.Shader_IR {
        shader      = shader_vs,
        entry_point = "vertexMain",
    }
    fragment_shader := gpu.Shader_IR {
        shader      = shader_ps,
        entry_point = "fragmentMain",
    }

    state.pso = gpu.pipeline_init(vertex_shader, fragment_shader, {
        color_format = .BGRA8Unorm,
        depth_format = .None,
    })

    state.textures = gpu.texture_init({
        dimensions  = {63, 63},
        format      = .RGBA8Unorm,
        type        = ._2D_Array,
        storage     = .Shared,
        usage       = {.Sampled},
        layer_count = 2,
    })

    _upload_png_to_array_layer(state.textures, 0, #load("bowser.png", []u8), "bowser.png")
    _upload_png_to_array_layer(state.textures, 1, #load("peach.png", []u8), "peach.png")

    state.sampler = gpu.sampler_init({
        min_filter = .Nearest,
        mag_filter = .Nearest,
        mip_filter = .Nearest,
        wrap_s     = .ClampToEdge,
        wrap_t     = .ClampToEdge,
        wrap_r     = .ClampToEdge,
    })

    state.camera_pos = {0, 0, 2}
}

_update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.5
}

_render :: proc(previous, current: ^State, alpha: f32) {
    scl :: 0.33
    angle := math.lerp(previous.angle, current.angle, alpha)

    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    instances := gpu.arena_alloc(frame_arena, nuppu.Sprite_Instance, INSTANCE_COUNT)
    for &isnt, idx in ([^]nuppu.Sprite_Instance)(instances.cpu)[:INSTANCE_COUNT] {
        i := f32(idx) / f32(INSTANCE_COUNT)
        x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
        y_off := math.sin((i + angle) * 2 * math.PI)

        isnt = nuppu.pack_sprite_instance(
            position      = {x_off, y_off, 0},
            //color = {i, 1 - i, math.sin(math.PI * i), 1},
            rotation      = {0, 0, angle},
            scale         = {scl, scl},
            texture_layer = u32(idx % 2),
        )
    }

    uniforms := gpu.arena_alloc(frame_arena, nuppu.Engine_Uniform, 1)

    uniforms_data := nuppu.frame_uniform(nuppu.Camera{
        position     = current.camera_pos,
        near         = 0.1,
        far          = 1_000,
        fovy         = 80,
        aspect_ratio = nuppu.aspect_ratio(),
    })
    (^nuppu.Engine_Uniform)(uniforms.cpu)^ = uniforms_data

    gpu.unmap(&frame_arena.ptr)

    gpu.copy(nuppu.global_frame_uniform(), uniforms)
    gpu.copy(nuppu.global_sprite_instances(), instances)
    gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color  = {12, 12, 12, 255},
        load_action  = .Clear,
        store_action = .Store,
        texture      = swapchain,
    }, {})

    gpu.set_pipeline(current.pso)

    quad_mesh := nuppu.get_built_in_mesh(.Quad)

    block := gpu.Parameter_Block {
        constants = { 0 = nuppu.global_frame_uniform() },
        read_resources = {
            0 = quad_mesh.verts,
            1 = nuppu.global_sprite_instances(),
            2 = current.textures,
        },
        read_write_resources = {},
        samplers = { 0 = current.sampler },
    }

    gpu.use_parameter_block(&block)
    nuppu.draw_mesh(quad_mesh, INSTANCE_COUNT)

    gpu.end_render_pass()
    gpu.end_frame()
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