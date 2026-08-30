package main

import nuppu "../../.."
import gpu "../../../gpu"
import "core:math"
import glm "core:math/linalg/glsl"
import "base:runtime"
import "base:intrinsics"
import "core:fmt"

state: ^State

State :: struct {
    angle: f32,
    
    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,
    camera_uniform: gpu.ptr,

    depth_pso: gpu.Depth_Stencil_State,
    pso: gpu.Pipeline,
    
    texture: gpu.Texture,

    sampler: gpu.Sampler,

    compute_pso: gpu.Compute_Pipeline,
    kernel: gpu.Shader,
}

Vertex :: struct #align(4) {
	position: glm.vec4, 
	normal:   glm.vec4, 
    tex_coord: glm.vec2,
    _pad: [2]u32,
}

Instance :: struct #align(4) {
	transform:        glm.mat4,
	color:            glm.vec4,
	normal_transform: [16]f32,
}

Camera :: struct #align(4) {
    perspective_transform:  glm.mat4,
    world_transform:        glm.mat4,
    world_normal_transform: glm.mat3,
}

init :: proc() {
when ODIN_OS == .Darwin {
    vertex_code := #load("compute.vs.metal", []u8)
    fragment_code := #load("compute.ps.metal", []u8)
    compute_code := #load("mandelbrot.metal", []u8)
}
when ODIN_OS == .JS {
    // WGSL uses same shader for vertex and fragment
    vertex_code := #load("compute.wgsl", []u8)
    fragment_code := vertex_code 
    compute_code := #load("mandelbrot.wgsl", []u8)
}

    shader_vs := gpu.shader_init("my_vert_shader", vertex_code)
    shader_ps := gpu.shader_init("my_frag_shader", fragment_code)

    vertex_shader := gpu.Shader_IR {
        shader = shader_vs,
        entry_point = "vertexMain",
    }

    fragment_shader := gpu.Shader_IR {
        shader = shader_ps,
        entry_point = "fragmentMain",
    }

    state.pso = gpu.pipeline_init(vertex_shader, fragment_shader, {
        color_format = .BGRA8Unorm,
        depth_format = .Depth32Float,
    })
    
    state.depth_pso = gpu.depth_stencil_state_init({compare = .Less, write_enabled = true})

    state.texture = gpu.texture_init({
        dimensions = {TEXTURE_WIDTH, TEXTURE_HEIGHT},
        format = .RGBA8Unorm,
        type = ._2D,
        storage = .Shared,
        usage = {.Write, .Sampled},
    })

    state.kernel = gpu.shader_init("my_compute_shader", compute_code)
    state.compute_pso = gpu.compute_pipeline_init(state.kernel, "mandelbrot_set")
    
    upload := gpu.arena_init()
    //defer nuppu.gpu_arena_deinit(&upload_arena)

    s :: f32(0.5)
    VERT_COUNT :: 24
    INDEX_COUNT :: 6 * 6

    verts := gpu.arena_alloc(&upload, Vertex, VERT_COUNT)
    vs := [VERT_COUNT]Vertex {
		//                                                       Texture
		//   Positions (.xyz)        Normals (.xyz)            Coordinates
		{{-s, -s, +s, 1}, { 0, 0, 1, 1}, {0, 1}, {}},
		{{+s, -s, +s, 1}, { 0, 0, 1, 1}, {1, 1}, {}},
		{{+s, +s, +s, 1}, { 0, 0, 1, 1}, {1, 0}, {}},
		{{-s, +s, +s, 1}, { 0, 0, 1, 1}, {0, 0}, {}},

		{{+s, -s, +s, 1}, { 1, 0, 0, 1}, {0, 1}, {}},
		{{+s, -s, -s, 1}, { 1, 0, 0, 1}, {1, 1}, {}},
		{{+s, +s, -s, 1}, { 1, 0, 0, 1}, {1, 0}, {}},
		{{+s, +s, +s, 1}, { 1, 0, 0, 1}, {0, 0}, {}},

		{{+s, -s, -s, 1}, { 0, 0, -1, 1}, {0, 1}, {}},
		{{-s, -s, -s, 1}, { 0, 0, -1, 1}, {1, 1}, {}},
		{{-s, +s, -s, 1}, { 0, 0, -1, 1}, {1, 0}, {}},
		{{+s, +s, -s, 1}, { 0, 0, -1, 1}, {0, 0}, {}},

		{{-s, -s, -s, 1}, {-1, 0, 0, 1}, {0, 1}, {}},
		{{-s, -s, +s, 1}, {-1, 0, 0, 1}, {1, 1}, {}},
		{{-s, +s, +s, 1}, {-1, 0, 0, 1}, {1, 0}, {}},
		{{-s, +s, -s, 1}, {-1, 0, 0, 1}, {0, 0}, {}},

		{{-s, +s, +s, 1}, { 0, 1, 0, 1}, {0, 1}, {}},
		{{+s, +s, +s, 1}, { 0, 1, 0, 1}, {1, 1}, {}},
		{{+s, +s, -s, 1}, { 0, 1, 0, 1}, {1, 0}, {}},
		{{-s, +s, -s, 1}, { 0, 1, 0, 1}, {0, 0}, {}},

		{{-s, -s, -s, 1}, { 0, -1, 0, 1}, {0, 1}, {}},
		{{+s, -s, -s, 1}, { 0, -1, 0, 1}, {1, 1}, {}},
		{{+s, -s, +s, 1}, { 0, -1, 0, 1}, {1, 0}, {}},
		{{-s, -s, +s, 1}, { 0, -1, 0, 1}, {0, 0}, {}},
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
    state.instance_gpu = gpu.malloc(.GPU_Storage, INSTANCE_COUNT, size_of(Instance), align_of(Instance), "Instances")
    state.camera_uniform = gpu.malloc(.GPU_Constant, 1, size_of(Camera), align_of(Camera), "Camera")
 
    gpu.begin_commands()
    gpu.copy(state.vertex_gpu, verts)
    gpu.copy(state.index_gpu, indices)
    gpu.barrier(.Transfer, .All)
    gpu.commit_commands()

    gpu.begin_commands()
    gpu.set_compute_pipeline(state.compute_pso)

    compute_block := gpu.Parameter_Block {
        constants = { },
        read_resources = { },
        read_write_resources = { 0 = state.texture },
        samplers = { },
    }
    gpu.use_parameter_block(&compute_block, .Compute)
    
    gpu.compute_dispatch({TEXTURE_WIDTH, TEXTURE_HEIGHT, 1}, {128, 1, 1})
    gpu.barrier(.Compute, .All)
    gpu.commit_commands()   

    state.sampler = gpu.sampler_init({
        min_filter = .Linear,
        mag_filter = .Linear,
        mip_filter = .Linear,
        wrap_s = .Repeat,
        wrap_t = .Repeat,
        wrap_r = .Repeat,
    })
}

INSTANCE_WIDTH  :: 10
INSTANCE_HEIGHT :: 10
INSTANCE_DEPTH  :: 10
INSTANCE_COUNT   :: INSTANCE_WIDTH*INSTANCE_HEIGHT*INSTANCE_DEPTH

TEXTURE_WIDTH  :: 128
TEXTURE_HEIGHT :: 128

deinit :: proc() { }

update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.45
}

