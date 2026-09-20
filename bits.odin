package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"

Bit_Mask64 :: distinct u64

MASK_BITS :: 64

mask64_first_zero :: proc "contextless" (mask: Bit_Mask64) -> (int, bool) {
    if mask == ~Bit_Mask64(0) { return 0, false }
    return int(intrinsics.count_trailing_zeros(~mask)), true
}

mask64_set_one :: proc "contextless" (mask: ^Bit_Mask64, #any_int index: int) {
    assert_contextless(0 <= index && index < MASK_BITS)
    mask^ |= Bit_Mask64(1) << uint(index)
}

mask64_clear_one :: proc "contextless" (mask: ^Bit_Mask64, #any_int index: int) {
    assert_contextless(0 <= index && index < MASK_BITS)
    mask^ &~= Bit_Mask64(1) << uint(index)
}

mask64_test :: proc "contextless" (mask: Bit_Mask64, #any_int index: int) -> bool {
    assert_contextless(0 <= index && index < MASK_BITS)
    return mask & (Bit_Mask64(1) << uint(index)) != 0
}

// ============================================================================
// Bit_Mask_Array
//
// A flat, owned array of Bit_Mask64 words. Bits in [0, bit_count) are usable;
// the tail bits of the last word are kept set so a free-bit scan never yields
// a padding slot. `free_hint` points at the first word that may still hold a
// zero.
// ============================================================================

Bit_Mask_Array :: struct {
    words:       [^]Bit_Mask64,
    word_count: int,
    bit_count:  int, // usable capacity; bits >= bit_count are padding (set)
    free_hint:  int, // first word that may contain a zero
    live:       int, // set bits within bit_count
    allocator:   runtime.Allocator,
}

@(require_results)
bit_mask_array_init :: proc(
    #any_int bit_count: int,
    alignment: int = mem.DEFAULT_ALIGNMENT,
    allocator := context.allocator,
) -> (arr: Bit_Mask_Array, err: runtime.Allocator_Error) #optional_allocator_error {
    assert(bit_count >= 0, "bit_mask_array_init: negative bit_count")

    word_count := (bit_count + MASK_BITS - 1) / MASK_BITS
    buf := runtime.make_aligned([]Bit_Mask64, word_count, alignment, allocator) or_return

    intrinsics.mem_zero(raw_data(buf), word_count * size_of(Bit_Mask64))

    arr = Bit_Mask_Array {
        words      = raw_data(buf),
        word_count = word_count,
        bit_count  = bit_count,
        free_hint  = 0,
        live       = 0,
        allocator  = allocator,
    }

    // Mark the unused high bits of the last word occupied.
    if used := bit_count % MASK_BITS; used != 0 {
        arr.words[word_count - 1] |= ~Bit_Mask64(0) << uint(used)
    }

    return arr, nil
}

bit_mask_array_destroy :: proc(arr: ^Bit_Mask_Array) {
    if arr.words == nil { return }
    mem.delete_slice(arr.words[:arr.word_count], arr.allocator)
    arr^ = {}
}

bit_mask_array_set :: proc "contextless" (arr: ^Bit_Mask_Array, #any_int index: int) {
    assert_contextless(index >= 0 && index < arr.bit_count, "bit_mask_array_set: out of range")

    w := index / MASK_BITS
    b := index % MASK_BITS
    if !mask64_test(arr.words[w], b) {
        mask64_set_one(&arr.words[w], b)
        arr.live += 1
    }
}

bit_mask_array_clear :: proc "contextless" (arr: ^Bit_Mask_Array, #any_int index: int) {
    assert_contextless(index >= 0 && index < arr.bit_count, "bit_mask_array_clear: out of range")

    w := index / MASK_BITS
    b := index % MASK_BITS
    if mask64_test(arr.words[w], b) {
        mask64_clear_one(&arr.words[w], b)
        arr.live -= 1
        if w < arr.free_hint {
            arr.free_hint = w
        }
    }
}

