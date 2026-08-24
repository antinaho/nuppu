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

    g_shader: gpu.Shader_Handle,
    
    vertex_gpu: gpu.ptr,
    index_gpu: gpu.ptr,
    instance_gpu: gpu.ptr,
    camera_uniform: gpu.ptr,

    depth_pso: gpu.Depth_Stencil_Handle,
    pso: gpu.Pipeline_Handle,
    
    c_shader: gpu.Shader_Handle,
    compute_pso: gpu.Compute_Pipeline_Handle,

    uniform_animation_index: gpu.ptr,

    texture: gpu.Texture,

    sampler: gpu.Sampler,
}

init :: proc() {
when ODIN_OS == .Darwin {
    g_shader_code := #load("graphics.metal", []u8)
    k_shader_code := #load("compute.metal", []u8)
}
when ODIN_OS == .JS {
    g_shader_code := #load("graphics.wgsl", []u8)
    k_shader_code := #load("compute.wgsl", []u8)
}

    state.g_shader = gpu.shader_init("my_shader", g_shader_code)
    state.c_shader = gpu.compute_shader_init("my_compute_shader", k_shader_code)

    state.pso = gpu.pipeline_init(state.g_shader, "vertexMain", state.g_shader, "fragmentMain", .BGRA8Unorm, .Depth32Float)
    state.depth_pso = gpu.depth_stencil_state_init({compare = .Less, write_enabled = true})
    state.compute_pso = gpu.compute_pipeline_init(state.c_shader, "mandelbrot_set")

    state.texture = gpu.texture_init({
        dimensions = {TEXTURE_WIDTH, TEXTURE_HEIGHT},
        format = .RGBA8Unorm,
        type = ._2D,
        storage = .Shared,
        usage = .Storage
    })

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

    indices := gpu.arena_alloc(&upload, u32, INDEX_COUNT)
    runtime.mem_copy_non_overlapping(indices.cpu, &nuppu.UNIT_CUBE_INDICES, size_of(u32) * INDEX_COUNT)
    
    state.vertex_gpu = gpu.malloc(.GPU_Storage, VERT_COUNT, size_of(Vertex), align_of(Vertex), "Vertices")
    state.index_gpu = gpu.malloc_index(INDEX_COUNT, .Uint32, "Indices")
    state.instance_gpu = gpu.malloc(.GPU_Storage, INSTANCE_COUNT, size_of(Instance_Data), align_of(Instance_Data), "Instances")
    state.camera_uniform = gpu.malloc(.GPU_Constant, 1, size_of(Camera_Data), align_of(Camera_Data), "Camera")
    state.uniform_animation_index = gpu.malloc(.GPU_Constant, 1, size_of(Anim), align_of(Anim), "Animation")

    gpu.unmap(&upload.ptr)

    gpu.begin_commands()
    gpu.copy(state.vertex_gpu, verts)
    gpu.copy(state.index_gpu, indices)
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
Anim :: struct {
    frame: u32,
    _pad: [3]u32, // pad to 48 bytes
}
Vertex :: struct {
	position: glm.vec3,
    _pad: u32,
	normal:   glm.vec3,
    _pad2: u32,
    tex_coord: glm.vec2,
    _pad3: [2]u32, // pad to 48 bytes
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

    instances := gpu.arena_alloc(frame_arena, Instance_Data, INSTANCE_COUNT)
    object_position := glm.vec3{0, 0, -7}
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
    camera_ptr := gpu.arena_alloc(frame_arena, Camera_Data, 1)
    (^Camera_Data)(camera_ptr.cpu)^ = cam

    anim := Anim {
        frame = curr.animation_index,
    }
    animation_ptr := gpu.arena_alloc(frame_arena, Anim, 1)
    (^Anim)(animation_ptr.cpu)^ = anim
    
    gpu.unmap(&frame_arena.ptr)

    gpu.copy(curr.uniform_animation_index, animation_ptr)
    gpu.copy(curr.instance_gpu, instances)
    gpu.copy(curr.camera_uniform, camera_ptr)
    gpu.barrier(.Transfer, .All)

    gpu.set_compute_pipeline(state.compute_pso)
    gpu.set_buffers({curr.uniform_animation_index}, {0, 1}, .Compute)
    gpu.set_textures({curr.texture}, {0, 1}, .Compute)
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
    
    gpu.set_textures({curr.texture}, {0, 1}, .Fragment)
    gpu.set_buffers({curr.vertex_gpu, curr.instance_gpu, curr.camera_uniform}, {0, 3}, .Vertex)
    gpu.set_samplers({curr.sampler}, {0, 1}, .Fragment)
    
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
