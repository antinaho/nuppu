package main

import nuppu "../../.."
import gpu "../../../gpu"

state: ^State

State :: struct { }

update :: proc() { }

render :: proc(prev, curr: ^State, alpha: f32) {
    gpu.begin_frame()
    swapchain := gpu.acquire_next_swapchain()

    gpu.begin_render_pass(
        {
            clear_color = {24, 24, 24, 255},
            load_action = .Clear,
            store_action = .Store,
            texture = swapchain,
        }
    )

    gpu.end_render_pass()
    
    gpu.end_frame()
}

desc := nuppu.App_Desc(State) {
    state = &state,
    window_size = {1000, 1000},
    update = update,
    render = render,
}

main :: proc() {
    nuppu.run(desc)
}