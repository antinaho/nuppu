package nuppu

import "base:runtime"
import "core:mem"
import "core:time"
import "core:fmt"

import "./platform"
import "./gpu"

IS_RELEASE :: #config(RELEASE, false)
IS_DEBUG :: !IS_RELEASE

State :: struct #align(64) {
    ctx: runtime.Context,
    initialized: bool,

    curr_time: u64,
    prev_time: u64,
    frame_dur_ns: u64,
    accumulator: u64,
    num_sim_ticks: u64,

    update_state_size: int,

    current_state: rawptr,
    previous_state: rawptr,

    window_size: [2]i32,

    application_state: platform.State,
    gpu_state: gpu.State,

    s: typeid,
    desc: struct {
        init: proc(),
        update: proc(),
        deinit: proc(),
        render: rawptr,
    },
}

_state: ^State

App_Desc :: struct($T: typeid) #all_or_none {
    state: ^^T,
    window_size: [2]i32,
    update: proc(),
	render: proc(previous, current: ^T, alpha: f32),
    using _: App_Optional,
}

App_Optional :: struct {
    window_title: string,
    init: proc(),
    deinit: proc(),
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
        }
        else {
            return true
        }
    }
    
    if !pre_update() {
        if _state.desc.deinit != nil {
            _state.desc.deinit()
        }
        return false
    }

    if _state.num_sim_ticks > 0 {
        platform.normalize_ticks(_state.num_sim_ticks)
        for _ in 0 ..< _state.num_sim_ticks {
            runtime.mem_copy_non_overlapping(_state.previous_state, _state.current_state, _state.update_state_size)
            _state.desc.update()
            platform.release_input()
        }
    }

    // Skip render?
    if !_window_visible() {
        return true
    }
    
    // Resize swapchain + depth?
    current_window_size := platform.window_size_pixel()
    if _state.window_size.x != current_window_size.x || _state.window_size.y != current_window_size.y {
        gpu.resize_swapchain(u32(current_window_size.x), u32(current_window_size.y))
        gpu.resize_depth(u32(current_window_size.x), u32(current_window_size.y))
        _state.window_size = current_window_size
    }

    render_fn := (proc(prev, curr: rawptr, alpha: f32))(_state.desc.render)

    render_fn(_state.previous_state, _state.current_state, _render_alpha())
    return true
}

run :: proc(desc: App_Desc($T)) {
    assert(_state == nil)

    alloc_err: runtime.Allocator_Error
    _state, alloc_err = new(State)
    if alloc_err != nil {
        panic("Failed to allocate state")
    }
    _state.ctx = context

    state_size := size_of(T)
    state_size = mem.align_forward_int(state_size, 64)

    states, states_err := mem.alloc(size_of(T) * 2, alignment = 64)
    if states_err != nil {
        panic("Failed to allocate states")
    }

    _state.s = T
    current_state := &([^]T)(states)[0]
    previous_state := &([^]T)(states)[1]
    desc.state^ = current_state

    _state.current_state = current_state
    _state.previous_state = previous_state
    _state.update_state_size = mem.align_forward_int(size_of(T), 64)

    platform.init(&_state.application_state, desc.window_size, desc.window_title)
    _state.prev_time = platform.get_time_ns()
    gpu.init(&_state.gpu_state, platform.native_window())

when ODIN_OS == .JS { // WEB
    _state.desc = {
        init = desc.init,
        update = desc.update,
        deinit = desc.deinit,
        render = rawptr(desc.render),
    }
}
else { // NATIVE
    
    _ready_up()
    if desc.init != nil {
        desc.init()
    }
    
    for {
        if !pre_update() {
            break
        }
        
        if _state.num_sim_ticks > 0 {
            platform.normalize_ticks(_state.num_sim_ticks)
            for _ in 0 ..< _state.num_sim_ticks {
                runtime.mem_copy_non_overlapping(_state.previous_state, _state.current_state, _state.update_state_size)
                desc.update()
                platform.release_input()
            }
        }

        // Skip render?
        if !_window_visible() {
            continue
        }
        
        // Resize swapchain + depth?
        current_window_size := platform.window_size_pixel()
        if _state.window_size.x != current_window_size.x || _state.window_size.y != current_window_size.y {
            gpu.resize_swapchain(u32(current_window_size.x), u32(current_window_size.y))
            gpu.resize_depth(u32(current_window_size.x), u32(current_window_size.y))
            _state.window_size = current_window_size
        }

        if _state.gpu_state.frame_n > gpu.FRAMES_IN_FLIGHT {
            gpu.semaphore_wait(_state.gpu_state.frame_semaphore, _state.gpu_state.frame_n - gpu.FRAMES_IN_FLIGHT)
        }
        
        desc.render((^T)(_state.previous_state), (^T)(_state.current_state), _render_alpha())
    }
    
    if desc.deinit != nil {
        desc.deinit()
    }
}
}

RENDER_TARGET_X :: 1280
RENDER_TARGET_Y :: 720
USE_RENDER_TARGET :: #config(USE_RENDER_TARGET, true)

_ready_up :: proc() {
    _state.gpu_state.frame_semaphore = gpu.semaphore(0)
    
    _state.window_size = platform.window_size_pixel()
    gpu.resize_swapchain(u32(_state.window_size.x), u32(_state.window_size.y))
    gpu.resize_depth(u32(_state.window_size.x), u32(_state.window_size.y))
    // if USE_RENDER_TARGET {
    //     gpu.resize_render_target(RENDER_TARGET_X, RENDER_TARGET_Y)
    //     gpu.resize_render_target_depth(RENDER_TARGET_X, RENDER_TARGET_Y)
    // }

    _state.initialized = true
}

_render_alpha :: proc() -> f32 {
    return f32(_state.accumulator) / f32(SIM_NS_PER_TICK)
}

_window_visible :: proc() -> bool {
    current_window_size := platform.window_size_pixel()

    if current_window_size.x <= 0 || current_window_size.y <= 0 || .Iconified in platform.window_flags() || .Visible not_in platform.window_flags() {
        return false
    }
    return true
}

SIM_TICKS_PER_SECOND :: 180
SIM_NS_PER_TICK     :: time.Second / SIM_TICKS_PER_SECOND

aspect_ratio :: proc() -> f32 {
    return platform.window_aspect_ratio()
}

sim_delta_time :: proc() -> f32 {
    return 1.0 / f32(SIM_TICKS_PER_SECOND)
}

pre_update :: proc() -> bool {
    free_all(context.temp_allocator)

    platform.platform_reset_frame_input()
    platform.poll_events()

    if platform.input_key_pressed(.KEY_ESCAPE) {
        return false
    }
    
    time_ns := platform.get_time_ns()
    _state.curr_time = time_ns
    _state.frame_dur_ns = time_ns - _state.prev_time
    _state.prev_time = time_ns
    _state.accumulator += _state.frame_dur_ns

    _state.num_sim_ticks = _state.accumulator / u64(SIM_NS_PER_TICK)
    _state.accumulator -= _state.num_sim_ticks * u64(SIM_NS_PER_TICK)

    return true
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

Vertex :: struct #align(16) {
    position: [3]f32,
    uv: [2]u16,
}
