package nuppu_gpu

import "base:runtime"
import "core:log"

Arena :: struct {
    using ptr: ptr,
    offset: uint,
}

arena_init :: proc(
    #any_int bytes    : uint,
    #any_int alignment: uint = 16,
    usage             : Buffer_Usage = .Staging,
    loc               := #caller_location,
) -> (Arena, bool) {
    arena: Arena

    if min_alignment := _min_alignment(usage); alignment < min_alignment {
        log.errorf("In arena_init: passed in alignment (%i) is less than the minimum required for usage (%v). Bump to at least (%i)", alignment, usage, min_alignment, location = loc)
        return {}, false
    }

    capacity := runtime.align_forward(bytes, alignment)

    _ptr := _malloc(bytes, alignment, usage, "Arena", loc)

    arena.ptr = {
        meta = Metadata {
            name = "ARENA",
            created_at = loc,
        },
        native = _ptr,
        cpu = _cpu_address(_ptr) if usage == .Staging else nil,
        gpu = _gpu_address(_ptr),
        flags = usage,
        access = .Read,
        alignment = alignment,
        total_capacity_bytes = capacity,
        byte_offset = 0,
    }
    arena.offset = 0


    return arena, true
}

arena_alloc_raw :: proc(arena: ^Arena, el_size, el_count, alignment: uint, loc := #caller_location) -> ptr {

    if arena.ptr.cpu != nil && uintptr(arena.ptr.cpu) % uintptr(alignment) != uintptr(arena.ptr.gpu) % uintptr(alignment) {
        log.panicf("In arena_alloc_raw: Could not satisfy alignment requirements with existing alignment (%v) and passed in alignment (%v)", arena.ptr.alignment, alignment, location = loc)
    }

    assert(alignment > 0)
    bytes := runtime.align_forward(el_size * el_count, alignment)

    arena.offset = runtime.align_forward(arena.offset, alignment)
    temp := arena.offset
    if arena.offset + bytes > uint(arena.total_capacity_bytes) {
        log.panicf("In arena_alloc_raw: Arena ran out of space while trying to allocate (%v) bytes, with remaining space being (%v)", bytes, arena.total_capacity_bytes - arena.offset, location = loc)
    }
    arena.offset += bytes

    view := sub_alloc(arena.ptr, temp, bytes)

    return view
}

// Helper for arena alloc
arena_alloc :: proc(arena: ^Arena, $T: typeid, #any_int el_count: uint = 1, loc := #caller_location) -> ptr {
    temp := arena_alloc_raw(arena, size_of(T), el_count, align_of(T), loc)

    // NOTE add typed return?
    // []T from aligned offset before bytes are added in
    // s := slice.from_ptr((^T)(temp.cpu), int(el_count))

    return temp
}

// Closes a transfer batch opened with `begin_commands`: flushes the recorded
// copies with a Transfer->All barrier, commits, and releases the staging buffer.
transfer_submit :: proc(staging: ^ptr) {
    barrier(.Transfer, .All)
    commit_commands()
    release_ptr(staging)
}

sub_alloc :: proc(parent: ptr, offset, length: uint) -> ptr {
    assert(offset + length <= parent.total_capacity_bytes)
    assert(length <= parent.total_capacity_bytes - offset)

    result := parent
    if parent.cpu != nil {
        result.cpu = rawptr(uintptr(parent.cpu) + uintptr(offset))
    }
    if parent.gpu != nil {
        result.gpu = rawptr(uintptr(parent.gpu) + uintptr(offset))
    }
    result.byte_offset          = parent.byte_offset + offset
    result.total_capacity_bytes = length

    return result
}
