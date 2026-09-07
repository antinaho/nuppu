package entity_tests

import "core:testing"
import "base:intrinsics"
import nuppu "../../"

Door :: struct {
    using e: nuppu.Entity,
    is_open: bool,
}

Frog :: struct {
    using e: nuppu.Entity,
    jump: f32,
}

Test_Union :: union {
    Frog,
    Door,
}

@(test)
test_add_get_roundtrip :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager(Test_Union))
    defer nuppu.entity_manager_deinit(manager)

    capacities := []int{
        intrinsics.type_variant_index_of(Test_Union, Door) = 4,
        intrinsics.type_variant_index_of(Test_Union, Frog) = 2,
    }
    nuppu.entity_manager_init(manager, capacities, 0, context.allocator)

    door := nuppu.entity_add(manager, Door)
    testing.expect(t, door != nil, "entity_add should return a pointer")
    if door == nil { return }
    door.is_open = true

    base := nuppu.entity_get(manager, door.handle)
    testing.expect(t, base != nil, "entity_get should return non-nil for valid handle")
    if base != nil {
        testing.expect_value(t, (cast(^Door)base).is_open, true)
        testing.expect(t, base.handle == door.handle, "retrieved handle must match")
    }
}

@(test)
test_stale_handle_after_remove :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager(Test_Union))
    defer nuppu.entity_manager_deinit(manager)

    capacities := []int{
        intrinsics.type_variant_index_of(Test_Union, Door) = 2,
        intrinsics.type_variant_index_of(Test_Union, Frog) = 2,
    }
    nuppu.entity_manager_init(manager, capacities, 0, context.allocator)

    door := nuppu.entity_add(manager, Door)
    if door == nil { return }
    handle := door.handle

    testing.expect_value(t, nuppu.entity_remove(manager, handle), true)

    testing.expect(t, nuppu.entity_get(manager, handle) == nil, "entity_get should return nil for stale handle")

    testing.expect_value(t, nuppu.entity_remove(manager, handle), false)
}

@(test)
test_reuse_bumps_generation :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager(Test_Union))
    defer nuppu.entity_manager_deinit(manager)

    capacities := []int{
        intrinsics.type_variant_index_of(Test_Union, Door) = 2,
        intrinsics.type_variant_index_of(Test_Union, Frog) = 2,
    }
    nuppu.entity_manager_init(manager, capacities, 0, context.allocator)

    first := nuppu.entity_add(manager, Door)
    if first == nil { return }
    first_handle := first.handle

    nuppu.entity_remove(manager, first_handle)

    second := nuppu.entity_add(manager, Door)
    if second == nil { return }
    second_handle := second.handle

    testing.expect(t, second_handle != first_handle, "reuse must produce a different generation")

    testing.expect(t, nuppu.entity_get(manager, first_handle) == nil, "stale handle should fail to look up")
    testing.expect(t, nuppu.entity_get(manager, second_handle) != nil, "fresh handle should look up")
}

@(test)
test_pool_full_returns_nil :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager(Test_Union))
    defer nuppu.entity_manager_deinit(manager)

    capacities := []int{
        intrinsics.type_variant_index_of(Test_Union, Door) = 3,
        intrinsics.type_variant_index_of(Test_Union, Frog) = 2,
    }
    nuppu.entity_manager_init(manager, capacities, 0, context.allocator)

    a := nuppu.entity_add(manager, Door)
    b := nuppu.entity_add(manager, Door)
    c := nuppu.entity_add(manager, Door)

    testing.expect(t, a != nil, "first add should succeed")
    testing.expect(t, b != nil, "second add should succeed")
    testing.expect(t, c == nil, "third add should fail when pool is full")
}
