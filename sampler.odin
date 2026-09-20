package nuppu

import "base:runtime"
import "gpu"

SAMPLER_HANDLE_RAW :: u16
Sampler_Handle :: distinct Handle(SAMPLER_HANDLE_RAW)
Sampler_Handle_Nil :: Sampler_Handle{}
SAMPLER_INDEX_MASK :: (1 << 16) - 1
#assert(MAX_SAMPLERS <= SAMPLER_INDEX_MASK, "MAX_SAMPLERS must fit a u16 handle")

Sampler_Library :: struct {
    table:   Resource_Table(gpu.Sampler),
    default: Sampler_Handle,

    __sampler_handles: [dynamic]Sampler_Handle, // debug-only, for leak reports
}

sampler_handle_unpack :: proc "contextless" (handle: Sampler_Handle) -> (idx: SAMPLER_HANDLE_RAW, ok: bool) #optional_ok {
    idx = handle.handle & SAMPLER_INDEX_MASK
    if idx == 0 || int(idx) >= MAX_SAMPLERS { return 0, false }
    return idx, true
}

NUPPU_sampler_library_init :: proc(lib: ^Sampler_Library, allocator := context.allocator) -> (err: runtime.Allocator_Error) {
    resource_table_init(&lib.table, MAX_SAMPLERS, allocator) or_return

    when ODIN_DEBUG {
        lib.__sampler_handles = make([dynamic]Sampler_Handle, 0, 64, context.allocator)
    }

    lib.default = sampler_create({
        mag_filter = .Nearest,
        min_filter = .Nearest,
        mip_filter = .Nearest,
        wrap_r     = .ClampToEdge,
        wrap_s     = .ClampToEdge,
        wrap_t     = .ClampToEdge,
    }, "default_sampler")

    return
}

NUPPU_sampler_library_deinit :: proc(lib: ^Sampler_Library) {
    it := bit_mask_array_iterator_init(&lib.table.occupied)
    for index in bit_mask_array_iterator_next(&it) {
        if index == 0 { continue } // sentinel
        gpu.sampler_deinit(&lib.table.items[index])
    }
    resource_table_destroy(&lib.table)

    when ODIN_DEBUG {
        delete(lib.__sampler_handles)
    }
    lib^ = {}
}

@(require_results)
sampler_create :: proc(desc: gpu.Sampler_Descriptor, name: string = "", loc := #caller_location) -> Sampler_Handle {
    lib := &_state.sampler_library
    index, ok := resource_table_acquire(&lib.table)
    assert(ok, "sampler_create: out of sampler slots, raise MAX_SAMPLERS")

    lib.table.items[index] = gpu.sampler_init(desc)

    handle := Sampler_Handle { handle = u16(index) }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
        append(&lib.__sampler_handles, handle)
    }
    return handle
}

@(require_results)
sampler_get :: proc(handle: Sampler_Handle) -> (^gpu.Sampler, bool) #optional_ok {
    index, ok := sampler_handle_unpack(handle)
    if !ok { return nil, false }
    return resource_table_get(&_state.sampler_library.table, index)
}

// Frees a user sampler. The engine's default sampler is ignored.
sampler_free :: proc(handle: Sampler_Handle) {
    lib := &_state.sampler_library
    if handle == lib.default { return }

    index, ok := sampler_handle_unpack(handle)
    if !ok { return }
    sampler, got := resource_table_get(&lib.table, index)
    if !got { return }

    gpu.sampler_deinit(sampler)
    resource_table_release(&lib.table, index)

    when ODIN_DEBUG {
        for h, i in lib.__sampler_handles {
            if h == handle {
                unordered_remove(&lib.__sampler_handles, i)
                break
            }
        }
    }
}

sampler_default :: proc "contextless" () -> Sampler_Handle {
    return _state.sampler_library.default
}
