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

glfw_init :: proc(window_size: [2]i32, window_title: string) -> API_State {
    state = new(GLFW_Platform_State)
    
    if !glfw.Init() {
        panic("Failed to initialize GLFW")
    }

    glfw.WindowHint(glfw.DECORATED, true)
	glfw.WindowHint(glfw.RESIZABLE, true)
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    state.window = glfw.CreateWindow(window_size.x, window_size.y, cstring(raw_data(window_title[:])), nil, nil)
    assert(state.window != nil, "In platform_glfw: glfw_platform_api_init: Failed to create GLFW window")

    glfw.SetFramebufferSizeCallback(state.window, glfw_resize_callback)
	glfw.SetKeyCallback(state.window, glfw_key_callback)
	glfw.SetMouseButtonCallback(state.window, glfw_mouse_button_callback)
	glfw.SetCursorPosCallback(state.window, glfw_cursor_pos_callback)
	glfw.SetScrollCallback(state.window, glfw_scroll_input_callback)
	// glfw.SetCharCallback(state.window, glfw_char_input_callback)
	glfw.SetWindowFocusCallback(state.window, glfw_window_focus_callback)
	glfw.SetWindowIconifyCallback(state.window, glfw_window_iconify_callback)
    
	glfw_center_window()

    return API_State(state)
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
	win_w, win_h := glfw.GetWindowSize(state.window)
	x := wx + (ww - win_w) / 2
	y := wy + (wh - win_h) / 2
	glfw.SetWindowPos(state.window, x, y)
}

// ---------------------------------------------------------------------------
// Callbacks

glfw_resize_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
    context = platform.ctx
	fire_resize_event()
}

glfw_key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = platform.ctx

	nolla_key := glfw_key_to_nolla_key(key)
	if nolla_key == .UNKNOWN {
		log.warnf("Unknown GLFW keycode: %i", key)
		return
	}

	input := &platform.input
	switch action {
	case glfw.PRESS:
		input.keys_press_started[nolla_key] = input.keys_held[nolla_key] ~ true
		input.keys_held[nolla_key] = true
	case glfw.RELEASE:
		input.keys_released[nolla_key] = true
		input.keys_held[nolla_key] = false
	case glfw.REPEAT:
	}
}

glfw_mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
	context = platform.ctx
	
	nolla_mouse_button := glfw_mouse_button_to_nolla_mouse_button(button)
	if nolla_mouse_button == .UNKNOWN { 
		log.warnf("Unknown GLFW mousebutton: %i", button)
		return 
	}

	input := &platform.input
	switch action {
	case glfw.PRESS:
		input.mouse_press_started[nolla_mouse_button] = input.mouse_held[nolla_mouse_button] ~ true
		input.mouse_held[nolla_mouse_button] = true
	case glfw.RELEASE:
		input.mouse_released[nolla_mouse_button] = true
		input.mouse_held[nolla_mouse_button] = false
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

// ---------------------------------------------------------------------------
// Input

glfw_mouse_button_to_nolla_mouse_button :: proc(button: c.int) -> Mouse_Button {
	switch button {
	case glfw.MOUSE_BUTTON_LEFT:   return .LEFT
	case glfw.MOUSE_BUTTON_RIGHT:  return .RIGHT
	case glfw.MOUSE_BUTTON_MIDDLE: return .MIDDLE
	case:                          return .UNKNOWN
	}
}

glfw_cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
	platform.input.previous_mouse_position = platform.mouse_position_window
	platform.mouse_position_window = {xpos, ypos}
}

glfw_scroll_input_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	platform.scroll_value = {xoffset, yoffset}
}

