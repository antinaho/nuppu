package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:time"
import "core:fmt"
import "core:log"
import "core:image"
import glm "core:math/linalg/glsl"

import "./platform"
import "./gpu"
import "bit_array"

_ :: fmt
_ :: log

UNION_LEN :: intrinsics.type_union_variant_count

SIM_TICKS_PER_SECOND :: 180
SIM_NS_PER_TICK     :: time.Second / SIM_TICKS_PER_SECOND

FRAMES_IN_FLIGHT :: 2

MAX_FRAME_DT_NS :: u64(f64(time.Second) * 0.1)
MAX_SIM_TICKS :: 5

MAX_MESHES :: 256
MAX_TEXTURES :: 256

Texture :: gpu.Texture
Texture_Descriptor :: gpu.Texture_Descriptor

// Handles carry metadata on debug builds
when ODIN_DEBUG {
    Metadata :: struct {
        created_at: runtime.Source_Code_Location,
        created_on_frame: u64,
    }

    Mesh_Handle :: struct {
        handle: bit_array.Handle,
        metadata: Metadata,
    }
    Mesh_Handle_Nil :: Mesh_Handle{}

    Texture_Handle :: struct {
        handle: bit_array.Handle,
        metadata: Metadata,
    }
    Texture_Handle_Nil :: Texture_Handle{}

    _debug_warned_call_sites: map[u64]bool

    debug_warn_hash :: proc(loc: runtime.Source_Code_Location) -> u64 {
        h: u64 = 0xcbf29ce484222325 // FNV-1a 64-bit offset basis
        for i in 0..<len(loc.file_path) {
            h = (h ~ u64(loc.file_path[i])) * 0x100000001b3 // FNV-1a prime
        }
        h = (h ~ u64(loc.line))   * 0x100000001b3
        h = (h ~ u64(loc.column)) * 0x100000001b3
        return h
    }

} else {
    Texture_Handle :: struct { handle: bit_array.Handle, }
    Texture_Handle_Nil :: Texture_Handle{}
    
    Mesh_Handle :: struct { handle: bit_array.Handle, }
    Mesh_Handle_Nil :: Mesh_Handle{}
}

State :: struct #align(64) {
    ctx: runtime.Context,
    initialized: bool,

    accumulator: u64,
    num_sim_ticks: u64,

    window_size: [2]i32,

    application_state: platform.State,
    gpu_state: gpu.State,

    update_state_size: int,
    current_state: rawptr,
    previous_state: rawptr,
    desc: struct {
        init: proc(),
        update: proc(),
        deinit: proc(),
        render: proc(curr: rawptr, alpha: f32),
    },

    vertex: gpu.Arena,
    index: gpu.Arena,
    frame_uniform: gpu.ptr,
    
    _instances: gpu.ptr,
    _instances_data: gpu.ptr,
    instance_batcher: Instance_Batcher,    

    sampler: gpu.Sampler,

    frame_semaphore: gpu.Timeline_Semaphore,
    frame_arenas: [dynamic; FRAMES_IN_FLIGHT]^gpu.Arena,
    frame_n: u64,

    // Built-in resources, currently representing quad sprite
    built_in_block: gpu.Parameter_Block,

    //
    meshes: bit_array.Bit_Array(Resource(Mesh), MAX_MESHES, Mesh_Handle),
    built_in_meshes: [Built_in_mesh]Mesh_Handle,

    textures: bit_array.Bit_Array(Resource(Texture), MAX_TEXTURES, Texture_Handle),
    built_in_textures: [Built_in_texture]Texture_Handle,

    entity_manager: ^Entity_Manager,
}

_state: ^State



Frame_Result :: enum { Continue, Skip_Render, Exit }

Frame :: struct {
    n:         u64,
    semaphore: gpu.Timeline_Semaphore,
    arena:     ^gpu.Arena,
}

App_Desc :: struct($T: typeid) #all_or_none {
    state: ^^T,
    window_size: [2]i32,
    update: proc(),
	render: proc(current: ^T, alpha: f32),
    using _: App_Optional,
}

App_Optional :: struct {
    window_title: string,
    init: proc(),
    deinit: proc(),
}

Resource :: struct($T: typeid) {
    handle: bit_array.Handle,
    data: T,
}

