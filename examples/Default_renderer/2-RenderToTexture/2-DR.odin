package main

import nuppu "../../../"
import "core:math"
import "core:slice"
import "core:container/handle_map"
import "core:mem"
import glm "core:math/linalg/glsl"
import "core:fmt"
import "core:sort"
import "core:log"

// 2-RenderToTexture
//
// Demonstrates the canonical pixel-art "small render target, large window"
// workflow:
//
//   1. Create a small offscreen render target texture (200x200).
//   2. Render a rotating cube grid into that target with cmd_begin_render_pass.
//   3. Stretch the offscreen target to fill the swapchain by drawing a single
//      fullscreen triangle that samples scene_color with `filter::nearest`.
//      The aspect ratio of the render target is preserved — extra space on
//      the window is letterboxed (or pillarboxed) with a clean dark fill
//      colour sourced from the swapchain's own clear.
//
// The letterbox bars are produced by a GPU scissor rectangle that clips
// the fullscreen triangle to the letterboxed pixel region. Fragments
// outside the scissor are discarded, letting the swapchain's clear colour
// show through. This is the canonical way to do partial-screen rendering
// and works for both letterbox (window taller than scene) and pillarbox
// (window wider than scene) cases.
//
// This is the right pattern for:
//   * Pixel-art games (render once at a low resolution, scale up crisply)
//   * Mini-maps / viewfinder style UI (render at native size, scale up)
//   * Post-processing pipelines (sample the offscreen target in another shader)
//   * Save-to-file workflows (read the offscreen target back to CPU)
//
// The library also exposes `cmd_blit_texture` for the simpler 1:1 byte-copy
// case; this example focuses on the stretched-sampling variant because
// that's the only way to actually fill the swapchain from a small target.
//
// We deliberately reuse the Default_Renderer (`dr_init`, `dr_push_mesh`) so
// the focus is on the render-target + fullscreen-triangle workflow rather
// than mesh plumbing.

basic_app: ^Basic

Basic :: struct {
    // Shaders + pipeline for the offscreen scene (renders INTO the render target).
    scene_v_shader: nuppu.Shader,
    scene_f_shader: nuppu.Shader,
    scene_pipeline: nuppu.Pipeline,

    // Shaders + pipeline for the screen pass (samples scene_color, stretches
    // it to fill the swapchain with letterboxing).
    screen_v_shader: nuppu.Shader,
    screen_f_shader: nuppu.Shader,
    screen_pipeline: nuppu.Pipeline,

    depth_stencil_state: nuppu.Depth_Stencil_State,

    // The 200x200 offscreen color + depth attachments. The color target carries
    // both `RenderTarget` (so we can render into it) and `ShaderRead` (so the
    // screen pass can sample it).
    scene_color: nuppu.Texture,
    scene_depth: nuppu.Texture,

    things: handle_map.Static_Handle_Map(nuppu.MAX_INSTANCES, Thing, Thing_Handle),

    camera: nuppu.Camera,
}

Thing_Handle :: distinct handle_map.Handle64
Thing :: struct {
    handle: Thing_Handle,
    position: [3]f32,
    rotation_eular: [3]f32,
    scale: [3]f32,

    mesh: nuppu.Mesh_Handle,

    is_alive: bool,
}


SCENE_WIDTH  :: 512 * 2 + 200
SCENE_HEIGHT :: 512 * 2
CAMERA_Z     :: -4.25

// Screen-bounds uniform passed to the screen vertex shader. The shader maps
// the fullscreen triangle's NDC positions into UV space using these bounds,
// which lets us render the textured region in only the letterboxed portion
// of the swapchain. Padded to 16 bytes for Metal alignment.
Screen_Bounds :: struct #align(16) {
    // (min_x, min_y) = bottom-left of letterboxed region in NDC
    // (max_x, max_y) = top-right of letterboxed region in NDC
    min_x, min_y, max_x, max_y: f32,
}

