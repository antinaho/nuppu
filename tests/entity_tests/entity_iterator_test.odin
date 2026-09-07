package entity_tests

import "core:testing"
import "base:intrinsics"
import nuppu "../../"

@(test)
test_iterator_empty :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    it := nuppu.entity_iterator_init(manager, Door)
    acc: bool // true if we iterated at least once
    for _, _ in nuppu.entity_iterator_next(&it) {
        acc = true
        break
    }
    testing.expect_value(t, acc, false)
}

@(test)
test_iterator_skips_sentinel :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    door := nuppu.entity_add(manager, Door)
    testing.expect(t, door != nil, "add should succeed")
    if door == nil { return }

    it := nuppu.entity_iterator_init(manager, Door)
    ent, h, ok := nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == door.handle, true)
        testing.expect(t, ent == cast(^nuppu.Entity)door, "iterator yields the same memory")
    }

    // Slot 0 sentinel must never appear.
    _, _, ok = nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_yields_all :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    n :: 3
    handles: [n]nuppu.Entity_Handle
    for i in 0..<n {
        d, ok := nuppu.entity_add(manager, Door)
        testing.expect_value(t, ok, true)
        if !ok { return }
        handles[i] = d.handle
    }

    it := nuppu.entity_iterator_init(manager, Door)
    count := 0
    seen: [n]bool
    for ent, h in nuppu.entity_iterator_next(&it) {
        count += 1
        resolved, ok2 := nuppu.entity_get(manager, h)
        testing.expect_value(t, ok2, true)
        testing.expect(t, resolved == ent, "handle resolves to the yielded entity")
        for i in 0..<n {
            if h == handles[i] { seen[i] = true }
        }
    }
    testing.expect_value(t, count, n)
    for i in 0..<n {
        testing.expect_value(t, seen[i], true)
    }
}

@(test)
test_iterator_skips_removed :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    a, ok1 := nuppu.entity_add(manager, Door)
    b, ok2 := nuppu.entity_add(manager, Door)
    testing.expect_value(t, ok1, true)
    testing.expect_value(t, ok2, true)
    if !ok1 || !ok2 { return }

    testing.expect_value(t, nuppu.entity_remove(manager, a.handle), true)

    it := nuppu.entity_iterator_init(manager, Door)
    ent, h, ok := nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == b.handle, true)
        testing.expect(t, ent == cast(^nuppu.Entity)b, "yielded entity is b")
    }

    _, _, ok = nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_after_reuse :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    a, ok1 := nuppu.entity_add(manager, Door)
    testing.expect_value(t, ok1, true)
    if !ok1 { return }
    h_a := a.handle

    testing.expect_value(t, nuppu.entity_remove(manager, h_a), true)

    b, ok2 := nuppu.entity_add(manager, Door)
    testing.expect_value(t, ok2, true)
    if !ok2 { return }

    testing.expect(t, b.handle.index == h_a.index, "reuse reclaims the same slot")
    testing.expect(t, b.handle.gen != h_a.gen, "gen bumps on reuse")

    it := nuppu.entity_iterator_init(manager, Door)
    _, h, ok := nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == b.handle, true)
    }
    _, _, ok = nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_type_specific :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    d, ok1 := nuppu.entity_add(manager, Door)
    f1, ok2 := nuppu.entity_add(manager, Frog)
    f2, ok3 := nuppu.entity_add(manager, Frog)
    testing.expect_value(t, ok1 && ok2 && ok3, true)
    if !ok1 || !ok2 || !ok3 { return }

    door_variant := d.handle.variant_idx

    // Door iterator must not see Frogs.
    door_it := nuppu.entity_iterator_init(manager, Door)
    ent, h, ok := nuppu.entity_iterator_next(&door_it)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == d.handle, true)
        testing.expect_value(t, h.variant_idx, door_variant)
        testing.expect(t, ent == cast(^nuppu.Entity)d, "yielded slot is d")
    }
    _, _, ok = nuppu.entity_iterator_next(&door_it)
    testing.expect_value(t, ok, false)

    // Frog iterator must see both Frogs and only Frogs.
    frog_it := nuppu.entity_iterator_init(manager, Frog)
    seen: [2]bool
    count := 0
    for _, h in nuppu.entity_iterator_next(&frog_it) {
        count += 1
        testing.expect_value(t, h.variant_idx, f1.handle.variant_idx)
        if h == f1.handle { seen[0] = true }
        if h == f2.handle { seen[1] = true }
    }
    testing.expect_value(t, count, 2)
    testing.expect_value(t, seen[0], true)
    testing.expect_value(t, seen[1], true)
}

@(test)
test_iterator_handles_resolve :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_deinit(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 4)
    nuppu.entity_manager_add_variant(manager, Frog, 4)

    d1, ok1 := nuppu.entity_add(manager, Door)
    d2, ok2 := nuppu.entity_add(manager, Door)
    testing.expect_value(t, ok1 && ok2, true)
    if !ok1 || !ok2 { return }

    it := nuppu.entity_iterator_init(manager, Door)
    for ent, h in nuppu.entity_iterator_next(&it) {
        resolved, ok2 := nuppu.entity_get(manager, h)
        testing.expect_value(t, ok2, true)
        testing.expect(t, resolved == ent, "handle.resolve == yielded pointer")
    }
}
