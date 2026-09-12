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

Material_Handle           :: distinct u16

MATERIAL_NIL              :: Material_Handle(0)
MATERIAL_INDEX_MASK       :: (1 << 15) - 1
MATERIAL_EMBED_BIT        ::  1 << 15

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
    material_types      : [dynamic]typeid, // indexed by material handle (validation)
    count               : int,

    allocator           : runtime.Allocator,
    is_init             : bool,
}


@(require_results)
material_register :: proc(data: ^$M, is_embed: bool = false, loc := #caller_location) -> (Material_Handle, bool) #optional_ok {
    return _material_register(&_state.material_library, data, is_embed, loc)
}

material_update :: proc(handle: Material_Handle, values: ^$M, loc := #caller_location) {
    _material_update(&_state.material_library, handle, values, loc)
}


_material_lib_init :: proc(lib: ^Material_Library, allocator := context.allocator) {
    if lib.is_init { return }
    lib.is_init = true
    lib.allocator = allocator

    lib.material_buffer, _ = gpu.malloc(
        u32(CONFIG.max_materials * size_of(GPU_Material)),
        u32(align_of(GPU_Material)), .Staging, "Material Buffer",
    )
    assert(lib.material_buffer.cpu != nil, "init_material_library: failed to alloc material buffer")

    lib.parameter_buffer, _ = gpu.arena_init(CONFIG.material_param_bytes, 16, flags=.Staging)
    assert(lib.parameter_buffer.cpu != nil, "init_material_library: failed to alloc parameter buffer")

    lib.material_to_pipeline = make(map[Material_Handle]typeid, 64, allocator = allocator)
    lib.material_types       = make([dynamic]typeid, 0, 64, allocator)
    lib.count = 1
}

_material_lib_deinit :: proc(lib: ^Material_Library) {
    gpu.release_ptr(&lib.material_buffer)
    gpu.release_ptr(&lib.parameter_buffer.ptr)
    delete(lib.material_to_pipeline)
    delete(lib.material_types)
    lib^ = {}
}

_material_register :: proc(lib: ^Material_Library, data: ^$M, is_embed: bool, loc := #caller_location) -> (Material_Handle, bool) {
    assert(lib.is_init)

    if lib.count >= CONFIG.max_materials {
        log.error("add_material: material library is full", location = loc)
        return 0, false
    }

    handle := Material_Handle(lib.count)
    
    if is_embed {
        if size_of(M) > MATERIAL_EMBED_DATA_BYTES {
            log.error("register_material: embed data size is too large", location = loc)
            return MATERIAL_NIL, false
        }
        handle |= MATERIAL_EMBED_BIT
    }
    
    mat := &([^]GPU_Material)(rawptr(lib.material_buffer.cpu))[lib.count]
    mat.handle = handle
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

    lib.count += 1
    lib.material_to_pipeline[handle] = {}
    append(&lib.material_types, M)

    return handle, true
}

_material_update :: proc(lib: ^Material_Library, handle: Material_Handle, values: ^$M, loc := #caller_location) {
    assert(lib.is_init, loc = loc)
    assert(handle != MATERIAL_NIL, "update_material: invalid material handle", loc = loc)
    assert(_material_handle_unpack(handle) < Material_Handle(lib.count), "update_material: invalid material handle", loc = loc)
    assert(lib.material_types[_material_handle_unpack(handle)] == M, "update_material: params do not match material type", loc = loc)

    mat := &([^]GPU_Material)(rawptr(lib.material_buffer.cpu))[_material_handle_unpack(handle)]
    if (mat.handle & MATERIAL_EMBED_BIT) != 0 {
        if size_of(M) > MATERIAL_EMBED_DATA_BYTES {
            log.error("update_material: embed data size is too large", loc = loc)
            return
        }
        intrinsics.mem_copy(&mat.user_data_1, values, size_of(M))
    } else {
        params_ptr := rawptr(uintptr(lib.parameter_buffer.cpu) + uintptr(mat.user_data_2))
        intrinsics.mem_copy(params_ptr, values, size_of(M))
    }
}

_material_handle_unpack :: proc(handle: Material_Handle) -> Material_Handle {
    return handle & MATERIAL_INDEX_MASK
}
