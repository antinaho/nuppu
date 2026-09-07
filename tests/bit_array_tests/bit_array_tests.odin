package bit_array_tests

import "core:testing"
import ba "../../bit_array"

Test_Handle :: struct {
    handle: ba.Handle,
}

Test_Thing :: struct {
    handle: ba.Handle,
    value: u32,
}

@(test)
test_pack_unpack_handle :: proc(t: ^testing.T) {
    {
        index      := u32(123)
        generation := u8(42)
        handle     := ba.pack_handle(index, generation)
        index2, generation2 := ba.unpack_handle(handle)

        testing.expect_value(t, index, index2)
        testing.expect_value(t, generation, generation2)
    }

    {
        handle     := ba.pack_handle(1, 1)
        index, generation := ba.unpack_handle(handle)

        testing.expect_value(t, index, 1)
        testing.expect_value(t, generation, 1)
    }
}

@(test)
test_add :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle)
    ba.init(&handle_map)

    handle, ok := ba.add(&handle_map, Test_Thing { value = 1 })

    testing.expect_value(t, ok, true)
    testing.expect_value(t, handle.handle, ba.pack_handle(1, 1))
}

@(test)
test_get :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle)
    ba.init(&handle_map)
    h1, _ := ba.add(&handle_map, Test_Thing{value = 42})


    {
        // Valid handle
        ptr, ok := ba.get(&handle_map, h1)
        testing.expect_value(t, ok, true)
        testing.expect_value(t, ptr.value, u32(42))
    }

    {
        // NIL handle
        _, ok := ba.get(&handle_map, Test_Handle{ handle = ba.NIL_HANDLE })
        testing.expect_value(t, ok, false)
    }

    {
        // Stale handle (wrong generation)
        _, ok := ba.get(&handle_map, Test_Handle{ handle = ba.pack_handle(1, 99) })
        testing.expect_value(t, ok, false)
    }

    {
        // After remove
        ba.remove(&handle_map, h1)
        _, ok := ba.get(&handle_map, h1)
        testing.expect_value(t, ok, false)
    }
}

@(test)
test_remove :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle)
    ba.init(&handle_map)
    h1, _ := ba.add(&handle_map, Test_Thing{value = 42})

    testing.expect_value(t, ba.remove(&handle_map, h1), true)
    testing.expect_value(t, ba.remove(&handle_map, h1), false) // already removed
    testing.expect_value(t, ba.remove(&handle_map, Test_Handle{ handle = ba.pack_handle(1, 99) }), false) // stale
    testing.expect_value(t, ba.remove(&handle_map, Test_Handle{ handle = ba.NIL_HANDLE }), false)
}

@(test)
test_iterator :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle) = {}
    ba.init(&handle_map)

    _ = ba.add(&handle_map, Test_Thing{value = 10})
    _ = ba.add(&handle_map, Test_Thing{value = 20})
    _ = ba.add(&handle_map, Test_Thing{value = 30})

    it := ba.iterator_init(&handle_map)

    seen_10, seen_20, seen_30 := false, false, false
    count := 0
    for item in ba.iterator_next(&it) {
        count += 1
        switch item.value {
        case 10: seen_10 = true
        case 20: seen_20 = true
        case 30: seen_30 = true
        }
    }

    testing.expect_value(t, count, 3)
    testing.expect_value(t, seen_10, true)
    testing.expect_value(t, seen_20, true)
    testing.expect_value(t, seen_30, true)
}

@(test)
test_iterator_empty :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle)
    ba.init(&handle_map)
    it := ba.iterator_init(&handle_map)
    _, ok := ba.iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_skips_removed :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle)
    ba.init(&handle_map)
    h1, _ := ba.add(&handle_map, Test_Thing{value = 10})
    h2, _ := ba.add(&handle_map, Test_Thing{value = 20})

    ba.remove(&handle_map, h1)

    it := ba.iterator_init(&handle_map)
    item, ok := ba.iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok { testing.expect_value(t, item.value, u32(20)) }

    _, ok = ba.iterator_next(&it)
    testing.expect_value(t, ok, false)
}

@(test)
test_iterator_skips_sentinel :: proc(t: ^testing.T) {
    handle_map: ba.Bit_Array(Test_Thing, 1024, Test_Handle) = {}
    ba.init(&handle_map)
    _ = ba.add(&handle_map, Test_Thing{value = 99})

    it := ba.iterator_init(&handle_map)
    item, ok := ba.iterator_next(&it)
    testing.expect_value(t, ok, true)
    if ok { testing.expect_value(t, item.value, u32(99)) }

    // Make sure we never see the sentinel (value 0 / handle 0)
    _, ok = ba.iterator_next(&it)
    testing.expect_value(t, ok, false)
}

// ---- Wrapper-mode tests --------------------------------------------------
//
// T.handle is the H wrapper itself (not raw Handle). Mirrors the new entity
// pattern: Entity_Handle wrapper is stored directly in each slot.

Wrapped_Handle :: struct {
    handle: ba.Handle,
}

Base :: struct {
    handle: Wrapped_Handle,
    name:   string,
}

Derived :: struct {
    using base: Base,
    value:      u32,
}

@(test)
test_wrapped_add_get :: proc(t: ^testing.T) {
    pool: ba.Bit_Array(Derived, 64, Wrapped_Handle)
    ba.init(&pool)

    h, ok := ba.add(&pool, Derived{ name = "alpha", value = 42 })
    testing.expect_value(t, ok, true)
    testing.expect_value(t, h.handle != ba.NIL_HANDLE, true)

    ptr, ok2 := ba.get(&pool, h)
    testing.expect_value(t, ok2, true)
    if ok2 {
        testing.expect_value(t, ptr.value, u32(42))
        testing.expect_value(t, ptr.name, "alpha")
    }

    testing.expect_value(t, ba.remove(&pool, h), true)

    _, ok3 := ba.get(&pool, h)
    testing.expect_value(t, ok3, false)
}

@(test)
test_wrapped_stale_handle :: proc(t: ^testing.T) {
    pool: ba.Bit_Array(Derived, 64, Wrapped_Handle)
    ba.init(&pool)

    h1, _ := ba.add(&pool, Derived{ name = "first", value = 1 })
    h2, _ := ba.add(&pool, Derived{ name = "second", value = 2 })

    // Stale h1 after h2 took its slot via reuse
    testing.expect_value(t, ba.remove(&pool, h1), true)
    h1b, _ := ba.add(&pool, Derived{ name = "third", value = 3 })

    // h1 should now be stale (different generation)
    _, ok := ba.get(&pool, h1)
    testing.expect_value(t, ok, false)

    // h1b and h2 should still work
    p1, ok1 := ba.get(&pool, h1b)
    testing.expect_value(t, ok1, true)
    if ok1 { testing.expect_value(t, p1.value, u32(3)) }
    p2, ok2 := ba.get(&pool, h2)
    testing.expect_value(t, ok2, true)
    if ok2 { testing.expect_value(t, p2.value, u32(2)) }
}