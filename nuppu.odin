package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:time"
import "core:fmt"
import "core:log"
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

MAX_TEXTURES :: 256

Texture :: gpu.Texture
Texture_Descriptor :: gpu.Texture_Descriptor

Handle :: struct($Raw: typeid) {
    handle:   Raw,
    metadata: Metadata,
}

// Debug-only metadata attached to a handle.
when ODIN_DEBUG {
    Metadata :: struct {
        created_at:       runtime.Source_Code_Location,
        created_on_frame: u64,
        name:             string,
    }
} else {
    Metadata :: struct{}
}

Texture_Handle :: Handle(bit_array.Handle)
Texture_Handle_Nil :: Texture_Handle{}

@(require_results)
get_texture :: proc(handle: Texture_Handle) -> (^gpu.Texture, bool) #optional_ok {
    return get_resource(&_state.textures, handle)
}

// Handles carry metadata on debug builds
when ODIN_DEBUG {
    _debug_warned_call_sites: map[u64]bool

    // Tracks every allocation made through `context.allocator` while the engine
    // runs. Lives outside `State` because it must exist before `new(State)`.
    _tracking_allocator: mem.Tracking_Allocator

    debug_warn_hash :: proc(loc: runtime.Source_Code_Location) -> u64 {
        h: u64 = 0xcbf29ce484222325 // FNV-1a 64-bit offset basis
        for i in 0..<len(loc.file_path) {
            h = (h ~ u64(loc.file_path[i])) * 0x100000001b3 // FNV-1a prime
        }
        h = (h ~ u64(loc.line))   * 0x100000001b3
        h = (h ~ u64(loc.column)) * 0x100000001b3
        return h
    }

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
    states: rawptr, // double-buffer backing for current/previous app state
    current_state: rawptr,
    previous_state: rawptr,
    desc: struct {
        init: proc(),
        update: proc(),
        deinit: proc(),
        render: proc(curr: rawptr, alpha: f32),
    },

    mesh_library: Mesh_Library,
    frame_uniform: gpu.ptr,

    draw_batcher: Draw_Batcher,
    material_library: Material_Library,
    shader_library: Shader_Library,

    sampler: gpu.Sampler,

    frame_semaphore: gpu.Timeline_Semaphore,
    frame_arenas: [FRAMES_IN_FLIGHT]gpu.Arena,
    frame_n: u64,

    //
    


    textures: bit_array.Bit_Array(Resource(Texture, Texture_Handle), MAX_TEXTURES, Texture_Handle),
    built_in_textures: [Built_in_texture]Texture_Handle,

    entity_manager: ^Entity_Manager,
    main_camera: Entity_Handle,
}

camera :: proc "contextless" () -> Entity_Handle {
    return _state.main_camera
}

Camera :: struct {
    using e: ^Entity,

    near: f32,
    far: f32,
    fovy: f32,
    aspect_ratio: f32,
}

update_camera :: proc(
    position: [3]f32,
    rotation: [3]f32,
    near: f32,
    far: f32,
    fovy: f32,
) {
    cam, ok := entity_get_typed(_state.entity_manager, _state.main_camera, Camera)
    if !ok { return }
    cam.position = position
    cam.rotation = rotation
    cam.near  = near
    cam.far   = far
    cam.fovy  = fovy
}

// Registers an entity variant with the global entity manager. Must be called
// before register_drawable for that type. Pass a data type as the fourth
// argument to upload the variant's field named `gpu_instance` (which must have
// that exact type) into the per-frame instance-data buffer.
register_entity :: proc{_register_entity, _register_entity_data}

_register_entity :: proc($T: typeid, $SHIFT: uint, flags: Entity_Flags = {}) {
    entity_manager_add_variant(_state.entity_manager, T, SHIFT, flags)
}

