package main

import nuppu "../../../"
import "core:fmt"
import "core:log"
import "core:math"
import "core:time"
import "core:path/filepath"
import "core:os"
import "core:slice"

basic_app: ^Basic

Basic :: struct {
    v_shader: nuppu.Shader,
    f_shader: nuppu.Shader,

    pipeline: nuppu.Pipeline,

    instances_in_use: u32,

    depth_stencil_state: nuppu.Depth_Stencil_State,
    depth_texture: nuppu.Texture,

}

init :: proc() {

    basic_app.instances_in_use = 32

    nuppu.dr_init()
    mesh_cube := nuppu.dr_push_mesh(nuppu.UNIT_CUBE_VERTICES, nuppu.UNIT_CUBE_INDICES)
    mesh_quad := nuppu.dr_push_mesh(nuppu.UNIT_QUAD_VERTICES, nuppu.UNIT_QUAD_INDICES)

    basic_app.v_shader = nuppu.shader_init(#load("1-primitive.metal", []u8), "vertexMain", .Vertex)
    basic_app.f_shader = nuppu.shader_init(#load("1-primitive.metal", []u8), "fragmentMain", .Fragment)

    basic_app.pipeline = nuppu.pipeline_init(basic_app.v_shader, basic_app.f_shader, {.BGRA8Unorm_sRGB}, .Depth32Float)

    basic_app.depth_stencil_state = nuppu.depth_stencil_state_init(
        {
            compare_func = .Less,
            depth_write = true,
        }
    )
    basic_app.depth_texture = nuppu.texture_depth_init({1280, 720}, .Depth32Float)
}

deinit :: proc() {
    nuppu.shader_deinit(basic_app.v_shader)
    nuppu.shader_deinit(basic_app.f_shader)

    nuppu.pipeline_deinit(basic_app.pipeline)

    nuppu.dr_deinit()
}
import glm "core:math/linalg/glsl"

render :: proc(prev, curr: Basic, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {
    @static angle: f32
    angle += nuppu.delta_time_f32() * 0.5
    scl :: 0.15

    object_position := glm.vec3{0, 0, 0}
    rt := glm.mat4Translate(object_position)
    rr := glm.mat4Rotate({0, 1, 0}, -angle)
    rt_inv := glm.mat4Translate(-object_position)
    full_obj_rot := rt * rr * rt_inv

    temp_insts := nuppu.gpu_arena_alloc(arena, nuppu.Instance, curr.instances_in_use)
    instances_array := slice.from_ptr((^nuppu.Instance)(temp_insts.cpu), int(curr.instances_in_use))

    INSTANCE_COUNT := f32(curr.instances_in_use)
    for &inst, idx in instances_array {

        i := f32(idx) / INSTANCE_COUNT
        xoff := (i*2 - 1) + (1.0/INSTANCE_COUNT)
        yoff := math.sin((i + angle) * math.TAU)

        scale := glm.mat4Scale({scl, scl, scl})
        zrot := glm.mat4Rotate({0, 0, 1}, angle)
        yrot := glm.mat4Rotate({0, 1, 0}, angle)
        translate := glm.mat4Translate(object_position + {xoff, yoff, 0})

        inst.mesh_id = 0
        inst.transform = full_obj_rot * translate * yrot * zrot * scale
        inst.color = {i, 1-i, math.sin(math.TAU * i), 1}
    }

    cmds := nuppu.begin_commands()

    current_frames_instance_ptr := nuppu.dr.instances_gpu[pass.value % 3]
    nuppu.cmd_mem_copy(cmds, current_frames_instance_ptr, temp_insts, u64(size_of(nuppu.Instance) * math.min(curr.instances_in_use, nuppu.MAX_INSTANCES)))
    nuppu.cmd_barrier(cmds, .Transfer, .All)

    swapchain := nuppu.acquire_next_swapchain(cmds)

    window_size_px := nuppu.window_size_pixel()
    if nuppu.texture_size(swapchain).x != window_size_px.x || nuppu.texture_size(swapchain).y != window_size_px.y {
        nuppu.gpu_resize_swapchain()
        nuppu.remake_depth_texture(curr.depth_texture, {int(window_size_px.x), int(window_size_px.y)}, .Depth32Float)
    }

    nuppu.cmd_begin_render_pass(cmds, 
        {
            {
                clear_color = {64, 128, 255, 255},
                load_action = .Clear,
                store_action = .Store,
                texture = swapchain,
            }
        },
        {
            clear_depth = 1,
            load_action = .Clear,
            store_action = .Store,
            texture = curr.depth_texture,
        }
    )

    nuppu.cmd_set_pipeline(cmds, basic_app.pipeline)
    nuppu.cmd_set_depth_stencil_state(cmds, basic_app.depth_stencil_state)

    nuppu.cmd_use_resources(cmds, {
        {nuppu.dr.mesh_data, {.Read}, {.Vertex}},
        {nuppu.dr.vertex_data, {.Read}, {.Vertex}},
        {current_frames_instance_ptr, {.Read}, {.Vertex}},
    })

    @static z: f32 = -3
    //z += nuppu.delta_time_f32() * 3

    camera := nuppu.Camera {
        position = {0, 0, z},
        near = 0.01,
        far = 1_000,
        fovy = 90,
        aspect_ratio = nuppu.aspect_ratio(),
    }

    cam_data := nuppu.camera_data(camera, {0, 0, 0})
    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&cam_data, size_of(nuppu.Camera_Data)), 1, .Vertex)


    shader_data := nuppu.Shader_Data {
        instances = (^nuppu.Instance)(current_frames_instance_ptr.gpu),
        meshes = (^nuppu.Mesh)(nuppu.dr.mesh_data.gpu),
        vertices = (^[3]f32)(nuppu.dr.vertex_data.gpu),
    }
    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&shader_data, size_of(nuppu.Shader_Data)), 0, .Vertex)
    
    nuppu.cmd_set_cull_mode(cmds, .Back)
    nuppu.cmd_set_front_face_winding(cmds, .CounterClockwise)

    nuppu.cmd_draw_indiced_primitives(cmds,
    .Triangle,
    nuppu.dr.index_data,
    curr.instances_in_use)

    nuppu.cmd_end_render_pass(cmds)
    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc(Basic) {
    init = init,
    deinit = deinit,
    render = render,
}

config :: nuppu.App_Config {
    window_size = [2]i32{1280, 720},
    window_title = "Window",
}

main :: proc() {
    nuppu.app_init(
        _desc,
        &basic_app,
        config
    )
}