package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:time"
import "core:fmt"
import "core:log"

import "./platform"
import "./gpu"
import "bit_array"

_ :: fmt
_ :: log

SIM_TICKS_PER_SECOND :: 180
SIM_NS_PER_TICK     :: time.Second / SIM_TICKS_PER_SECOND

State :: struct #align(64) {
    ctx: runtime.Context,
    initialized: bool,

    curr_time: u64,
    prev_time: u64,
    frame_dur_ns: u64,
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
        render: proc(prev, curr: rawptr, alpha: f32),
    },

    vertex: gpu.Arena,
    index: gpu.Arena,
    frame_uniform: gpu.ptr,

    built_in_meshes: [Built_in_mesh]bit_array.Handle,
    meshes: bit_array.Bit_Array(Resource(Mesh), 512),
}

_state: ^State

Frame_Result :: enum { Continue, Skip_Render, Exit }

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

Resource :: struct($T: typeid) {
    handle: bit_array.Handle,
    data: T,
    metadata: Metadata,
}

Metadata :: struct {
    name: string,
    created_at: runtime.Source_Code_Location,
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
    _state.prev_time = platform.get_time_ns()
    gpu.init(&_state.gpu_state, platform.native_window())

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
            return
        case .Skip_Render:
            continue
        case .Continue:
            if _state.gpu_state.frame_n > gpu.FRAMES_IN_FLIGHT {
                gpu.semaphore_wait(_state.gpu_state.frame_semaphore, _state.gpu_state.frame_n - gpu.FRAMES_IN_FLIGHT)
            }
            desc.render((^T)(_state.previous_state), (^T)(_state.current_state), _render_alpha())
        }
    }
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
        return false
    case .Skip_Render:
        return true
    case .Continue:
        _state.desc.render(_state.previous_state, _state.current_state, _render_alpha())
        return true
    }
    return true
}

_frame :: proc() -> Frame_Result {

    free_all(context.temp_allocator)

    platform.platform_reset_frame_input()
    platform.poll_events()

    if platform.input_key_pressed(.KEY_ESCAPE) {
        return .Exit
    }
    
    time_ns := platform.get_time_ns()
    _state.curr_time = time_ns
    _state.frame_dur_ns = time_ns - _state.prev_time
    _state.prev_time = time_ns
    _state.accumulator += _state.frame_dur_ns

    _state.num_sim_ticks = _state.accumulator / u64(SIM_NS_PER_TICK)
    _state.accumulator -= _state.num_sim_ticks * u64(SIM_NS_PER_TICK)

    if _state.num_sim_ticks > 0 {
        platform.normalize_ticks(_state.num_sim_ticks)
        for _ in 0 ..< _state.num_sim_ticks {
            runtime.mem_copy_non_overlapping(_state.previous_state, _state.current_state, _state.update_state_size)
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
        gpu.resize_depth(u32(current.x), u32(current.y))
        _state.window_size = current
    }

    return .Continue
}

_ready_up :: proc() {
    _state.gpu_state.frame_semaphore = gpu.semaphore(0)

    _state.window_size = platform.window_size_pixel()
    gpu.resize_swapchain(u32(_state.window_size.x), u32(_state.window_size.y))
    gpu.resize_depth(u32(_state.window_size.x), u32(_state.window_size.y))

    // Currently forcing vertex to by Vertex type and index to Vertex_Index
    _state.vertex = gpu.arena_init(usage = .GPU_Storage)
    _state.index = gpu.arena_init(el_size = size_of(Vertex_Index), el_count = 1024, alignment = 4, usage = .GPU_Index)

    _state.frame_uniform = gpu.malloc(.GPU_Constant, 1, size_of(Engine_Uniform), align_of(Engine_Uniform), "Frame Uniform")
    create_built_in_meshes()

    _state.initialized = true
}

global_frame_uniform :: proc() -> gpu.ptr {
    return _state.frame_uniform
}

global_vertex_buffer :: proc() -> gpu.ptr {
    return _state.vertex.ptr
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

add_resource :: proc(array: ^bit_array.Bit_Array(Resource($T), $N), res: T, meta: Metadata) -> bit_array.Handle {
    resource_handle := bit_array.add(array, Resource(T) {
        data = res,
        metadata = meta,
    })

    return resource_handle
}

get_resource :: proc(array: ^bit_array.Bit_Array(Resource($T), $N), handle: bit_array.Handle) -> (^T, bool) {
    resource_ptr, ok := bit_array.get(array, handle)
    return &resource_ptr.data, ok
}
