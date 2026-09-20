/*
Test common functionality of the entity manager
Add, remove, get, and get_typed
*/

package entity_tests

import "core:testing"
import nuppu "../../"

Door :: struct {
    using e: ^nuppu.Entity,
    is_open: bool,
}

Frog :: struct {
    using e: ^nuppu.Entity,
    jump: f32,
}

// The ^Entity back-pointer may also sit behind a `using` chain.
Entity_Base :: struct {
    using e: ^nuppu.Entity,
}

Deep_Entity :: struct {
    using base: Entity_Base,
}

@(test)
test_entity_back_pointer_through_using :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Deep_Entity, 6)

    h, ok := nuppu._entity_add(manager, Deep_Entity)
    testing.expect_value(t, ok, true)
    if !ok { return }

    d, d_ok := nuppu.entity_get_typed(manager, h, Deep_Entity)
    testing.expect_value(t, d_ok, true)
    if !d_ok { return }

    // Offset 0 must hold the ^Entity back-pointer, even when nested in `using`.
    testing.expect(t, d.base.e != nil, "back-pointer resolved through using")
    e, e_ok := nuppu.entity_get(manager, h)
    testing.expect_value(t, e_ok, true)
    if e_ok {
        testing.expect(t, e.handle == h, "handle round-trips")
    }
}

@(test)
test_sprite_animation_frames :: proc(t: ^testing.T) {
    a: nuppu.Sprite_Animation
    nuppu.sprite_animation_configure(&a, 2, 2, 10.0) // 2x2 atlas, 10 fps

    testing.expect_value(t, a.frame_n, u32(0))
    uv_min, uv_size := nuppu.sprite_animation_uv(&a)
    testing.expect_value(t, uv_min, [2]f32{0.0, 0.0})
    testing.expect_value(t, uv_size, [2]f32{0.5, 0.5})

    nuppu.sprite_animation_advance(&a, 0.1) // exactly one frame
    testing.expect_value(t, a.frame_n, u32(1))
    uv_min, uv_size = nuppu.sprite_animation_uv(&a)
    testing.expect_value(t, uv_min, [2]f32{0.5, 0.0})
    testing.expect_value(t, uv_size, [2]f32{0.5, 0.5})

    // Large dt must not hang and must wrap correctly.
    nuppu.sprite_animation_advance(&a, 1_000_000.0)
    testing.expect(t, a.frame_n < 4, "frame_n must stay within the atlas")

    // Out-of-range frame_n is reduced by uv computation; rect stays in the atlas.
    a.frame_n = 9
    uv_min, uv_size = nuppu.sprite_animation_uv(&a)
    testing.expect(t, uv_min.x >= 0 && uv_min.x + uv_size.x <= 1.0, "uv must stay inside the atlas")
    testing.expect(t, uv_min.y >= 0 && uv_min.y + uv_size.y <= 1.0, "uv must stay inside the atlas")

    // Non-square grid: 3x2 = 6 frames, all rects inside [0,1], wraps cleanly.
    b: nuppu.Sprite_Animation
    nuppu.sprite_animation_configure(&b, 3, 2, 10.0)
    for _ in 0 ..< 6 {
        bmin, bsize := nuppu.sprite_animation_uv(&b)
        testing.expect(t, bmin.x + bsize.x <= 1.0 && bmin.y + bsize.y <= 1.0)
        nuppu.sprite_animation_advance(&b, 0.1)
    }
    testing.expect_value(t, b.frame_n, u32(0))

    // fps <= 0 leaves frame_n untouched.
    c: nuppu.Sprite_Animation
    nuppu.sprite_animation_configure(&c, 2, 2, 0)
    c.frame_n = 2
    nuppu.sprite_animation_advance(&c, 1.0)
    testing.expect_value(t, c.frame_n, u32(2))

    // Sub-frame remainder must accumulate across calls (dt not a multiple of 1/fps).
    d: nuppu.Sprite_Animation
    nuppu.sprite_animation_configure(&d, 2, 2, 4.0) // frame_dt = 0.25
    nuppu.sprite_animation_advance(&d, 0.375) // 1 step + 0.125 remainder
    testing.expect_value(t, d.frame_n, u32(1))
    nuppu.sprite_animation_advance(&d, 0.375) // 0.5 -> 2 more steps
    testing.expect_value(t, d.frame_n, u32(3))
}

