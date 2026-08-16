#+build darwin
package nuppu

import "vendor:glfw"
import "core:fmt"
import "core:log"
import "core:c"

GLFW_PLATFORM_API :: Platform_API {
    state_size = glfw_state_size,
    init = glfw_init,
	deinit = glfw_deinit,
    poll_events = glfw_poll_events,
	native_window = glfw_native_window,
	window_size_logical = glfw_get_window_size_logical,
	window_size_pixel   = glfw_get_window_size_pixel,
	pixel_scale = glfw_get_pixel_scale,
	set_window_title = glfw_set_window_title,
	monitor_size_logical = glfw_monitor_size_logical,
	set_window_size = glfw_set_window_size,
}

@(private="file")
state: ^GLFW_Platform_State

GLFW_Platform_State :: struct {
    window: glfw.WindowHandle,
}

// ---------------------------------------------------------------------------
// 

glfw_state_size :: proc() -> int {
    return size_of(GLFW_Platform_State)
}

glfw_init :: proc(window_size: [2]i32, window_title: string) -> Platform_API_State {
    state = new(GLFW_Platform_State)
    
    if !glfw.Init() {
        panic("Failed to initialize GLFW")
    }

	// If user asked for size that doesnt fit, clamp to monitor size
    monitor_size := monitor_size_logical()
    window_x, window_y := min(window_size.x, monitor_size.x), min(window_size.y, monitor_size.y) 

    glfw.WindowHint(glfw.DECORATED, true)
	glfw.WindowHint(glfw.RESIZABLE, true)
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    state.window = glfw.CreateWindow(window_x, window_y, cstring(raw_data(window_title[:])), nil, nil)
    assert(state.window != nil, "In platform_glfw: glfw_platform_api_init: Failed to create GLFW window")

	glfw.SetKeyCallback(state.window, glfw_key_callback)
	glfw.SetMouseButtonCallback(state.window, glfw_mouse_button_callback)
	glfw.SetCursorPosCallback(state.window, glfw_cursor_pos_callback)
	glfw.SetScrollCallback(state.window, glfw_scroll_input_callback)
	// glfw.SetCharCallback(state.window, glfw_char_input_callback)
	glfw.SetWindowFocusCallback(state.window, glfw_window_focus_callback)
	glfw.SetWindowIconifyCallback(state.window, glfw_window_iconify_callback)
    
	glfw_center_window()

	// GLFW doesnt expose this so we assume its always true
	// Just need to make sure we don't zero out the flags at some point..
	platform.flags += {.Visible}
	platform_ready()
    return Platform_API_State(state)
}

glfw_deinit :: proc() {
	glfw.DestroyWindow(state.window)
	glfw.Terminate()
	free(state)
}

glfw_poll_events :: proc() {
    glfw.PollEvents()
}

// ---------------------------------------------------------------------------
// Window Properties

glfw_get_window_size_logical :: proc() -> [2]i32 {
	iw, ih := glfw.GetWindowSize(state.window)
	return {iw, ih}
}

glfw_get_window_size_pixel :: proc() -> [2]i32 {
	iw, ih := glfw.GetFramebufferSize(state.window)
	return {iw, ih}
}

glfw_native_window :: proc () -> rawptr {
	when ODIN_OS == .Darwin {
		return glfw.GetCocoaWindow(state.window)
	}
	return nil
}

glfw_get_pixel_scale :: proc() -> [2]f32 {
	scale_x, scale_y := glfw.GetWindowContentScale(state.window)
	return {scale_x, scale_y}
}

glfw_set_window_size :: proc(w, h: i32) {
	glfw.SetWindowSize(state.window, w, h)
}

glfw_set_window_title :: proc(title: string) {
	glfw.SetWindowTitle(state.window, cstring(raw_data(title[:])))
}

glfw_center_window :: proc() {
	monitor := glfw.GetPrimaryMonitor()
	wx, wy, ww, wh := glfw.GetMonitorWorkarea(monitor)
	win := glfw_get_window_size_logical()
	x := wx + (ww - win.x) / 2
	y := wy + (wh - win.y) / 2
	glfw.SetWindowPos(state.window, x, y)
}

glfw_monitor_size_logical :: proc() -> [2]i32 {
	monitor := glfw.GetPrimaryMonitor()
	wx, wy, ww, wh := glfw.GetMonitorWorkarea(monitor)
	return {ww, wh}
}

// ---------------------------------------------------------------------------
// Callbacks

glfw_key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = platform.ctx

	nuppu_key := glfw_key_to_nuppu_key(key)
	if nuppu_key == .UNKNOWN {
		log.warnf("Unknown GLFW keycode: %i", key)
		return
	}

	input := &platform.input
	switch action {
	case glfw.PRESS:
		input.keys_press_started[nuppu_key] = input.keys_held[nuppu_key] ~ true
		input.keys_held[nuppu_key] = true
	case glfw.RELEASE:
		input.keys_released[nuppu_key] = true
		input.keys_held[nuppu_key] = false
	case glfw.REPEAT:
	}
}

glfw_mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
	context = platform.ctx
	
	nuppu_mouse_button := glfw_mouse_button_to_nuppu_mouse_button(button)
	if nuppu_mouse_button == .UNKNOWN { 
		log.warnf("Unknown GLFW mousebutton: %i", button)
		return 
	}

	input := &platform.input
	switch action {
	case glfw.PRESS:
		input.mouse_press_started[nuppu_mouse_button] = input.mouse_held[nuppu_mouse_button] ~ true
		input.mouse_held[nuppu_mouse_button] = true
	case glfw.RELEASE:
		input.mouse_released[nuppu_mouse_button] = true
		input.mouse_held[nuppu_mouse_button] = false
	}	
}