run :: proc(desc: App_Desc($T)) {

    logger := log.create_console_logger()
    
    assert(_state == nil)

    alloc_err: runtime.Allocator_Error
    _state, alloc_err = new(State)
    if alloc_err != nil {
        panic("Failed to allocate state")
    }

    context.logger = logger
    _state.ctx = context

    when ODIN_DEBUG {
        _debug_warned_call_sites = make(map[u64]bool)
    }

    states, states_err := mem.alloc(size_of(T) * 2, alignment = 64)
    if states_err != nil {
        panic("Failed to allocate states")
    }

    current_state := &([^]T)(states)[0]
    previous_state := &([^]T)(states)[1]
    desc.state^ = current_state

    _state.current_state = current_state
    _state.previous_state = previous_state
    _state.update_state_size = mem.align_forward_int(size_of(T), 64)

    _state.desc = {
        init = desc.init,
        update = desc.update,
        deinit = desc.deinit,
        render = auto_cast desc.render,
    }

    platform.init(&_state.application_state, desc.window_size, desc.window_title)
    gpu.init(&_state.gpu_state, platform.native_window(), .BGRA8Unorm)

    if hz, ok := platform.display_refresh_hz(); ok {
        set_gpu_hz_target(hz)
    }

when ODIN_OS != .JS { // JS runtime drives the loop via the exported step() on each tick.

    _ready_up()
    if desc.init != nil {
        desc.init()
    }

    for {
        switch _frame() {
        case .Exit:
            if desc.deinit != nil {
                desc.deinit()
            }
            entity_manager_destroy(_state.entity_manager)
            return
        case .Skip_Render:
            continue
        case .Continue:
            if _state.frame_n > FRAMES_IN_FLIGHT {
                gpu.semaphore_wait(_state.frame_semaphore, _state.frame_n - FRAMES_IN_FLIGHT)
            }
            desc.render((^T)(_state.current_state), _render_alpha())
        }
    }
}
}

begin_frame :: proc() -> Frame {
    gpu.begin_frame()
    n := _state.frame_n
    arena := _state.frame_arenas[n % FRAMES_IN_FLIGHT]
    arena.offset = 0
    return Frame {
        n         = n,
        semaphore = _state.frame_semaphore,
        arena     = arena,
    }
}

end_frame :: proc(frame: Frame) {
    gpu.end_frame(frame.semaphore, frame.n)
    _state.frame_n += 1

    recycle_frame_arena(frame.arena)
}

update_constants :: proc(prev, curr: Camera, alpha: f32) {
    cam := update_camera(prev, curr, alpha)

    staging, ok := gpu.malloc(
        size_of(Engine_Uniform), align_of(Engine_Uniform),
        .Staging, "Frame Uniform Staging",
    )
    if !ok {
        log.error("update_constants: failed to allocate staging buffer")
        return
    }
    defer gpu.release_ptr(&staging)

    uniforms := (^Engine_Uniform)(staging.cpu)
    uniforms.cam_perspective_transform = glm.mat4Perspective(
        glm.radians_f32(cam.fovy), cam.aspect_ratio, cam.near, cam.far,
    )
    uniforms.cam_ortho_transform = 1
    uniforms.cam_view_transform   = glm.mat4Translate(-cam.position)
    uniforms.cam_position        = cam.position
    uniforms._pad                = 0

    gpu.unmap(&staging)
    gpu.copy(_state.frame_uniform, staging)
}

frame_arena :: proc(frame: Frame) -> ^gpu.Arena {
    return frame.arena
}

depth :: proc() -> Texture_Handle {
    return _state.built_in_textures[.Depth]
}

resize_depth :: proc(width, height: u32) {
    if old_handle := _state.built_in_textures[.Depth]; old_handle.handle != bit_array.NIL_HANDLE {
        if old_tex, ok := get_resource(&_state.textures, old_handle); ok {
            gpu.release_texture(old_tex)
            bit_array.remove(&_state.textures, old_handle)
        }
    }
    gpu_tex := gpu.texture_depth_init({width, height}, .Depth32Float)
    _state.built_in_textures[.Depth] = add_resource(&_state.textures, gpu_tex)
}

Load_Action  :: gpu.Load_Action
Store_Action :: gpu.Store_Action
Clear_Color  :: gpu.Clear_Color