@(test)
test_add_get_roundtrip :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    handle: nuppu.Entity_Handle
    // Create and modify door
    {
        h, ok := nuppu._entity_add(manager, Door)
        testing.expect(t, ok, "entity_add should succeed")
        if !ok { return }
        door, _ := nuppu.entity_get_typed(manager, h, Door)
        door.is_open = true
        handle = h
    }

    // Retrieve door and validate
    {
        door, ok := nuppu.entity_get_typed(manager, handle, Door)
        testing.expect(t, ok, "entity_get_typed should return non-nil for valid handle")
        if ok {
            testing.expect_value(t, door.is_open, true)
        }
    }
}

@(test)
test_stale_handle_after_remove :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)
    nuppu.entity_manager_add_variant(manager, Frog, 6)

    handle: nuppu.Entity_Handle
    {
        h, ok := nuppu._entity_add(manager, Door)
        if !ok { return }
        handle = h
    }

    testing.expect_value(t, nuppu.entity_remove(manager, handle), true)

    testing.expect(t, nuppu.entity_get(manager, handle) == nil, "entity_get should return nil for stale handle")

    testing.expect_value(t, nuppu.entity_remove(manager, handle), false)
}

@(test)
test_reuse_bumps_generation :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)
    nuppu.entity_manager_add_variant(manager, Frog, 6)
    
    // Add -> remove -> add
    first_handle: nuppu.Entity_Handle
    {
        first, ok := nuppu._entity_add(manager, Door)
        if !ok { return }
        first_handle = first
    }

    nuppu.entity_remove(manager, first_handle)

    second_handle: nuppu.Entity_Handle
    {
        second, ok := nuppu._entity_add(manager, Door)
        if !ok { return }
        second_handle = second
    }
    testing.expect(t, nuppu.entity_get(manager, first_handle) == nil, "stale handle should fail to look up")
    testing.expect(t, nuppu.entity_get(manager, second_handle) != nil, "fresh handle should look up")

    testing.expect(t, second_handle.handle.gen != first_handle.handle.gen, "reuse must produce a different generation")
    testing.expect(t, second_handle.handle.index == first_handle.handle.index, "reuse must produce same index")
}

@(test)
test_chunk_growth_keeps_addresses_stable :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    data := &manager.variants[0]

    // Sentinel occupies index 0; fill the remaining 63 slots of chunk 0.
    a, ok_a := nuppu._entity_add(manager, Door)
    testing.expect(t, ok_a, "first add should succeed")
    if !ok_a { return }
    for _ in 0..<62 {
        _ = nuppu._entity_add(manager, Door)
    }

    testing.expect_value(t, data.top, 64)
    testing.expect_value(t, data.cap, 64)
    testing.expect_value(t, len(data.chunks), 1)

    a_door, _ := nuppu.entity_get_typed(manager, a, Door)
    a_entity_ptr  := a_door.e
    a_variant_ptr := a_door

    // Next add must append chunk 1 (geometric: 64 -> 128 slots).
    _, ok_c := nuppu._entity_add(manager, Door)
    testing.expect(t, ok_c, "chunk-crossing add should succeed")
    testing.expect_value(t, data.top, 65)
    testing.expect_value(t, data.cap, 192) // 64 + 128
    testing.expect_value(t, len(data.chunks), 2)

    // Earlier element addresses must not move across chunk growth.
    testing.expect(t, a_door.e == a_entity_ptr,  "base entity address stays stable across chunk growth")
    testing.expect(t, a_door == a_variant_ptr,   "variant address stays stable across chunk growth")

    a_again, ok := nuppu.entity_get_typed(manager, a, Door)
    testing.expect(t, ok, "a still resolves after growth")
    if ok {
        testing.expect(t, a_again == a_door, "a resolves to the same variant address")
        testing.expect(t, a_again.e == a_entity_ptr, "a's entity back-pointer is unchanged")
    }
}

@(test)
test_reacquire_prefers_earliest_chunk :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    data := &manager.variants[0]

    // Sentinel + 63 fill chunk 0; the next spills into chunk 1.
    a, _ := nuppu._entity_add(manager, Door) // index 1
    for _ in 0..<62 {
        _ = nuppu._entity_add(manager, Door) // indices 2..63
    }
    c, _ := nuppu._entity_add(manager, Door) // index 64 (chunk 1)

    a_handle := a
    c_handle := c

    testing.expect_value(t, a_handle.handle.index, 1)
    testing.expect_value(t, c_handle.handle.index, 64)
    testing.expect_value(t, len(data.chunks), 2)

    // Free the later chunk first, then the earlier one.
    testing.expect_value(t, nuppu.entity_remove(manager, c_handle), true)
    testing.expect_value(t, nuppu.entity_remove(manager, a_handle), true)

    // Reacquire must take the hole in the earliest chunk (index 1).
    d, _ := nuppu._entity_add(manager, Door)
    testing.expect_value(t, d.handle.index, 1)
    testing.expect(t, d.handle.gen != a_handle.handle.gen, "reused slot bumps generation")

    // The remaining hole lives in chunk 1 (index 64).
    e, _ := nuppu._entity_add(manager, Door)
    testing.expect_value(t, e.handle.index, 64)

    // High-water len must not grow while holes exist.
    testing.expect_value(t, data.top, 65)
}