init :: proc() {
    basic_app.camera = nuppu.Camera {
        position = {0, 0, CAMERA_Z},
        near = 0.01,
        far = 1_000,
        fovy = 90,
        aspect_ratio = f32(SCENE_WIDTH) / f32(SCENE_HEIGHT),
    }

    // Default_Renderer owns the mesh / vertex / index arenas. We push two
    // meshes: a high-poly bunny (loaded from OBJ) and a unit cube, both of
    // which get their own slot in the GPU's Mesh array. The offscreen scene
    // only instances the cube — the bunny upload is here purely to prove the
    // multi-mesh upload path works (i.e. mesh_id=1 reads cube data and not
    // the bunny's).
    nuppu.dr_init()

    bunny_mesh_obj, _ := nuppu.mesh_load_from_obj(fmt.tprintf("%v%v", #directory, "bunny.obj"), context.temp_allocator)
    defer nuppu.mesh_destroy(&bunny_mesh_obj, context.temp_allocator)
    bunny_mesh := nuppu.dr_push_mesh(bunny_mesh_obj.positions, bunny_mesh_obj.indices, bunny_mesh_obj.uvs, bunny_mesh_obj.normals)

    cube_mesh := nuppu.dr_push_mesh(nuppu.UNIT_CUBE_VERTICES, nuppu.UNIT_CUBE_INDICES, nuppu.UNIT_CUBE_TEXCOORDS, nuppu.UNIT_CUBE_NORMALS)

    _ = handle_map.static_add(&basic_app.things, Thing{
        position = {2, 0, 0},
        rotation_eular = {0, 0, 180},
        scale = {1, 1, 1} * 5,
        is_alive = true,
        mesh = bunny_mesh,
    })

    _ = handle_map.static_add(&basic_app.things, Thing{
        position = {-2, 0, 0},
        rotation_eular = {0, 0, 0},
        scale = {1, 1, 1},
        is_alive = true,
        mesh = cube_mesh,
    })

    _ = handle_map.static_add(&basic_app.things, Thing{
        position = {4, 0, 0},
        rotation_eular = {0, 0, 0},
        scale = {1, 1, 1} * 5,
        is_alive = true,
        mesh = bunny_mesh,
    })


    // Shaders for the offscreen scene.
    basic_app.scene_v_shader = nuppu.shader_init(#load("2-primitive.metal", []u8), "vertexMain", .Vertex)
    basic_app.scene_f_shader = nuppu.shader_init(#load("2-primitive.metal", []u8), "fragmentMain", .Fragment)

    // Pipeline pixel format MUST match the render target's pixel format (the
    // first Color_Attachment format below). We use .BGRA8Unorm_sRGB to match
    // the swapchain so the screen pass can sample it without format conversion.
    basic_app.scene_pipeline = nuppu.pipeline_init(
        basic_app.scene_v_shader,
        basic_app.scene_f_shader,
        {.BGRA8Unorm_sRGB},
        .Depth32Float,
    )

    basic_app.depth_stencil_state = nuppu.depth_stencil_state_init(
        {
            compare_func = .Less,
            depth_write = true,
        }
    )

    // Create the offscreen render target.
    basic_app.scene_color = nuppu.texture_init(
        {
            dimensions = {SCENE_WIDTH, SCENE_HEIGHT},
            format = .BGRA8Unorm_sRGB,
            texture_type = .Type2D,
            storage_mode = .Private,
            // RenderTarget so we can write into it during the offscreen pass.
            // ShaderRead so the screen pass can sample it (nearest filtering).
            usage = {.RenderTarget, .ShaderRead},
        }
    )

    basic_app.scene_depth = nuppu.texture_depth_init({SCENE_WIDTH, SCENE_HEIGHT}, .Depth32Float)

    // Shaders for the screen pass. They live in the same .metal source file
    // as the offscreen scene shaders — Metal libraries hold multiple
    // functions, and we look them up by entry-point name.
    basic_app.screen_v_shader = nuppu.shader_init(#load("2-primitive.metal", []u8), "screenVertexMain", .Vertex)
    basic_app.screen_f_shader = nuppu.shader_init(#load("2-primitive.metal", []u8), "screenFragmentMain", .Fragment)

    // Screen pipeline: same pixel format as the swapchain, NO depth attachment.
    // Depth format `.Invalid` (which maps to MTL.PixelFormat.Invalid) signals
    // "no depth" to the pipeline state.
    basic_app.screen_pipeline = nuppu.pipeline_init(
        basic_app.screen_v_shader,
        basic_app.screen_f_shader,
        {.BGRA8Unorm_sRGB},
        .Invalid,
    )

    // Sanity check: the new texture_format() and texture_type() APIs confirm
    // at runtime that the offscreen color target has the properties we need:
    //   - .BGRA8Unorm_sRGB: matches the swapchain so the screen sampler sees
    //                       the same colours as the swapchain expects.
    //   - .Type2D: the screen pipeline samples with a 2D texture sampler.
    offscreen_format := nuppu.texture_format(basic_app.scene_color)
    assert(offscreen_format == .BGRA8Unorm_sRGB,
           "scene_color must be .BGRA8Unorm_sRGB so the screen pass samples correct colours")
    assert(nuppu.texture_type(basic_app.scene_color) == .Type2D,
           "scene_color must be a 2D texture")
}

deinit :: proc() {
    nuppu.shader_deinit(basic_app.scene_v_shader)
    nuppu.shader_deinit(basic_app.scene_f_shader)

    nuppu.shader_deinit(basic_app.screen_v_shader)
    nuppu.shader_deinit(basic_app.screen_f_shader)

    nuppu.pipeline_deinit(basic_app.scene_pipeline)
    nuppu.pipeline_deinit(basic_app.screen_pipeline)

    nuppu.depth_stencil_state_deinit(basic_app.depth_stencil_state)
    nuppu.texture_deinit(basic_app.scene_color)
    nuppu.texture_deinit(basic_app.scene_depth)

    nuppu.dr_deinit()
}

update :: proc() {
    @static angle: f32
    angle += nuppu.delta_time_f32() * 2

    iter := handle_map.static_iterator_make(&basic_app.things)
    for thing, _ in handle_map.iterate(&iter) {
        thing.rotation_eular.y = angle
    }
}

// Compute everything the screen pass needs to draw a letterboxed, aspect-
// preserving fullscreen triangle:
//   - ndc_bounds: passed to the vertex shader so UVs outside the letterboxed
//     region get clamped to the edge texel of scene_color (this is what
//     gives clean dark bars even WITHOUT the scissor — the scissor just
//     makes the bars render at GPU speed instead of fragment-shader speed).
//   - scissor:    passed to cmd_set_scissor_rect so the GPU clips the
//     fullscreen triangle to exactly the letterboxed pixel rectangle,
//     leaving the swapchain's own dark clear visible in the bars.
//
//   - If window is wider than the scene (A > S): pillarbox bars LEFT/RIGHT.
//   - If window is taller than the scene (A < S): letterbox bars TOP/BOTTOM.
Screen_Layout :: struct {
    ndc_bounds: Screen_Bounds,
    scissor_x, scissor_y, scissor_w, scissor_h: i32,
}

compute_screen_layout :: proc(window_w, window_h: i32) -> Screen_Layout {
    window_aspect := f32(window_w) / f32(window_h)
    scene_aspect  := f32(SCENE_WIDTH) / f32(SCENE_HEIGHT)

    ndc_x, ndc_y: f32
    scissor_w, scissor_h: i32
    scissor_x, scissor_y: i32

    if window_aspect > scene_aspect {
        // Pillarbox: scene fills the full height; width is the height scaled
        // to preserve the scene's aspect ratio.
        ndc_x = scene_aspect / window_aspect
        ndc_y = 1.0
        scissor_h = window_h
        scissor_w = i32(f32(window_h) * scene_aspect)
        scissor_x = (window_w - scissor_w) / 2
        scissor_y = 0
    } else {
        // Letterbox: scene fills the full width; height is the width scaled
        // to preserve the scene's aspect ratio.
        ndc_x = 1.0
        ndc_y = window_aspect / scene_aspect
        scissor_w = window_w
        scissor_h = i32(f32(window_w) / scene_aspect)
        scissor_x = 0
        scissor_y = (window_h - scissor_h) / 2
    }

    return Screen_Layout {
        ndc_bounds = Screen_Bounds {
            min_x = -ndc_x, min_y = -ndc_y,
            max_x =  ndc_x, max_y =  ndc_y,
        },
        scissor_x = scissor_x,
        scissor_y = scissor_y,
        scissor_w = scissor_w,
        scissor_h = scissor_h,
    }
}

// You must not modify prev or curr in render or planet will explode.
render :: proc(prev, curr: ^Basic, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {
    cam := nuppu.update_camera(prev.camera, curr.camera, alpha)
    cam_data := nuppu.camera_data(cam, {0, 0, 0})

    staged := nuppu.gpu_arena_alloc(arena, nuppu.Instance, curr.things.used_len) // pre-allocate for the worst case (all slots occupied)
    staged_idx: int

    curr_things := handle_map.static_iterator_make(&curr.things)
    for thing, handle in handle_map.iterate(&curr_things) {
        // Compare against stale handle
        prev_thing := prev.things.items[handle.idx]
        if handle.gen != prev_thing.handle.gen do continue

        position := math.lerp(prev_thing.position, thing.position, alpha)
        rotation := nuppu.lerp_rotation(prev_thing.rotation_eular * math.RAD_PER_DEG, thing.rotation_eular * math.RAD_PER_DEG, alpha)
        scale := math.lerp(prev_thing.scale, thing.scale, alpha)
        to_world := glm.mat4Translate(position) * glm.mat4Scale(scale) * rotation

        mesh_impl := nuppu.resource_library_get(&nuppu.dr.meshes, thing.mesh)
        inst := nuppu.Instance {
            transform = to_world,
            mesh_id = mesh_impl.slot_in_buffer,
        }

        cpu_ptr := uintptr((^nuppu.Instance)(staged.cpu)) + uintptr(staged_idx * size_of(nuppu.Instance))
        mem.copy(rawptr(cpu_ptr), &inst, size_of(nuppu.Instance))
        staged_idx += 1
    }

    instance_slice := slice.from_ptr((^nuppu.Instance)(staged.cpu), staged_idx)
    sort.heap_sort_proc(instance_slice[:], proc(a, b: nuppu.Instance) -> int {
        return int(a.mesh_id) - int(b.mesh_id)
    })

    dest := nuppu.dr.instances_gpu[pass.value % nuppu.RENDER_FRAMES_IN_FLIGHT]

    cmds := nuppu.begin_commands()
    nuppu.cmd_mem_copy(cmds, dest, staged, u64(size_of(nuppu.Instance) * staged_idx))
    nuppu.cmd_barrier(cmds, .Transfer, .All)

    // --- PASS 1: Render the cube grid into the OFFSCREEN 200x200 target. ----
    // The .texture field of the color attachment is the render target. The
    // store_action is .Store so the contents survive to be sampled in pass 2.
    nuppu.cmd_begin_render_pass(cmds,
        {
            {
                clear_color = {64, 128, 255, 255},
                load_action = .Clear,
                store_action = .Store,
                texture = curr.scene_color,
            }
        },
        {
            clear_depth = 1,
            load_action = .Clear,
            store_action = .Store,
            texture = curr.scene_depth,
        }
    )

    // Pack the Shader_Data blob and bind at buffer(0).
    shader_data := nuppu.Shader_Data {
        instances        = (^nuppu.Instance)(dest.gpu),
        meshes           = (^nuppu.Mesh)(nuppu.dr.mesh_data.gpu),
        vertex_positions = (^nuppu.Vertex_Position)(nuppu.dr.vertex_positions_data.gpu),
        vertex_uvs       = (^nuppu.Vertex_UV)(nuppu.dr.vertex_uvs_data.gpu),
        vertex_normals   = (^nuppu.Vertex_Normal)(nuppu.dr.vertex_normals_data.gpu),
    }
    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&shader_data, size_of(nuppu.Shader_Data)), 0, .Vertex)

    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&cam_data, size_of(nuppu.Camera_Data)), 1, .Vertex)

    nuppu.cmd_set_pipeline(cmds, curr.scene_pipeline)
    nuppu.cmd_set_depth_stencil_state(cmds, curr.depth_stencil_state)

    nuppu.cmd_set_cull_mode(cmds, .Back)
    nuppu.cmd_set_front_face_winding(cmds, .CounterClockwise)

    nuppu.cmd_use_resources(cmds, {
        {nuppu.dr.mesh_data,             {.Read}, {.Vertex}},
        {nuppu.dr.vertex_positions_data, {.Read}, {.Vertex}},
        {nuppu.dr.vertex_uvs_data,       {.Read}, {.Vertex}},
        {dest,                     {.Read}, {.Vertex}},
    })

    i := 0
    for i < staged_idx {
        mesh_idx := instance_slice[i].mesh_id

        j := i + 1
        for j < staged_idx && instance_slice[j].mesh_id == mesh_idx {
            j += 1
        }
        mesh :nuppu.Mesh= nuppu.dr.slot_to_mesh[mesh_idx]

        nuppu.cmd_draw_indiced_primitives(cmds, .Triangle, nuppu.dr.index_data, mesh.index_range.length, mesh.index_range.location, u32(j - i), u32(i))

        i = j
    }

    nuppu.cmd_end_render_pass(cmds)

    // --- PASS 2: Stretch the offscreen target to fill the swapchain -------
    // (with aspect-preserving letterbox bars on the leftover area).
    swapchain := nuppu.acquire_next_swapchain(cmds)

    // Resize swapchain if window was resized.
    window_size_px := nuppu.window_size_pixel()
    swapchain_size := nuppu.texture_size(swapchain)
    if swapchain_size.x != window_size_px.x || swapchain_size.y != window_size_px.y {
        nuppu.gpu_resize_swapchain()
    }

    // Single render pass: clear the swapchain to a dark, distinctive
    // background (this becomes the letterbox/pillarbox bar colour), then
    // draw the fullscreen triangle that samples scene_color with nearest
    // filtering. A GPU scissor clips the triangle to exactly the letterboxed
    // pixel rectangle so the bars are filled by the swapchain clear colour
    // instead of the stretched edge texels of scene_color.
    nuppu.cmd_begin_render_pass(cmds,
        {
            {
                clear_color = {20, 20, 28, 255},
                load_action = .Clear,
                store_action = .Store,
                texture = swapchain,
            }
        },
    )

    nuppu.cmd_set_pipeline(cmds, curr.screen_pipeline)

    // Compute the letterboxed layout for this frame's window size.
    layout := compute_screen_layout(swapchain_size.x, swapchain_size.y)

    // Upload the NDC bounds (vertex shader maps its fullscreen triangle's UVs
    // so UVs outside this rect fall outside [0,1] and clamp to scene_color's
    // edge — a backstop that works even if the scissor is ever disabled).
    nuppu.gpu_temp_malloc(cmds, slice.bytes_from_ptr(&layout.ndc_bounds, size_of(Screen_Bounds)), 0, .Vertex)

    // Clip the fullscreen triangle to the letterboxed pixel rectangle. The
    // swapchain's dark clear shows through outside the scissor, giving clean
    // pillarbox/letterbox bars that match the swapchain background.
    nuppu.cmd_set_scissor_rect(
        cmds,
        u32(layout.scissor_x), u32(layout.scissor_y),
        u32(layout.scissor_w), u32(layout.scissor_h),
    )

    // Bind scene_color as the source texture in slot 0 of the fragment stage.
    nuppu.cmd_set_texture(cmds, {{curr.scene_color, 0}}, .Fragment)

    // Draw the single fullscreen triangle (3 vertices, no index buffer). The
    // scissor above restricts the rasterized fragments to the letterboxed
    // pixel rectangle.
    nuppu.cmd_draw_primitives(cmds, .Triangle, 3)

    nuppu.cmd_end_render_pass(cmds)

    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc(Basic) {
    init = init,
    deinit = deinit,
    update = update,
    render = render,
}

config :: nuppu.App_Config {
    window_size = [2]i32{1280, 720},
    window_title = "Render-To-Texture (Pixel-Art Stretch)",
}

main :: proc() {
    nuppu.app_init(
        _desc,
        &basic_app,
        config
    )
}
