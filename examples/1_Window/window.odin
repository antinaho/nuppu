package main

import nuppu "../../"
import "core:fmt"
import "core:log"
import "core:math"
import "core:time"
import "core:path/filepath"


window_app: ^Window

Window :: struct {
    number: [2]f32,

    v_shader: nuppu.Shader,
    f_shader: nuppu.Shader,

    verts_gpu: nuppu.ptr,
    indices_gpu: nuppu.ptr,

    pipeline: nuppu.Pipeline,

    depth_so: nuppu.Depth_Stencil_State,
}

Vertex :: struct {
    position: [2]f32,
    tex_coords: [2]f32,
    color: [4]f32,
}

init :: proc() {
    window_app.v_shader = nuppu.shader_init(#load("triangle.metal", []u8), "vertexMain", .Vertex)
    window_app.f_shader = nuppu.shader_init(#load("triangle.metal", []u8), "fragmentMain", .Fragment)

    window_app.pipeline = nuppu.pipeline_init(window_app.v_shader, window_app.f_shader, {.RGBA8Unorm}, .Invalid)

    window_app.depth_so = nuppu.depth_stencil_state_init(nuppu.Depth_Stencil_State_Descriptor {
        compare_func = .Less,
        depth_write = true,
    })

    upload_arena := nuppu.gpu_arena_init()
    defer nuppu.gpu_arena_deinit(&upload_arena)

    verts := nuppu.gpu_arena_alloc_T(&upload_arena, Vertex, 4)
    verts_array := ([^]Vertex)(verts.cpu)
    verts_array[0] = {position = {-0.5,  0.5}, tex_coords = {}, color = {1, 0, 0, 1}}
    verts_array[1] = {position = { 0.5,  0.5}, tex_coords = {}, color = {0, 1, 0, 1}}
    verts_array[2] = {position = { 0.5, -0.5}, tex_coords = {}, color = {0, 0, 1, 1}}
    verts_array[3] = {position = {-0.5, -0.5}, tex_coords = {}, color = {1, 1, 0, 1}}

    indices := nuppu.gpu_arena_alloc_T(&upload_arena, u32, 6)
    indices_array := ([^]u32)(indices.cpu)
    indices_array[0] = 0
    indices_array[1] = 2
    indices_array[2] = 1
    indices_array[3] = 0
    indices_array[4] = 3
    indices_array[5] = 2

    window_app.verts_gpu = nuppu.gpu_malloc(size_of(Vertex) * 4, align_of(Vertex), .GPU_Only)
    window_app.indices_gpu = nuppu.gpu_malloc(size_of(u32) * 6, align_of(u32), .GPU_Only)

    cmds := nuppu.begin_commands()
    nuppu.cmd_mem_copy(cmds, window_app.verts_gpu, verts, size_of(Vertex) * 4)
    nuppu.cmd_mem_copy(cmds, window_app.indices_gpu, indices, size_of(u32) * 6)
    nuppu.end_commands(cmds, {})


    path := fmt.tprintf("%v/%v", #directory, "viking_room.png")
    png := nuppu.png_init(path, {.alpha_add_if_missing})
    defer nuppu.png_deinit(png)

    texture_descriptor := nuppu.Texture_Descriptor {
        dimensions = {png.width, png.height},
        format = .RGBA8Unorm,
    }

    texture := nuppu.texture_init(texture_descriptor)
    sampler := nuppu.sampler_init(nuppu.Sampler_Descriptor {
        min_filter = .Linear,
        mag_filter = .Linear,
        mip_filter = .Linear,
        address_mode = [3]nuppu.Sampler_Address_Mode {
            .ClampToEdge,
            .ClampToEdge,
            .ClampToEdge,
        },        
    })


}

deinit :: proc() {
    nuppu.shader_deinit(window_app.v_shader)
    nuppu.shader_deinit(window_app.f_shader)

    nuppu.depth_stencil_state_deinit(window_app.depth_so)
    nuppu.pipeline_deinit(window_app.pipeline)

    nuppu.gpu_free(window_app.verts_gpu)
    nuppu.gpu_free(window_app.indices_gpu)
}

update :: proc() {
    window_app.number.x = math.sin(nuppu.sim_time() * 0.33) * 0.33
    window_app.number.y = math.cos(nuppu.sim_time() * 0.33) * 0.33
}

render :: proc(prev, curr: Window, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {

    cmds := nuppu.begin_commands()
    swapchain := nuppu.acquire_next_swapchain(cmds)

    nuppu.cmd_begin_render_pass(cmds, {
        {
            load_action = .Clear,
            store_action = .Store,
            texture = swapchain,
        }
    })

    Data :: struct {
        extra: [2]f32,
        verts: ^Vertex,
    }
    position := math.lerp(prev.number, curr.number, alpha)

    data_ptr := nuppu.gpu_arena_alloc_T(arena, Data)
    (^Data)(data_ptr.cpu)^ = Data {
        extra = position,
        verts = (^Vertex)(window_app.verts_gpu.gpu)
    }

    nuppu.cmd_set_pipeline(cmds, window_app.pipeline)
    // nuppu.MTL_cmd_set_depth_stencil_state(cmds, window_app.depth_so) // This after we have depth texture and such into renderpass

    nuppu.cmd_draw(cmds, data_ptr, window_app.indices_gpu, 1, {
        {window_app.verts_gpu, {.Read}, {.Vertex}},
    })

    nuppu.cmd_end_render_pass(cmds)
    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc(Window) {
    init = init,
    deinit = deinit,
    update = update,
    render = render,
}

config :: nuppu.App_Config {
    window_size = [2]i32{800, 600},
    window_title = "Window",
}

main :: proc() {
    nuppu.app_init(
        _desc,
        &window_app,
        config
    )
}