@(test)
test_get_typed_rejects_wrong_type :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)
    nuppu.entity_manager_add_variant(manager, Frog, 6)

    door, ok := nuppu._entity_add(manager, Door)
    testing.expect_value(t, ok, true)
    if !ok { return }

    _, wrong := nuppu.entity_get_typed(manager, door, Frog)
    testing.expect_value(t, wrong, false)

    _, right := nuppu.entity_get_typed(manager, door, Door)
    testing.expect_value(t, right, true)
}

@(test)
test_chunk_size_from_shift :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6) // 1 << 6 = 64
    nuppu.entity_manager_add_variant(manager, Frog, 7) // 1 << 7 = 128

    testing.expect_value(t, manager.variants[0].first_chunk_size, 64)
    testing.expect_value(t, manager.variants[1].first_chunk_size, 128)
}

@(test)
test_min_shift_chunk_growth :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 1) // first chunk = 2 slots

    data := &manager.variants[0]
    testing.expect_value(t, data.first_chunk_size, 2)

    handles: [6]nuppu.Entity_Handle
    for i in 0..<6 {
        d, ok := nuppu._entity_add(manager, Door)
        testing.expect_value(t, ok, true)
        if !ok { return }
        handles[i] = d
        testing.expect_value(t, d.handle.index, nuppu.ENTITY_INDEX(i + 1))
    }

    // Geometric growth from 2: 2 + 4 + 8 slots cover indices 0..13.
    testing.expect_value(t, len(data.chunks), 3)
    testing.expect_value(t, data.chunks[0].occupied.live, 2) // sentinel + index 1
    testing.expect_value(t, data.chunks[1].occupied.live, 4) // indices 2..5
    testing.expect_value(t, data.chunks[2].occupied.live, 1) // index 6

    for i in 0..<6 {
        e, ok := nuppu.entity_get(manager, handles[i])
        testing.expect_value(t, ok, true)
        if ok {
            testing.expect_value(t, e.handle, handles[i])
        }
    }
}

@(test)
test_min_shift_bitmap_padding :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 1) // first chunk = 2 slots

    // Sentinel + one entity fills the 2-slot first chunk. The padding bits must
    // read as occupied so the slot search never yields a bit past `cap`.
    _, _ = nuppu._entity_add(manager, Door) // index 1
    d, _ := nuppu._entity_add(manager, Door) // index 2, next chunk

    data := &manager.variants[0]
    testing.expect_value(t, d.handle.index, 2)
    testing.expect_value(t, data.chunks[0].occupied.live, 2)
    testing.expect_value(t, data.chunks[0].occupied.words[0], ~nuppu.Bit_Mask64(0))
}

@(test)
test_min_shift_reuse :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 1)

    a, _ := nuppu._entity_add(manager, Door) // index 1, fills chunk 0
    b, _ := nuppu._entity_add(manager, Door) // index 2, chunk 1

    testing.expect_value(t, nuppu.entity_remove(manager, a), true)
    testing.expect_value(t, nuppu.entity_remove(manager, b), true)

    // Freed slots are reused from the earliest chunk that has a hole.
    c, _ := nuppu._entity_add(manager, Door)
    d, _ := nuppu._entity_add(manager, Door)
    testing.expect_value(t, c.handle.index, 1)
    testing.expect_value(t, d.handle.index, 2)
}

@(test)
test_index_mapping_across_chunks :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 6)

    N :: 200
    handles: [N]nuppu.Entity_Handle
    for i in 0..<N {
        d, ok := nuppu._entity_add(manager, Door)
        testing.expect_value(t, ok, true)
        if !ok { return }
        handles[i] = d
        testing.expect_value(t, d.handle.index, nuppu.ENTITY_INDEX(i + 1))
    }

    // 64 + 128 + 256 slots.
    testing.expect_value(t, len(manager.variants[0].chunks), 3)

    // Chunk boundaries: index 63 ends chunk 0, 64 starts chunk 1, 191 ends
    // chunk 1, 192 starts chunk 2.
    testing.expect_value(t, handles[62].handle.index, 63)
    testing.expect_value(t, handles[63].handle.index, 64)
    testing.expect_value(t, handles[190].handle.index, 191)
    testing.expect_value(t, handles[191].handle.index, 192)

    // Every handle must resolve to its own slot.
    for i in 0..<N {
        e, ok := nuppu.entity_get(manager, handles[i])
        testing.expect_value(t, ok, true)
        if ok {
            testing.expect_value(t, e.handle, handles[i])
        }
    }
}

