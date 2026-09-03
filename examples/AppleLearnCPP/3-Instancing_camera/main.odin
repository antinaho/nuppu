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
import "base:intrinsics"

State :: struct {
    angle: f32,

    pso:      gpu.Pipeline,
    depth_pso: gpu.Depth_Stencil_State,
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

    state.depth_pso = gpu.depth_stencil_state_init({compare = .Less, write_enabled = true})

    state.pso = gpu.pipeline_init(vertex_shader, fragment_shader, {
        color_format = .BGRA8Unorm,
        depth_format = .Depth32Float,
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
    state.angle += nuppu.sim_delta_time() * 0.09
}

_render :: proc(previous, current: ^State, alpha: f32) {
    scl :: 0.33
    angle := math.lerp(previous.angle, current.angle, alpha)

    nuppu._batch.len = 0
    nuppu._batch.cap = 0

    nuppu._batch_2.len = 0
    nuppu._batch_2.cap = 0

    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    for idx in 0 ..< INSTANCE_COUNT {
        i := f32(idx) / f32(INSTANCE_COUNT)
        x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
        y_off := math.sin((i + angle) * 2 * math.PI)

        nuppu.draw_sprite(
            position      = {x_off, y_off, 0},
            rotation      = {0, 0, angle},
            scale         = {scl, scl},
            material_idx = u32(idx % 2),
        )
    }

    for idx in 0 ..< INSTANCE_COUNT {
        i := f32(idx) / f32(INSTANCE_COUNT)
        x_off := (i * 2 - 1) + (1.0 / INSTANCE_COUNT)
        y_off := math.sin((i + angle) * 2 * math.PI)

        nuppu.draw_cube(
            position      = {-y_off, -x_off, x_off * 0.5},
            rotation      = {0, angle, 0},
            scale         = {scl, scl, scl},
            material_idx = u32(idx % 2),
        )
    }

    nuppu._batch_2.last_len = nuppu._batch_2.len
    nuppu._batch.last_len = nuppu._batch.len
    
    sprite_instances_base := gpu.arena_alloc_raw(frame_arena, size_of(nuppu.Instance), uint(nuppu._batch.len), align_of(nuppu.Instance))    
    sprite_instances_data := gpu.arena_alloc_raw(frame_arena, size_of(nuppu.Sprite_Instance), uint(nuppu._batch.len), align_of(nuppu.Sprite_Instance))
    intrinsics.mem_copy_non_overlapping(sprite_instances_base.cpu, nuppu._batch.base_instances, size_of(nuppu.Instance) * nuppu._batch.len)
    intrinsics.mem_copy_non_overlapping(sprite_instances_data.cpu, nuppu._batch.frame_instances, size_of(nuppu.Sprite_Instance) * nuppu._batch.len)

    cube_instances_base := gpu.arena_alloc_raw(frame_arena, size_of(nuppu.Instance), uint(nuppu._batch_2.len), align_of(nuppu.Instance))
    cube_instances_data := gpu.arena_alloc_raw(frame_arena, size_of(nuppu.Mesh_Instance), uint(nuppu._batch_2.len), align_of(nuppu.Mesh_Instance))
    intrinsics.mem_copy_non_overlapping(cube_instances_base.cpu, nuppu._batch_2.base_instances, size_of(nuppu.Instance) * nuppu._batch_2.len)
    intrinsics.mem_copy_non_overlapping(cube_instances_data.cpu, nuppu._batch_2.frame_instances, size_of(nuppu.Mesh_Instance) * nuppu._batch_2.len)

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

    gpu.copy(nuppu.instances(), sprite_instances_base) // Sprite instances
    gpu.copy(nuppu.instances(), cube_instances_base, nuppu._batch.len * size_of(nuppu.Instance)) // Cube instances

    gpu.copy(nuppu.instances_data(), sprite_instances_data) // Sprites
    gpu.copy(nuppu.instances_data(), cube_instances_data, nuppu._batch.len * size_of(nuppu.Sprite_Instance)) // Cubes
    gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()
    gpu.begin_render_pass({
        clear_color  = {12, 12, 12, 255},
        load_action  = .Clear,
        store_action = .Store,
        texture      = swapchain,
    }, {
        load_action = .Clear,
        store_action = .Store,
        texture = gpu.depth(),
    })

    gpu.set_pipeline(current.pso)
    gpu.set_depth_stencil_state(current.depth_pso)

    nuppu.draw_mesh_builtin(.Quad, INSTANCE_COUNT)
    nuppu.draw_mesh_builtin(.Cube, INSTANCE_COUNT, nuppu._batch.len)

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