Color_Attachment :: struct {
    clear_color:    Clear_Color,
    load_action:    Load_Action,
    store_action:   Store_Action,
    texture:        Texture_Handle,
    resolve_texture: Texture_Handle,
}

Depth_Attachment :: struct {
    load_action:  Load_Action,
    store_action: Store_Action,
    texture:      Texture_Handle,
}

begin_render_pass :: proc(color: Color_Attachment, depth: Depth_Attachment = {}) {
    color_tex: gpu.Texture
    if tex, ok := get_resource(&_state.textures, color.texture); ok {
        color_tex = tex^
    }
    color_resolve: gpu.Texture
    if tex, ok := get_resource(&_state.textures, color.resolve_texture); ok {
        color_resolve = tex^
    }
    depth_tex: gpu.Texture
    if tex, ok := get_resource(&_state.textures, depth.texture); ok {
        depth_tex = tex^
    }

    gpu.begin_render_pass(
        gpu.Color_Attachment {
            clear_color    = color.clear_color,
            load_action    = color.load_action,
            store_action   = color.store_action,
            texture        = color_tex,
            resolve_texture = color_resolve,
        },
        gpu.Depth_Attachment {
            load_action  = depth.load_action,
            store_action = depth.store_action,
            texture      = depth_tex,
        },
    )
}

end_render_pass :: proc() {
    gpu.end_render_pass()
}

recycle_frame_arena :: proc(arena: ^gpu.Arena) {
    when ODIN_OS != .JS {
        /* no op */
    }
}

@(private="file", export)
step :: proc(dt: f32) -> bool {
    assert(_state != nil)
    context = _state.ctx

    if !_state.initialized {
        if gpu.is_init() {
            _ready_up()
            if _state.desc.init != nil {
                _state.desc.init()
            }
        } else {
            return true
        }
    }

    switch _frame() {
    case .Exit:
        if _state.desc.deinit != nil {
            _state.desc.deinit()
        }
        entity_manager_destroy(_state.entity_manager)
        return false
    case .Skip_Render:
        return true
    case .Continue:
        _state.desc.render(_state.current_state, _render_alpha())
        return true
    }
    return true
}

_frame :: proc() -> Frame_Result {

    free_all(context.temp_allocator)
    reset_batches(&_state.instance_batcher)

    platform.platform_reset_frame_input()
    platform.poll_events()

    if platform.input_key_pressed(.KEY_ESCAPE) {
        return .Exit
    }
    
    interval_ns := gpu.frame_interval_ns()

    if interval_ns > MAX_FRAME_DT_NS {
        interval_ns = MAX_FRAME_DT_NS
    }
    _state.accumulator += interval_ns

    _state.num_sim_ticks = _state.accumulator / u64(SIM_NS_PER_TICK)
    if _state.num_sim_ticks > MAX_SIM_TICKS {
        _state.num_sim_ticks = MAX_SIM_TICKS
    }
    _state.accumulator -= _state.num_sim_ticks * u64(SIM_NS_PER_TICK)

    if _state.num_sim_ticks > 0 {
        platform.normalize_ticks(_state.num_sim_ticks)
        for _ in 0 ..< _state.num_sim_ticks {
            runtime.mem_copy_non_overlapping(_state.previous_state, _state.current_state, _state.update_state_size)
            entity_interpolation_snapshot(_state.entity_manager)
            _state.desc.update()
            platform.release_input()
        }
    }

    current_window_size := platform.window_size_pixel()
    if current_window_size.x <= 0 || current_window_size.y <= 0 || .Iconified in platform.window_flags() || .Visible not_in platform.window_flags() {
        return .Skip_Render
    }
    
    // Resize swapchain + depth?
    current := platform.window_size_pixel()
    if _state.window_size.x != current.x || _state.window_size.y != current.y {
        gpu.resize_swapchain(u32(current.x), u32(current.y))
        resize_depth(u32(current.x), u32(current.y))
        _state.window_size = current
    }

    return .Continue
}