glfw_key_to_nolla_key :: proc "contextless" (key: c.int) -> Keyboard_Key {
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

key_to_glfw_key :: proc(key: Keyboard_Key) -> c.int {
	switch key {
	case .KEY_0:            return glfw.KEY_0
	case .KEY_1:            return glfw.KEY_1
	case .KEY_2:            return glfw.KEY_2
	case .KEY_3:            return glfw.KEY_3
	case .KEY_4:            return glfw.KEY_4
	case .KEY_5:            return glfw.KEY_5
	case .KEY_6:            return glfw.KEY_6
	case .KEY_7:            return glfw.KEY_7
	case .KEY_8:            return glfw.KEY_8
	case .KEY_9:            return glfw.KEY_9

	case .KEY_A:            return glfw.KEY_A
	case .KEY_B:            return glfw.KEY_B
	case .KEY_C:            return glfw.KEY_C
	case .KEY_D:            return glfw.KEY_D
	case .KEY_E:            return glfw.KEY_E
	case .KEY_F:            return glfw.KEY_F
	case .KEY_G:            return glfw.KEY_G
	case .KEY_H:            return glfw.KEY_H
	case .KEY_I:            return glfw.KEY_I
	case .KEY_J:            return glfw.KEY_J
	case .KEY_K:            return glfw.KEY_K
	case .KEY_L:            return glfw.KEY_L
	case .KEY_M:            return glfw.KEY_M
	case .KEY_N:            return glfw.KEY_N
	case .KEY_O:            return glfw.KEY_O
	case .KEY_P:            return glfw.KEY_P
	case .KEY_Q:            return glfw.KEY_Q
	case .KEY_R:            return glfw.KEY_R
	case .KEY_S:            return glfw.KEY_S
	case .KEY_T:            return glfw.KEY_T
	case .KEY_U:            return glfw.KEY_U
	case .KEY_V:            return glfw.KEY_V
	case .KEY_W:            return glfw.KEY_W
	case .KEY_X:            return glfw.KEY_X
	case .KEY_Y:            return glfw.KEY_Y
	case .KEY_Z:            return glfw.KEY_Z

	case .KEY_ESCAPE:       return glfw.KEY_ESCAPE
	case .KEY_ENTER:        return glfw.KEY_ENTER
	case .KEY_TAB:          return glfw.KEY_TAB
	case .KEY_BACKSPACE:    return glfw.KEY_BACKSPACE
	case .KEY_INSERT:       return glfw.KEY_INSERT
	case .KEY_DELETE:       return glfw.KEY_DELETE
	case .KEY_RIGHT:        return glfw.KEY_RIGHT
	case .KEY_LEFT:         return glfw.KEY_LEFT
	case .KEY_DOWN:         return glfw.KEY_DOWN
	case .KEY_UP:           return glfw.KEY_UP
	case .KEY_PAGE_UP:      return glfw.KEY_PAGE_UP
	case .KEY_PAGE_DOWN:    return glfw.KEY_PAGE_DOWN
	case .KEY_HOME:         return glfw.KEY_HOME
	case .KEY_END:          return glfw.KEY_END
	case .KEY_CAPS_LOCK:    return glfw.KEY_CAPS_LOCK
	case .KEY_SCROLL_LOCK:  return glfw.KEY_SCROLL_LOCK
	case .KEY_NUM_LOCK:     return glfw.KEY_NUM_LOCK
	case .KEY_PRINT_SCREEN: return glfw.KEY_PRINT_SCREEN
	case .KEY_PAUSE:        return glfw.KEY_PAUSE

	case .KEY_F1:            return glfw.KEY_F1
	case .KEY_F2:            return glfw.KEY_F2
	case .KEY_F3:            return glfw.KEY_F3
	case .KEY_F4:            return glfw.KEY_F4
	case .KEY_F5:            return glfw.KEY_F5
	case .KEY_F6:            return glfw.KEY_F6
	case .KEY_F7:            return glfw.KEY_F7
	case .KEY_F8:            return glfw.KEY_F8
	case .KEY_F9:            return glfw.KEY_F9
	case .KEY_F10:           return glfw.KEY_F10
	case .KEY_F11:           return glfw.KEY_F11
	case .KEY_F12:           return glfw.KEY_F12

	case .UNKNOWN:          return glfw.KEY_UNKNOWN
	case:                   return glfw.KEY_UNKNOWN
	}
}
