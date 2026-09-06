package nuppu_gpu

import "base:runtime"
import "core:log"
import "core:mem"

Arena :: struct {
    using ptr: ptr,
    offset: uint,
}


// Linear bump arena that allocates staging buffer. Helps if multiple types of staging data is needed to be copied simultaneously.
arena_init :: proc(
    bytes: u32,
    #any_int alignment: u32 = 16,
    loc:                     = #caller_location,
    flags: Buffer_Flag      = .Staging,
) -> (Arena, bool) {
    arena: Arena

    if min_alignment := _min_alignment(flags); alignment < min_alignment {
        log.errorf("In malloc() passed in alignment %i is less than the minimum required for flags %v. Bump to %i", alignment, flags, min_alignment)
        return {}, false
    }

    capacity := runtime.align_forward(uint(bytes), uint(alignment))

    _ptr := _malloc(bytes, alignment, flags, "ARENA", loc)

    arena.ptr = {
        meta = Metadata {
            name = "ARENA",
            created_at = loc,
        },
        native = _ptr,
        cpu = _cpu_address(_ptr) if flags == .Staging else nil,
        gpu = _gpu_address(_ptr),
        flags = flags,
        alignment = alignment,
        total_capacity_bytes = u32(capacity),
        byte_offset = 0,
    }
    arena.offset = 0


    return arena, true
}

// Returns ptr with correct field values.
arena_alloc_raw :: proc(arena: ^Arena, el_size, el_count, align: uint, loc := #caller_location) -> ptr {
    // assert(_mapped(arena.ptr)) IF staging buffer
    alignment := max(u32(align), arena.ptr.alignment)
    if arena.ptr.cpu != nil && uintptr(arena.ptr.cpu) % uintptr(alignment) != uintptr(arena.ptr.gpu) % uintptr(alignment) {
        panic("Could not satisfy alignment requirements in GPU arena allocation.")
    }

    bytes := el_size * el_count
    assert(bytes >= 0 && alignment > 0)
    bytes_aligned := runtime.align_forward_uint(uint(bytes), uint(alignment))

    arena.offset = mem.align_forward_uint(arena.offset, uint(alignment))
    temp := arena.offset
    if arena.offset + bytes_aligned > uint(arena.total_capacity_bytes) {
        panic("Arena: out of space")
    }
    arena.offset += bytes_aligned

    view := sub_alloc(arena.ptr, u32(temp), u32(bytes_aligned))

    return view
}

// Helper for arena alloc
arena_alloc :: proc(arena: ^Arena, $T: typeid, el_count: uint = 1, loc := #caller_location) -> ptr {
    temp := arena_alloc_raw(arena, size_of(T), el_count, align_of(T), loc)

    // NOTE add typed return?
    // []T from aligned offset before bytes are added in
    // s := slice.from_ptr((^T)(temp.cpu), int(el_count))

    return temp
}

sub_alloc :: proc(parent: ptr, offset, length: u32) -> ptr {
    assert(offset + length <= parent.total_capacity_bytes)
    assert(length <= parent.total_capacity_bytes - offset)

    result := parent
    result.cpu                  = rawptr(uintptr(parent.cpu) + uintptr(offset))
    result.gpu                  = rawptr(uintptr(parent.gpu) + uintptr(offset))
    result.byte_offset          = parent.byte_offset + offset
    result.total_capacity_bytes = length

    return result
}
