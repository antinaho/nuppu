package nuppu

import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import "core:mem"
import "base:runtime"
import "core:os"

App_Desc :: struct($T: typeid) {
    init: proc(),
    deinit: proc(),
	update: proc(),
	render: proc(previous: T, current: T, alpha: f32, frame_arena: ^GPU_Arena, frame_pass: Frame_Pass),
}

App_Config :: struct {
    window_size: [2]i32,
    window_title: string,
    render_frames_in_flight: u64,
}

FPS :: 240
DT_TARGET_S_F64 :: 1.0 / f64(FPS)
DT_TARGET_NS_F64 :: DT_TARGET_S_F64 * f64(time.Second)

app_init :: proc(
    desc: App_Desc($T),
    app_state: ^^T,
    config: App_Config,
) {
when ODIN_DEBUG && ODIN_OS == .Darwin {
    os.set_env("MTL_DEBUG_LAYER", "1") // API validation
    os.set_env("MTL_SHADER_VALIDATION", "1") // Shader validation
    os.set_env("MTL_CAPTURE_ENABLED", "1") // GPU capture (.gputrace)
    os.set_env("MTL_HUD_ENABLED", "1") // HUD (performance counters)
    os.set_env("OBJC_DEBUG_MISSING_POOLS", "YES") // Track missing autorelease pools
}
    defer app_print_tracking()
    
    when ODIN_DEBUG {
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
	}

    logger := log.create_console_logger()
    defer log.destroy_console_logger(logger)
    context.logger = logger

    apps := new([2]T)
    app := &apps[0]
    app_state^ = app
    prev_app := &apps[1]

    defer free(apps)

    platform_init(config.window_size, config.window_title)
    defer platform_deinit()

    window_size := config.window_size
    gpu_init()
    defer gpu_deinit()

    render_frames_in_flight := max(config.render_frames_in_flight, 1)
    frame_arenas := make([]GPU_Arena, len=render_frames_in_flight)
    defer delete(frame_arenas)
    for &A in frame_arenas { A = gpu_arena_init() }
    defer for &A in frame_arenas { gpu_arena_deinit(&A) }
    next_frame := u64(1)
    signal := gpu_signal_init(0)
    defer gpu_signal_deinit(signal)

    if desc.init != nil {
        desc.init()
    }

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
                runtime.mem_copy_non_overlapping(prev_app, app, size_of(T))
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
        if current_window_size.x <= 0 || current_window_size.y <= 0 || is_iconified() {
            continue
        }

        if current_window_size.x != window_size.x || current_window_size.y != window_size.y {
            gpu_resize_swapchain()
            window_size = current_window_size
        }

        // Enable this once the signaling is fixed so we don't wait indefinitely
        if next_frame > render_frames_in_flight {
            gpu_signal_wait_for(signal, next_frame - render_frames_in_flight)
        }
        frame_arena := &frame_arenas[next_frame % render_frames_in_flight]
        gpu_arena_free_all(frame_arena)

        alpha := f64(accumulator) / f64(actual_ns_target)
        pass := Frame_Pass {
            signal = signal,
            value = next_frame,
        }
        if desc.render != nil {
            desc.render((^T)(prev_app)^, (^T)(app)^, f32(alpha), frame_arena, pass) // something here has to signal the next frame, not sure whats the best way to do that yet? Maybe need to get render_buffer as return and use that to signal?
            next_frame += 1
        }
    }

    if desc.deinit != nil {   
        desc.deinit()   
    }
}

track: mem.Tracking_Allocator
app_print_tracking :: proc() {
    if len(track.allocation_map) > 0 {
        fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
            fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
        }
    }
    if len(track.bad_free_array) > 0 {
        fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
            fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
        }
    }
    mem.tracking_allocator_destroy(&track)
}
