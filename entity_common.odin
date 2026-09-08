package nuppu

entity_set_transform :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle,
    position, rotation, scale: [3]f32,
) {
    e, ok := entity_get(manager, handle)
    if !ok { return }
    e.position = position
    e.rotation = rotation
    e.scale    = scale
}

entity_move :: proc "contextless" (manager: ^Entity_Manager, handle: Entity_Handle, delta: [3]f32) {
    e, ok := entity_get(manager, handle)
    if !ok { return }
    e.position += delta
}

set_transform :: proc "contextless" (
    handle: Entity_Handle,
    position, rotation, scale: [3]f32,
) {
    entity_set_transform(_state.entity_manager, handle, position, rotation, scale)
}

move :: proc "contextless" (handle: Entity_Handle, delta: [3]f32) {
    entity_move(_state.entity_manager, handle, delta)
}