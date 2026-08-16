package nuppu

import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import "core:mem"
import "base:runtime"
// import "core:os"

App_Desc :: struct {
    size: int,
    init: proc(),
    deinit: proc(),
	update: proc(),
	render: proc(previous, current: rawptr, alpha: f32, frame_arena: ^GPU_Arena, frame_pass: Frame_Pass),
}

App_Config :: struct {
    window_size: [2]i32,
    window_title: string,
}

FPS :: 240
DT_TARGET_S_F64 :: 1.0 / f64(FPS)
DT_TARGET_NS_F64 :: DT_TARGET_S_F64 * f64(time.Second)

RENDER_FRAMES_IN_FLIGHT :: 3

Application :: struct {
    track: mem.Tracking_Allocator,
    WEB_CTX: WEB_Context,
}

@(private="file")
application: ^Application

app_deinit :: proc() {
    free(application)
}

app_init :: proc(
    desc: App_Desc,
    app_state: ^^$T,
    config: App_Config,
) {
    application = new(Application)

// when ODIN_DEBUG && ODIN_OS == .Darwin {
//     os.set_env("MTL_DEBUG_LAYER", "1") // API validation
//     os.set_env("MTL_SHADER_VALIDATION", "1") // Shader validation
//     os.set_env("MTL_CAPTURE_ENABLED", "1") // GPU capture (.gputrace)
//     os.set_env("MTL_HUD_ENABLED", "1") // HUD (performance counters)
//     os.set_env("OBJC_DEBUG_MISSING_POOLS", "YES") // Track missing autorelease pools
// }
    defer app_deinit()
    defer app_print_tracking()
    
    when ODIN_DEBUG {
		mem.tracking_allocator_init(&application.track, context.allocator)
		context.allocator = mem.tracking_allocator(&application.track)
	}

    logger := log.create_console_logger()
    defer log.destroy_console_logger(logger)
    context.logger = logger

    apps_ptr, err := mem.alloc(desc.size * 2)
    if err != nil {
        log.panicf("app_init: failed to allocate app state: %v", err)
    }
    apps := (^T)(apps_ptr)
    
    app_state^ = apps

    base := apps
    prev := rawptr(uintptr(apps) + uintptr(desc.size))

    platform_init(config.window_size, config.window_title)
    gpu_init()




when ODIN_OS == .JS {
    application.WEB_CTX = WEB_Context {
        frame_arenas = make([]GPU_Arena, len=RENDER_FRAMES_IN_FLIGHT),
        next_frame = 1,
        ctx = context,
        accumulator = 0,
        actual_ns_target = i64(math.floor(DT_TARGET_NS_F64)),

        size = size_of(T),
        desc_init = desc.init,
        update = desc.update,
        render = desc.render,

        previous = prev,
        current = base,
    }
} else { // NATIVE

    for !platform_is_ready() || !GPU_is_ready() {
        time.sleep(20)
    }

    if desc.init != nil {
        desc.init()
    }

    defer free(apps_ptr)
    defer platform_deinit()
    defer gpu_deinit()

    frame_arenas := make([]GPU_Arena, len=RENDER_FRAMES_IN_FLIGHT)
    defer delete(frame_arenas)
    for &A in frame_arenas { A = gpu_arena_init() }
    defer for &A in frame_arenas { gpu_arena_deinit(&A) }
    next_frame := u64(1)
    signal := gpu_signal_init(0)
    defer gpu_signal_deinit(signal)

    @static accumulator: i64
    actual_ns_target := i64(math.floor(DT_TARGET_NS_F64))

    for platform_proceed() {
        frame_duration_ns := i64(time.tick_since(platform.previous_time))
        platform.previous_time = time.tick_now()
        accumulator += frame_duration_ns

        num_ticks := accumulator / actual_ns_target
        accumulator -= num_ticks * actual_ns_target

        if num_ticks > 0 {
            platform.delta_mouse = (platform.input.mouse_position_window - platform.input.previous_mouse_position) / f64(num_ticks)
            platform.scroll_value = platform.input.scroll_value / f64(num_ticks)
            for _ in 0 ..< num_ticks {
                runtime.mem_copy_non_overlapping(prev, base, desc.size)
                if desc.update != nil {
                    desc.update()
                }
                platform.sim_time += time.Duration(actual_ns_target)

                platform.input.mouse_released = {}
                platform.input.keys_released = {}	
            }
        }

        // Skip render if window isn't visible
        current_window_size := window_size_logical()
        if current_window_size.x <= 0 || current_window_size.y <= 0 || window_is_iconified() || !window_is_visible() {
            continue
        }

        if next_frame > RENDER_FRAMES_IN_FLIGHT {
            gpu_signal_wait_for(signal, next_frame - RENDER_FRAMES_IN_FLIGHT)
        }
        frame_arena := &frame_arenas[next_frame % RENDER_FRAMES_IN_FLIGHT]
        gpu_arena_free_all(frame_arena)

        alpha := f64(accumulator) / f64(actual_ns_target)
        pass := Frame_Pass {
            signal = signal,
            value = next_frame,
        }
        if desc.render != nil {
            desc.render(prev, base, f32(alpha), frame_arena, pass) // something here has to signal the next frame, not sure whats the best way to do that yet? Maybe need to get render_buffer as return and use that to signal?
            next_frame += 1
        }
    }

    if desc.deinit != nil {   
        desc.deinit()   
    }
} // NATIVE
}

