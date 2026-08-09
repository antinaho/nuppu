package main

import nuppu "../../"
import "core:fmt"

Application :: struct {

}

update :: proc() {
    //fmt.println(nuppu.total_runtime())
}

render :: proc(prev, curr: Application, alpha: f32) {}

@export _desc := nuppu.App_Desc(Application) {
    update = update,
    render = render,
}

config :: nuppu.App_Config {
    window_size = [2]i32{800, 600},
    window_title = "Window",
}

main :: proc() {
    nuppu.app_init(
        _desc,
        config
    )
}