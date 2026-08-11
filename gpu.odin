package nuppu

import "base:runtime"
import "core:mem"
import "core:os"
import "core:time"
import "core:container/handle_map"
import "core:log"

Memory :: enum {
    CPU_GPU,
    GPU_Only,
}

ptr :: struct {
    cpu: rawptr,
    gpu: rawptr,
    _data: [2]rawptr,
}

ptr_T :: struct($T: typeid) {
    cpu: ^T,
    gpu: rawptr,
    _data: [2]rawptr,
}

Renderer :: struct {
    ctx: runtime.Context,
    
    api: Renderer_API,
    api_state: Renderer_API_State,
}

Shader_Resource :: struct {
    ptr: ptr,
    usage: Resource_Usage,
    stage: Render_Stages,
}

Resource_Usage_Flag :: enum u64 {
	Read   = 0,
	Write  = 1,
	Sample = 2,
}
Resource_Usage :: distinct bit_set[Resource_Usage_Flag; u64]

Render_Stage :: enum u64 {
	Vertex   = 0,
	Fragment = 1,
	Tile     = 2,
	Object   = 3,
	Mesh     = 4,
}
Render_Stages :: distinct bit_set[Render_Stage; u64]

@(private="file")
state: ^Renderer

Renderer_API_State :: distinct rawptr

Renderer_API :: struct #all_or_none {
    init: proc() -> Renderer_API_State,
    deinit: proc(),
    resize_swapchain: proc(),

    malloc: proc(size: int, align: int, usage: Memory) -> ptr,
    temp_malloc: proc(command_buffer: Command_Buffer, bytes: []u8, buffer_index: u32, shader_stage: Shader_Stage),
    gpu_address: proc(ptr: ^ptr),
    free: proc(ptr: ptr),

    signal_init: proc(value: u64) -> Signal,
    signal_deinit: proc(signal: Signal),
    signal_wait_for: proc(signal: Signal, value: u64, timeout_milliseconds: time.Duration) -> bool,

    begin_commands: proc() -> Command_Buffer,
    end_commands: proc(command_buffer: Command_Buffer, frame_pass: Frame_Pass),
    cmd_present: proc(command_buffer: Command_Buffer, texture: Texture),
    acquire_next_swapchain: proc(cmd_buffer: Command_Buffer) -> Texture,
    cmd_begin_render_pass: proc(command_buffer: Command_Buffer, color_attachments: []Color_Attachment),
    cmd_end_render_pass: proc(command_buffer: Command_Buffer),
    cmd_mem_copy: proc(command_buffer: Command_Buffer, dst, src: ptr, size: u64),

    shader_init: proc(code: []u8, entry_point: string, stage: Graphics_Stage) -> Shader,
    shader_deinit: proc(shader: Shader),

    pipeline_init: proc(vertex_shader, fragment_shader: Shader, formats: []Pixel_Format, depth_format: Pixel_Format) -> Pipeline,
    pipeline_deinit: proc(pipeline: Pipeline),
    cmd_set_pipeline: proc(command_buffer: Command_Buffer, pipeline: Pipeline),

    cmd_use_resources: proc(command_buffer: Command_Buffer, resource_list: []Shader_Resource),
    cmd_draw_primitives: proc(command_buffer: Command_Buffer, buffer_pairs: []ptr_index_pair, primitive: Primitive_Type, vertex_count: u32),
    cmd_draw_indiced_primitives: proc(command_buffer: Command_Buffer, buffer_pairs: []ptr_index_pair, primitive: Primitive_Type, index_buffer: ptr, instance_count: u32),

    depth_stencil_state_init: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State,
    depth_stencil_state_deinit: proc(depth_stencil_state: Depth_Stencil_State),

    sampler_init: proc(desc: Sampler_Descriptor) -> Sampler,
    sampler_deinit: proc(sampler: Sampler),

    texture_init: proc(desc: Texture_Descriptor) -> Texture,
    texture_deinit: proc(texture: Texture),
}

Resource_Library :: struct($N: uint, $T: typeid, $Handle_T: typeid) {
    resources: handle_map.Static_Handle_Map(N, Resource(T, Handle_T), Handle_T),
    is_init: bool,
}

Resource :: struct($T: typeid, $Handle_T: typeid) {
    handle: Handle_T,
    info: T,
    meta: Resource_Metadata,
}

Resource_Metadata :: struct {
    name: string,
    created_at_frame: int,
}

Pixel_Format :: enum {
    Invalid,
    BGRA8Unorm_sRGB,
    RGBA8Unorm,
    Depth32Float,
}