@(test)
test_bitmap_reuse_across_words :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    // 128 slots => 2 whole bitmap words (no padding needed).
    nuppu.entity_manager_add_variant(manager, Door, 7)

    data := &manager.variants[0]

    // Sentinel occupies index 0; fill the rest of chunk 0.
    N :: 127
    handles: [N]nuppu.Entity_Handle
    for i in 0..<N {
        d, ok := nuppu._entity_add(manager, Door)
        testing.expect_value(t, ok, true)
        if !ok { return }
        handles[i] = d
    }

    testing.expect_value(t, len(data.chunks), 1)
    testing.expect_value(t, data.first_chunk_size, 128) // 128 slots => 2 bitmap words
    testing.expect_value(t, data.chunks[0].occupied.live, 128) // sentinel + 127
    testing.expect_value(t, data.top, 128)

    // Free one slot in each word: global indices 1 and 65.
    testing.expect_value(t, nuppu.entity_remove(manager, handles[0]), true)  // index 1
    testing.expect_value(t, nuppu.entity_remove(manager, handles[64]), true) // index 65

    // Reacquire returns the lowest hole first, then the next.
    d1, _ := nuppu._entity_add(manager, Door)
    d2, _ := nuppu._entity_add(manager, Door)
    testing.expect_value(t, d1.handle.index, 1)
    testing.expect_value(t, d2.handle.index, 65)
    testing.expect_value(t, data.top, 128) // no growth while holes exist

    // Chunk 0 is full again; the next add spills into a fresh chunk.
    d3, _ := nuppu._entity_add(manager, Door)
    testing.expect_value(t, d3.handle.index, 128)
    testing.expect_value(t, data.top, 129)
    testing.expect_value(t, len(data.chunks), 2)
}

@(test)
test_manager_clear :: proc(t: ^testing.T) {
    manager, _ := new(nuppu.Entity_Manager)
    defer nuppu.entity_manager_destroy(manager)

    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Door, 1) // first chunk = 2 slots
    nuppu.entity_manager_add_variant(manager, Frog, 6)

    a, a_ok := nuppu._entity_add(manager, Door)
    b, b_ok := nuppu._entity_add(manager, Door)
    f, f_ok := nuppu._entity_add(manager, Frog)
    testing.expect(t, a_ok && b_ok && f_ok, "adds succeed")
    testing.expect_value(t, nuppu.parent_add(manager, b, a), true)

    data := &manager.variants[0]
    testing.expect_value(t, len(data.chunks), 2) // chunk 0 full, b in chunk 1
    testing.expect_value(t, data.top, 3)

    nuppu.entity_manager_clear(manager)

    // Variant registrations and chunk allocations survive; only entities reset.
    testing.expect_value(t, len(manager.variants), 2)
    testing.expect_value(t, len(data.chunks), 2)
    testing.expect_value(t, data.top, 1)
    testing.expect_value(t, data.partial, 0)
    testing.expect_value(t, data.chunks[0].occupied.live, 1) // sentinel only
    testing.expect_value(t, data.chunks[1].occupied.live, 0)
    // Padding bits (2..63) stay occupied so the scan can't yield them.
    testing.expect_value(
        t,
        data.chunks[0].occupied.words[0],
        ~nuppu.Bit_Mask64(0) &~ (nuppu.Bit_Mask64(1) << 1),
    )

    testing.expect(t, nuppu.entity_get(manager, a) == nil, "old handle is stale after clear")
    testing.expect(t, nuppu.entity_get(manager, f) == nil, "old handle is stale after clear")
    testing.expect_value(t, nuppu.entity_root(manager).first_child, nuppu.NIL_ENTITY_HANDLE)

    // Fresh adds reuse the freed index space from the start.
    c, c_ok := nuppu._entity_add(manager, Door)
    d, d_ok := nuppu._entity_add(manager, Door)
    testing.expect(t, c_ok && d_ok, "adds after clear succeed")
    testing.expect_value(t, c.handle.index, 1)
    testing.expect_value(t, d.handle.index, 2)

    // Iteration sees only the two fresh entities.
    it := nuppu.entity_iterator_init(manager, Door)
    count := 0
    for {
        _, _, ok := nuppu.entity_iterator_next(&it)
        if !ok { break }
        count += 1
    }
    testing.expect_value(t, count, 2)
}
