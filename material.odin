#+vet unused shadowing using-param style semicolon cast explicit-allocators

/*
TODO:

Guard material_to_handle with debug flag

*/

package nuppu

#assert(CONFIG.max_materials <= MATERIAL_INDEX_MASK, "CONFIG.max_materials must be <= MATERIAL_INDEX_MASK")

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "gpu"

_ :: log

MATERIAL_INDEX_MASK       :: (1 << 15) - 1
MATERIAL_EMBED_BIT        ::  1 << 15

MATERIAL_EMBED_DATA_BYTES :: 6

Material_Handle :: Handle(u16)
MATERIAL_NIL    :: Material_Handle{}

when !ODIN_DEBUG {
    #assert(size_of(Material_Handle) == size_of(u16))
}

#assert(size_of(GPU_Material_Instance) == 8)
GPU_Material_Instance :: struct #align(8) {
    handle     : u16, // raw index | embed flag
    user_data_1: u16,
    user_data_2: u32, // inline user data, or byte offset into the parameter buffer
}

Material_Library :: struct {
    material_buffer     : gpu.ptr,   // [CONFIG.max_materials]GPU_Material
    parameter_buffer    : gpu.Arena, // [CONFIG.material_param_bytes]u8 variable-size params

    material_to_pipeline: map[u16]typeid,
    material_types      : [dynamic]typeid, // indexed by material index (validation)
    top                 : int,

    allocator           : runtime.Allocator,
    is_init             : bool,
}


@(require_results)
material_register :: proc(data: ^$M, name: string = "", is_embed: bool = false, loc := #caller_location) -> (Material_Handle, bool) #optional_ok {
    return _material_register(&_state.material_library, data, name, is_embed, loc)
}

material_update :: proc(handle: Material_Handle, values: ^$M, loc := #caller_location) {
    _material_update(&_state.material_library, handle, values, loc)
}


_material_lib_init :: proc(lib: ^Material_Library, allocator := context.allocator) {
    if lib.is_init { return }
    lib.is_init = true
    lib.allocator = allocator

    lib.material_buffer, _ = gpu.malloc(
        u32(CONFIG.max_materials * size_of(GPU_Material_Instance)),
        u32(align_of(GPU_Material_Instance)), .Staging, "Material Buffer",
    )
    assert(lib.material_buffer.cpu != nil, "material_lib_init: failed to alloc material buffer")

    lib.parameter_buffer, _ = gpu.arena_init(CONFIG.material_param_bytes, 16, flags=.Staging)
    assert(lib.parameter_buffer.cpu != nil, "material_lib_init: failed to alloc parameter buffer")

    lib.material_to_pipeline = make(map[u16]typeid, 64, allocator = allocator)
    lib.material_types       = make([dynamic]typeid, 0, 64, allocator)
    lib.top = 1 // slot 0 is MATERIAL_NIL
}

_material_lib_deinit :: proc(lib: ^Material_Library) {
    gpu.release_ptr(&lib.material_buffer)
    gpu.release_ptr(&lib.parameter_buffer.ptr)
    delete(lib.material_to_pipeline)
    delete(lib.material_types)
    lib^ = {}
}

_material_lib_clear :: proc(lib: ^Material_Library) {
    lib.top = 1
    lib.parameter_buffer.offset = 0
}

_material_register :: proc(lib: ^Material_Library, data: ^$M, name: string, is_embed: bool, loc := #caller_location) -> (Material_Handle, bool) {
    assert(lib.is_init)

    if lib.top >= CONFIG.max_materials {
        log.error("material_register: material library is full", location = loc)
        return MATERIAL_NIL, false
    }

    raw := u16(lib.top)
    if is_embed {
        if size_of(M) > MATERIAL_EMBED_DATA_BYTES {
            log.error("material_register: embed data size is too large", location = loc)
            return MATERIAL_NIL, false
        }
        raw |= MATERIAL_EMBED_BIT
    }

    mat := &([^]GPU_Material_Instance)(rawptr(lib.material_buffer.cpu))[lib.top]
    mat.handle = raw
    mat.user_data_1 = 0
    mat.user_data_2 = 0

    size_t := size_of(M)
    if size_t <= MATERIAL_EMBED_DATA_BYTES && is_embed {
        intrinsics.mem_copy(&mat.user_data_1, rawptr(data), size_t)
    } else {
        view := gpu.arena_alloc_raw(&lib.parameter_buffer, uint(size_t), 1, 16)
        intrinsics.mem_zero(view.cpu, size_t)
        intrinsics.mem_copy(view.cpu, rawptr(data), size_t)
        mat.user_data_2 = view.byte_offset
    }

    lib.top += 1
    lib.material_to_pipeline[raw] = {}
    append(&lib.material_types, M)

    handle := Material_Handle { handle = raw }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
    }

    return handle, true
}

_material_update :: proc(lib: ^Material_Library, handle: Material_Handle, values: ^$M, loc := #caller_location) {
    assert(lib.is_init, loc = loc)
    assert(handle != MATERIAL_NIL, "material_update: invalid material handle", loc = loc)
    assert(_material_handle_unpack(handle) < u16(lib.top), "material_update: invalid material handle", loc = loc)
    assert(lib.material_types[_material_handle_unpack(handle)] == M, "material_update: params do not match material type", loc = loc)

    mat := &([^]GPU_Material_Instance)(rawptr(lib.material_buffer.cpu))[_material_handle_unpack(handle)]
    if (mat.handle & MATERIAL_EMBED_BIT) != 0 {
        if size_of(M) > MATERIAL_EMBED_DATA_BYTES {
            log.error("material_update: embed data size is too large", loc = loc)
            return
        }
        intrinsics.mem_copy(&mat.user_data_1, values, size_of(M))
    } else {
        params_ptr := rawptr(uintptr(lib.parameter_buffer.cpu) + uintptr(mat.user_data_2))
        intrinsics.mem_copy(params_ptr, values, size_of(M))
    }
}

_material_handle_unpack :: proc(handle: Material_Handle) -> u16 {
    return handle.handle & MATERIAL_INDEX_MASK
}
