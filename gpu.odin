package nuppu

import "base:runtime"
import "core:mem"
import "core:os"
import "core:time"
import "core:container/handle_map"
import "core:log"

Color :: distinct [4]u8

Color_Attachment :: struct {
    clear_color: Color,
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
    // Optional: when non-nil, the rendering engine will resolve the multisample
    // data from `texture` into `resolve_texture` at the end of the render pass.
    // Useful for MSAA-to-non-MSAA or render-to-texture pipelines. The matching
    // `store_action` must be `.MultisampleResolve` or `.StoreAndMultisampleResolve`.
    //
    // IMPORTANT: `resolve_texture` must be a SINGLE-SAMPLE texture (i.e. its
    // `texture_type` is not `Type2DMultisample`). It must also differ from
    // `texture`.
    resolve_texture: Texture,
}

GPU_Arena :: struct {
    using ptr: ptr,
    size: uint,
    offset: uint,
}

Memory :: enum u64 {
    CPU_GPU,
    GPU_Only,
}

ptr :: struct {
    cpu: rawptr,
    gpu: rawptr,
    // Offset into underlying buffer. cpu and gpu pointer (if set) already start at that offset. 
    // No need to do math for their 'correct' position
    _buffer_offset: uint, 
    using __b: Buffer,
}

Buffer :: struct {
    _data: rawptr,
}

GPU :: struct {
    ctx: runtime.Context,
    
    api: GPU_API,
    api_state: GPU_API_State,
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

Stage :: enum u64 {
	Transfer         = 0,
	Compute          = 1,
	Raster_Color_Out = 2,
	Fragment_Shader  = 3,
	Vertex_Shader    = 4,
	Build_BVH        = 5,
	All              = 6,
}

Storage_Mode :: enum u64 {
	Shared     = 0,
	Managed    = 1,
	Private    = 2,
	Memoryless = 3,
}

@(private="file")
state: ^GPU

GPU_API_State :: distinct rawptr

GPU_API :: struct #all_or_none {
    init: proc() -> GPU_API_State,
    deinit: proc(),
    resize_swapchain: proc(),

    malloc: proc(size: uint, align: uint, usage: Memory) -> ptr,
    temp_malloc: proc(command_buffer: Command_Buffer, bytes: []u8, buffer_index: u32, shader_stage: Shader_Stage),
    mem_copy_to_texture: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32),
    free: proc(ptr: ptr),

    texture_size: proc(texture: Texture) -> [3]i32,
    texture_format: proc(texture: Texture) -> Pixel_Format,
    texture_type: proc(texture: Texture) -> Texture_Type,
    remake_texture: proc(texture: Texture, descriptor: Texture_Descriptor),

    signal_init: proc(value: u64) -> Signal,
    signal_deinit: proc(signal: Signal),
    signal_wait_for: proc(signal: Signal, value: u64, timeout_milliseconds: time.Duration) -> bool,

    begin_commands: proc() -> Command_Buffer,
    end_commands: proc(command_buffer: Command_Buffer, frame_pass: Frame_Pass),
    cmd_present: proc(command_buffer: Command_Buffer, texture: Texture),
    acquire_next_swapchain: proc(cmd_buffer: Command_Buffer) -> Texture,
    cmd_begin_render_pass: proc(command_buffer: Command_Buffer, color_attachments: []Color_Attachment, depth_attachment: Depth_Attachment),
    cmd_end_render_pass: proc(command_buffer: Command_Buffer),
    cmd_mem_copy: proc(command_buffer: Command_Buffer, dst, src: ptr, size: u64),
    cmd_barrier: proc(command_buffer: Command_Buffer, before: Stage, after: Stage),

    cmd_blit_texture: proc(command_buffer: Command_Buffer, src, dst: Texture),

    shader_init: proc(code: []u8, entry_point: string, stage: Graphics_Stage) -> Shader,
    shader_deinit: proc(shader: Shader),
    kernel_init: proc(code: []u8, entry_point: string) -> Shader,
    cmd_set_compute_pipeline: proc(command_buffer: Command_Buffer, kernel: Shader),

    pipeline_init: proc(vertex_shader, fragment_shader: Shader, formats: []Pixel_Format, depth_format: Pixel_Format) -> Pipeline,
    pipeline_deinit: proc(pipeline: Pipeline),
    cmd_set_pipeline: proc(command_buffer: Command_Buffer, pipeline: Pipeline),

    cmd_use_resources: proc(command_buffer: Command_Buffer, resource_list: []Shader_Resource),
    cmd_draw_primitives: proc(command_buffer: Command_Buffer, primitive: Primitive_Type, vertex_count: u32, vertex_start: u32),
    cmd_draw_indiced_primitives: proc(command_buffer: Command_Buffer, primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_instance: u32),

    cmd_set_scissor_rect: proc(command_buffer: Command_Buffer, x, y, width, height: u32),

    depth_stencil_state_init: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State,
    depth_stencil_state_deinit: proc(depth_stencil_state: Depth_Stencil_State),
    cmd_set_depth_stencil_state: proc(command_buffer: Command_Buffer, depth_stencil_state: Depth_Stencil_State),

    texture_init: proc(desc: Texture_Descriptor) -> Texture,
    texture_deinit: proc(texture: Texture),
    cmd_set_textures: proc(command_buffer: Command_Buffer, textures: []Texture, range: Range, stage: Shader_Stage),
    
    cmd_set_cull_mode: proc(command_buffer: Command_Buffer, cull_mode: Cull_Mode),
    cmd_set_front_face_winding: proc(command_buffer: Command_Buffer, front_face_winwing: Winding),

    cmd_set_texture: proc(command_buffer: Command_Buffer, pairs: []texture_index_pair, stage: Shader_Stage),
    cmd_dispatch: proc(command_buffer: Command_Buffer, threads_per_grid, threads_per_thread_group: [3]int),
    max_total_threads_per_threadgroup: proc(kernel: Shader) -> int,

    cmd_set_buffer: proc(command_buffer: Command_Buffer, buffer: ptr, index: u32, stage: Shader_Stage, offset: uint = 0),
    cmd_set_buffers: proc(command_buffer: Command_Buffer, buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage),
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

