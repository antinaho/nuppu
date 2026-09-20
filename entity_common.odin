package nuppu

import "core:math"

entity_set_transform :: proc "contextless" (
    manager                  : ^Entity_Manager,
    handle                   : Entity_Handle,
    position, rotation, scale: [3]f32,
) {
    e, ok := _entity_get(manager, handle)
    if !ok { return }
    e.position = position
    e.rotation = rotation
    e.scale    = scale
}

entity_move :: proc "contextless" (
    manager: ^Entity_Manager,
    handle : Entity_Handle,
    delta  : [3]f32
) {
    e, ok := _entity_get(manager, handle)
    if !ok { return }
    e.position += delta
}

set_transform :: proc "contextless" (
    handle                   : Entity_Handle,
    position, rotation, scale: [3]f32,
) {
    entity_set_transform(_state.entity_manager, handle, position, rotation, scale)
}

move :: proc "contextless" (
    handle: Entity_Handle,
    delta : [3]f32
) {
    entity_move(_state.entity_manager, handle, delta)
}

// CPU-side sprite-sheet playback state. Pair it with a sprite entity and feed
// the resulting uv rect to `submit_sprite`:
//
//   Sprite :: struct {
//       using e: ^Entity,
//       anim: nuppu.Sprite_Animation,
//   }
//
//   uv_min, uv_size := nuppu.sprite_animation_uv(&e.anim)
//   nuppu.submit_sprite(e, uv_min, uv_size)
Sprite_Animation :: struct {
    elapsed: f32,
    fps:     f32,
    columns: u32,
    rows:    u32,
    frame_n: u32,
}

sprite_animation_configure :: proc(anim: ^Sprite_Animation, columns, rows: u32, fps: f32) {
    anim.columns = max(columns, 1)
    anim.rows    = max(rows, 1)
    anim.fps     = fps
    anim.elapsed = 0
    anim.frame_n = 0
}

// Advances playback by `dt` seconds. O(1) in `dt`; non-finite or non-positive
// `dt` leaves `frame_n` unchanged.
sprite_animation_advance :: proc(anim: ^Sprite_Animation, dt: f32) {
    if anim.columns == 0 || anim.rows == 0 { return }
    if anim.fps <= 0 || dt <= 0 || math.is_nan_f32(dt) || math.is_inf_f32(dt) { return }

    frame_dt := 1.0 / anim.fps
    if frame_dt <= 0 { return }

    anim.elapsed += dt
    if anim.elapsed >= frame_dt {
        steps := math.floor(f64(anim.elapsed) / f64(frame_dt))
        anim.elapsed = f32(f64(anim.elapsed) - steps * f64(frame_dt))
        if anim.elapsed < 0 { anim.elapsed = 0 }
        total := u64(max(anim.columns * anim.rows, 1))
        anim.frame_n = u32(math.mod(f64(anim.frame_n) + steps, f64(total)))
    }
}

// UV rect of the current frame, as (min, size).
sprite_animation_uv :: proc(anim: ^Sprite_Animation) -> (uv_min, uv_size: [2]f32) {
    columns := max(anim.columns, 1)
    rows    := max(anim.rows, 1)
    total   := columns * rows
    frame   := anim.frame_n % total
    col     := frame % columns
    row     := frame / columns

    uv_min  = {f32(col) / f32(columns), f32(row) / f32(rows)}
    uv_size = {1.0 / f32(columns), 1.0 / f32(rows)}
    return
}
