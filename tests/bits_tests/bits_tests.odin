package bits_tests

import "base:runtime"
import "core:testing"
import nuppu "../../"

@(test)
test_mask64_first_zero :: proc(t: ^testing.T) {
    // Empty mask -> bit 0 is the first zero.
    {
        index, ok := nuppu.mask64_first_zero(nuppu.Bit_Mask64(0))
        testing.expect_value(t, ok, true)
        testing.expect_value(t, index, 0)
    }

    // Full mask -> no zero bit exists.
    {
        _, ok := nuppu.mask64_first_zero(~nuppu.Bit_Mask64(0))
        testing.expect_value(t, ok, false)
    }

    // Bits 0 and 1 occupied -> first free is bit 2.
    {
        index, ok := nuppu.mask64_first_zero(nuppu.Bit_Mask64(0b011))
        testing.expect_value(t, ok, true)
        testing.expect_value(t, index, 2)
    }

    // Only the top bit free.
    {
        mask := ~nuppu.Bit_Mask64(0) &~ (nuppu.Bit_Mask64(1) << 63)
        index, ok := nuppu.mask64_first_zero(mask)
        testing.expect_value(t, ok, true)
        testing.expect_value(t, index, 63)
    }
}

@(test)
test_mask64_set_clear_test :: proc(t: ^testing.T) {
    mask: nuppu.Bit_Mask64

    testing.expect_value(t, nuppu.mask64_test(mask, 5), false)

    nuppu.mask64_set_one(&mask, 5)
    testing.expect_value(t, nuppu.mask64_test(mask, 5), true)

    nuppu.mask64_clear_one(&mask, 5)
    testing.expect_value(t, nuppu.mask64_test(mask, 5), false)
    testing.expect_value(t, mask, nuppu.Bit_Mask64(0))
}

@(test)
test_bit_mask_array_tail_padding :: proc(t: ^testing.T) {
    arr, ok := nuppu.bit_mask_array_init(2)
    testing.expect_value(t, ok, nil)
    defer nuppu.bit_mask_array_destroy(&arr)

    testing.expect_value(t, arr.word_count, 1)
    testing.expect_value(t, arr.bit_count, 2)
    testing.expect_value(t, arr.live, 0)
    // Bits 2..63 are padding and must read as occupied.
    full := ~nuppu.Bit_Mask64(0)
    testing.expect_value(t, arr.words[0], full &~ nuppu.Bit_Mask64(0b11))

    i0, ok0 := nuppu.bit_mask_array_flip_first_zero(&arr)
    i1, ok1 := nuppu.bit_mask_array_flip_first_zero(&arr)
    _, ok2 := nuppu.bit_mask_array_flip_first_zero(&arr)
    testing.expect_value(t, ok0, true)
    testing.expect_value(t, i0, 0)
    testing.expect_value(t, ok1, true)
    testing.expect_value(t, i1, 1)
    testing.expect_value(t, ok2, false)
    testing.expect_value(t, arr.live, 2)
}

@(test)
test_bit_mask_array_clear_reuse :: proc(t: ^testing.T) {
    arr, ok := nuppu.bit_mask_array_init(128)
    testing.expect_value(t, ok, nil)
    defer nuppu.bit_mask_array_destroy(&arr)

    for i in 0 ..< 128 {
        got, taken := nuppu.bit_mask_array_flip_first_zero(&arr)
        testing.expect_value(t, taken, true)
        testing.expect_value(t, got, i)
    }
    _, full := nuppu.bit_mask_array_flip_first_zero(&arr)
    testing.expect_value(t, full, false)
    testing.expect_value(t, arr.live, 128)

    // Clearing a high word lowers free_hint so the hole is found first.
    nuppu.bit_mask_array_clear(&arr, 65)
    testing.expect_value(t, arr.live, 127)
    got, taken := nuppu.bit_mask_array_flip_first_zero(&arr)
    testing.expect_value(t, taken, true)
    testing.expect_value(t, got, 65)
    testing.expect_value(t, arr.live, 128)
}

@(test)
test_bit_mask_array_iterator :: proc(t: ^testing.T) {
    arr, ok := nuppu.bit_mask_array_init(130)
    testing.expect_value(t, ok, nil)
    defer nuppu.bit_mask_array_destroy(&arr)

    nuppu.bit_mask_array_set(&arr, 1)
    nuppu.bit_mask_array_set(&arr, 64)
    nuppu.bit_mask_array_set(&arr, 129)
    testing.expect_value(t, arr.live, 3)

    expected := [?]int{1, 64, 129}
    it := nuppu.bit_mask_array_iterator_init(&arr)
    n := 0
    for {
        index, more := nuppu.bit_mask_array_iterator_next(&it)
        if !more { break }
        testing.expect_value(t, index, expected[n])
        n += 1
    }
    testing.expect_value(t, n, len(expected))
}
