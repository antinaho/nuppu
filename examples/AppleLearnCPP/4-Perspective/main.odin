package main

import "core:math"
import "core:mem"
import glm "core:math/linalg/glsl"

import nuppu "../../.."
import gpu "../../../gpu"

state: ^Window

Window :: struct {
    angle: f32,

    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,
    camera_uniform: gpu.ptr,
    
    pso: gpu.Pipeline,
    depth_pso: gpu.Depth_Stencil_State,
}

Vertex :: struct #align(16) {
    position: [4]f32,
}

Instance :: struct #align(16) {
    transform: matrix[4, 4]f32,
    color: [4]f32
}

Camera :: struct #align(16) {
    world_transform: matrix[4, 4]f32,
    perspective_transform: matrix[4, 4]f32,
}

init :: proc() {
when ODIN_OS == .Darwin {
    vertex_code := #load("perspective.vs.metal", []u8)
    fragment_code := #load("perspective.ps.metal", []u8)
}
when ODIN_OS == .JS {
    // WGSL uses same shader for vertex and fragment
    vertex_code := #load("perspective.wgsl", []u8)
    fragment_code := vertex_code 
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

    upload := gpu.arena_init()

    s :: f32(0.5)
    VERT_COUNT :: 8
    INDEX_COUNT :: 6 * 6

    verts := gpu.arena_alloc(&upload, Vertex, VERT_COUNT)
    mem.copy_non_overlapping(
        verts.cpu, &[VERT_COUNT]Vertex {
            {{ -s, -s, +s, 1.0 }},
            {{ +s, -s, +s, 1.0 }},
            {{ +s, +s, +s, 1.0 }},
            {{ -s, +s, +s, 1.0 }},
            {{ -s, -s, -s, 1.0 }},
            {{ -s, +s, -s, 1.0 }},
            {{ +s, +s, -s, 1.0 }},
            {{ +s, -s, -s, 1.0 }},
        }, VERT_COUNT * size_of(Vertex)
    )

    indices := gpu.arena_alloc(&upload, u32, INDEX_COUNT)
    mem.copy_non_overlapping(indices.cpu, &[INDEX_COUNT]u32{
        0, 1, 2, /* front */
        2, 3, 0,

        1, 7, 6, /* right */
        6, 2, 1,

        7, 4, 5, /* back */
        5, 6, 7,

        4, 0, 3, /* left */
        3, 5, 4,

        3, 2, 6, /* top */
        6, 5, 3,

        4, 7, 1, /* bottom */
        1, 0, 4  
    }, INDEX_COUNT * size_of(u32))
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
}

INSTANCE_COUNT :: 18

update :: proc() {
    state.angle += nuppu.sim_delta_time() * 0.35
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

render :: proc(prev, curr: ^Window, alpha: f32) {
    scl :: 0.22
    angle := math.lerp(prev.angle, curr.angle, alpha)

    gpu.begin_frame()
    frame_arena := gpu.frame_arena()

    instances := gpu.arena_alloc(frame_arena, Instance, INSTANCE_COUNT)

    object_position := glm.vec3{0, 0, -4}
    rt := glm.mat4Translate(object_position)
    rr := glm.mat4Rotate({0, 1, 0}, -angle)
    rt_inv := glm.mat4Translate(-object_position)
    full_obj_rot := rt * rr * rt_inv
    
    for &instance, idx in ([^]Instance)(instances.cpu)[:INSTANCE_COUNT] {
        i := f32(idx) / INSTANCE_COUNT
        xoff := (i*2 - 1) + (1.0/INSTANCE_COUNT)
        yoff := math.sin((i + angle) * math.TAU)

        scale := glm.mat4Scale({scl, scl, scl})
        zrot := glm.mat4Rotate({0, 0, 1}, angle)
        yrot := glm.mat4Rotate({0, 1, 0}, angle)
        translate := glm.mat4Translate(object_position + {xoff, yoff, 0})

        instance.transform = full_obj_rot * translate * yrot * zrot * scale
        instance.color = {i, 1-i, math.sin(math.TAU * i), 1}
    }

    cam_ptr := gpu.arena_alloc(frame_arena, Camera, 1)
    
    cam := Camera {
        perspective_transform = glm.mat4Perspective(glm.radians_f32(45), nuppu.aspect_ratio(), 0.03, 500),
		world_transform = 1
    }

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

    gpu.set_pipeline(state.pso)
    gpu.set_depth_stencil_state(state.depth_pso)

    block := gpu.Parameter_Block {
        constants = { 
            0 = curr.camera_uniform 
        },
        read_resources = {
            0 = curr.vertex_gpu,
            1 = curr.instance_gpu,
        },
        read_write_resources = {},
        samplers = {},
    }

    gpu.use_parameter_block(&block)

    // Just using dedicated buffer for uniform for camera data right now so Metal + wgpu can have same code
    // gpu.temp_malloc(slice.bytes_from_ptr(&cam, size_of(Camera_Data)), 2, .Vertex)
    // gpu.set_cull_mode(.Back)
    // gpu.set_front_face_winding(.CCW)
    // gpu.set_buffers({state.vertex_gpu, curr.instance_gpu, curr.camera_uniform}, {0, 3}, .Vertex)
    
    gpu.draw_indiced_primitives(
    .Triangle,
    curr.index_gpu,
    6 * 6, 0,
    INSTANCE_COUNT,
    0, 0)

    gpu.end_render_pass()

    gpu.end_frame()    
}

desc := nuppu.App_Desc(Window) {
    state = &state,
    window_size = {1000, 1000},
    init = init,
    update = update,
    render = render,
}

main :: proc() {
    nuppu.run(desc)
}