Texture_Usage_Flags :: enum {
    ShaderRead,
    ShaderWrite,
    RenderTarget,
}
Texture_Usage :: bit_set[Texture_Usage_Flags]

Load_Action :: enum {
    Dont_Care,
    Clear,
    Load,
}

Store_Action :: enum {
    Dont_Care,
    Store,
}

Depth_Stencil_State :: distinct rawptr
Depth_Stencil_State_Descriptor :: struct {
    compare_func: Compare_Function,
    depth_write: bool,
}

Compare_Function :: enum u64 {
	Never        = 0,
	Less         = 1,
	Equal        = 2,
	LessEqual    = 3,
	Greater      = 4,
	NotEqual     = 5,
	GreaterEqual = 6,
	Always       = 7,
}

// ---------------------------------------------------------------------------
// 

gpu_init :: proc() {
    state = new(Renderer)

    state.ctx = context
    state.api = RENDERER_API

    state.api_state = state.api.init()
}

gpu_deinit :: proc() {
    state.api.deinit()
    free(state)
}

gpu_debug_init :: proc( ) {   
when ODIN_DEBUG && ODIN_OS == .Darwin {
    os.set_env("MTL_DEBUG_LAYER", "1") // API validation
    os.set_env("MTL_SHADER_VALIDATION", "1") // Shader validation
    os.set_env("MTL_CAPTURE_ENABLED", "1") // GPU capture (.gputrace)
    os.set_env("MTL_HUD_ENABLED", "1") // HUD (performance counters)
    os.set_env("OBJC_DEBUG_MISSING_POOLS", "YES") // Track missing autorelease pools
}
}

gpu_resize_swapchain :: proc() {
    state.api.resize_swapchain()
}

// ---------------------------------------------------------------------------
// Resource Library

resource_library_init :: proc(library: ^Resource_Library($N, $T, $Handle_T)) {
    library.is_init = true
}

resource_library_add :: proc(library: ^Resource_Library($N, $T, $Handle_T), info: T, meta: Resource_Metadata) -> Handle_T {
    assert(library.is_init)
    handle, ok := handle_map.static_add(&library.resources, Resource(T, Handle_T) {
        info = info,
        meta = meta,
    })
    assert(ok, "resource_library_add: handle_map.static_add failed")
    return handle
}

resource_library_get :: proc(library: ^Resource_Library($N, $T, $Handle_T), handle: Handle_T) -> (^T, bool) #optional_ok {
    result, ok := handle_map.static_get(&library.resources, handle)
    return &result.info, ok
}

resource_library_remove :: proc(library: ^Resource_Library($N, $T, $Handle_T), handle: Handle_T) {
    handle_map.static_remove(&library.resources, handle)
}

resource_library_deinit :: proc(library: ^Resource_Library($N, $T, $Handle_T)) {
    if !library.is_init { return }
    library^ = {}
}

// ---------------------------------------------------------------------------
// Arena

GPU_Arena :: struct {
    using ptr: ptr,
    size: int,
    offset: int,
}

gpu_arena_init :: proc(size: int = 4 * 1024 * 1024) -> GPU_Arena {
    ptr := gpu_malloc(size, 16, .CPU_GPU)
    return GPU_Arena {
        ptr = ptr,
        size = size,
        offset = 0,
    }
}

gpu_arena_deinit :: proc(arena: ^GPU_Arena) {
    gpu_free(arena)
    arena^ = {}
}

gpu_arena_free_all :: proc(arena: ^GPU_Arena) {
    arena.offset = 0
}

gpu_arena_alloc_raw :: proc(arena: ^GPU_Arena, #any_int el_size: int, #any_int el_count: int, #any_int align: int = 16) -> ptr {
    return gpu_arena_alloc_bytes(arena, el_size * el_count, align)
}

gpu_arena_alloc_T :: proc(arena: ^GPU_Arena, $T: typeid, el_count: int = 1) -> ptr {
    return gpu_arena_alloc_bytes(arena, size_of(T) * el_count, align_of(T))
}

gpu_arena_alloc_bytes :: proc(arena: ^GPU_Arena, bytes: int, align: int = 16) -> ptr {
    assert(bytes >= 0 && align > 0)
    if bytes == 0 do return {}

    // If we request an alignment of > 16 and cpu/gpu are only aligned to 16,
    // it's impossible to find the same offset for both.
    if arena.cpu != nil && uintptr(arena.cpu) % uintptr(align) != uintptr(arena.gpu) % uintptr(align) {
        panic("Could not satisfy alignment requirements in GPU arena allocation.")
    }

    arena.offset = mem.align_forward_int(arena.offset, align)
    if arena.offset + bytes > arena.size {
        panic("Linear_Arena: out of space")
    }

    temp := ptr {
        cpu = rawptr(uintptr(arena.cpu) + uintptr(arena.offset)),
        gpu = rawptr(uintptr(arena.gpu) + uintptr(arena.offset)),
        _data = {arena._data[0], rawptr(uintptr(arena._data[1]) + uintptr(arena.offset))},
    }

    arena.offset += bytes
    return temp
}

