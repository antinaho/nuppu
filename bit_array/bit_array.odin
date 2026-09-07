package bit_array

import "base:intrinsics"
import "core:container/handle_map"

// https://gist.github.com/gingerBill/7282ff54744838c52cc80c559f697051
// https://jakubtomsu.github.io/posts/bit_pools/

Handle :: distinct u32
// 24 bits - index
// 8 bits  - generation

NIL_HANDLE :: Handle {}
//
Bit_Array :: struct($T: typeid, $N: u64, $H: typeid)
    where N > 0 &&
          N < (1 << 23) &&
          intrinsics.type_has_field (T, "handle") &&
          (
              intrinsics.type_field_type(T, "handle") == Handle ||
              intrinsics.type_field_type(T, "handle") == H
          ) &&
          intrinsics.type_has_field (H, "handle") &&
          intrinsics.type_field_type(H, "handle") == Handle
{
    items:  [N]T,
    bucket: Bit_Bucket(N),
    is_init: bool,
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

unpack_handle :: proc "contextless" (handle: $T/Handle) -> (index: u32, generation: u8) {
    index      = u32((handle >> 8)   & 0xFFFFFF)
    generation = u8 ((handle >> 0)   & 0xFF)

    return
}

// Peel the raw Handle out of a slot's `handle` field, which is either
// exactly `Handle` (raw) or the `H` wrapper (one extra `.handle` indirection).
slot_raw :: proc "contextless" (item: ^$T) -> Handle {
    when intrinsics.type_field_type(T, "handle") == Handle {
        return item.handle
    } else {
        return item.handle.handle
    }
}

init :: proc "contextless" (array: ^Bit_Array($T, $N, $H)) {
    if array.is_init { return }

    // Insert sentinal value at slot 0
    array.items[0] = {}
    set_1(&array.bucket, 0)
    
    array.is_init = true
}

@(require_results)
add :: proc "contextless" (
    handle_map: ^Bit_Array($T, $N, $H),
    item      : T
) -> (H, bool) #optional_ok {
    assert_contextless(handle_map.is_init)
    
    free_slot := find_0(handle_map.bucket)
    if free_slot == -1 {
        return H{ handle = NIL_HANDLE }, false
    }

    ptr := &handle_map.items[free_slot]

    prev_raw: Handle
    when intrinsics.type_field_type(T, "handle") == Handle {
        prev_raw = ptr.handle
    } else {
        prev_raw = ptr.handle.handle
    }
    _, prev_gen := unpack_handle(prev_raw)

    ptr^ = item

    raw := pack_handle(u32(free_slot), prev_gen + 1)
    when intrinsics.type_field_type(T, "handle") == Handle {
        ptr.handle = raw
    } else {
        ptr.handle = H{ handle = raw }
    }
    set_1(&handle_map.bucket, free_slot)

    return H{ handle = raw }, true
}

@(require_results)
get :: proc "contextless" (
    handle_map: ^Bit_Array($T, $N, $H),
    handle: H,
) -> (^T, bool) #optional_ok {
    assert_contextless(handle_map.is_init)
    if handle.handle == NIL_HANDLE {
        return nil, false
    }

    req_index, req_gen := unpack_handle(handle.handle)

    if req_index >= u32(N) {
        return nil, false
    }

    // Bucket bit must be set — otherwise the slot is empty and
    // items[index].handle holds stale data from a previous allocation.
    if !is_1(handle_map.bucket, u64(req_index)) {
        return nil, false
    }

    _, cur_gen := unpack_handle(slot_raw(&handle_map.items[req_index]))
    if cur_gen != req_gen {
        return nil, false
    }

    return &handle_map.items[req_index], true
}

remove :: proc "contextless" (
    handle_map: ^Bit_Array($T, $N, $H),
    handle: H,
) -> bool {
    assert_contextless(handle_map.is_init)
    if handle.handle == NIL_HANDLE {
        return false
    }

    req_index, req_gen := unpack_handle(handle.handle)

    if req_index >= u32(N) {
        return false
    }

    if !is_1(handle_map.bucket, u64(req_index)) {
        return false
    }

    _, cur_gen := unpack_handle(slot_raw(&handle_map.items[req_index]))
    if cur_gen != req_gen {
        return false
    }

    set_0(&handle_map.bucket, u64(req_index))

    return true
}

Bit_Handle_Map_Iterator :: struct($T: typeid, $N: u64, $H: typeid) {
    array:  ^Bit_Array(T, N, H),
    cursor: u64,
}

iterator_init :: proc "contextless" (
    array: ^Bit_Array($T, $N, $H),
) -> Bit_Handle_Map_Iterator(T, N, H) {
    assert_contextless(array.is_init)
    return Bit_Handle_Map_Iterator(T, N, H) {
        array  = array,
        cursor = 1,  // skip sentinel at slot 0
    }
}

@(require_results)
iterator_next :: proc "contextless" (
    it: ^Bit_Handle_Map_Iterator($T, $N, $H),
) -> (item: ^T, ok: bool) {
    array := it.array

    for it.cursor < N {
        defer it.cursor += 1
        if is_1(array.bucket, it.cursor) {
            return &array.items[it.cursor], true
        }
    }

    return nil, false
}

//

Bit_Bucket :: struct($N: u64)
    where N > 0 &&
          N % 64 == 0
{
    l0: [N / 64]u64,
    l1: [(N + 4095) / 4096]u64,
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

    if l0_index == -1 || u64(l0_index) >= (N / 64) {
        return -1 // Pool is full
    }

    // Find the actual slot within the L0 block
    l0_slot := int(intrinsics.count_trailing_zeros(~bucket.l0[l0_index]))
    if l0_slot != 64 {
        return l0_index * 64 + l0_slot
    }

    return -1 // Pool is full
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

is_1 :: proc "contextless" (bucket: Bit_Bucket($N), #any_int index: u64) -> bool {
    assert_contextless(index >= 0 && index < u64(N))
    l0_index := index / 64
    l0_slot  := index % 64
    return (bucket.l0[l0_index] & (1 << l0_slot)) != 0
}