_register_entity_data :: proc($T: typeid, $SHIFT: uint, flags: Entity_Flags, $D: typeid) {
    entity_manager_add_variant_data(_state.entity_manager, T, SHIFT, flags, D)
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

// The slot's `handle` is the full wrapper `H` (not the raw bit_array handle),
// so the debug metadata (name + creation site) travels with the resource and
// the owning library can report leaks on shutdown.
Resource :: struct($T: typeid, $H: typeid) {
    handle: H,
    data:   T,
}

run :: proc(desc: App_Desc($T)) {

    when ODIN_DEBUG {
        // Track every allocation from here on, using the base allocator as the
        // backing store so the tracker's own bookkeeping is not self-tracked.
        mem.tracking_allocator_init(&_tracking_allocator, context.allocator)
        _tracking_allocator.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
        context.allocator = mem.tracking_allocator(&_tracking_allocator)
    }

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

    // Two interpolation states, each padded up to `update_state_size` so the
    // snapshot copy below stays inside the allocation.
    _state.update_state_size = mem.align_forward_int(size_of(T), 64)

    states, states_err := mem.alloc(_state.update_state_size * 2, alignment = 64)
    if states_err != nil {
        panic("Failed to allocate states")
    }

    current_state := &([^]T)(states)[0]
    previous_state := (^T)(rawptr(uintptr(states) + uintptr(_state.update_state_size)))
    desc.state^ = current_state

    _state.states = states
    _state.current_state = current_state
    _state.previous_state = previous_state

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
            deinit()
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

deinit :: proc() {
    entity_manager_clear(_state.entity_manager)
    entity_manager_destroy(_state.entity_manager)
    when ODIN_DEBUG {
        _report_unfreed_resources()
    }

    if _state.frame_semaphore != nil {
        // `end_frame` signals the semaphore with the frame's `n`; the last
        // submitted frame is `frame_n - 1`.
        gpu.semaphore_wait(_state.frame_semaphore, _state.frame_n - 1)
    }

    destroy_draw_batcher(&_state.draw_batcher)
    _shader_lib_deinit(&_state.shader_library)
    _material_lib_deinit(&_state.material_library)

    for i in 0 ..< FRAMES_IN_FLIGHT {
        gpu.release_ptr(&_state.frame_arenas[i].ptr)
    }
    gpu.release_ptr(&_state.frame_uniform)
    gpu.release_ptr(&_state.mesh_library.vertex_arena.ptr)
    gpu.release_ptr(&_state.mesh_library.index_arena.ptr)

    if depth_handle := _state.built_in_textures[.Depth]; depth_handle.handle != bit_array.NIL_HANDLE {
        if depth_texture, ok := get_resource(&_state.textures, depth_handle); ok {
            gpu.release_texture(depth_texture)
        }
    }

    gpu.deinit()

    when ODIN_DEBUG {
        delete(_debug_warned_call_sites)
    }
    log.destroy_console_logger(_state.ctx.logger)

    // Engine-lifetime Odin allocations.
    free(_state.states)
    free(_state)
    _state = nil

    when ODIN_DEBUG {
        _report_allocator()
    }
}

// Debug-only: dump every allocation still live at shutdown and any bad frees,
// then tear the tracking allocator down.
when ODIN_DEBUG {
    _report_allocator :: proc() {
        if len(_tracking_allocator.allocation_map) > 0 {
            fmt.eprintf("=== %v allocations not freed: ===\n", len(_tracking_allocator.allocation_map))
            for _, leak in _tracking_allocator.allocation_map {
                fmt.eprintf("- %v bytes @ %v\n", leak.size, leak.location)
            }
        }

        if len(_tracking_allocator.bad_free_array) > 0 {
            fmt.eprintf("=== %v incorrect frees: ===\n", len(_tracking_allocator.bad_free_array))
            for bad in _tracking_allocator.bad_free_array {
                fmt.eprintf("- %p @ %v\n", bad.memory, bad.location)
            }
        }

        context.allocator = _tracking_allocator.backing
        mem.tracking_allocator_destroy(&_tracking_allocator)
    }
}

// Debug-only: walk every resource library and report anything that was not
// released, using the name + creation site carried on the handle. Engine
// built-ins (depth / swapchain) are skipped.
when ODIN_DEBUG {
    _report_unfreed_resources :: proc() {
        total := 0
        total += _report_unfreed_library("mesh", &_state.mesh_library.meshes, []Mesh_Handle{
            _state.mesh_library.built_in_lookup[.Quad],
            _state.mesh_library.built_in_lookup[.Cube],
        })
        total += _report_unfreed_library("texture", &_state.textures, []Texture_Handle{
            _state.built_in_textures[.Depth],
            _state.built_in_textures[.Swapchain],
        })
        total += _report_unfreed_library("shader", &_state.shader_library.shaders)
        total += _report_unfreed_materials()
        total += _report_live_entities()

        if total > 0 {
            log.warnf("[nuppu] %d resource(s) were not freed before shutdown", total)
        }
    }

    // Entities are not GPU resources, but a non-empty manager at shutdown is
    // usually a leak. Print every live entity's handle metadata (name + site).
    _report_live_entities :: proc() -> int {
        em := _state.entity_manager
        if em == nil { return 0 }

        count := 0
        for variant_idx in 0 ..< len(em.variants) {
            data := &em.variants[variant_idx]
            for chunk_idx in 0 ..< len(data.chunks) {
                chunk := &data.chunks[chunk_idx]
                it := bit_mask_array_iterator_init(&chunk.occupied)
                for {
                    off, ok := bit_mask_array_iterator_next(&it)
                    if !ok { break }

                    entity := &chunk.entities[off]
                    if entity.handle.handle.index == 0 { continue } // sentinel

                    _report_unfreed("entity", entity.handle.metadata)
                    count += 1
                }
            }
        }
        return count
    }

    _report_unfreed_library :: proc(
        kind:    string,
        array:   ^bit_array.Bit_Array(Resource($Res, $RHandle), $N, $H),
        exclude: []RHandle = nil,
    ) -> int {
        count := 0
        it := bit_array.iterator_init(array)
        for {
            item, ok := bit_array.iterator_next(&it)
            if !ok { break }

            skip := false
            for e in exclude {
                if item.handle == e {
                    skip = true
                    break
                }
            }
            if skip { continue }

            _report_unfreed(kind, item.handle.metadata)
            count += 1
        }
        return count
    }

    _report_unfreed_materials :: proc() -> int {
        lib := &_state.material_library
        count := 0
        for i in 1 ..< len(lib.material_handles) {
            _report_unfreed("material", lib.material_handles[i].metadata)
            count += 1
        }
        return count
    }

    _report_unfreed :: proc(kind: string, meta: Metadata) {
        log.warnf(
            "[nuppu] unfreed %s '%s' created at %s:%d",
            kind,
            meta.name,
            meta.created_at.file_path,
            meta.created_at.line,
        )
    }
}

begin_frame :: proc() -> Frame {
    gpu.begin_frame()
    n := _state.frame_n
    arena := &_state.frame_arenas[n % FRAMES_IN_FLIGHT]
    arena.offset = 0

    frame := Frame {
        n         = n,
        semaphore = _state.frame_semaphore,
        arena     = arena,
    }

    batcher_reset(&_state.draw_batcher)

    return frame
}

end_frame :: proc(frame: Frame) {
    gpu.end_frame(frame.semaphore, frame.n)
    _state.frame_n += 1
}

update_constants :: proc(frame: Frame) {
    cam, ok := entity_get_typed(_state.entity_manager, _state.main_camera, Camera)
    if !ok { return }

    uniform := gpu.arena_alloc(frame.arena, Engine_Uniform, 1)
    u := (^Engine_Uniform)(uniform.cpu)
    u.cam_perspective_transform = glm.mat4Perspective(
        glm.radians_f32(cam.fovy), cam.aspect_ratio, cam.near, cam.far,
    )
    u.cam_ortho_transform = 1
    u.cam_world_transform  = glm.mat4Translate(-cam.position)  // identity entity-world; just the camera shift
    u.cam_position        = cam.position

    gpu.copy(_state.frame_uniform, uniform)
    gpu.barrier(.Transfer, .All)
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

    switch _frame(u64(f64(dt) * f64(time.Second))) {
    case .Exit:
        if _state.desc.deinit != nil {
            _state.desc.deinit()
        }
        deinit()
        return false
    case .Skip_Render:
        return true
    case .Continue:
        _state.desc.render(_state.current_state, _render_alpha())
        return true
    }
    return true
}

_frame :: proc(external_ns : u64 = 0) -> Frame_Result {

    free_all(context.temp_allocator)
    //reset_batches(&_state.instance_batcher)

    platform.platform_reset_frame_input()
    platform.poll_events()

    if platform.should_close() {
        return .Exit
    }

    if platform.input_key_pressed(.KEY_ESCAPE) {
        return .Exit
    }
    
    interval_ns := external_ns if external_ns > 0 else gpu.frame_interval_ns()
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

        camera_ptr, ok := entity_get_typed(_state.entity_manager, _state.main_camera, Camera)
        if ok {
            camera_ptr.aspect_ratio = platform.window_aspect_ratio()
        }
    }

    return .Continue
}

_ready_up :: proc() {
    _state.frame_n = 1
    _state.frame_semaphore = gpu.semaphore(0)

    for i in 0 ..< FRAMES_IN_FLIGHT {
        _state.frame_arenas[i], _ = gpu.arena_init(CONFIG.frame_upload_bytes)
    }

    _state.window_size = platform.window_size_pixel()
    gpu.resize_swapchain(u32(_state.window_size.x), u32(_state.window_size.y))

    bit_array.init(&_state.textures)
    resize_depth(u32(_state.window_size.x), u32(_state.window_size.y))

    _state.entity_manager = new(Entity_Manager)
    entity_manager_init(_state.entity_manager)

    // Camera
    {
        entity_manager_add_variant(_state.entity_manager, Camera, 6, flags = {.Interpolate})
        camera_handle := _entity_add(_state.entity_manager, Camera, "camera") 
        camera := entity_get_typed(_state.entity_manager, camera_handle, Camera)

        camera.scale = {1, 1, 1}
        camera.near = 0.01
        camera.far = 1_000
        camera.fovy = 90
        camera.aspect_ratio = platform.window_aspect_ratio()
    
        _state.main_camera = camera.handle
    }

    mesh_library_init(&_state.mesh_library)

    _state.frame_uniform, _ = gpu.malloc(size_of(Engine_Uniform), 256, .Constant, "Frame Uniform")

    _state.sampler = gpu.sampler_init({
        mag_filter = .Nearest,
        min_filter = .Nearest,
        mip_filter = .Nearest,
        wrap_r = .ClampToEdge,
        wrap_s = .ClampToEdge,
        wrap_t = .ClampToEdge,
    })

    init_draw_batcher(&_state.draw_batcher)
    _material_lib_init(&_state.material_library)
    _shader_lib_init(&_state.shader_library)

    _state.initialized = true
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

add_resource :: proc(
    array: ^bit_array.Bit_Array(Resource($Res, $RHandle), $N, $H),
    res:   Res,
    name:  string = "",
    loc:          = #caller_location,
) -> H {
    handle, _ := bit_array.add(array, Resource(Res, RHandle) {
        data = res,
    })
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
        // Stash the full handle (with metadata) back in the slot so the leak
        // report can find it without a separate registry.
        if slot, ok := bit_array.get(array, handle); ok {
            slot.handle = handle
        }
    }
    return handle
}

get_resource :: proc(array: ^bit_array.Bit_Array(Resource($Res, $RHandle), $N, $H), handle: H, loc := #caller_location) -> (^Res, bool) {
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
    name: string = "",
    loc: = #caller_location,
) -> Texture_Handle {
    desc := gpu.Texture_Descriptor {
        dimensions = dimensions,
        format = .RGBA8Unorm,
        storage = .Shared,
        usage = {.Sampled},
        layer_count = 1,
        type = ._2D,
    }

    return texture_init_ex(desc, data, name, loc)
}

texture_init_ex :: proc(
    descriptor: Texture_Descriptor,
    data: rawptr = nil,
    name: string = "",
    loc: = #caller_location,
) -> Texture_Handle {

    texture := gpu.texture_init(descriptor)

    handle := add_resource(&_state.textures, texture, name, loc)

    if data != nil {
        gpu.copy_to_texture(texture, {0, 0, 0}, {descriptor.dimensions.x, descriptor.dimensions.y, 1}, 0, data, descriptor.dimensions.x * 4)
    }

    return handle
}