// ---------------------------------------------------------------------------
// GPU Memory

// Allocates a buffer of `size` bytes on the GPU.
gpu_malloc :: proc(size: int, align: int = 16, usage: Memory = .CPU_GPU) -> ptr {
    return state.api.malloc(size, align, usage)
}

gpu_temp_malloc :: proc(command_buffer: Command_Buffer, bytes: []u8, buffer_index: u32, shader_stage: Shader_Stage = .Vertex) {
when ODIN_DEBUG {   
    if len(bytes) > 32 {
        log.error("GPU_Arena: temp_malloc: len of temp bytes > 32, consider binding a full buffer instead")
    }
}
    state.api.temp_malloc(command_buffer, bytes, buffer_index, shader_stage)   
}

// Fills the GPU address of the ptr if not filled.
gpu_address :: proc(ptr: ^ptr) {
    state.api.gpu_address(ptr)
}

// Frees the memory view's underlying buffer.
gpu_free :: proc(ptr: ptr) {
    state.api.free(ptr)
}

// ---------------------------------------------------------------------------
// Shaders

Shader :: distinct rawptr

Shader_Stage :: enum {
    Vertex,
    Fragment,
    Compute
}

Graphics_Stage :: enum {
    Vertex,
    Fragment,
}

shader_init :: proc(code: []u8, entry_point: string, stage: Graphics_Stage) -> Shader {
    return state.api.shader_init(code, entry_point, stage)
}

shader_deinit :: proc(shader: Shader) {
    state.api.shader_deinit(shader)
}

// ---------------------------------------------------------------------------
// Texture






Sampler :: distinct rawptr

Sampler_Descriptor :: struct {
    min_filter: Sampler_Min_Mag_Filter,
    mag_filter: Sampler_Min_Mag_Filter,
    mip_filter: Sampler_Mip_Filter,
    address_mode: [3]Sampler_Address_Mode,
}

sampler_init :: proc(desc: Sampler_Descriptor) -> Sampler {
    return state.api.sampler_init(desc)
}

sampler_deinit :: proc(sampler: Sampler) {
    state.api.sampler_deinit(sampler)
}

Texture_Descriptor :: struct {
    dimensions: [2]int,
    format: Pixel_Format,
}

texture_init :: proc(desc: Texture_Descriptor) -> Texture {
    return state.api.texture_init(desc)
}

texture_deinit :: proc(texture: Texture) {
    state.api.texture_deinit(texture)
}

// ---------------------------------------------------------------------------
// Commands / Frame loop

Signal :: distinct rawptr

gpu_signal_init :: proc(value: u64) -> Signal {
    return state.api.signal_init(value)
}

gpu_signal_deinit :: proc(signal: Signal) {
    state.api.signal_deinit(signal)
}

gpu_signal_wait_for :: proc(signal: Signal, value: u64, timeout_milliseconds: time.Duration = time.MAX_DURATION) -> bool {
    return state.api.signal_wait_for(signal, value, timeout_milliseconds)
}


Command_Buffer :: distinct handle_map.Handle16

begin_commands :: proc() -> Command_Buffer {
    return state.api.begin_commands()
}

end_commands :: proc(command_buffer: Command_Buffer, frame_pass: Frame_Pass) {
    state.api.end_commands(command_buffer, frame_pass)
}

Texture :: distinct handle_map.Handle64

cmd_present :: proc(command_buffer: Command_Buffer, texture: Texture) {
    state.api.cmd_present(command_buffer, texture)
}

cmd_mem_copy :: proc(command_buffer: Command_Buffer, dst, src: ptr, size: u64) {
    state.api.cmd_mem_copy(command_buffer, dst, src, size)
}

acquire_next_swapchain :: proc(cmd_buffer: Command_Buffer) -> Texture {
    return state.api.acquire_next_swapchain(cmd_buffer)
}

cmd_begin_render_pass :: proc(command_buffer: Command_Buffer, color_attachments: []Color_Attachment) {
    state.api.cmd_begin_render_pass(command_buffer, color_attachments)
}

cmd_end_render_pass :: proc(cmd_buffer: Command_Buffer) {
    state.api.cmd_end_render_pass(cmd_buffer)
}