glfw_window_iconify_callback :: proc "c" (window: glfw.WindowHandle, iconified: c.int) {
    input := &platform.input
	input^ = {}
	if iconified == c.int(true) {
		platform.flags += {.Iconified}
	} else {
		platform.flags -= {.Iconified}
	}
}

glfw_window_focus_callback :: proc "c" (window: glfw.WindowHandle, focused: c.int) {
    input := &platform.input
	input^ = {}
	if focused == c.int(true) {
		platform.flags += {.Focused}
	} else {
		platform.flags -= {.Focused}
	}
}

glfw_cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
	platform.input.previous_mouse_position = platform.mouse_position_window
	platform.mouse_position_window = {xpos, ypos}
}

glfw_scroll_input_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	platform.scroll_value = {xoffset, yoffset}
}

// ---------------------------------------------------------------------------
// Input

glfw_mouse_button_to_nuppu_mouse_button :: proc(button: c.int) -> Mouse_Button {
	switch button {
	case glfw.MOUSE_BUTTON_LEFT:   return .LEFT
	case glfw.MOUSE_BUTTON_RIGHT:  return .RIGHT
	case glfw.MOUSE_BUTTON_MIDDLE: return .MIDDLE
	case:                          return .UNKNOWN
	}
}

glfw_key_to_nuppu_key :: proc "contextless" (key: c.int) -> Keyboard_Key {
	switch key {
	case glfw.KEY_0:            return .KEY_0
	case glfw.KEY_1:            return .KEY_1
	case glfw.KEY_2:            return .KEY_2
	case glfw.KEY_3:            return .KEY_3
	case glfw.KEY_4:            return .KEY_4
	case glfw.KEY_5:            return .KEY_5
	case glfw.KEY_6:            return .KEY_6
	case glfw.KEY_7:            return .KEY_7
	case glfw.KEY_8:            return .KEY_8
	case glfw.KEY_9:            return .KEY_9

	case glfw.KEY_A:            return .KEY_A
	case glfw.KEY_B:            return .KEY_B
	case glfw.KEY_C:            return .KEY_C
	case glfw.KEY_D:            return .KEY_D
	case glfw.KEY_E:            return .KEY_E
	case glfw.KEY_F:            return .KEY_F
	case glfw.KEY_G:            return .KEY_G
	case glfw.KEY_H:            return .KEY_H
	case glfw.KEY_I:            return .KEY_I
	case glfw.KEY_J:            return .KEY_J
	case glfw.KEY_K:            return .KEY_K
	case glfw.KEY_L:            return .KEY_L
	case glfw.KEY_M:            return .KEY_M
	case glfw.KEY_N:            return .KEY_N
	case glfw.KEY_O:            return .KEY_O
	case glfw.KEY_P:            return .KEY_P
	case glfw.KEY_Q:            return .KEY_Q
	case glfw.KEY_R:            return .KEY_R
	case glfw.KEY_S:            return .KEY_S
	case glfw.KEY_T:            return .KEY_T
	case glfw.KEY_U:            return .KEY_U
	case glfw.KEY_V:            return .KEY_V
	case glfw.KEY_W:            return .KEY_W
	case glfw.KEY_X:            return .KEY_X
	case glfw.KEY_Y:            return .KEY_Y
	case glfw.KEY_Z:            return .KEY_Z

	case glfw.KEY_ESCAPE:       return .KEY_ESCAPE
	case glfw.KEY_ENTER:        return .KEY_ENTER
	case glfw.KEY_TAB:          return .KEY_TAB
	case glfw.KEY_BACKSPACE:    return .KEY_BACKSPACE
	case glfw.KEY_INSERT:       return .KEY_INSERT
	case glfw.KEY_DELETE:       return .KEY_DELETE
	case glfw.KEY_RIGHT:        return .KEY_RIGHT
	case glfw.KEY_LEFT:         return .KEY_LEFT
	case glfw.KEY_DOWN:         return .KEY_DOWN
	case glfw.KEY_UP:           return .KEY_UP
	case glfw.KEY_PAGE_UP:      return .KEY_PAGE_UP
	case glfw.KEY_PAGE_DOWN:    return .KEY_PAGE_DOWN
	case glfw.KEY_HOME:         return .KEY_HOME
	case glfw.KEY_END:          return .KEY_END
	case glfw.KEY_CAPS_LOCK:    return .KEY_CAPS_LOCK
	case glfw.KEY_SCROLL_LOCK:  return .KEY_SCROLL_LOCK
	case glfw.KEY_NUM_LOCK:     return .KEY_NUM_LOCK
	case glfw.KEY_PRINT_SCREEN: return .KEY_PRINT_SCREEN
	case glfw.KEY_PAUSE:          return .KEY_PAUSE

	case glfw.KEY_F1:            return .KEY_F1
	case glfw.KEY_F2:            return .KEY_F2
	case glfw.KEY_F3:            return .KEY_F3
	case glfw.KEY_F4:            return .KEY_F4
	case glfw.KEY_F5:            return .KEY_F5
	case glfw.KEY_F6:            return .KEY_F6
	case glfw.KEY_F7:            return .KEY_F7
	case glfw.KEY_F8:            return .KEY_F8
	case glfw.KEY_F9:            return .KEY_F9
	case glfw.KEY_F10:           return .KEY_F10
	case glfw.KEY_F11:           return .KEY_F11
	case glfw.KEY_F12:           return .KEY_F12

	case glfw.KEY_UNKNOWN:      return .UNKNOWN
	case:                       return .UNKNOWN
	}
}

