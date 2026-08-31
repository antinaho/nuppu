package bit_array

import "base:intrinsics"

// Bit bucket:
// https://jakubtomsu.github.io/posts/bit_pools/

Handle :: distinct u32
// 24 bits - index
// 8 bits  - generation

NIL_HANDLE :: Handle {}

Bit_Array :: struct($T: typeid, $N: int) 
    where N > 0 &&
    N < (1 << 23) - 1 &&
    intrinsics.type_has_field (T, "handle"),
	intrinsics.type_field_type(T, "handle") == Handle
{
    items:  [N]T,
    bucket: Bit_Bucket(N),
    used_count: u32,
}

Bit_Bucket :: struct($N: int)
    where N > 0 &&
    N % 64 == 0
{
    l0: [N / 64]u64,
    l1: [(N + 4095) / 4096]u64,
}

pack_handle :: proc "contextless" (
    index: u32,
    generation: u8,
) -> Handle {
    handle := 
        (index           << 8 ) |
        (u32(generation) << 0 )

    return Handle(handle)
}

unpack_handle :: proc "contextless" (handle: Handle) -> (index: u32, generation: u8) {
    index      = u32((handle >> 8)   & 0xFFFFFF)
    generation = u8 ((handle >> 0)   & 0xFF)

    return
}

@(require_results)
add :: proc "contextless" (
    handle_map: ^Bit_Array($T, $N),
    item: T
) -> (Handle, bool) #optional_ok {

    // Initialize the zero-value sentinel
    if handle_map.used_count == 0 {
        handle_map.items[0] = {}
        handle_map.used_count += 1
        set_1(&handle_map.bucket, 0)
    }

    // Find a free slot
    free_slot := find_0(handle_map.bucket)
    if free_slot == -1 {
        return NIL_HANDLE, false
    }

    ptr := &handle_map.items[free_slot]
    _, prev_gen := unpack_handle(ptr.handle)

    ptr^ = item

    ptr.handle = pack_handle(u32(free_slot), prev_gen + 1)
    set_1(&handle_map.bucket, free_slot)
    handle_map.used_count += 1

    return ptr.handle, true
}

@(require_results)
get :: proc "contextless" (
    handle_map: ^Bit_Array($T, $N),
    handle: Handle,
) -> (^T, bool) #optional_ok {
    if handle == NIL_HANDLE {
        return nil, false
    }

    req_index, req_gen := unpack_handle(handle)

    if req_index >= u32(N) {
        return nil, false
    }

    // Bucket bit must be set — otherwise the slot is empty and
    // items[index].handle holds stale data from a previous allocation.
    if !is_1(handle_map.bucket, u64(req_index)) {
        return nil, false
    }

    _, cur_gen := unpack_handle(handle_map.items[req_index].handle)
    if cur_gen != req_gen {
        return nil, false
    }

    return &handle_map.items[req_index], true
}

remove :: proc "contextless" (
    handle_map: ^Bit_Array($T, $N),
    handle: Handle,
) -> bool {
    if handle == NIL_HANDLE {
        return false
    }

    req_index, req_gen := unpack_handle(handle)

    if req_index >= u32(N) {
        return false
    }

    if !is_1(handle_map.bucket, u64(req_index)) {
        return false
    }

    _, cur_gen := unpack_handle(handle_map.items[req_index].handle)
    if cur_gen != req_gen {
        return false
    }

    set_0(&handle_map.bucket, u64(req_index))
    handle_map.used_count -= 1

    return true
}

set_1 :: proc "contextless" (bp: ^Bit_Bucket($N), #any_int index: u64) {
    assert_contextless(index >= 0 && index < u64(N))
    
    l0_index := index / 64
    l0_slot := index % 64

    l1_index := l0_index / 64
    l1_slot := l0_index % 64

    bucket := bp.l0[l0_index]
    bucket |= 1 << l0_slot

    if bucket == max(u64) { // if full
        bp.l1[l1_index] |= 1 << l1_slot
    }

    bp.l0[l0_index] = bucket
}

set_0 :: proc "contextless" (bp: ^Bit_Bucket($N), #any_int index: u64) {
    assert_contextless(index >= 0 && index < u64(N))

    l0_index := index / 64
    l0_slot := index % 64

    l1_index := l0_index / 64
    l1_slot := l0_index % 64

    // Always clear L0, it must be non-empty after deleting from L1
    bp.l1[l1_index] &= ~(1 << l1_slot)
    bp.l0[l0_index] &= ~(1 << l0_slot)
}

find_0 :: proc "contextless" (bucket: Bit_Bucket($N)) -> (index: int) {
    l0_index := -1

    // Find suitable L0 block by searching L1
    for used, i in bucket.l1 {
        l1_slot := int(intrinsics.count_trailing_zeros(~used))
        if l1_slot != 64 {
            l0_index = 64 * i + l1_slot
            break
        }
    }

    if l0_index == -1 || l0_index >= (N / 64) {
        return -1 // Pool is full
    }

    // Find the actual slot within the L0 block
    l0_slot := int(intrinsics.count_trailing_zeros(~bucket.l0[l0_index]))
    if l0_slot != 64 {
        return l0_index * 64 + l0_slot
    }

    return -1 // Pool is full
}

is_1 :: proc "contextless" (bucket: Bit_Bucket($N), #any_int index: u64) -> bool {
    assert_contextless(index >= 0 && index < u64(N))
    l0_index := index / 64
    l0_slot  := index % 64
    return (bucket.l0[l0_index] & (u64(1) << l0_slot)) != 0
}

Bit_Handle_Map_Iterator :: struct($T: typeid, $N: int) {
    array:  ^Bit_Array(T, N),
    cursor: int,  // next item index to scan (>= 1; never0)
}

iterator_init :: proc "contextless" (
    array: ^Bit_Array($T, $N),
) -> Bit_Handle_Map_Iterator(T, N) {
    return Bit_Handle_Map_Iterator(T, N) {
        array  = array,
        cursor = 1,  // skip sentinel at slot 0
    }
}

@(require_results)
iterator_next :: proc "contextless" (
    it: ^Bit_Handle_Map_Iterator($T, $N),
) -> (item: ^T, ok: bool) {
    array := it.array

    for it.cursor < N {
        l0_index := it.cursor / 64
        l0_slot  := it.cursor % 64

        // L1 fast-skip: if this L0 block is fully used, every slot is occupied.
        // Skip the L0 read + count_trailing_zeros entirely.
        l1_index := l0_index / 64
        l1_slot  := l0_index % 64
        is_full  := (array.bucket.l1[l1_index] & (u64(1) << u64(l1_slot))) != 0

        if is_full {
            item_index := it.cursor
            it.cursor += 1
            return &array.items[item_index], true
        }

        l0_block := array.bucket.l0[l0_index]
        if l0_slot > 0 {
            l0_block &= ~((u64(1) << u64(l0_slot)) - 1)
        }

        if l0_block != 0 {
            bit        := int(intrinsics.count_trailing_zeros(l0_block))
            item_index := l0_index * 64 + bit
            it.cursor  = item_index + 1
            return &array.items[item_index], true
        }

        // No bits in this L0 word — skip to the start of the next one
        it.cursor = (l0_index + 1) * 64
    }

    return nil, false
}