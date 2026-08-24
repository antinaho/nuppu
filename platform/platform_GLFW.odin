#+build darwin
package nuppu_platform

import "core:log"
import "core:c"
import "vendor:glfw"
import "core:time"
import "core:os"

when PLATFORM_BACKEND == PLATFORM_BACKEND_GLFW { 

    _State :: struct {
        window: glfw.WindowHandle,
    }

    _init :: proc(window_size: [2]i32, window_title: string) -> bool {
        
        when ODIN_DEBUG {
            os.set_env("MTL_DEBUG_LAYER", "1") // API validation
            os.set_env("MTL_SHADER_VALIDATION", "1") // Shader validation
            os.set_env("MTL_CAPTURE_ENABLED", "1") // GPU capture (.gputrace)
            os.set_env("MTL_HUD_ENABLED", "1") // HUD (performance counters)
            os.set_env("OBJC_DEBUG_MISSING_POOLS", "YES") // Track missing autorelease pools
        }

        if window_size.x <= 0 || window_size.y <= 0 {
            log.error("platform_GLFW: _init: Window size must be greater than 0")
            return false
        }

        if !glfw.Init() {
            panic("platform_GLFW: _init: Failed to initialize GLFW")
        }

        // Open on primary monitor as default
        // Limit window size to monitor's size
        monitor := glfw.GetPrimaryMonitor()
        mx, my, mw, mh := glfw.GetMonitorWorkarea(monitor)
        
        x_scale, y_scale := f32(1.0), f32(1.0)
        if mw < window_size.x {
            x_scale = f32(mw) / f32(window_size.x)
        }
        if mh < window_size.y {
            y_scale = f32(mh) / f32(window_size.y)
        }

        if x_scale < 1.0 || y_scale < 1.0 {
            min_scale := min(x_scale, y_scale)
            window_size := window_size
            window_size.x = i32(f32(window_size.x) * min_scale)
            window_size.y = i32(f32(window_size.y) * min_scale)
        }

        glfw.WindowHint(glfw.DECORATED, false)
        glfw.WindowHint(glfw.RESIZABLE, false)
        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

        // Window
        window_title := window_title if len(window_title) > 0 else " "
        _state.window = glfw.CreateWindow(window_size.x, window_size.y, cstring(raw_data(window_title[:])), nil, nil)
        assert(_state.window != nil, "platform_GLFW: _init: Failed to create GLFW window")

        // Center window
        iw, ih := glfw.GetWindowSize(_state.window)
        x := mx + (mw - iw) / 2
	    y := my + (mh - ih) / 2
	    glfw.SetWindowPos(_state.window, x, y)

        // Callbacks
        glfw.SetKeyCallback(_state.window, _key_callback)
	    glfw.SetMouseButtonCallback(_state.window, _mouse_button_callback)
	    glfw.SetCursorPosCallback(_state.window, _cursor_pos_callback)
	    glfw.SetScrollCallback(_state.window, _scroll_input_callback)
	    glfw.SetWindowFocusCallback(_state.window, _window_focus_callback)
	    glfw.SetWindowIconifyCallback(_state.window, _window_iconify_callback)

        // Finalize
        _state.flags += {.Visible}
        _state.is_init = true

        return true
    }

    _deinit :: proc() {
        glfw.DestroyWindow(_state.window)
	    glfw.Terminate()
    }

    _native_window :: proc () -> rawptr {
        when ODIN_OS == .Darwin {
            return glfw.GetCocoaWindow(_state.window)
        }
        return nil
    }

    _window_size_logical :: proc() -> [2]i32 {
        w, h := glfw.GetWindowSize(_state.window)
        return {w, h}
    }

    _window_size_pixel :: proc() -> [2]i32 {
        w, h := glfw.GetFramebufferSize(_state.window)
        return {w, h}
    }

    _poll_events :: proc() {
        glfw.PollEvents()
    }

    _get_time_ns :: proc() -> u64 {
        return u64(glfw.GetTime() * f64(time.Second))
    }

    _window_aspect_ratio :: proc() -> f32 {
        dims := _window_size_logical()
        return f32(dims.x) / f32(dims.y)
    }

    _key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
        context = _state.ctx

        nuppu_key := _key_to_nuppu_key(key)
        if nuppu_key == .UNKNOWN {
            log.errorf("Unknown GLFW keycode: %i", key)
            return
        }

        input := &_state.input
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

    _mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
        context = _state.ctx
        
        nuppu_mouse_button := _mouse_button_to_nuppu_mouse_button(button)
        if nuppu_mouse_button == .UNKNOWN { 
            log.errorf("Unknown GLFW mousebutton: %i", button)
            return 
        }

        input := &_state.input
        switch action {
        case glfw.PRESS:
            input.mouse_press_started[nuppu_mouse_button] = input.mouse_held[nuppu_mouse_button] ~ true
            input.mouse_held[nuppu_mouse_button] = true
        case glfw.RELEASE:
            input.mouse_released[nuppu_mouse_button] = true
            input.mouse_held[nuppu_mouse_button] = false
        }	
    }

    _cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
        _state.input.previous_mouse_position = _state.input.mouse_position_window
        _state.input.mouse_position_window = {xpos, ypos}
    }

    _scroll_input_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
        _state.input.scroll_value = {xoffset, yoffset}
    }

    _window_focus_callback :: proc "c" (window: glfw.WindowHandle, focused: c.int) {
        input := &_state.input
        input^ = {}
        if focused == c.int(true) {
            _state.flags += {.Focused}
        } else {
            _state.flags -= {.Focused}
        }
    }

    _window_iconify_callback :: proc "c" (window: glfw.WindowHandle, iconified: c.int) {
        input := &_state.input
        input^ = {}
        if iconified == c.int(true) {
            _state.flags += {.Iconified}
        } else {
            _state.flags -= {.Iconified}
        }
    }

    _mouse_button_to_nuppu_mouse_button :: proc(button: c.int) -> Mouse_Button {
        switch button {
        case glfw.MOUSE_BUTTON_LEFT:   return .LEFT
        case glfw.MOUSE_BUTTON_RIGHT:  return .RIGHT
        case glfw.MOUSE_BUTTON_MIDDLE: return .MIDDLE
        case:                          return .UNKNOWN
        }
    }

    _key_to_nuppu_key :: proc "contextless" (key: c.int) -> Keyboard_Key {
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

        case:                       return .UNKNOWN
        }
    }
}