_ready_up :: proc() {
    _state.frame_n = 1
    _state.frame_semaphore = gpu.semaphore(0)

    for _ in 0 ..< FRAMES_IN_FLIGHT {
        frame_arena := new(gpu.Arena, context.allocator)
        frame_arena^, _ = gpu.arena_init(4 * 1024 * 1024)
        append(&_state.frame_arenas, frame_arena)
    }

    _state.window_size = platform.window_size_pixel()
    gpu.resize_swapchain(u32(_state.window_size.x), u32(_state.window_size.y))

    bit_array.init(&_state.textures)
    resize_depth(u32(_state.window_size.x), u32(_state.window_size.y))

    _state.entity_manager = new(Entity_Manager)
    entity_manager_init(_state.entity_manager)

    // Global buffers wrapped in arena
    VERTEX_BLOB_SIZE :: 16 * mem.Megabyte
    GLOBAL_INDEX_COUNT_MAX :: 1 << 16
    
    MAX_INSTANCES :: 10_000
    INSTANCE_BLOB_SIZE :: 64 * mem.Megabyte
    
    // MAX_MATERIAL_COUNT :: 1 << 8 // If this raises need to increase material idx on sprite instance
    
    _state.vertex, _ = gpu.arena_init(VERTEX_BLOB_SIZE, flags = .Default)
    _state.index, _ = gpu.arena_init(size_of(Vertex_Index) * GLOBAL_INDEX_COUNT_MAX, flags = .Index)
    _state._instances, _ = gpu.arena_init(size_of(Instance) * MAX_INSTANCES, alignment = align_of(Instance), flags = .Default)
    _state._instances_data, _ = gpu.arena_init(INSTANCE_BLOB_SIZE, flags = .Default)
    
    _state.instance_batcher.instance_buffer, _ = gpu.malloc(size_of(Instance) * MAX_INSTANCES, align_of(Instance), .Staging)
    _state.instance_batcher.instance_data_buffer_blob, _ = gpu.malloc(INSTANCE_BLOB_SIZE, 16, .Staging)
    
    _state.frame_uniform, _ = gpu.malloc(size_of(Engine_Uniform), align_of(Engine_Uniform), .Constant, "Frame Uniform")

    // 
    // _state.built_in_textures = gpu.texture_init({
    //     dimensions  = {63, 63},
    //     format      = .RGBA8Unorm,
    //     type        = ._2D_Array,
    //     storage     = .Shared,
    //     usage       = {.Sampled},
    //     layer_count = 16,
    // })

    _state.sampler = gpu.sampler_init({
        mag_filter = .Nearest,
        min_filter = .Nearest,
        mip_filter = .Nearest,
        wrap_r = .ClampToEdge,
        wrap_s = .ClampToEdge,
        wrap_t = .ClampToEdge,
    })

    PNG_DIM :: [2]u32{63, 63}

    
    textures_handle := texture_init_ex(Texture_Descriptor {
        dimensions = PNG_DIM,
        format = .RGBA8Unorm,
        storage = .Shared,
        usage = {.Sampled},
        layer_count = 2,
        type = ._2D_Array,
    })
    texture_array, _ := get_resource(&_state.textures, textures_handle)

    {
        img, img_err := image.load_from_bytes(#load("./examples/AppleLearnCPP/3-Instancing_camera/bowser.png", []u8), {.alpha_add_if_missing}, context.temp_allocator)
        if img_err != nil {
            panic(fmt.tprintf("nuppu: failed to decode bowser.png: %v", img_err))
        }
        gpu.copy_to_texture(texture_array^, {0, 0, 0}, {PNG_DIM.x, PNG_DIM.y, 1}, 0, raw_data(img.pixels.buf[:]), PNG_DIM.x * 4)
        image.destroy(img, context.temp_allocator)
    }

    {
        img, img_err := image.load_from_bytes(#load("./examples/AppleLearnCPP/3-Instancing_camera/peach.png", []u8), {.alpha_add_if_missing}, context.temp_allocator)
        if img_err != nil {
            panic(fmt.tprintf("nuppu: failed to decode peach.png: %v", img_err))
        }
        gpu.copy_to_texture(texture_array^, {0, 0, 1}, {PNG_DIM.x, PNG_DIM.y, 1}, 0, raw_data(img.pixels.buf[:]), PNG_DIM.x * 4)
        image.destroy(img, context.temp_allocator)
    }

    bit_array.init(&_state.meshes)
    create_built_in_meshes()

    _state.built_in_block = gpu.Parameter_Block {
        constants = { 0 = _state.frame_uniform },
        read_resources = {
            0 = _state.vertex.ptr,
            1 = _state._instances,
            2 = _state._instances_data,
            3 = texture_array^,
        },
        read_write_resources = {},
        samplers = { 0 = _state.sampler },
    }

    _state.initialized = true
}

global_frame_uniform :: proc() -> gpu.ptr {
    return _state.frame_uniform
}

global_index_buffer :: proc() -> gpu.ptr {
    return _state.index.ptr
}

///////////////////////////////////////////////////////////////

_render_alpha :: proc() -> f32 {
    return f32(_state.accumulator) / f32(SIM_NS_PER_TICK)
}

aspect_ratio :: proc() -> f32 {
    return platform.window_aspect_ratio()
}

sim_delta_time :: proc() -> f32 {
    return 1.0 / f32(SIM_TICKS_PER_SECOND)
}

set_gpu_hz_target :: proc(hz: u32) {
    clamped := hz
    if clamped > platform.MAX_HZ { clamped = platform.MAX_HZ }
    gpu.set_hz(clamped)
}

acquire_next_swapchain :: proc() -> Texture_Handle {
    gpu_tex := gpu.acquire_next_swapchain()

    if _state.built_in_textures[.Swapchain].handle == bit_array.NIL_HANDLE {
        _state.built_in_textures[.Swapchain] = add_resource(&_state.textures, gpu_tex)
        return _state.built_in_textures[.Swapchain]
    }

    tex_ptr, _ := get_resource(&_state.textures, _state.built_in_textures[.Swapchain])
    tex_ptr^ = gpu_tex
    return _state.built_in_textures[.Swapchain]
}

Screen_Bounds :: struct #align(16) {
    // (min_x, min_y) = bottom-left of letterboxed region in NDC
    // (max_x, max_y) = top-right of letterboxed region in NDC
    min_x, min_y, max_x, max_y: f32,
}

Screen_Layout :: struct {
    ndc_bounds: Screen_Bounds,
    scissor_x, scissor_y, scissor_w, scissor_h: i32,
}

compute_screen_layout :: proc(window_w, window_h: i32, internal_w, internal_h: i32) -> Screen_Layout {
    window_aspect := f32(window_w) / f32(window_h)
    scene_aspect  := f32(internal_w) / f32(internal_h)

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

add_resource :: proc(array: ^bit_array.Bit_Array(Resource($Res), $N, $H), res: Res, loc := #caller_location) -> H {
    handle, _ := bit_array.add(array, Resource(Res) {
        data = res,
    })
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at = loc,
            created_on_frame = _state.frame_n,
        }
    }
    return handle
}