WEB_Context :: struct {
    frame_arenas: []GPU_Arena,
    next_frame: i64,
    ctx: runtime.Context,
    accumulator: i64,
    actual_ns_target: i64,

    size: int,
    previous: rawptr,
    current: rawptr,

    desc_init_called: bool,
    desc_init: proc(),
    update: proc(),
    render: proc(previous, current: rawptr, alpha: f32, frame_arena: ^GPU_Arena, frame_pass: Frame_Pass),
}

// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
@(private="file", export)
step :: proc(dt: f32) -> bool {
	context = application.WEB_CTX.ctx
    CTX := &application.WEB_CTX

    for !platform_is_ready() || !GPU_is_ready() {
        return true
    }

    if !CTX.desc_init_called {
        if CTX.desc_init != nil {
            CTX.desc_init()
        }
        CTX.desc_init_called = true
    }

    if !platform_proceed() {
        return false
    }

    frame_duration_ns := i64(dt * f32(time.Second))
    platform.previous_time = time.tick_now()
    CTX.accumulator += frame_duration_ns

    num_ticks := CTX.accumulator / CTX.actual_ns_target
    CTX.accumulator -= num_ticks * CTX.actual_ns_target

    if num_ticks > 0 {
        platform.delta_mouse = (platform.input.mouse_position_window - platform.input.previous_mouse_position) / f64(num_ticks)
        platform.scroll_value = platform.input.scroll_value / f64(num_ticks)
        for _ in 0 ..< num_ticks {
            runtime.mem_copy_non_overlapping(CTX.previous, CTX.current, CTX.size)
            if CTX.update != nil {
                CTX.update()
            }
            platform.sim_time += time.Duration(CTX.actual_ns_target)

            platform.input.mouse_released = {}
            platform.input.keys_released = {}	
        }
    }

    // Skip render if window isn't visible
    current_window_size := window_size_logical()
    if current_window_size.x <= 0 || current_window_size.y <= 0 || window_is_iconified() || !window_is_visible() {
        return true
    }

    frame_arena := &CTX.frame_arenas[CTX.next_frame % RENDER_FRAMES_IN_FLIGHT]
    gpu_arena_free_all(frame_arena)

    alpha := f64(CTX.accumulator) / f64(CTX.actual_ns_target)
    if CTX.render != nil {
        CTX.render((CTX.previous), (CTX.current), f32(alpha), frame_arena, {})
        CTX.next_frame += 1
    }

	return true
}

app_print_tracking :: proc() {
    if len(application.track.allocation_map) > 0 {
        fmt.eprintf("=== %v allocations not freed: ===\n", len(application.track.allocation_map))
        for _, entry in application.track.allocation_map {
            fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
        }
    }
    if len(application.track.bad_free_array) > 0 {
        fmt.eprintf("=== %v incorrect frees: ===\n", len(application.track.bad_free_array))
        for entry in application.track.bad_free_array {
            fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
        }
    }
    mem.tracking_allocator_destroy(&application.track)
}