Pipeline :: distinct rawptr

pipeline_init :: proc(vertex_shader, fragment_shader: Shader, formats: []Pixel_Format, depth_format: Pixel_Format) -> Pipeline {
    return state.api.pipeline_init(vertex_shader, fragment_shader, formats, depth_format)
}

pipeline_deinit :: proc(pipeline: Pipeline) {
    state.api.pipeline_deinit(pipeline)
}

cmd_set_pipeline :: proc(command_buffer: Command_Buffer, pipeline: Pipeline) {
    state.api.cmd_set_pipeline(command_buffer, pipeline)
}

ptr_index_pair :: struct {
    ptr: ptr,
    index: u32,
}

Primitive_Type :: enum u64 {
	Point         = 0,
	Line          = 1,
	Line_Strip     = 2,
	Triangle      = 3,
	Triangle_Strip = 4,
}

cmd_draw_primitives :: proc(command_buffer: Command_Buffer, buffer_pairs: []ptr_index_pair, primitive: Primitive_Type, vertex_count: u32) {
    state.api.cmd_draw_primitives(command_buffer, buffer_pairs, primitive, vertex_count)
}

cmd_draw_indiced_primitives :: proc(command_buffer: Command_Buffer, buffer_pairs: []ptr_index_pair, primitive: Primitive_Type, index_buffer: ptr, instance_count: u32 = 1) {
    state.api.cmd_draw_indiced_primitives(command_buffer, buffer_pairs, primitive, index_buffer, instance_count)
}

cmd_use_resources :: proc(command_buffer: Command_Buffer, resource_list: []Shader_Resource) {
    state.api.cmd_use_resources(command_buffer, resource_list)
}
// cmd_set_shaders :: proc(cmd_buffer: Command_Buffer, vertex, fragment: Shader) {
//     state.api.cmd_set_shaders(cmd_buffer, vertex, fragment)
// }

// cmd_draw :: proc(cmd_buffer: Command_Buffer, vertex_stage_in, indices: Memory_View, used_resources: []Memory_View, instance_count: u32 = 1) {
//     state.api.cmd_draw(cmd_buffer, vertex_stage_in, indices, used_resources, instance_count)
// }

// // Copies `size` bytes from `src` to `dst` with optional offsets.
// cmd_mem_copy :: proc(cmd_buffer: Command_Buffer, dst: Memory_View, dst_offset: u64, src: Memory_View, src_offset: u64, size: u64) {
//     assert(dst.gpu != nil, "gpu_mem_copy: dst must have GPU ptr set")
//     assert(src.gpu != nil, "gpu_mem_copy: src must have GPU ptr set")

//     state.api.cmd_mem_copy(cmd_buffer, dst, dst_offset, src, src_offset, size)
// }

// ---------------------------------------------------------------------------
// Barriers

depth_stencil_state_init :: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State {
    return state.api.depth_stencil_state_init(desc)
}

depth_stencil_state_deinit :: proc(depth_stencil_state: Depth_Stencil_State) {
    state.api.depth_stencil_state_deinit(depth_stencil_state)
}

// // `before` = the stage that must finish first (producer), `after` = the stage that waits (consumer).
// gpu_barrier :: proc(cmd_buffer: Command_Buffer, before, after: Pipeline_Stages, hazards: Hazard_Flags = {.Buffers, .Textures, .RenderTargets}) {
//     state.api.cmd_barrier(cmd_buffer, before, after, hazards)
// }

// gpu_signal_after :: proc(cmd_buffer: Command_Buffer, after: Pipeline_Stages) {
//     state.api.cmd_signal_fence(cmd_buffer, after)
// }

// gpu_wait_before :: proc(cmd_buffer: Command_Buffer, before: Pipeline_Stages, hazards: Hazard_Flags = {}) {
//     state.api.cmd_wait_fence(cmd_buffer, before, hazards)
// }

// // Blit-side cache flush: emit `synchronizeResource` on the underlying buffer.
// // Pairs with cmd_mem_copy to make a freshly-copied buffer visible to later reads.
// // Cannot be called while a render encoder is active.
// cmd_gpu_synchronize :: proc(cmd_buffer: Command_Buffer, resources: []Memory_View) {
//     state.api.cmd_synchronize(cmd_buffer, resources)
// }

// // ---------------------------------------------------------------------------
// // GPU Debug

// gpu_debug_start_recording :: proc() {
//     when ODIN_DEBUG {
//         state.api.gpu_debug_start_recording()
//     } else {
//         log.error("DEBUG_CAPTURE is not enabled, ignoring gpu_debug_start_recording")
//     }
// }
