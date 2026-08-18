package nuppu_platform

import "base:runtime"

PLATFORM_BACKEND_GLFW :: "GLFW"
PLATFORM_BACKEND_WEB :: "Web"
PLATFORM_INVALID_BACKEND :: "Invalid"

when ODIN_OS == .JS {
    PLATFORM_BACKEND :: PLATFORM_BACKEND_WEB
}
else when ODIN_OS == .Darwin {
    PLATFORM_BACKEND :: PLATFORM_BACKEND_GLFW
} else {
    PLATFORM_BACKEND :: PLATFORM_INVALID_BACKEND
    #panic("Platform not supported")
}

State :: struct #align(64) {
    using impl: _State,
    is_init: bool,
    ctx: runtime.Context,
    flags: Window_Flags,

    input: Input,
}

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

Mouse_Button :: enum u32 {
	UNKNOWN,
	LEFT,
	RIGHT,
	MIDDLE
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

Window_Flag :: enum u8 {
    Visible,
    Focused,
    Iconified,
}

Window_Flags :: bit_set[Window_Flag]

window_flags :: proc() -> Window_Flags {
    return _state.flags
}

_state: ^State

init :: proc(state: ^State, window_size: [2]i32, window_title: string) -> bool {
    if _state != nil {
        return true
    }

    _state = state
    _state.ctx = context

    return _init(window_size, window_title)
}

is_init :: proc() -> bool {
    return _state.is_init
}

native_window :: proc() -> rawptr {
	return _native_window()
}

window_size_logical :: proc() -> [2]i32 {
	return _window_size_logical()
}

window_size_pixel :: proc() -> [2]i32 {
	return _window_size_pixel()
}

poll_events :: proc() {
	_poll_events()
}

platform_reset_frame_input :: proc() {
    _state.input.mouse_press_started = {}
	_state.input.mouse_released = {}
	_state.input.delta_mouse = {}

	_state.input.scroll_value = {}
	
	_state.input.keys_press_started = {}
	_state.input.keys_released = {}	
}

get_time_ns :: proc() -> u64 {
    return _get_time_ns()
}

normalize_ticks :: proc(num_ticks: u64) {
	_state.input.delta_mouse = (_state.input.mouse_position_window - _state.input.previous_mouse_position) / f64(num_ticks)
    _state.input.scroll_value = _state.input.scroll_value / f64(num_ticks)
}

release_input :: proc() {
	_state.input.mouse_released = {}
    _state.input.keys_released = {}	
}


input_mouse_position_window :: proc() -> [2]f64 {
	return _state.input.mouse_position_window
}

input_mouse_position_delta :: proc() -> [2]f64 {
	return _state.input.delta_mouse
}

input_scroll_value :: proc() -> [2]f64 {
	return _state.input.scroll_value
}

input_key_pressed :: proc(key: Keyboard_Key) -> bool {
	return _state.input.keys_press_started[key]
}

input_key_released :: proc(key: Keyboard_Key) -> bool {
	return _state.input.keys_released[key]
}

input_key_held :: proc(key: Keyboard_Key) -> bool {
	return _state.input.keys_held[key]
}

input_mouse_button_pressed :: proc(button: Mouse_Button) -> bool {
	return _state.input.mouse_press_started[button]
}

input_mouse_button_released :: proc(button: Mouse_Button) -> bool {
	return _state.input.mouse_released[button]
}

input_mouse_button_held :: proc(button: Mouse_Button) -> bool {
	return _state.input.mouse_held[button]
}