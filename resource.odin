package nuppu

import "base:runtime"

// Shared slot table for engine resources: a dense, handle-indexed array plus an
// occupancy bitmap. Slot 0 is always reserved as a nil sentinel, so index 0
// round-trips to a zero handle. Release only frees the slot; anything the item
// owns (native handles, dynamic buffers) is the owning library's job.
Resource_Table :: struct($T: typeid) {
    items:     []T,
    occupied:  Bit_Mask_Array,
    allocator: runtime.Allocator,
}

@(require_results)
resource_table_init :: proc(
    table: ^Resource_Table($T),
    #any_int capacity: int,
    allocator := context.allocator,
) -> (err: runtime.Allocator_Error) {
    assert(capacity > 0, "resource_table_init: capacity must be > 0")
    table.allocator = allocator
    table.occupied  = bit_mask_array_init(capacity, allocator = allocator) or_return
    table.items     = make([]T, len = capacity, allocator = allocator) or_return
    bit_mask_array_flip_first_zero(&table.occupied) // reserve slot 0
    return
}

resource_table_acquire :: proc(table: ^Resource_Table($T)) -> (index: int, ok: bool) #optional_ok {
    return bit_mask_array_flip_first_zero(&table.occupied)
}

resource_table_get :: proc(table: ^Resource_Table($T), #any_int index: int) -> (item: ^T, ok: bool) #optional_ok {
    if index <= 0 || index >= table.occupied.bit_count { return nil, false }
    if !bit_mask_array_test(&table.occupied, index) { return nil, false }
    return &table.items[index], true
}

resource_table_release :: proc(table: ^Resource_Table($T), #any_int index: int) {
    if index <= 0 || index >= table.occupied.bit_count { return }
    bit_mask_array_clear(&table.occupied, index)
}

resource_table_destroy :: proc(table: ^Resource_Table($T)) {
    bit_mask_array_destroy(&table.occupied)
    if table.items != nil {
        delete(table.items, table.allocator)
    }
    table^ = {}
}