// Clears every usable bit. Padding bits are re-marked so free-bit scans stay
// valid. Does not resize.
bit_mask_array_clear_all :: proc "contextless" (arr: ^Bit_Mask_Array) {
    if arr.words == nil { return }

    intrinsics.mem_zero(raw_data(arr.words[:arr.word_count]), arr.word_count * size_of(Bit_Mask64))
    arr.live      = 0
    arr.free_hint = 0

    if used := arr.bit_count % MASK_BITS; used != 0 {
        arr.words[arr.word_count - 1] |= ~Bit_Mask64(0) << uint(used)
    }
}

bit_mask_array_test :: proc "contextless" (arr: ^Bit_Mask_Array, #any_int index: int) -> bool {
    return mask64_test(arr.words[index / MASK_BITS], index % MASK_BITS)
}

// First free bit, scanning from `free_hint`. Does not mutate.
bit_mask_array_first_zero :: proc "contextless" (arr: ^Bit_Mask_Array) -> (index: int, ok: bool) {
    for w := arr.free_hint; w < arr.word_count; w += 1 {
        if b, found := mask64_first_zero(arr.words[w]); found {
            return w * MASK_BITS + b, true
        }
    }
    return 0, false
}

// First free bit, marked occupied. Returns false when the array is full.
bit_mask_array_flip_first_zero :: proc "contextless" (arr: ^Bit_Mask_Array) -> (index: int, ok: bool) #optional_ok {
    for arr.free_hint < arr.word_count {
        w := arr.free_hint
        b, found := mask64_first_zero(arr.words[w])
        if !found {
            arr.free_hint += 1
            continue
        }
        mask64_set_one(&arr.words[w], b)
        arr.live += 1
        return w * MASK_BITS + b, true
    }
    return 0, false
}

// Iterates set bits in ascending index order.
Bit_Mask_Array_Iterator :: struct {
    array: ^Bit_Mask_Array,
    word:  int,
    bits:  Bit_Mask64,
}

bit_mask_array_iterator_init :: proc "contextless" (arr: ^Bit_Mask_Array) -> Bit_Mask_Array_Iterator {
    return Bit_Mask_Array_Iterator {
        array = arr,
    }
}

bit_mask_array_iterator_next :: proc "contextless" (it: ^Bit_Mask_Array_Iterator) -> (index: int, ok: bool) {
    for {
        if it.bits != 0 {
            b := int(intrinsics.count_trailing_zeros(it.bits))
            it.bits &~= Bit_Mask64(1) << uint(b)

            index := (it.word - 1) * MASK_BITS + b
            if index >= it.array.bit_count {
                return 0, false // ignore tail padding bits
            }
            return index, true
        }

        if it.word >= it.array.word_count {
            return 0, false
        }
        it.bits = it.array.words[it.word]
        it.word += 1
    }
}


// Yields maximal runs of bits set in `a` but not in `b`, as [start, start+length).
// Requires equal word counts; padding bits are zero in the diff by construction.
bit_mask_array_diff_ranges :: proc(a, b: ^Bit_Mask_Array, allocator := context.temp_allocator) -> []Range {
    assert(a.word_count == b.word_count, "diff_ranges: word count mismatch")

    ranges := make([dynamic]Range, 0, 8, allocator = allocator)
    current := Range{ start = -1, length = 0 }

    for w in 0 ..< a.word_count {
        diff := a.words[w] &~ b.words[w]
        base := w * MASK_BITS

        for diff != 0 {
            start := int(intrinsics.count_trailing_zeros(u64(diff)))
            ones  := int(intrinsics.count_trailing_ones(u64(diff) >> uint(start)))
            g_start := base + start

            if current.start >= 0 && g_start == current.start + int(current.length) {
                current.length += uint(ones)        // continues (even across a word)
            } else {
                if current.start >= 0 { append(&ranges, current) }
                current = { start = g_start, length = uint(ones) }
            }

            end := start + ones
            if end >= MASK_BITS { diff = 0 }
            else { diff &~= (Bit_Mask64(1) << uint(end)) - 1 }
        }
    }

    if current.start >= 0 { append(&ranges, current) }
    return ranges[:]
}