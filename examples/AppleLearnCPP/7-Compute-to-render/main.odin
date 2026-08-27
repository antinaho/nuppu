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
    animation_index: u32,
    
    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,
    camera_uniform: gpu.ptr,
    animation_uniform: gpu.ptr,
    grid_uniform: gpu.ptr,

    depth_pso: gpu.Depth_Stencil_State,
    pso: gpu.Pipeline,
    
    texture: gpu.Texture,

    sampler: gpu.Sampler,

    compute_pso: gpu.Compute_Pipeline,
    kernel: gpu.Shader,
}

Vertex :: struct #align(4) {
	position: glm.vec3, 
	normal:   glm.vec3, 
    tex_coord: glm.vec2,
}

Instance :: struct #align(4) {
	transform:        glm.mat4,
	color:            glm.vec4,
	normal_transform: glm.mat3,
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
        format = .BGRA8Unorm,
        type = ._2D,
        storage = .Private,
        usage = .Storage,
    })

    state.kernel = gpu.compute_shader_init("my_compute_shader", compute_code)
    state.compute_pso = gpu.compute_pipeline_init(state.kernel, "mandelbrot_set")

    upload := gpu.arena()
    // defer nuppu.gpu_arena_deinit(&upload_arena)

    VERT_COUNT :: nuppu.UNIT_CUBE_VERTEX_COUNT
    INDEX_COUNT :: nuppu.UNIT_CUBE_INDEX_COUNT

    verts := gpu.arena_alloc(&upload, Vertex, VERT_COUNT)
    vs: [VERT_COUNT]Vertex
    for &v, idx in vs {
        v.position = nuppu.UNIT_CUBE_VERTICES[idx]
        v.normal = nuppu.UNIT_CUBE_NORMALS[idx]
        v.tex_coord = nuppu.UNIT_CUBE_TEXCOORDS[idx]
    }
    runtime.mem_copy_non_overlapping(verts.cpu, &vs, size_of(Vertex) * VERT_COUNT)

    grid_size := gpu.arena_alloc(&upload, [2]u32, 1)
    (^[2]u32)(grid_size.cpu)^ = {TEXTURE_WIDTH, TEXTURE_HEIGHT}

    indices := gpu.arena_alloc(&upload, u32, INDEX_COUNT)
    runtime.mem_copy_non_overlapping(indices.cpu, &nuppu.UNIT_CUBE_INDICES, size_of(u32) * INDEX_COUNT)
    
    state.vertex_gpu = gpu.malloc(.GPU_Storage, VERT_COUNT, size_of(Vertex), align_of(Vertex), "Vertices")
    state.index_gpu = gpu.malloc_index(INDEX_COUNT, .Uint32, "Indices")
    state.instance_gpu = gpu.malloc(.GPU_Storage, INSTANCE_COUNT, size_of(Instance), align_of(Instance), "Instances")
    state.camera_uniform = gpu.malloc(.GPU_Constant, 1, size_of(Camera), align_of(Camera), "Camera")
    state.animation_uniform = gpu.malloc(.GPU_Constant, 1, size_of(u32), align_of(u32), "Animation")
    state.grid_uniform = gpu.malloc(.GPU_Constant, 1, size_of([2]u32), align_of([2]u32), "Grid_Size")

    gpu.unmap(&upload.ptr)

    gpu.begin_commands()
    gpu.copy(state.vertex_gpu, verts)
    gpu.copy(state.index_gpu, indices)
    gpu.copy(state.grid_uniform, grid_size)
    gpu.barrier(.Transfer, .All)
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

deinit :: proc() {

}

update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.45
    state.animation_index = (state.animation_index + 1) % 5000
}

render :: proc(prev, curr: ^State, alpha: f32) {
    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    angle := math.lerp(prev.angle, curr.angle, alpha)

    instances := gpu.arena_alloc(frame_arena, Instance, INSTANCE_COUNT)
    object_position := glm.vec3{0, 0, -7}
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
        instance.normal_transform = glm.mat3(instance.transform)

        r := f32(idx) / INSTANCE_COUNT
        instance.color = {r, 1-r, math.sin(math.TAU * r), 1}
    }

    camera_ptr := gpu.arena_alloc(frame_arena, Camera, 1)
    cam := Camera {
		perspective_transform = glm.mat4Perspective(glm.radians_f32(45), nuppu.aspect_ratio(), 0.03, 500),
		world_transform = 1,
		world_normal_transform = glm.mat3(1)
    }
    (^Camera)(camera_ptr.cpu)^ = cam

    animation_ptr := gpu.arena_alloc(frame_arena, u32, 1)
    (^u32)(animation_ptr.cpu)^ = curr.animation_index
    
    
    gpu.unmap(&frame_arena.ptr)

    gpu.copy(curr.camera_uniform, camera_ptr)
    gpu.copy(curr.animation_uniform, animation_ptr)
    gpu.copy(curr.instance_gpu, instances)
    gpu.barrier(.Transfer, .All)

    gpu.set_compute_pipeline(state.compute_pso)

    compute_block := gpu.Parameter_Block {
        constants = {
            0 = curr.grid_uniform,
            1 = curr.animation_uniform,
        },
        read_resources = {},
        read_write_resources = {0 = curr.texture},
        samplers = {},
    }

    gpu.use_parameter_block(&compute_block, .Compute)

    gpu.compute_dispatch({TEXTURE_WIDTH, TEXTURE_HEIGHT, 1}, {128, 1, 1})
    gpu.barrier(.Compute, .All)
    
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

    gpu.set_pipeline(state.pso)
    gpu.set_depth_stencil_state(state.depth_pso)

    gpu.set_cull_mode(.Back)
    gpu.set_front_face_winding(.CCW)

    block := gpu.Parameter_Block {
        constants = { 0 = curr.camera_uniform },
        read_resources = {0 = curr.vertex_gpu, 1 = curr.instance_gpu, 2 = curr.texture},
        read_write_resources = {},
        samplers = {0 = curr.sampler},
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
