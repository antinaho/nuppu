package main

import nuppu "../../../"
import "core:fmt"
import "core:log"

basic_app: ^Basic

Basic :: struct {
}

render :: proc(prev, curr: rawptr, alpha: f32, arena: ^nuppu.GPU_Arena, pass: nuppu.Frame_Pass) {
    prev := (^Basic)(prev)
    curr := (^Basic)(curr)

    cmds := nuppu.begin_commands()
    swapchain := nuppu.acquire_next_swapchain(cmds)

    nuppu.cmd_begin_render_pass(cmds, {
        {
            clear_color = {64, 128, 255, 255},
            load_action = .Clear,
            store_action = .Store,
            texture = swapchain,
        }
    })

    nuppu.cmd_end_render_pass(cmds)
    nuppu.cmd_present(cmds, swapchain)
    nuppu.end_commands(cmds, pass)
}

@export _desc := nuppu.App_Desc {
    size = size_of(Basic),
    render = render,
}

config :: nuppu.App_Config {
    window_size = [2]i32{1280, 720},
    window_title = "Window",
}

main :: proc() {
    nuppu.app_init(
        _desc,
        &basic_app,
        config
    )
}