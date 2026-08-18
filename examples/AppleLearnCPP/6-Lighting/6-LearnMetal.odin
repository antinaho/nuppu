package main

import nuppu "../../../"
import "core:log"
import "core:math"
import "core:slice"
import "core:mem"
import glm "core:math/linalg/glsl"

window_app: ^Window

Window :: struct {
    number: [2]f32,

    v_shader: nuppu.Shader,
    f_shader: nuppu.Shader,

    vertex_gpu: nuppu.ptr,
    index_gpu: nuppu.ptr,
    instance_gpu: nuppu.ptr,

    depth_stencil_state: nuppu.Depth_Stencil_State,

    pipeline: nuppu.Pipeline,
    depth_texture: nuppu.Texture,
}

init :: proc() {
    window_app.v_shader = nuppu.shader_init(#load("6-lighting.metal", []u8), "vertexMain", .Vertex)
    window_app.f_shader = nuppu.shader_init(#load("6-lighting.metal", []u8), "fragmentMain", .Fragment)

    window_app.pipeline = nuppu.pipeline_init(window_app.v_shader, window_app.f_shader, {.BGRA8Unorm_sRGB}, .Depth32Float)
    window_app.depth_stencil_state = nuppu.depth_stencil_state_init(
        {
            compare_func = .Less,
            depth_write = true,
        }
    )

    upload_arena := nuppu.gpu_arena_init()
    defer nuppu.gpu_arena_deinit(&upload_arena)

    s :: f32(0.5)
    VERT_COUNT :: 24
    INDEX_COUNT :: 6 * 6

    verts := nuppu.gpu_arena_alloc(&upload_arena, Vertex, VERT_COUNT)
    vs := []Vertex {
        //   Positions     Normals
		{{-s, -s, +s}, {0,  0,  1}},
		{{+s, -s, +s}, {0,  0,  1}},
		{{+s, +s, +s}, {0,  0,  1}},
		{{-s, +s, +s}, {0,  0,  1}},
		{{+s, -s, +s}, {1,  0,  0}},
		{{+s, -s, -s}, {1,  0,  0}},
		{{+s, +s, -s}, {1,  0,  0}},
		{{+s, +s, +s}, {1,  0,  0}},
		{{+s, -s, -s}, {0,  0, -1}},
		{{-s, -s, -s}, {0,  0, -1}},
		{{-s, +s, -s}, {0,  0, -1}},
		{{+s, +s, -s}, {0,  0, -1}},

		{{-s, -s, -s}, {-1, 0,  0}},
		{{-s, -s, +s}, {-1, 0,  0}},
		{{-s, +s, +s}, {-1, 0,  0}},
		{{-s, +s, -s}, {-1, 0,  0}},

		{{-s, +s, +s}, {0,  1,  0}},
		{{+s, +s, +s}, {0,  1,  0}},
		{{+s, +s, -s}, {0,  1,  0}},
		{{-s, +s, -s}, {0,  1,  0}},

		{{-s, -s, -s}, {0, -1,  0}},
		{{+s, -s, -s}, {0, -1,  0}},
		{{+s, -s, +s}, {0, -1,  0}},
		{{-s, -s, +s}, {0, -1,  0}},
    }
    nuppu.gpu_ptr_fill_slice(verts, vs)

    indices := nuppu.gpu_arena_alloc(&upload_arena, u32, INDEX_COUNT)
    is := []u32 {
		 0,  1,  2,  2,  3,  0, // front
		 4,  5,  6,  6,  7,  4, // right
		 8,  9, 10, 10, 11,  8, // back
		12, 13, 14, 14, 15, 12, // left
		16, 17, 18, 18, 19, 16, // top
		20, 21, 22, 22, 23, 20, // bottom
    }
    nuppu.gpu_ptr_fill_slice(indices, is)

    window_app.vertex_gpu = nuppu.__gpu_malloc_bytes(size_of(Vertex) * VERT_COUNT, align_of(Vertex), .GPU_Only)
    window_app.index_gpu = nuppu.__gpu_malloc_bytes(size_of(u32) * INDEX_COUNT, align_of(u32), .GPU_Only)
    window_app.instance_gpu = nuppu.__gpu_malloc_bytes(size_of(Instance_Data) * INSTANCE_COUNT, align_of(Instance_Data), .GPU_Only)

    cmds := nuppu.begin_commands()
    nuppu.cmd_mem_copy(cmds, window_app.vertex_gpu, verts, size_of(Vertex) * VERT_COUNT)
    nuppu.cmd_mem_copy(cmds, window_app.index_gpu, indices, size_of(u32) * INDEX_COUNT)
    nuppu.cmd_barrier(cmds, .Transfer, .All)
    nuppu.end_commands(cmds, {})

    window_app.depth_texture = nuppu.texture_depth_init({1280, 720}, .Depth32Float)
}

Vertex :: struct {
	position: glm.vec3,
	normal:   glm.vec3,
}

INSTANCE_WIDTH  :: 10
INSTANCE_HEIGHT :: 10
INSTANCE_DEPTH  :: 10
INSTANCE_COUNT   :: INSTANCE_WIDTH*INSTANCE_HEIGHT*INSTANCE_DEPTH
Instance_Data :: struct #align(16) {
	transform:        glm.mat4,
	color:            glm.vec4,
	normal_transform: glm.mat3,
}

Camera_Data :: struct #align(16) {
    perspective_transform:  glm.mat4,
    world_transform:        glm.mat4,
    world_normal_transform: glm.mat3,
}

