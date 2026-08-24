package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:log"
import "core:math"
import "core:slice"
import "core:mem"
import glm "core:math/linalg/glsl"
import "base:runtime"

state: ^State

State :: struct {
    angle: f32,

    shader: gpu.Shader_Handle,
    

    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,
    camera_uniform: gpu.ptr,


    depth_pso: gpu.Depth_Stencil_Handle,
    pso: gpu.Pipeline_Handle,
}

init :: proc() {
when ODIN_OS == .Darwin {
    shader_code := #load("lighting.metal", []u8)
}
when ODIN_OS == .JS {
    shader_code := #load("lighting.wgsl", []u8)
}
    state.shader = gpu.shader_init("my_shader", shader_code)
    state.pso = gpu.pipeline_init(state.shader, "vertexMain", state.shader, "fragmentMain", .BGRA8Unorm, .Depth32Float)
    state.depth_pso = gpu.depth_stencil_state_init({compare = .Less, write_enabled = true})

    upload := gpu.arena()
    // defer nuppu.gpu_arena_deinit(&upload_arena)

    s :: f32(0.5)
    VERT_COUNT :: 24
    INDEX_COUNT :: 6 * 6

    verts := gpu.arena_alloc(&upload, Vertex, VERT_COUNT)
    vs := [VERT_COUNT]Vertex {
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

    runtime.mem_copy_non_overlapping(verts.cpu, &vs, size_of(Vertex) * VERT_COUNT)

    indices := gpu.arena_alloc(&upload, u32, INDEX_COUNT)
    is := [INDEX_COUNT]u32 {
		 0,  1,  2,  2,  3,  0, // front
		 4,  5,  6,  6,  7,  4, // right
		 8,  9, 10, 10, 11,  8, // back
		12, 13, 14, 14, 15, 12, // left
		16, 17, 18, 18, 19, 16, // top
		20, 21, 22, 22, 23, 20, // bottom
    }
    runtime.mem_copy_non_overlapping(indices.cpu, &is, size_of(u32) * INDEX_COUNT)

    gpu.unmap(&upload.ptr)

    state.vertex_gpu = gpu.malloc(.GPU_Storage, VERT_COUNT, size_of(Vertex), align_of(Vertex), "Vertices")
    state.index_gpu = gpu.malloc_index(INDEX_COUNT, .Uint32, "Indices")
    state.instance_gpu = gpu.malloc(.GPU_Storage, INSTANCE_COUNT, size_of(Instance_Data), align_of(Instance_Data), "Instances")
    state.camera_uniform = gpu.malloc(.GPU_Constant, 1, size_of(Camera_Data), align_of(Camera_Data), "Camera")

    gpu.begin_commands()
    gpu.copy(state.vertex_gpu, verts)
    gpu.copy(state.index_gpu, indices)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()
}

update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.3
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
    // nuppu.shader_deinit(state.v_shader)
    // nuppu.shader_deinit(state.f_shader)

    // nuppu.pipeline_deinit(state.pipeline)

    // nuppu.gpu_free(state.vertex_gpu)
    // nuppu.gpu_free(state.index_gpu)
    // nuppu.gpu_free(state.instance_gpu)

    // nuppu.depth_stencil_state_deinit(state.depth_stencil_state)
}

render :: proc(prev, curr: ^State, alpha: f32) {
    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    instances := gpu.arena_alloc(frame_arena, Instance_Data, INSTANCE_COUNT)
    
    angle := math.lerp(prev.angle, curr.angle, alpha)

    scl :: 0.1
    object_position := glm.vec3{0, 0, -10}
    rt := glm.mat4Translate(object_position)
    rr1 := glm.mat4Rotate({0, 1, 0}, -angle)
    rr0 := glm.mat4Rotate({1, 0, 0}, angle*0.5)
    rt_inv := glm.mat4Translate(-object_position)
    full_obj_rot := rt * rr1 * rr0 * rt_inv

    ix, iy, iz := 0, 0, 0

    for &instance, idx in ([^]Instance_Data)(instances.cpu)[:INSTANCE_COUNT] {
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

    cam := Camera_Data {
		perspective_transform = glm.mat4Perspective(glm.radians_f32(45), nuppu.aspect_ratio(), 0.03, 500),
		world_transform = 1,
		world_normal_transform = glm.mat3(1)
    }

    cam_ptr := gpu.arena_alloc(frame_arena, Camera_Data, 1)
    (^Camera_Data)(cam_ptr.cpu)^ = cam

    gpu.unmap(&frame_arena.ptr)

    gpu.copy(curr.camera_uniform, cam_ptr)
    gpu.copy(curr.instance_gpu, instances)
    gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()

    gpu.begin_render_pass(
        {
            clear_color = {64, 128, 255, 255},
            load_action = .Clear,
            store_action = .Store,
            texture = swapchain,
        },
        {
            load_action = .Clear,
            store_action = .Store,
            texture = gpu.depth(),
        }
    )

    gpu.set_pipeline(curr.pso)
    gpu.set_depth_stencil_state(curr.depth_pso)



    gpu.set_cull_mode(.Back)
    gpu.set_front_face_winding(.CCW)
//    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&cam, size_of(Camera_Data)), 2, .Vertex)
    gpu.set_buffers({curr.vertex_gpu, curr.instance_gpu, curr.camera_uniform}, {0, 3}, .Vertex)

    gpu.draw_indiced_primitives(
    .Triangle,
    curr.index_gpu,
    6 * 6, 0,
    INSTANCE_COUNT,
    0, 0)
    
    // nuppu.cmd_draw_indiced_primitives(cmds,
    // .Triangle,
    // state.index_gpu,
    // INSTANCE_COUNT)

    gpu.end_render_pass()
    
    gpu.end_frame()
}

desc := nuppu.App_Desc(State) {
    state = &state,
    window_size = {1000, 1000},
    init = init,
    update = update,
    render = render,
}

main :: proc() {
    nuppu.run(desc)
}