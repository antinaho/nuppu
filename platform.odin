package nuppu

import "base:runtime"
import "core:time"
import "core:math"
import "core:log"

Platform :: struct {
    is_running: bool,
    ctx: runtime.Context,

    api: Platform_API,
    api_state: Platform_API_State,

	flags: Window_Flags,

    using input: Input,
	start_tick: time.Tick,
	runtime_duration: time.Duration,
	sim_time:         time.Duration,
	previous_time: time.Tick,
	frame_counter: int,

	debug_shutdown_key: Keyboard_Key,
}

Platform_API_State :: distinct rawptr

Platform_API :: struct #all_or_none {
    state_size: proc() -> int,
    init: proc(window_size: [2]i32, window_title: string) -> Platform_API_State,
	deinit: proc(),
	poll_events: proc(),
	native_window: proc() -> rawptr,

    window_size_logical: proc() -> [2]i32,
	window_size_pixel:   proc() -> [2]i32,
	pixel_scale: proc() -> [2]f32,

	set_window_title: proc(title: string),
}

Force_Shutdown_Proc :: #type proc() -> bool
Resize_Window_Proc :: #type proc()

Window_Flag :: enum {
	Iconified,
	Focused,
}
Window_Flags :: bit_set[Window_Flag]

Input :: struct {
	previous_mouse_position: [2]f64,
	mouse_position_window: [2]f64,
	scroll_value: [2]f64,

	keys_press_started:   #sparse [Keyboard_Key]bool,
	keys_held:            #sparse [Keyboard_Key]bool,
	keys_released:        #sparse [Keyboard_Key]bool,

	mouse_press_started:   #sparse [Mouse_Button]bool,
	mouse_held:            #sparse [Mouse_Button]bool,
	mouse_released:        #sparse [Mouse_Button]bool,

	delta_mouse: [2]f64,
}

Keyboard_Key :: enum u32 {
	UNKNOWN,

	/* Alphanumeric characters */
	KEY_0,
	KEY_1,
	KEY_2,
	KEY_3,
	KEY_4,
	KEY_5,
	KEY_6,
	KEY_7,
	KEY_8,
	KEY_9,

	KEY_A,
	KEY_B,
	KEY_C,
	KEY_D,
	KEY_E,
	KEY_F,
	KEY_G,
	KEY_H,
	KEY_I,
	KEY_J,
	KEY_K,
	KEY_L,
	KEY_M,
	KEY_N,
	KEY_O,
	KEY_P,
	KEY_Q,
	KEY_R,
	KEY_S,
	KEY_T,
	KEY_U,
	KEY_V,
	KEY_W,
	KEY_X,
	KEY_Y,
	KEY_Z,

	/** Function keys **/

	/* Named non-printable keys */
	KEY_ESCAPE,
	KEY_ENTER,
	KEY_TAB,
	KEY_BACKSPACE,
	KEY_INSERT,
	KEY_DELETE,
	KEY_RIGHT,
	KEY_LEFT,
	KEY_DOWN,
	KEY_UP,
	KEY_PAGE_UP,
	KEY_PAGE_DOWN,
	KEY_HOME,
	KEY_END,
	KEY_CAPS_LOCK,
	KEY_SCROLL_LOCK,
	KEY_NUM_LOCK,
	KEY_PRINT_SCREEN,
	KEY_PAUSE,

	/** Function keys **/
	KEY_F1,
	KEY_F2,
	KEY_F3,
	KEY_F4,
	KEY_F5,
	KEY_F6,
	KEY_F7,
	KEY_F8,
	KEY_F9,
	KEY_F10,
	KEY_F11,
	KEY_F12,
}

Mouse_Button :: enum u32 {
	UNKNOWN,
	LEFT,
	RIGHT,
	MIDDLE
}

@(private="package")
platform: ^Platform


// ---------------------------------------------------------------------------
// Callbacks

on_resize_proc: proc()

set_resize_callback :: proc(p: Resize_Window_Proc) {
	on_resize_proc = p
}

fire_resize_event :: proc() {
	if on_resize_proc == nil {
		return
	}
	on_resize_proc()
}

