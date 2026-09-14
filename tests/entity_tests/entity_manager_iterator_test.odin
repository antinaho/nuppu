/*
Entity manager iteration tests
test iterating base entities or typed ones
*/

package entity_tests

import "core:testing"
import "core:slice"
import nuppu "../../"

// Build an Entity_Iterator directly. entity_iterator_init cannot be used here
// because it references an undeclared helper in entity.odin.
@(private="file")
_make_iterator :: proc(manager: ^nuppu.Entity_Manager, $T: typeid) -> nuppu.Entity_Iterator {
    variant_idx, _ := slice.linear_search(manager.types[:], T)
    return nuppu.Entity_Iterator {
        manager     = manager,
        variant_idx = nuppu.ENTITY_VARIANT(variant_idx),
    }
}

@(test)
test_iterator_empty :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    it := _make_iterator(manager, Door)
    acc := false // true if we iterated at least once
    for _, _ in nuppu.entity_iterator_next(&it) {
        acc = true
        break
    }
    testing.expect_value(t, acc, false)
}

@(test)
test_iterator_skips_sentinel :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    door, ok := nuppu._entity_add(manager, Door)
    testing.expect(t, ok, "add should succeed")
    if !ok { return }

    it := _make_iterator(manager, Door)
    ent, h, ok2 := nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok2, true)
    if ok2 {
        testing.expect_value(t, h == door, true)
        base, _ := nuppu.entity_get(manager, door)
        testing.expect(t, ent == base, "iterator yields the base entity of the variant")
    }

    // Slot 0 sentinel must never appear.
    _, _, ok2 = nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok2, false)
}

@(test)
test_iterator_yields_all :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    n :: 3
    handles: [n]nuppu.Entity_Handle
    for i in 0..<n {
        d, ok := nuppu._entity_add(manager, Door)
        testing.expect_value(t, ok, true)
        if !ok { return }
        handles[i] = d
    }

    it := _make_iterator(manager, Door)
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
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    a, ok1 := nuppu._entity_add(manager, Door)
    b, ok2 := nuppu._entity_add(manager, Door)
    testing.expect_value(t, ok1, true)
    testing.expect_value(t, ok2, true)
    if !ok1 || !ok2 { return }

    testing.expect_value(t, nuppu.entity_remove(manager, a), true)

    it := _make_iterator(manager, Door)
    ent, h, ok := nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == b, true)
        b_base, _ := nuppu.entity_get(manager, b)
        testing.expect(t, ent == b_base, "yielded entity is b")
    }

    _, _, ok = nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_after_reuse :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    a, ok1 := nuppu._entity_add(manager, Door)
    testing.expect_value(t, ok1, true)
    if !ok1 { return }
    h_a := a

    testing.expect_value(t, nuppu.entity_remove(manager, h_a), true)

    b, ok2 := nuppu._entity_add(manager, Door)
    testing.expect_value(t, ok2, true)
    if !ok2 { return }

    testing.expect(t, b.handle.index == h_a.handle.index, "reuse reclaims the same slot")
    testing.expect(t, b.handle.gen != h_a.handle.gen, "gen bumps on reuse")

    it := _make_iterator(manager, Door)
    _, h, ok := nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == b, true)
    }
    _, _, ok = nuppu.entity_iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_type_specific :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)
    nuppu.entity_manager_add_variant(manager, Frog, 6)

    d, ok1 := nuppu._entity_add(manager, Door)
    f1, ok2 := nuppu._entity_add(manager, Frog)
    f2, ok3 := nuppu._entity_add(manager, Frog)
    testing.expect_value(t, ok1 && ok2 && ok3, true)
    if !ok1 || !ok2 || !ok3 { return }

    door_variant := d.handle.variant

    // Door iterator must not see Frogs.
    door_it := _make_iterator(manager, Door)
    ent, h, ok := nuppu.entity_variant_iterator_next(&door_it, Door)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, h == d, true)
        testing.expect_value(t, h.handle.variant, door_variant)
        d_ptr, _ := nuppu.entity_get_typed(manager, d, Door)
        testing.expect(t, ent == d_ptr, "yielded slot is d")
    }
    _, _, ok = nuppu.entity_iterator_next(&door_it)
    testing.expect_value(t, ok, false)

    // Frog iterator must see both Frogs and only Frogs.
    frog_it := _make_iterator(manager, Frog)
    seen: [2]bool
    count := 0
    for _, h in nuppu.entity_variant_iterator_next(&frog_it, Frog) {
        count += 1
        testing.expect_value(t, h.handle.variant, f1.handle.variant)
        if h == f1 { seen[0] = true }
        if h == f2 { seen[1] = true }
    }
    testing.expect_value(t, count, 2)
    testing.expect_value(t, seen[0], true)
    testing.expect_value(t, seen[1], true)
}

@(test)
test_iterator_handles_resolve :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)
    nuppu.entity_manager_add_variant(manager, Frog, 6)

    _, ok1 := nuppu._entity_add(manager, Door)
    _, ok2 := nuppu._entity_add(manager, Door)
    testing.expect_value(t, ok1 && ok2, true)
    if !ok1 || !ok2 { return }

    it := _make_iterator(manager, Door)
    for ent, h in nuppu.entity_iterator_next(&it) {
        resolved, ok2 := nuppu.entity_get(manager, h)
        testing.expect_value(t, ok2, true)
        testing.expect(t, resolved == ent, "handle.resolve == yielded pointer")
    }
}

@(test)
test_iterator_across_chunks :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    // chunk 0 = 64 slots (sentinel + 63), chunk 1 = 128 slots.
    nuppu.entity_manager_add_variant(manager, Door, 6)

    n :: 64
    handles: [n]nuppu.Entity_Handle
    for i in 0..<n {
        d, ok := nuppu._entity_add(manager, Door)
        testing.expect_value(t, ok, true)
        if !ok { return }
        handles[i] = d
    }

    testing.expect_value(t, len(manager.variants[0].chunks), 2)

    it := _make_iterator(manager, Door)
    count := 0
    seen: [n]bool
    for _, h in nuppu.entity_iterator_next(&it) {
        count += 1
        for i in 0..<n {
            if h == handles[i] { seen[i] = true }
        }
    }
    testing.expect_value(t, count, n)
    for i in 0..<n {
        testing.expect_value(t, seen[i], true)
    }
}