render :: proc(prev, curr: ^State, alpha: f32) {
    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    instances := gpu.arena_alloc(frame_arena, Instance, INSTANCE_COUNT)

    angle := math.lerp(prev.angle, curr.angle, alpha)
    object_position := glm.vec3{0, 0, -10}
    rt := glm.mat4Translate(object_position)
    rr1 := glm.mat4Rotate({0, 1, 0}, -angle)
    rr0 := glm.mat4Rotate({1, 0, 0}, angle*0.5)
    rt_inv := glm.mat4Translate(-object_position)
    full_obj_rot := rt * rr1 * rr0 * rt_inv


    ix, iy, iz := 0, 0, 0

    for &instance, idx in ([^]Instance)(instances.cpu)[:INSTANCE_COUNT] {
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
        instance.normal_transform = intrinsics.matrix_flatten(glm.mat4(glm.mat3(instance.transform)))

        r := f32(idx) / INSTANCE_COUNT
        instance.color = {r, 1-r, math.sin(math.TAU * r), 1}
    }

    cam := Camera {
		perspective_transform = glm.mat4Perspective(glm.radians_f32(45), nuppu.aspect_ratio(), 0.03, 500),
		world_transform = 1,
		world_normal_transform = glm.mat3(1)
    }
    cam_ptr := gpu.arena_alloc(frame_arena, Camera, 1)
    (^Camera)(cam_ptr.cpu)^ = cam

    gpu.unmap(&frame_arena.ptr)

    gpu.copy(curr.instance_gpu, instances)
    gpu.copy(curr.camera_uniform, cam_ptr)
    gpu.barrier(.Transfer, .All)

    swapchain := gpu.acquire_next_swapchain()

    gpu.begin_render_pass(
        {
            clear_color = {12, 12, 12, 255},
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
    
    block := gpu.Parameter_Block {
        constants = { 0 = curr.camera_uniform },
        read_resources = { 0 = curr.vertex_gpu, 1 = curr.instance_gpu, 2 = curr.texture },
        read_write_resources = {},
        samplers = { 0 = curr.sampler },
    }

    gpu.use_parameter_block(&block)
    
    gpu.draw_indiced_primitives(
    .Triangle,
    curr.index_gpu,
    6 * 6, 0,
    INSTANCE_COUNT,
    0, 0)

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