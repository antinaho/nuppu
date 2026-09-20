package entity_tests

import "core:testing"
import "core:mem"
import nuppu "../../"

Transform_Node :: struct {
    using e: ^nuppu.Entity,
}

@(private="file")
_make_manager :: proc() -> ^nuppu.Entity_Manager {
    manager := new(nuppu.Entity_Manager)
    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Transform_Node, 6)
    return manager
}

@(private="file")
_destroy_manager :: proc(manager: ^nuppu.Entity_Manager) {
    nuppu.entity_manager_destroy(manager)
}

@(test)
test_set_transform_writes_all_three_fields :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    nuppu.entity_set_transform(
        manager,
        node,
        position = {1, 2, 3},
        rotation = {0.1, 0.2, 0.3},
        scale    = {2, 2, 2},
    )

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{1, 2, 3})
    testing.expect_value(t, e.rotation, [3]f32{0.1, 0.2, 0.3})
    testing.expect_value(t, e.scale,    [3]f32{2, 2, 2})
}

@(test)
test_set_transform_overwrites_previous_values :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    nuppu.entity_set_transform(manager, node, {1, 1, 1}, {0, 0, 0}, {1, 1, 1})
    nuppu.entity_set_transform(manager, node, {5, 6, 7}, {1, 1, 1}, {2, 3, 4})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{5, 6, 7})
    testing.expect_value(t, e.rotation, [3]f32{1, 1, 1})
    testing.expect_value(t, e.scale,    [3]f32{2, 3, 4})
}

@(test)
test_set_transform_does_not_touch_prev_fields :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    nuppu.entity_set_transform(manager, node, {9, 9, 9}, {0, 0, 0}, {2, 2, 2})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.prev_position, [3]f32{0, 0, 0})
    testing.expect_value(t, e.prev_rotation, [3]f32{0, 0, 0})
    testing.expect_value(t, e.prev_scale,    [3]f32{0, 0, 0})
}

@(test)
test_set_transform_stale_handle_is_noop :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    bogus := nuppu.Entity_Handle { handle = { index = 999, gen = 1, variant = 0 } }
    nuppu.entity_set_transform(manager, bogus, {1, 2, 3}, {4, 5, 6}, {7, 8, 9})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{0, 0, 0})
    testing.expect_value(t, e.rotation, [3]f32{0, 0, 0})
    // New entities default to unit scale.
    testing.expect_value(t, e.scale,    [3]f32{1, 1, 1})
}

@(test)
test_set_transform_root_handle :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    root := nuppu.entity_root(manager)
    nuppu.entity_set_transform(manager, root.handle, {4, 5, 6}, {0, 0, 0}, {1, 1, 1})

    testing.expect_value(t, root.position, [3]f32{4, 5, 6})
}

@(test)
test_move_increments_position :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    nuppu.entity_set_transform(manager, node, {1, 2, 3}, {0, 0, 0}, {1, 1, 1})
    nuppu.entity_move(manager, node, {10, 20, 30})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{11, 22, 33})
}

@(test)
test_move_leaves_rotation_and_scale_alone :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    nuppu.entity_set_transform(manager, node, {0, 0, 0}, {0.5, 0.5, 0.5}, {3, 3, 3})
    nuppu.entity_move(manager, node, {1, 1, 1})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{1, 1, 1})
    testing.expect_value(t, e.rotation, [3]f32{0.5, 0.5, 0.5})
    testing.expect_value(t, e.scale,    [3]f32{3, 3, 3})
}

@(test)
test_move_accumulates_across_calls :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    nuppu.entity_move(manager, node, {1, 0, 0})
    nuppu.entity_move(manager, node, {0, 2, 0})
    nuppu.entity_move(manager, node, {0, 0, 4})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{1, 2, 4})
}

@(test)
test_move_stale_handle_is_noop :: proc(t: ^testing.T) {
    manager := _make_manager()
    defer _destroy_manager(manager)

    node := nuppu._entity_add(manager, Transform_Node)

    bogus := nuppu.Entity_Handle { handle = { index = 999, gen = 1, variant = 0 } }
    nuppu.entity_move(manager, bogus, {100, 100, 100})

    e, _ := nuppu.entity_get(manager, node)
    testing.expect_value(t, e.position, [3]f32{0, 0, 0})
}
