package main

import nuppu "../../.."

state: ^State

State :: struct { }

_update :: proc() { }

_render :: proc(current: ^State, alpha: f32) {
    frame := nuppu.begin_frame()
    defer nuppu.end_frame(frame)

    swapchain := nuppu.acquire_next_swapchain()
    nuppu.begin_render_pass({
        clear_color  = {24, 24, 24, 255},
        load_action  = .Clear,
        store_action = .Store,
        texture      = swapchain,
    })
    nuppu.end_render_pass()
}

desc := nuppu.App_Desc(State) {
    state       = &state,
    window_size = {1000, 1000},
    update      = _update,
    render      = _render,
}

main :: proc() {
    nuppu.run(desc)
}
