package nuppu_platform

import "core:sys/wasm/js"
import "core:container/queue"
import "core:log"
import "core:time"

when PLATFORM_BACKEND == PLATFORM_BACKEND_WEB {

    _State :: struct {
        events: queue.Queue(js.Event),
    }

    _init :: proc(window_size: [2]i32, window_title: string) -> bool {
        assert(js.add_window_event_listener(.Key_Down, nil, _key_down_callback))
        assert(js.add_window_event_listener(.Key_Up, nil, _key_up_callback))

        assert(js.add_window_event_listener(.Mouse_Down, nil, _mouse_down_callback))
        assert(js.add_window_event_listener(.Mouse_Up, nil, _mouse_up_callback))

        assert(js.add_window_event_listener(.Wheel, nil, _scroll_input_callback))
        
        assert(js.add_event_listener("wgpu-canvas", .Mouse_Move, nil, _cursor_pos_callback))

        queue.init(&_state.events)

    	_state.flags += {.Visible}
        _state.is_init = true

        return true
    }

    _key_down_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _key_up_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _mouse_down_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _mouse_up_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _focus_gained_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _focus_lost_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _cursor_pos_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _scroll_input_callback :: proc(event: js.Event) {
        js.event_prevent_default()
        queue.push(&_state.events, event)
    }

    _native_window :: proc () -> rawptr {
        return {}
    }

    _window_size_logical :: proc() -> [2]i32 {
        rect := js.get_bounding_client_rect("body")
        return {i32(rect.width), i32(rect.height)}
    }

    _window_size_pixel :: proc() -> [2]i32 {
        logical := _window_size_logical()
        scale := _pixel_scale()
        return {i32(f32(logical.x) * scale.x), i32(f32(logical.y) * scale.y)}
    }

    _pixel_scale :: proc() -> [2]f32 {
        ratio := f32(js.device_pixel_ratio())
        return {ratio, ratio}
    }

    _get_time_ns :: proc() -> u64 {
        return u64(time.tick_now()._nsec)
    }

    _poll_events :: proc() {
        if queue.len(_state.events) == 0 {
            return
        }
        input := &_state.input
        for {
            event := queue.pop_front(&_state.events)

            #partial switch event.kind {
            case .Key_Down:
                nuppu_key := _key_to_nuppu_key(event.key.code)
                if nuppu_key == .UNKNOWN {
                    log.warnf("Unknown Web keycode: %i", event.key.code)
                    return
                }

                input.keys_press_started[nuppu_key] = input.keys_held[nuppu_key] ~ true
                input.keys_held[nuppu_key] = true
            case .Key_Up:
                nuppu_key := _key_to_nuppu_key(event.key.code)
                if nuppu_key == .UNKNOWN {
                    log.warnf("Unknown Web keycode: %i", event.key.code)
                    return
                }

                input.keys_released[nuppu_key] = true
                input.keys_held[nuppu_key] = false
            case .Mouse_Down:
                nuppu_mouse_button := _mouse_button_to_nuppu_mouse_button(event.mouse.button)
                if nuppu_mouse_button == .UNKNOWN { 
                    log.warnf("Unknown Web mousebutton: %i", event.mouse.button)
                    return 
                }

                input.mouse_press_started[nuppu_mouse_button] = input.mouse_held[nuppu_mouse_button] ~ true
                input.mouse_held[nuppu_mouse_button] = true
            case .Mouse_Up:
                nuppu_mouse_button := _mouse_button_to_nuppu_mouse_button(event.mouse.button)
                if nuppu_mouse_button == .UNKNOWN { 
                    log.warnf("Unknown Web mousebutton: %i", event.mouse.button)
                    return 
                }

                input.mouse_released[nuppu_mouse_button] = true
                input.mouse_held[nuppu_mouse_button] = false
            case .Focus:
                _state.flags += {.Focused}
            case .Blur:
                _state.flags -= {.Focused}
            case .Mouse_Move:
                _state.input.previous_mouse_position = _state.input.mouse_position_window
                _state.input.mouse_position_window = {f64(event.mouse.client.x), f64(event.mouse.client.y)}
            case .Scroll:
                _state.input.scroll_value = {event.scroll.delta.x, event.scroll.delta.y}
            }

            if queue.len(_state.events) == 0 {
                break
            }
        }
    }

    _mouse_button_to_nuppu_mouse_button :: proc(button: i16) -> Mouse_Button {
        switch button {
        case 0:   return .LEFT
        case 2:  return .RIGHT
        case 1: return .MIDDLE
        case: return .UNKNOWN
        }
    }

    _key_to_nuppu_key :: proc "contextless" (key: string) -> Keyboard_Key {
        switch key {
        case "Digit0":            return .KEY_0
        case "Digit1":            return .KEY_1
        case "Digit2":            return .KEY_2
        case "Digit3":            return .KEY_3
        case "Digit4":            return .KEY_4
        case "Digit5":            return .KEY_5
        case "Digit6":            return .KEY_6
        case "Digit7":            return .KEY_7
        case "Digit8":            return .KEY_8
        case "Digit9":            return .KEY_9

        case "KeyA":            return .KEY_A
        case "KeyB":            return .KEY_B
        case "KeyC":            return .KEY_C
        case "KeyD":            return .KEY_D
        case "KeyE":            return .KEY_E
        case "KeyF":            return .KEY_F
        case "KeyG":            return .KEY_G
        case "KeyH":            return .KEY_H
        case "KeyI":            return .KEY_I
        case "KeyJ":            return .KEY_J
        case "KeyK":            return .KEY_K
        case "KeyL":            return .KEY_L
        case "KeyM":            return .KEY_M
        case "KeyN":            return .KEY_N
        case "KeyO":            return .KEY_O
        case "KeyP":            return .KEY_P
        case "KeyQ":            return .KEY_Q
        case "KeyR":            return .KEY_R
        case "KeyS":            return .KEY_S
        case "KeyT":            return .KEY_T
        case "KeyU":            return .KEY_U
        case "KeyV":            return .KEY_V
        case "KeyW":            return .KEY_W
        case "KeyX":            return .KEY_X
        case "KeyY":            return .KEY_Y
        case "KeyZ":            return .KEY_Z

        case "Escape":       return .KEY_ESCAPE
        case "Enter":        return .KEY_ENTER

        case:                       return .UNKNOWN
        }
    }


}