package nuppu

import "core:math"

entity_set_transform :: proc "contextless" (
    manager                  : ^Entity_Manager,
    handle                   : Entity_Handle,
    position, rotation, scale: [3]f32,
) {
    e, ok := entity_get(manager, handle)
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
    e, ok := entity_get(manager, handle)
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

// Shader-visible per-entity instance data for a sprite-sheet frame. Put this in
// a field literally named `gpu_instance` on the entity variant; that field's
// bytes are uploaded to the GPU every frame.
Sprite_Instance :: struct {
    uv_min:  [2]f32,
    uv_max:  [2]f32,
    frame_n: u32,
    _pad:    u32,
}
#assert(size_of(Sprite_Instance) == 24)
#assert(offset_of(Sprite_Instance, frame_n) == 16)

// CPU-side sprite-sheet playback state. Keep it next to the `gpu_instance`
// field so only the 24-byte `Sprite_Instance` is uploaded:
//
//   Sprite :: struct {
//       using e: ^Entity,
//       gpu_instance: Sprite_Instance,
//       anim:         Sprite_Animation,
//   }
Sprite_Animation :: struct {
    elapsed:   f32,
    fps:       f32,
    columns:   u32,
    rows:      u32,
}

sprite_animation_configure :: proc(gpu: ^Sprite_Instance, anim: ^Sprite_Animation, columns, rows: u32, fps: f32) {
    anim.columns = max(columns, 1)
    anim.rows    = max(rows, 1)
    anim.fps     = fps
    anim.elapsed = 0
    gpu.frame_n  = 0
    _sprite_animation_apply(gpu, anim)
}

// Advances playback by `dt` seconds and writes the current frame's uv rect.
// O(1) in `dt`; non-finite or non-positive `dt` only re-applies the uv rect.
sprite_animation_advance :: proc(gpu: ^Sprite_Instance, anim: ^Sprite_Animation, dt: f32) {
    if anim.columns == 0 || anim.rows == 0 { return }

    if anim.fps > 0 && dt > 0 && !math.is_nan_f32(dt) && !math.is_inf_f32(dt) {
        frame_dt := 1.0 / anim.fps
        if frame_dt > 0 {
            anim.elapsed += dt
            if anim.elapsed >= frame_dt {
                steps := math.floor(f64(anim.elapsed) / f64(frame_dt))
                anim.elapsed = f32(f64(anim.elapsed) - steps * f64(frame_dt))
                if anim.elapsed < 0 { anim.elapsed = 0 }
                total := u64(max(anim.columns * anim.rows, 1))
                gpu.frame_n = u32(math.mod(f64(gpu.frame_n) + steps, f64(total)))
            }
        }
    }
    _sprite_animation_apply(gpu, anim)
}

_sprite_animation_apply :: proc(gpu: ^Sprite_Instance, anim: ^Sprite_Animation) {
    if anim.columns == 0 || anim.rows == 0 { return }

    total := max(anim.columns * anim.rows, 1)
    f     := gpu.frame_n % total
    gpu.frame_n = f
    col   := f % anim.columns
    row   := f / anim.columns
    gpu.uv_min = {f32(col) / f32(anim.columns), f32(row) / f32(anim.rows)}
    gpu.uv_max = {f32(col + 1) / f32(anim.columns), f32(row + 1) / f32(anim.rows)}
}