// ---------------------------------------------------------------------------
// Window Flags

is_flag_set :: proc "contextless" (flag: Window_Flag) -> bool { return flag in platform.flags }

is_iconified :: proc "contextless" () -> bool { return .Iconified in platform.flags }
is_focused :: proc "contextless" () -> bool { return .Focused in platform.flags }

// ---------------------------------------------------------------------------
// Timers

fps :: proc "contextless" () -> f64 {
	return 1.0 / delta_time()
}

// Measured in seconds
delta_time :: proc "contextless" () -> f64 {
    return DT_TARGET_S_F64
}

delta_time_f32 :: proc "contextless" () -> f32 {
    return f32(DT_TARGET_S_F64)
}

// Measured in seconds
sim_time :: proc "contextless" () -> f32 {
    return f32(time.duration_seconds(platform.sim_time))
}

// ---------------------------------------------------------------------------
// Window Properties

window_size_logical :: proc() -> [2]i32 {
	return platform.api.window_size_logical()
}

window_size_pixel :: proc() -> [2]i32 {
	return platform.api.window_size_pixel()
}

pixel_scale :: proc() -> [2]f32 {
	return platform.api.pixel_scale()
}

set_window_title :: proc(title: string) {
    platform.api.set_window_title(title)
}

native_window :: proc() -> rawptr {
    return platform.api.native_window()
}

aspect_ratio :: proc() -> f32 {
	window_size := window_size_logical()
	return f32(window_size.x) / f32(window_size.y)
}

// ---------------------------------------------------------------------------
// API

platform_init :: proc(window_size: [2]i32, window_title: string) {
    platform = new(Platform)

    platform.ctx = context
    platform.api = PLATFORM_API

    platform.api_state = platform.api.init(window_size, window_title)

	platform.is_running = true
	platform.start_tick = time.tick_now()
	platform.previous_time = time.tick_now()

	platform.debug_shutdown_key = .KEY_ESCAPE
}

platform_deinit :: proc() {
    platform.is_running = false
	platform.api.deinit()
	free(platform)
}

poll_events :: proc() {
	platform.api.poll_events()
}

platform_proceed :: proc() -> bool {
	if !platform.is_running {
		return false
	}

	free_all(context.temp_allocator)

	platform_reset_frame_input()
	poll_events()

	if platform.debug_shutdown_key != .UNKNOWN && input_key_pressed(platform.debug_shutdown_key) {
		request_shutdown()
		return false
	}

    platform.runtime_duration = time.tick_since(platform.start_tick)
    platform.frame_counter += 1
	
	return platform.is_running
}

request_shutdown :: proc() {
    platform.is_running = false
}

// ---------------------------------------------------------------------------
// Input

platform_reset_frame_input :: proc() {
    platform.input.mouse_press_started = {}
	platform.input.mouse_released = {}
	platform.input.delta_mouse = {}

	platform.input.scroll_value = {}
	
	platform.input.keys_press_started = {}
	platform.input.keys_released = {}	
}

input_mouse_position_window :: proc() -> [2]f64 {
	return platform.input.mouse_position_window
}

input_mouse_position_delta :: proc() -> [2]f64 {
	return platform.input.delta_mouse
}

input_scroll_value :: proc() -> [2]f64 {
	return platform.input.scroll_value
}

input_key_pressed :: proc(key: Keyboard_Key) -> bool {
	return platform.input.keys_press_started[key]
}

input_key_released :: proc(key: Keyboard_Key) -> bool {
	return platform.input.keys_released[key]
}

input_key_held :: proc(key: Keyboard_Key) -> bool {
	return platform.input.keys_held[key]
}

input_mouse_button_pressed :: proc(button: Mouse_Button) -> bool {
	return platform.input.mouse_press_started[button]
}

input_mouse_button_released :: proc(button: Mouse_Button) -> bool {
	return platform.input.mouse_released[button]
}

input_mouse_button_held :: proc(button: Mouse_Button) -> bool {
	return platform.input.mouse_held[button]
}
