/*
TODO:
Guard material_to_handle with debug flag
*/

package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:log"
import "gpu"

Material_Handle           :: distinct u16

MATERIAL_INDEX_MASK       :: (1 << 14) - 1
MATERIAL_EMBED_BIT        ::  1 << 14
MATERIAL_BASE_BIT         ::  1 << 15

MAX_MATERIALS             :: 512 // Bump if need more
#assert(MAX_MATERIALS <= MATERIAL_INDEX_MASK)
MATERIAL_PARAM_BYTES      :: 1 * mem.Megabyte

MATERIAL_EMBED_DATA_BYTES :: 6


#assert(size_of(GPU_Material) == 8)
GPU_Material :: struct #align(8) {
    handle     : Material_Handle, // this
    user_data_1: u16,
    user_data_2: u32, // user_data or buffer byte offset
}

Material_Library :: struct {
    material_buffer     : gpu.ptr,   // [MAX_MATERIALS]GPU_Material
    parameter_buffer    : gpu.Arena, // [MATERIAL_PARAM_BYTES]u8 variable-size params
    
    material_to_pipeline: map[Material_Handle]typeid,
    count               : int,
    material_to_handle  : map[typeid][dynamic]Material_Handle, // Only for validation, on keep in debug

    allocator           : runtime.Allocator,
    is_init             : bool,
}

register_material :: proc(data: $M, is_embed: bool = false) -> (Material_Handle, bool) {
    data := data
    return _register_material(_state.material_library, &data, is_embed, false)
}

_init_material_library :: proc(lib: ^Material_Library, allocator := context.allocator) {
    if lib.is_init { return }
    lib.is_init = true
    lib.allocator = allocator

    lib.material_buffer, _ = gpu.malloc(
        u32(MAX_MATERIALS * size_of(GPU_Material)),
        u32(align_of(GPU_Material)), .Staging, "Material Buffer",
    )
    assert(lib.material_buffer.cpu != nil, "init_material_library: failed to alloc material buffer")

    lib.parameter_buffer, _ = gpu.arena_init(MATERIAL_PARAM_BYTES, 16, flags=.Staging)
    assert(lib.parameter_buffer.cpu != nil, "init_material_library: failed to alloc parameter buffer")

    lib.material_to_pipeline = make(map[Material_Handle]typeid, 64, allocator = allocator)
    lib.material_to_handle   = make(map[typeid][dynamic]Material_Handle, 64, allocator = allocator)
    lib.count = 1
}

_register_material :: proc(lib: ^Material_Library, data: ^$M, is_embed, is_base: bool) -> (Material_Handle, bool) {
    assert(lib.is_init)

    if lib.count >= MAX_MATERIALS {
        log.error("add_material: material library is full")
        return 0, false
    }

    if M not_in lib.material_to_handle {
        lib.material_to_handle[M] = make([dynamic]Material_Handle, allocator = lib.allocator)
    }

    handle := Material_Handle(lib.count)
    
    if is_embed {
        assert(size_of(M) <= MATERIAL_EMBED_DATA_BYTES, "register_material: embed data size is too large")
        handle |= MATERIAL_EMBED_BIT
    }
    if is_base {
        handle |= MATERIAL_BASE_BIT
    }
    
    mat := &([^]GPU_Material)(rawptr(lib.material_buffer.cpu))[lib.count]
    mat.handle = handle

    size_t := size_of(M)
    if size_t <= MATERIAL_EMBED_DATA_BYTES && is_embed {
        intrinsics.mem_copy(&mat.user_data_1, rawptr(data), size_t)
    } else {
        view := gpu.arena_alloc_raw(&lib.parameter_buffer, uint(size_t), 1, 16)
        intrinsics.mem_zero(view.cpu, size_t)
        intrinsics.mem_copy(view.cpu, rawptr(data), size_t)
        mat.user_data_2 = view.byte_offset
    }

    lib.count += 1
    lib.material_to_pipeline[handle] = {}
    
    list := &lib.material_to_handle[M]
    append(list, handle)

    return handle, true
}

// Rewrites an existing material instance's params in place.
_update_material :: proc(lib: ^Material_Library, handle: Material_Handle, values: ^$M) {
    assert(lib.is_init)
    assert(handle != 0, "update_material: invalid material handle")
    assert(_unpack_handle(handle) < Material_Handle(lib.count), "update_material: invalid material handle")
    assert(M in lib.material_to_handle)
    
    found: bool
    for h in lib.material_to_handle[M] {
        if h == handle {
            found = true
            break
        }
    }
    assert(found, "update_material: material isnt registered with this handle")

    mat := &([^]GPU_Material)(rawptr(lib.material_buffer.cpu))[_unpack_handle(handle)]
    if (mat.handle & MATERIAL_EMBED_BIT) != 0 {
        assert(size_of(M) <= MATERIAL_EMBED_DATA_BYTES, "update_material: embed data size is too large")
        intrinsics.mem_copy(&mat.user_data_1, values, size_of(M))
    } else {
        params_ptr := rawptr(uintptr(lib.parameter_buffer.cpu) + uintptr(mat.user_data_2))
        intrinsics.mem_copy(params_ptr, values, size_of(M))
    }
}

_unpack_handle :: proc(handle: Material_Handle) -> Material_Handle {
    return handle & MATERIAL_INDEX_MASK
}
