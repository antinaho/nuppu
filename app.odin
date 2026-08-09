package nuppu

import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import "core:mem"

App_Desc :: struct($T: typeid) {
    init: proc(),
	update: proc(),
	render: proc(previous: T, current: T, alpha: f32),
}

App_Config :: struct {
    window_size: [2]i32,
    window_title: string,
}

app: rawptr
prev_app: rawptr

app_init :: proc(
    desc: App_Desc($T),
    config: App_Config,
) {
    defer app_print_tracking()
    
    when ODIN_DEBUG {
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
	}

    logger := log.create_console_logger()
    defer log.destroy_console_logger(logger)
    context.logger = logger

    app = new(T)
    defer free(app)
    prev_app = new(T)
    defer free(prev_app)

    platform_init(config.window_size, config.window_title)
    defer platform_deinit()

    if desc.init != nil {
        desc.init()
    }

    @static accumulator: i64
    for platform_proceed() {
        frame_duration_ns := i64(time.tick_since(platform.previous_time))
        platform.previous_time = time.tick_now()
        accumulator += frame_duration_ns

        DT_TARGET_S_F64 :: 1.0 / 240
        DT_TARGET_NS_F64 :: DT_TARGET_S_F64 * f64(time.Second)
        actual_ns_target := i64(math.floor(DT_TARGET_NS_F64))

        num_ticks := accumulator / actual_ns_target
        accumulator -= num_ticks * actual_ns_target

        if num_ticks > 0 {
            platform.delta_mouse = (platform.input.mouse_position_window - platform.input.previous_mouse_position) / f64(num_ticks)
            platform.scroll_value = platform.input.scroll_value / f64(num_ticks)
            for T in 0 ..< num_ticks {
                desc.update()
                platform.input.mouse_released = {}
                platform.input.keys_released = {}	
            }
        }

        alpha := accumulator / actual_ns_target
        desc.render((^T)(prev_app)^, (^T)(app)^, f32(alpha))
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