Pixel_Format :: enum u64 {
    Invalid,
    BGRA8Unorm_sRGB,
    RGBA8Unorm,
    Depth32Float,
}

Texture_Usage_Flags :: enum u64 {
    ShaderRead,
    ShaderWrite,
    RenderTarget,
}
Texture_Usage :: bit_set[Texture_Usage_Flags; u64]

Load_Action :: enum u64 {
    Dont_Care,
    Clear,
    Load,
}

Sampler_Min_Mag_Filter :: enum u64 {
	Nearest = 0,
	Linear  = 1,
}

Sampler_Mip_Filter :: enum u64 {
	NotMipmapped = 0,
	Nearest      = 1,
	Linear       = 2,
}

Sampler_Address_Mode :: enum u64 {
	ClampToEdge        = 0,
	MirrorClampToEdge  = 1,
	Repeat             = 2,
	MirrorRepeat       = 3,
	ClampToZero        = 4,
	ClampToBorderColor = 5,
}

Store_Action :: enum {
    Dont_Care,
    Store,
    MultisampleResolve,
    StoreAndMultisampleResolve,
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

Shader :: distinct rawptr

Shader_Stage :: enum u64 {
    Vertex   = 0,
    Fragment = 1,
    Compute
}

Graphics_Stage :: enum u64 {
    Vertex   = 0,
    Fragment = 1,
}

Texture :: distinct handle_map.Handle64
Texture_nil :: Texture {}

Texture_Type :: enum u64 {
	Type1D                 = 0,
	Type1DArray            = 1,
	Type2D                 = 2,
	Type2DArray            = 3,
	Type2DMultisample      = 4,
	TypeCube               = 5,
	TypeCubeArray          = 6,
	Type3D                 = 7,
	Type2DMultisampleArray = 8,
	TypeTextureBuffer      = 9,
}

Texture_Descriptor :: struct {
    dimensions: [2]int,
    format: Pixel_Format,
    usage: Texture_Usage,
    storage_mode: Storage_Mode,
    texture_type: Texture_Type,
}

Signal :: distinct rawptr

Command_Buffer :: distinct handle_map.Handle16

Pipeline :: distinct rawptr

Primitive_Type :: enum u64 {
	Point         = 0,
	Line          = 1,
	Line_Strip     = 2,
	Triangle      = 3,
	Triangle_Strip = 4,
}

Cull_Mode :: enum u64 {
    None  = 0,
	Front = 1,
	Back  = 2,
}

Winding :: enum u64 {
	Clockwise        = 0,
	CounterClockwise = 1,
}

Depth_Attachment :: struct {
    clear_depth: f64,
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
    // Optional: when non-nil, the rendering engine will resolve the multisample
    // depth data from `texture` into `resolve_texture` at the end of the render pass.
    // Useful for MSAA-to-non-MSAA pipelines. The matching `store_action` must be
    // `.MultisampleResolve` or `.StoreAndMultisampleResolve`.
    //
    // IMPORTANT: `resolve_texture` must be a SINGLE-SAMPLE texture (i.e. its
    // `texture_type` is not `Type2DMultisample`). It must also differ from
    // `texture`.
    resolve_texture: Texture,
}

bit_set_to_another :: proc(input: $T/bit_set[$TT; $TI], $Out: typeid, interop: [TT]$O) -> (result: Out) {
    for f in input { result |= {interop[f]} }
    return
}

// ---------------------------------------------------------------------------
// 

gpu_init :: proc() {
    state = new(GPU)

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

resource_library_iterator_make :: proc(library: ^Resource_Library($N, $T, $Handle_T)) -> handle_map.Static_Handle_Map_Iterator(handle_map.Static_Handle_Map(N, Resource(T, Handle_T), Handle_T)) {
    result := handle_map.static_iterator_make(&library.resources)
    return result
}

// ---------------------------------------------------------------------------
// Arena

gpu_arena_init :: proc(size: uint = 4 * 1024 * 1024, align: uint = 16, mem: Memory = .CPU_GPU) -> GPU_Arena {
    ptr := __gpu_malloc_bytes(size, align, mem)
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

gpu_arena_alloc :: proc {
    gpu_arena_alloc_typed,
    gpu_arena_alloc_raw,
}

gpu_arena_alloc_typed :: proc(arena: ^GPU_Arena, $T: typeid, #any_int count: uint = 1) -> ptr {
    return _gpu_arena_alloc_bytes(arena, size_of(T) * count, align_of(T))
}

gpu_arena_alloc_raw :: proc(arena: ^GPU_Arena, #any_int size, count, align: uint) -> ptr {
    return _gpu_arena_alloc_bytes(arena, size * count, align)
}

_gpu_arena_alloc_bytes :: proc(arena: ^GPU_Arena, bytes: uint, align: uint = 16) -> ptr {
    assert(bytes >= 0 && align > 0)
    if bytes == 0 do return {}

    // If we request an alignment of > 16 and cpu/gpu are only aligned to 16,
    // it's impossible to find the same offset for both.
    if arena.cpu != nil && uintptr(arena.cpu) % uintptr(align) != uintptr(arena.gpu) % uintptr(align) {
        panic("Could not satisfy alignment requirements in GPU arena allocation.")
    }

    arena.offset = mem.align_forward_uint(arena.offset, align)
    if arena.offset + bytes > arena.size {
        panic("Linear_Arena: out of space")
    }

    temp := ptr {
        cpu = rawptr(uintptr(arena.cpu) + uintptr(arena.offset)),
        gpu = rawptr(uintptr(arena.gpu) + uintptr(arena.offset)),
        _buffer_offset = arena._buffer_offset + arena.offset,
        _data = arena._data,
    }

    arena.offset += bytes
    return temp
}

gpu_ptr_fill_slice :: proc(dst: ptr, src: []$T) {
    if dst.cpu == nil {
        log.error("gpu_ptr_fill_slice: dst must have CPU ptr set. Is ptr GPU private?")
        return
    }
    mem.copy(dst.cpu, raw_data(src[:]), size_of(T) * len(src))
}

// ---------------------------------------------------------------------------
// GPU Memory

gpu_malloc :: proc {
    gpu_malloc_typed,
    gpu_malloc_raw,
}

gpu_malloc_typed :: proc($T: typeid, #any_int count: uint = 1, mem_access: Memory = .CPU_GPU) -> ptr {
    return __gpu_malloc_bytes(size_of(T) * count, align_of(T), mem_access)
}

gpu_malloc_raw :: proc(#any_int size, count, align: uint, mem_access: Memory = .CPU_GPU) -> ptr {
    return __gpu_malloc_bytes(size * count, align, mem_access)
}

// Allocates a buffer of 'size' bytes on the GPU.
__gpu_malloc_bytes :: proc(bytes: uint, align: uint = 16, mem_access: Memory = .CPU_GPU) -> ptr {
    return state.api.malloc(bytes, align, mem_access)
}

gpu_temp_malloc :: proc(command_buffer: Command_Buffer, bytes: []u8, buffer_index: u32, shader_stage: Shader_Stage) {
    state.api.temp_malloc(command_buffer, bytes, buffer_index, shader_stage)   
}

// Frees the ptr's underlying buffer.
gpu_free :: proc(ptr: ptr) {
    state.api.free(ptr)
}

// ---------------------------------------------------------------------------
// Shaders

shader_init :: proc(code: []u8, entry_point: string, stage: Shader_Stage) -> (shader: Shader) {
    if stage == .Vertex || stage == .Fragment {
        shader = state.api.shader_init(code, entry_point, transmute(Graphics_Stage)stage)
    }
    else if stage == .Compute {
        shader = state.api.kernel_init(code, entry_point)
    }

    return shader
}

shader_deinit :: proc(shader: Shader) {
    state.api.shader_deinit(shader)
}

// ---------------------------------------------------------------------------
// Texture

texture_depth_init :: proc(dimensions: [2]int, format: Pixel_Format) -> Texture {
    desc := Texture_Descriptor {
        dimensions = dimensions,
        format = format,
        usage = {.RenderTarget},
        storage_mode = .Private,
        texture_type = .Type2D,
    }

    return texture_init(desc)
}

texture_init :: proc(desc: Texture_Descriptor) -> Texture {
    return state.api.texture_init(desc)
}

texture_deinit :: proc(texture: Texture) {
    state.api.texture_deinit(texture)
}

// ---------------------------------------------------------------------------
// Commands / Frame loop

gpu_signal_init :: proc(value: u64) -> Signal {
    return state.api.signal_init(value)
}

gpu_signal_deinit :: proc(signal: Signal) {
    state.api.signal_deinit(signal)
}

gpu_signal_wait_for :: proc(signal: Signal, value: u64, timeout_milliseconds: time.Duration = time.MAX_DURATION) -> bool {
    return state.api.signal_wait_for(signal, value, timeout_milliseconds)
}

begin_commands :: proc() -> Command_Buffer {
    return state.api.begin_commands()
}

end_commands :: proc(command_buffer: Command_Buffer, frame_pass: Frame_Pass) {
    state.api.end_commands(command_buffer, frame_pass)
}

cmd_present :: proc(command_buffer: Command_Buffer, texture: Texture) {
    state.api.cmd_present(command_buffer, texture)
}

cmd_mem_copy :: proc(command_buffer: Command_Buffer, dst, src: ptr, size: u64) {
    if size == 0 {
        return
    }
    state.api.cmd_mem_copy(command_buffer, dst, src, size)
}

gpu_mem_copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
    state.api.mem_copy_to_texture(texture, origin, size, level, data, bytes_per_row)
}

cmd_barrier :: proc(command_buffer: Command_Buffer, before: Stage, after: Stage) {
    state.api.cmd_barrier(command_buffer, before, after)
}

// Blits (copies) the entire contents of `src` into `dst`. Commonly used to
// display a render-target texture on the swapchain (e.g. render scene to a
// 200x200 offscreen target, then blit it to the swapchain to present).
//
// Size mismatches: Metal silently clamps the blit to the overlapping region.
//
// Pixel-format mismatches: the blit still executes but raw bytes are copied
// without any sRGB conversion or channel reordering. For example, blitting
// a `.RGBA8Unorm` source into a `.BGRA8Unorm_sRGB` destination (the typical
// swapchain format) will produce visibly wrong colors. In these cases create
// a texture view If you need format conversion, render the offscreen target
// with the SAME pixel format as the destination.
//
// Caller must ensure no render encoder is active for `command_buffer`. If a
// render pass just ended, call `cmd_barrier(cmd, .Raster_Color_Out, .Transfer)`
// before this blit. `src` and `dst` must be different textures.
//
// The swapchain drawable is NOT `framebufferOnly`, so it can be used as the
// destination (this is the canonical render-target-to-display path).
cmd_blit_texture :: proc(command_buffer: Command_Buffer, src, dst: Texture) {
    state.api.cmd_blit_texture(command_buffer, src, dst)
}

acquire_next_swapchain :: proc(cmd_buffer: Command_Buffer) -> Texture {
    return state.api.acquire_next_swapchain(cmd_buffer)
}

cmd_begin_render_pass :: proc(command_buffer: Command_Buffer, color_attachments: []Color_Attachment, depth_attachment: Depth_Attachment = {}) {
    state.api.cmd_begin_render_pass(command_buffer, color_attachments, depth_attachment)
}

cmd_end_render_pass :: proc(cmd_buffer: Command_Buffer) {
    state.api.cmd_end_render_pass(cmd_buffer)
}

pipeline_init :: proc(vertex_shader, fragment_shader: Shader, formats: []Pixel_Format, depth_format: Pixel_Format) -> Pipeline {
    return state.api.pipeline_init(vertex_shader, fragment_shader, formats, depth_format)
}

pipeline_deinit :: proc(pipeline: Pipeline) {
    state.api.pipeline_deinit(pipeline)
}

cmd_set_pipeline :: proc {
    _cmd_set_graphics_pipeline,
    _cmd_set_compute_pipeline,
}

_cmd_set_compute_pipeline :: proc(command_buffer: Command_Buffer, kernel: Shader) {
    state.api.cmd_set_compute_pipeline(command_buffer, kernel)
}

_cmd_set_graphics_pipeline :: proc(command_buffer: Command_Buffer, pipeline: Pipeline) {
    state.api.cmd_set_pipeline(command_buffer, pipeline)
}

cmd_set_buffer :: proc(command_buffer: Command_Buffer, buffer: ptr, index: u32, stage: Shader_Stage, offset: uint = 0) {
    state.api.cmd_set_buffer(command_buffer, buffer, index, stage, offset)
}

cmd_set_buffers :: proc(command_buffer: Command_Buffer, buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
    state.api.cmd_set_buffers(command_buffer, buffers, offsets, range, stage)
}

cmd_draw_primitives :: proc(command_buffer: Command_Buffer, primitive: Primitive_Type, vertex_count: u32, vertex_start: u32 = 0) {
    state.api.cmd_draw_primitives(command_buffer, primitive, vertex_count, vertex_start)
}

// Issues an indexed draw on the active render command encoder.
//
// `index_count` is in indices (i.e. the number of indices to consume).
// `index_offset` is ALSO in indices — it's the starting index into `index_buffer`,
// matching `Mesh.index_range.location` from the Default_Renderer. The backend
// converts this to bytes internally. Defaults to 0 (start of buffer).
//
// `instance_count` is the number of instances to draw. Defaults to 1
// (non-instanced).
//
// `base_instance` is the starting instance index (added to `instance_id` in
// the shader). Defaults to 0 (instance_id starts at 0). Set this when batching
// instances across multiple draws — pass the absolute offset of this batch's
// first instance in the instance buffer.
//
// Caller must ensure no other command is currently encoding draws and that
// the index buffer has `index_offset + index_count` valid indices remaining.
cmd_draw_indiced_primitives :: proc(command_buffer: Command_Buffer, primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32 = 0, instance_count: u32 = 1, base_instance: u32 = 0) {
    state.api.cmd_draw_indiced_primitives(command_buffer, primitive, index_buffer, index_count, index_offset, instance_count, base_instance)
}

// Sets the GPU scissor rectangle for subsequent draw calls on this command
// buffer. Fragments outside the scissor are clipped before the fragment
// shader runs, which is the canonical way to constrain rendering to a
// sub-region of the render target (e.g. letterbox bars around an offscreen
// render target, partial updates, UI overlays).
//
// Coordinates are in PIXELS with the origin at the top-left of the render
// target, matching Metal's `setScissorRect:` convention. Must be issued
// while a render command encoder is active.
cmd_set_scissor_rect :: proc(command_buffer: Command_Buffer, x, y, width, height: u32) {
    state.api.cmd_set_scissor_rect(command_buffer, x, y, width, height)
}

cmd_use_resources :: proc(command_buffer: Command_Buffer, resource_list: []Shader_Resource) {
    state.api.cmd_use_resources(command_buffer, resource_list)
}

// ---------------------------------------------------------------------------
// Barriers

depth_stencil_state_init :: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State {
    return state.api.depth_stencil_state_init(desc)
}

depth_stencil_state_deinit :: proc(depth_stencil_state: Depth_Stencil_State) {
    state.api.depth_stencil_state_deinit(depth_stencil_state)
}

cmd_set_depth_stencil_state :: proc(command_buffer: Command_Buffer, depth_stencil_state: Depth_Stencil_State) {
    state.api.cmd_set_depth_stencil_state(command_buffer, depth_stencil_state)
}

cmd_set_texture :: proc(command_buffer: Command_Buffer, pairs: []texture_index_pair, stage: Shader_Stage) {
    state.api.cmd_set_texture(command_buffer, pairs, stage)
}

cmd_set_textures :: proc(command_buffer: Command_Buffer, textures: []Texture, range: Range, stage: Shader_Stage) {
    state.api.cmd_set_textures(command_buffer, textures, range, stage)    
}

cmd_dispatch :: proc(command_buffer: Command_Buffer, threads_per_grid, threads_per_thread_group: [3]int) {
    state.api.cmd_dispatch(command_buffer, threads_per_grid, threads_per_thread_group)
}

cmd_set_cull_mode :: proc(command_buffer: Command_Buffer, cull_mode: Cull_Mode) {
    state.api.cmd_set_cull_mode(command_buffer, cull_mode)
}

cmd_set_front_face_winding :: proc(command_buffer: Command_Buffer, front_face_winwing: Winding) {
    state.api.cmd_set_front_face_winding(command_buffer, front_face_winwing)
}

max_total_threads_per_threadgroup :: proc(kernel: Shader) -> int {
    return state.api.max_total_threads_per_threadgroup(kernel)
}


texture_size :: proc(texture: Texture) -> [3]i32 {
    return state.api.texture_size(texture)
}

texture_format :: proc(texture: Texture) -> Pixel_Format {
    return state.api.texture_format(texture)
}

texture_type :: proc(texture: Texture) -> Texture_Type {
    return state.api.texture_type(texture)
}

remake_texture :: proc(texture: Texture, descriptor: Texture_Descriptor) {
    state.api.remake_texture(texture, descriptor)
}

remake_depth_texture :: proc(texture: Texture, dimensions: [2]int, format: Pixel_Format) {
    desc := Texture_Descriptor {
        dimensions = dimensions,
        format = format,
        usage = {.RenderTarget},
        storage_mode = .Private,
        texture_type = .Type2D,
    }
    remake_texture(texture, desc)
}
