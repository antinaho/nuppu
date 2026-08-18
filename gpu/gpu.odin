#+vet explicit-allocators shadowing unused
package nuppu_gpu

import "base:runtime"
import "core:mem"

GPU_BACKEND_METAL :: "Metal"
GPU_BACKEND_WGPU :: "WGPU"
GPU_INVALID_BACKEND :: "Invalid"

when ODIN_OS == .JS {
    GPU_BACKEND :: GPU_BACKEND_WGPU
}
else when ODIN_OS == .Darwin {
    GPU_BACKEND :: GPU_BACKEND_METAL
}
else {
    GPU_BACKEND :: GPU_INVALID_BACKEND
    #panic("GPU not supported")
}
    
_state: ^State

MAX_RESOURCES :: 1 << 16
MAX_SHADERS :: 256
MAX_TEXTURES :: 256
MAX_PIPELINES :: 256

Resource :: struct {
    using _ : struct #raw_union {
        texture: Texture,
        shader: Shader,
        pipeline: Pipeline,
    },
    idx: u16,
    name: string,
}

Resource_Pool :: struct($N: int) {
    resources: [N]Resource,
    current: u16,
}

State :: struct #align(64) {
    using impl: _State,

    ctx: runtime.Context,
    is_init: bool,

    textures: Resource_Pool(MAX_TEXTURES),
    shaders: Resource_Pool(MAX_SHADERS),
    pipelines: Resource_Pool(MAX_PIPELINES),
}

init :: proc(state: ^State, native_window: rawptr) -> bool {
    if _state != nil {
        return true
    }

    _state = state
    _state.ctx = context

    return _init(native_window)
}

deinit :: proc() {
    if _state == nil {
        return
    }

    _deinit()
    
    _state = nil
}

is_init :: proc() -> bool {
    return _state.is_init
}

begin_frame :: proc() {
    _begin_frame()
}

end_frame :: proc() {
    _end_frame()
}

acquire_next_swapchain :: proc() -> Texture {
    return _acquire_next_swapchain()
}

begin_render_pass :: proc(color_attachment: Color_Attachment) {
    _begin_render_pass(color_attachment)
}

end_render_pass :: proc() {
    _end_render_pass()
}

present :: proc(texture: Texture) {
    _present(texture)
}

resize_swapchain :: proc(width, height: i32) -> bool {
    return _resize_swapchain(width, height)
}

Pixel_Format :: enum u8 {
    BGRA8Unorm,
    Depth32Float,
}

Texture_Descriptor :: struct {
    dimensions: [2]u32,
    format: Pixel_Format,
}

MAX_TEXTURE_SIZE :: 4096

texture_init :: proc(td: Texture_Descriptor) -> Resource {
    assert(td.dimensions.x <= MAX_TEXTURE_SIZE && td.dimensions.y <= MAX_TEXTURE_SIZE, "texture_init: texture dimensions must be <= 4096")
    return _texture_init(td)
}

pipeline_init :: proc(vertex_shader: Resource, vertex_function: string, fragment_shader: Resource, fragment_function: string, format: Pixel_Format) -> Resource {
    return _pipeline_init(vertex_shader, vertex_function, fragment_shader, fragment_function, format)
}

Color :: [4]u8

Load_Action :: enum u8 {
    Dont_Care,
    Clear,
    Load,
}

Store_Action :: enum u8 {
    Dont_Care,
    Store,
}

Shader :: struct {
    using impl: _Shader,
}

Pipeline :: struct {
    using impl: _Pipeline,
}

Shader_Stage :: enum u8 {
    Vertex,
    Fragment,
    Compute,
}

shader_init :: proc(name: string, code: []u8) -> Resource {
    return _shader_init(name, code)
}

Texture :: struct {
    using impl: _Texture,
}

Color_Attachment :: struct {
    clear_color: Color,
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
    resolve_texture: Texture,
}

Buffer :: struct {
    using _ : _Buffer,
}

ptr :: struct {
    cpu: rawptr,
    gpu: rawptr,
    offset: uint,
    buffer: Buffer,
}

Arena :: struct {
    using ptr: ptr,
    size: uint,
}

Memory :: enum u64 {
    CPU_GPU,
    GPU_Only,
}

buffer_init :: proc(bytes: uint, align: uint, memory: Memory) -> ptr {
    return _buffer_init(bytes, align, memory)
}

arena_init :: proc(size: uint = 4 * 1024 * 1024, align: uint = 16, memory: Memory = .CPU_GPU) -> Arena {
    ptr := _buffer_init(size, align, memory)
    return Arena {
        ptr = ptr,
        size = size,
        offset = 0,
    }
}

arena_alloc :: proc(arena: ^Arena, $T: typeid, #any_int count: uint = 1) -> ptr {
    return _arena_alloc_bytes(arena, size_of(T) * count, align_of(T))
}

ptr_fill_slice :: proc(dst: ^ptr, src: []$T) {
    _ptr_fill_slice(dst, raw_data(src[:]), size_of(T), len(src))
}

_arena_alloc_bytes :: proc(arena: ^Arena, bytes: uint, align: uint) -> ptr {
    assert(bytes >= 0 && align > 0)
    if bytes == 0 do return {}

    // If we request an alignment of > 16 and cpu/gpu are only aligned to 16,
    // it's impossible to find the same offset for both.
    if arena.cpu != nil && uintptr(arena.cpu) % uintptr(align) != uintptr(arena.gpu) % uintptr(align) {
        panic("Could not satisfy alignment requirements in GPU arena allocation.")
    }

    arena.offset = mem.align_forward_uint(arena.offset, align)
    if arena.offset + bytes > arena.size {
        panic("Arena: out of space")
    }

    temp := ptr {
        cpu = rawptr(uintptr(arena.cpu)),
        gpu = rawptr(uintptr(arena.gpu)),
        offset = arena.offset,
        buffer = arena.buffer,
    }

    arena.offset += bytes
    return temp
}

set_pipeline :: proc(pipeline: Resource) {
    _set_pipeline(pipeline.pipeline)
}

Range :: struct {
    location: u32,
    length:  u32,
}

Primitive_Type :: enum u8 {
    Triangle      = 3,
}

set_buffers :: proc(buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
    _set_buffers(buffers, offsets, range, stage)
}

draw_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, vertex_count: u32, vertex_start: u32) {
    _draw_primitives(primitive, index_buffer, vertex_count, vertex_start)
}

upload_one_shot :: proc(
    items: []struct {dst: ^ptr, src: ptr, bytes: uint}
) {
    _upload_one_shot(items)
}