get_resource :: proc(array: ^bit_array.Bit_Array(Resource($Res), $N, $H), handle: H, loc := #caller_location) -> (^Res, bool) {
    resource_ptr, ok := bit_array.get(array, handle)
    when ODIN_DEBUG {
        if !ok && handle.handle != bit_array.NIL_HANDLE {
            h := debug_warn_hash(loc)
            if h not_in _debug_warned_call_sites {
                index, _ := bit_array.unpack_handle(handle.handle)
                log.warnf(
                    "[nuppu] stale handle idx=%v — created at %v:%v on frame %v (lookup at %v:%v)",
                    index,
                    handle.metadata.created_at.file_path,
                    handle.metadata.created_at.line,
                    handle.metadata.created_on_frame,
                    loc.file_path,
                    loc.line,
                )
                _debug_warned_call_sites[h] = true
            }
        }
    }
    return &resource_ptr.data, ok
}




// Simple 2D texture
texture_2D_init :: proc(
    dimensions: [2]u32,
    data: rawptr = nil,
) -> Texture_Handle {
    desc := gpu.Texture_Descriptor {
        dimensions = dimensions,
        format = .RGBA8Unorm,
        storage = .Shared,
        usage = {.Sampled},
        layer_count = 1,
        type = ._2D,
    }

    return texture_init_ex(desc, data)
}

texture_init_ex :: proc(
    descriptor: Texture_Descriptor,
    data: rawptr = nil,
) -> Texture_Handle {

    texture := gpu.texture_init(descriptor)

    handle := add_resource(&_state.textures, texture)

    if data != nil {
        gpu.copy_to_texture(texture, {0, 0, 0}, {descriptor.dimensions.x, descriptor.dimensions.y, 1}, 0, data, descriptor.dimensions.x * 4)
    }

    return handle
}