deinit :: proc() {
    nuppu.shader_deinit(window_app.v_shader)
    nuppu.shader_deinit(window_app.f_shader)

    nuppu.pipeline_deinit(window_app.pipeline)

    nuppu.gpu_free(window_app.vertex_gpu)
    nuppu.gpu_free(window_app.index_gpu)
    nuppu.gpu_free(window_app.instance_gpu)

    nuppu.depth_stencil_state_deinit(window_app.depth_stencil_state)
}

render :: proc(prev, curr: rawptr, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {
    curr := (^Window)(curr)
    prev := (^Window)(prev)

    @static angle: f32
    angle += nuppu.delta_time_f32() * 0.45

    instances := nuppu.gpu_arena_alloc(arena, Instance_Data, INSTANCE_COUNT)
    instances_array := slice.from_ptr((^Instance_Data)(instances.cpu), INSTANCE_COUNT)
    
    scl :: 0.1
    object_position := glm.vec3{0, 0, -10}
    rt := glm.mat4Translate(object_position)
    rr1 := glm.mat4Rotate({0, 1, 0}, -angle)
    rr0 := glm.mat4Rotate({1, 0, 0}, angle*0.5)
    rt_inv := glm.mat4Translate(-object_position)
    full_obj_rot := rt * rr1 * rr0 * rt_inv

    ix, iy, iz := 0, 0, 0

    for &instance, idx in instances_array {
        if ix == INSTANCE_WIDTH {
            ix = 0
            iy += 1
        }
        if iy == INSTANCE_HEIGHT {
            iy = 0
            iz += 1
        }
        defer ix += 1

        scl :: 0.2

        scale := glm.mat4Scale({scl, scl, scl})
        zrot := glm.mat4Rotate({0, 0, 1}, angle * math.sin(f32(ix)))
        yrot := glm.mat4Rotate({0, 1, 0}, angle * math.cos(f32(iy)))

        pos := glm.vec3{
            (f32(ix) - INSTANCE_WIDTH * 0.5) * 2*scl + scl,
            (f32(iy) - INSTANCE_HEIGHT* 0.5) * 2*scl + scl,
            (f32(iz) - INSTANCE_DEPTH * 0.5) * 2*scl,
        }

        translate := glm.mat4Translate(object_position + pos)

        instance.transform = full_obj_rot * translate * yrot * zrot * scale
        instance.normal_transform = glm.mat3(instance.transform)

        r := f32(idx) / INSTANCE_COUNT
        instance.color = {r, 1-r, math.sin(math.TAU * r), 1}
    }

    cmds := nuppu.begin_commands()

    nuppu.cmd_mem_copy(cmds, curr.instance_gpu, instances, size_of(Instance_Data) * INSTANCE_COUNT)
    nuppu.cmd_barrier(cmds, .Transfer, .All)

    swapchain := nuppu.acquire_next_swapchain(cmds)

    nuppu.cmd_begin_render_pass(cmds, {
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

    nuppu.cmd_set_pipeline(cmds, window_app.pipeline)
    nuppu.cmd_set_depth_stencil_state(cmds, window_app.depth_stencil_state)

    cam := Camera_Data {
		perspective_transform = glm.mat4Perspective(glm.radians_f32(45), nuppu.aspect_ratio(), 0.03, 500),
		world_transform = 1,
		world_normal_transform = glm.mat3(1)
    }

    nuppu.cmd_set_cull_mode(cmds, .Back)
    nuppu.cmd_set_front_face_winding(cmds, .CounterClockwise)
    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&cam, size_of(Camera_Data)), 2, .Vertex)
    nuppu.cmd_set_buffers(cmds, {window_app.vertex_gpu, curr.instance_gpu}, {0, 0}, {0, 2}, .Vertex)
    nuppu.cmd_draw_indiced_primitives(cmds,
    .Triangle,
    window_app.index_gpu,
    INSTANCE_COUNT)

    nuppu.cmd_end_render_pass(cmds)
    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc {
    size = size_of(Window),
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
        &window_app,
        config
    )
}
