#+vet explicit-allocators shadowing unused
package nuppu_gpu

import "base:runtime"
import "core:mem"
import "core:log"
import "core:strings"
import "core:fmt"

_ :: fmt
_ :: log

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

// Limits based of WGSL https://www.w3.org/TR/WGSL/#limits
__MAX_CONSTANT_BUFFERS     :: 12 // Seperate limit from MAX_BUFFERS
__MAX_BUFFERS              :: 8  // 8 in total between read + read_write
__MAX_SAMPLED_TEXTURES     :: 16
__MAX_READ_WRITE_TEXTURES  :: 4
__MAX_SAMPLERS             :: 16

__MAX_READ_RESOURCE        :: __MAX_BUFFERS + __MAX_SAMPLED_TEXTURES
__MAX_READ_WRITE_RESOURCES :: __MAX_BUFFERS + __MAX_READ_WRITE_TEXTURES

__MAX_LAYOUT_BINDINGS      :: __MAX_CONSTANT_BUFFERS + __MAX_BUFFERS + __MAX_SAMPLED_TEXTURES + __MAX_READ_WRITE_TEXTURES + __MAX_SAMPLERS

// Nuppu limits that make sense for the API. These can be changed if you need more
MAX_CONSTANT_BUFFERS      :: 4
MAX_BUFFERS               :: 4
MAX_SAMPLED_TEXTURES      :: 4
MAX_READ_WRITE_TEXTURES   :: 4
MAX_SAMPLERS              :: 4

MAX_READ_RESOURCE         :: MAX_BUFFERS + MAX_SAMPLED_TEXTURES
MAX_READ_WRITE_RESOURCES  :: MAX_BUFFERS + MAX_READ_WRITE_TEXTURES

MAX_LAYOUT_BINDINGS       :: MAX_CONSTANT_BUFFERS + MAX_BUFFERS + MAX_SAMPLED_TEXTURES + MAX_READ_WRITE_TEXTURES + MAX_SAMPLERS

#assert(MAX_CONSTANT_BUFFERS <= __MAX_CONSTANT_BUFFERS)
#assert(MAX_BUFFERS <= __MAX_BUFFERS)
#assert(MAX_SAMPLED_TEXTURES <= __MAX_SAMPLED_TEXTURES)
#assert(MAX_READ_WRITE_TEXTURES <= __MAX_READ_WRITE_TEXTURES)
#assert(MAX_SAMPLERS <= __MAX_SAMPLERS)
#assert(MAX_READ_RESOURCE <= __MAX_READ_RESOURCE)
#assert(MAX_READ_WRITE_RESOURCES <= __MAX_READ_WRITE_RESOURCES)
#assert(MAX_LAYOUT_BINDINGS <= __MAX_LAYOUT_BINDINGS)

MAX_TEXTURE_SIZE :: 4096

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

_state: ^State

State :: struct #align(64) {
    using impl: _State,

    ctx: runtime.Context,
    is_init: bool,
}

// Resources inside arrays need to be declared in the same order as they are in the shader
// ConstantBuffer -> Texture/StructuredBuffer -> R/W/RWTexture -> Sampler
Parameter_Block :: struct {
    constants           : [MAX_CONSTANT_BUFFERS]ptr,
    read_resources      : [MAX_READ_RESOURCE]Parameter_Resource,
    read_write_resources: [MAX_READ_WRITE_RESOURCES]Parameter_Resource,
    samplers            : [MAX_SAMPLERS]Sampler,
}

Parameter_Resource :: union {
    ptr,
    Texture,
}

Parameter_Block_Destination :: enum {
    Graphics,
    Compute,
}

ptr :: struct #all_or_none {
    cpu: rawptr,
    gpu: rawptr,

    flags: Buffer_Flag,
    alignment: u32,
    total_capacity_bytes: u32,
    byte_offset: u32,

    meta: Metadata,

    using native: _ptr,
}

Buffer_Flag :: enum u32 {
    Staging = 0,  // Host + Device visible

    Default,      // Device local
    Index,        // Device local
    Constant,     // Device local
}

Index_Buffer_Type :: enum u8 {
    Uint16,
    Uint32,
}

Metadata :: struct
{
    name: string,
    created_at: runtime.Source_Code_Location,
}

Arena :: struct {
    using ptr: ptr,
    offset: uint,
}

// Bucket_State :: enum {
//     Mapped,
//     Unmapped,
//     Locked,
// }
// Bucket :: struct {
//     state: Bucket_State,
//     buffer: ptr,
//     cursor: uint,
// }

// Bucket_Arena :: struct($N: int) {
//     buckets: [N]Bucket,
//     bucket_capacity: uint,
// }

// bucket_arena_init :: proc($N: int, capacity: uint, alignment: uint = 16, loc := #caller_location) -> Bucket_Arena(N) {
//     bucket_arena: Bucket_Arena(N)

//     for I in 0 ..< N {
//         _ptr   := _malloc(.Staging, 1, int(capacity), int(alignment), "BUCKET")
//         bucket_arena.buckets[I] = Bucket {
//             state = .Mapped,
//             cursor = 0,
//             buffer = ptr {
//                 native = _ptr,
//                 cpu    = _cpu_address(_ptr),
//                 gpu    = _gpu_address(_ptr),
//                 meta = Metadata {
//                     name = "BUCKET",
//                     created_at = loc,
//                 },
//             }
//         }
//     }

//     bucket_arena.bucket_capacity = capacity
//     return bucket_arena
// }

// // Sub-allocates within the first chunk in `mapped` that has space.
// // Returns the view (cpu/gpu pointers set) and the byte length of the
// // allocation. Chunks that don't yet satisfy alignment, are full, or
// // haven't finished remapping on WGPU (the BufferMapAsync callback has
// // not yet fired) are skipped.
// @(require_results)
// bucket_arena_alloc :: proc(arena: ^Bucket_Arena($N), el_size, el_count, align: uint) -> ptr {
//     bytes := el_size * el_count

//     for &bucket in arena.buckets {
//         if bucket.state != .Mapped { continue }
//         if uintptr(bucket.buffer.cpu) % uintptr(align) != uintptr(bucket.buffer.gpu) % uintptr(align) {
//             continue
//         }

//         alignment := max(uint(align), uint(_min_alignment(bucket.buffer)))
//         bytes_aligned := runtime.align_forward_uint(uint(bytes), alignment)

//         temp := mem.align_forward_uint(bucket.cursor, alignment)
//         if temp + bytes_aligned > arena.bucket_capacity {
//             continue
//         }

//         bucket.cursor = temp + bytes_aligned
//         return sub_alloc(bucket.buffer, temp, bytes_aligned)
//     }

//     panic("Bucket_Arena: out of space (all chunks full or remap pending)")
// }

// // Unmap any chunk that had `cursor > 0` (i.e. CPU wrote to it this frame)
// // and move it from `mapped` to `dirty`. Chunks with `cursor == 0` stay in
// // `mapped` untouched. Removal is done after a pre-pass to avoid
// // mutating-while-iterating.
// bucket_arena_finish :: proc(arena: ^Bucket_Arena($N)) {
//     for &chunk in arena.buckets {
//         if chunk.cursor > 0 && chunk.state == .Mapped {
//             _unmap(&chunk.buffer.native)
//             chunk.state = .Unmapped
//         }
//     }
// }

// // Move every `locked` chunk back into `mapped`, reset its cursor, and
// bucket_arena_recall :: proc(arena: ^Bucket_Arena($N)) {
//     _bucket_arena_kick_remap(arena)
// }

Shader :: struct {
    using native: _Shader,
}

Shader_IR :: struct {
    shader: Shader,
    entry_point: string,
}

Shader_Stage :: enum u8 {
    Vertex,
    Fragment,
    Compute,
}

Sampler :: struct {
    using native: _Sampler,
}

Sampler_Min_Mag_Filter :: enum u8 {
	Nearest = 0,
	Linear,
}

Sampler_Mip_Filter :: enum u8 {
	NotMipmapped = 0,
	Nearest,
	Linear,
}

Sampler_Address_Mode :: enum u8 {
	ClampToEdge  = 0,
	MirrorRepeat,
	Repeat,
}

Sampler_Descriptor :: struct {
    min_filter: Sampler_Min_Mag_Filter,
    mag_filter: Sampler_Min_Mag_Filter,
    mip_filter: Sampler_Mip_Filter,
    wrap_s: Sampler_Address_Mode,
    wrap_t: Sampler_Address_Mode,
    wrap_r: Sampler_Address_Mode,
}

Texture :: struct {

    using native: _Texture,
}

Texture_Type :: enum u8 {
    _2D,
    _2D_Array,
}

Texture_Descriptor :: struct #all_or_none {
    dimensions: [2]u32,
    format: Pixel_Format,
    storage: StorageMode,
    usage: Texture_Usage,
    type: Texture_Type,
    layer_count: u32, // 0 == 1
}

StorageMode :: enum u8 {
	Shared     = 0,
	Private    = 2,
}

Texture_Usage_Flag :: enum {
    Sampled,
    Read,
    Write,
    Color_Attachment,
    Depth_Attachment,
}
Texture_Usage :: bit_set[Texture_Usage_Flag; u8]

Color :: [4]u8

Pixel_Format :: enum u8 {
    None,
    BGRA8Unorm,
    RGBA8Unorm,
    RGBA32Float,
    Depth32Float,
}

Timeline_Semaphore :: distinct rawptr

Stage :: enum u8 {
    Transfer         = 0,
    Compute          = 1,
    All              = 6,
}

Color_Attachment :: struct {
    clear_color: Color,
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
    resolve_texture: Texture,
}

Depth_Attachment :: struct {
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
}

Depth_Stencil_State :: struct {
    using native: _Depth_Stencil_State,
}   

Depth_Stencil_State_Descriptor :: struct {
	write_enabled: bool,
	compare: Compare_Function,
}

Compare_Function :: enum u8 {
    Never = 0x00000001,
    Less = 0x00000002,
    Equal = 0x00000003,
    LessEqual = 0x00000004,
    Greater = 0x00000005,
    NotEqual = 0x00000006,
    GreaterEqual = 0x00000007,
    Always = 0x00000008,
}

Load_Action :: enum u8 {
    Dont_Care,
    Clear,
    Load,
}

Store_Action :: enum u8 {
    Dont_Care,
    Store,
}

Pipeline :: struct {
    using native: _Pipeline,
}

Compute_Pipeline :: struct {
    using native: _Compute_Pipeline,
}

Pipeline_Descriptor :: struct {
    color_format: Pixel_Format,
    depth_format: Pixel_Format,
}

Front_Face :: enum i32 {
    CCW = 0x00000001,
    CW = 0x00000002,
}

Cull_Mode :: enum i32 {
    None = 0x00000001,
	Front = 0x00000002,
	Back = 0x00000003,
}

Multisample_State :: struct {
    count: u32,
    mask: u32,
}

Primitive_Type :: enum u8 {
    Triangle      = 3,
}

Blend_State :: struct {
    color: Blend_Component,
	alpha: Blend_Component,
}

Blend_Component :: struct {
	operation: Blend_Operation,
	srcFactor: Blend_Factor,
	dstFactor: Blend_Factor,
}

Blend_Operation :: enum i32 {
	Add = 0x00000000,
	Subtract = 0x00000001,
	ReverseSubtract = 0x00000002,
	Min = 0x00000003,
	Max = 0x00000004,
}

Blend_Factor :: enum i32 {
	Undefined = 0x00000000,
	Zero = 0x00000001,
	One = 0x00000002,
	Src = 0x00000003,
	OneMinusSrc = 0x00000004,
	SrcAlpha = 0x00000005,
	OneMinusSrcAlpha = 0x00000006,
	Dst = 0x00000007,
	OneMinusDst = 0x00000008,
	DstAlpha = 0x00000009,
	OneMinusDstAlpha = 0x0000000A,
	SrcAlphaSaturated = 0x0000000B,
	Constant = 0x0000000C,
	OneMinusConstant = 0x0000000D,
	Src1 = 0x0000000E,
	OneMinusSrc1 = 0x0000000F,
	Src1Alpha = 0x00000010,
	OneMinusSrc1Alpha = 0x00000011,
}

init :: proc(state: ^State, native_window: rawptr) -> bool {
    if _state != nil {
        return true
    }

    _state = state
    _state.ctx = context

    success := _init(native_window)

    return success
}

deinit :: proc() {
    if _state == nil {
        return
    }
    
    _deinit()
    
    // destroy resources and other stuff

    _state = nil
}

is_init :: proc() -> bool {
    return _state.is_init
}

resize_swapchain :: proc(width, height: u32) {
    _resize_swapchain(width, height)
}

release_texture :: proc(texture: ^Texture) {
    _release_texture(texture)
}

release_ptr :: proc(ptr: ^ptr) {
    _release_ptr(ptr)
}

// CPU side copy
copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
    _copy_to_texture(texture, origin, size, level, data, bytes_per_row)
}

depth_stencil_state_init :: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State {
    _depth_pso := _depth_stencil_state_init(desc)

    return Depth_Stencil_State {
        native = _depth_pso,
    }
}

shader_init :: proc(name: string, code: []u8) -> Shader {
    native := _shader_init(name, code)

    return Shader {
        native = native,
    }
}

pipeline_init :: proc(vertex, fragment: Shader_IR, pipeline_descriptor: Pipeline_Descriptor) -> Pipeline {
    assert(vertex.entry_point != "")
    assert(fragment.entry_point != "")
    assert(pipeline_descriptor.color_format != .None)

    native := _pipeline_init(vertex, fragment, pipeline_descriptor)

    return Pipeline {
        native = native,
    }
}

compute_pipeline_init :: proc(shader: Shader, entry_point: string) -> Compute_Pipeline {
    native := _compute_pipeline_init(shader, entry_point)

    result := Compute_Pipeline {
        native = native,
    }

    return result
}

begin_commands :: proc() {
    _begin_commands()
}

commit_commands :: proc() {
    _commit_commands()
}

begin_frame :: proc() {
    _begin_frame()
}

end_frame :: proc(semaphore: Timeline_Semaphore, frame_n: u64) {
    _end_frame(semaphore, frame_n)
}

acquire_next_swapchain :: proc() -> Texture {
    native := _acquire_next_swapchain()

    return Texture {
        native = native,
    }
}

compute_dispatch :: proc(num_groups: [3]u32, num_threads_per_group: [3]u32) {
    _compute_dispatch(num_groups, num_threads_per_group)
}

set_compute_pipeline :: proc(compute_pipeline: Compute_Pipeline) {
    _set_compute_pipeline(compute_pipeline)
}

set_pipeline :: proc(pipeline: Pipeline) {
    _set_pipeline(pipeline)
}

sampler_init :: proc(desc: Sampler_Descriptor) -> Sampler {
    native := _sampler_init(desc)
    
    return Sampler {
        native = native,
    }
}

texture_init :: proc(desc: Texture_Descriptor) -> Texture {
    assert(desc.dimensions.x <= MAX_TEXTURE_SIZE)
    assert(desc.dimensions.y <= MAX_TEXTURE_SIZE)
    native := _texture_init(desc)

    tex := Texture { native = native }

    return tex
}

texture_depth_init :: proc(dimensions: [2]u32, format: Pixel_Format) -> Texture {
    desc := Texture_Descriptor {
        dimensions = dimensions,
        format = format,
        usage = {.Depth_Attachment},
        storage = .Private,
        type = ._2D,
        layer_count = 1,
    }
    return texture_init(desc)
}

set_depth_stencil_state :: proc(depth_stencil_state: Depth_Stencil_State) {
    _set_depth_stencil_state(depth_stencil_state)
}

begin_render_pass :: proc(color_attachment: Color_Attachment, depth_attachment: Depth_Attachment = {}) {
    _begin_render_pass(color_attachment, depth_attachment)
}

end_render_pass :: proc() {
    _end_render_pass()
}

set_cull_mode :: proc(cull_mode: Cull_Mode) {
    _set_cull_mode(cull_mode)
}

set_front_face_winding :: proc(winding: Front_Face) {
    _set_front_face_winding(winding)
}

when ODIN_OS != .JS {
// Push struct to buffer
temp_malloc :: proc(bytes: []u8, buffer_index: u32, shader_stage: Shader_Stage) {
    _temp_malloc(bytes, buffer_index, shader_stage)       
}
}

draw_indiced_primitives :: proc(parameter_block: ^Parameter_Block, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
    _draw_indiced_primitives(parameter_block, .Triangle, index_buffer, index_count, index_offset, instance_count, base_vertex, base_instance, .Uint16)
}

// Allocate a buffer of the given type.
//   - .Staging     returns ptr with valid .cpu; caller fills data then calls copy() + unmap()
//   - .GPU_*       returns ptr with .cpu=nil; receive data via copy() from a Staging buffer
//   - .Readback    returns ptr with .cpu=nil; receive data via copy()
malloc :: proc(
    bytes: u32,
    alignment:   u32,
    flag: Buffer_Flag,
    name:        string     = "",
    loc:                    = #caller_location,
) -> (ptr, bool) {

    if min_alignment := _min_alignment(flag); alignment < min_alignment {
        log.errorf("In malloc() passed in alignment %i is less than the minimum required for flags %v. Bump to %i", alignment, flag, min_alignment)
        return {}, false
    }
    
    capacity := runtime.align_forward(uint(bytes), uint(alignment))

    _ptr := _malloc(bytes, alignment, flag, name, loc)

    return ptr {
        native = _ptr,
        cpu    = _cpu_address(_ptr) if flag == .Staging else nil,
        gpu    = _gpu_address(_ptr),
        flags = flag,
        alignment = alignment,
        total_capacity_bytes = u32(capacity),
        byte_offset = 0,
        meta   = Metadata {
            name = strings.clone(name, context.allocator),
            created_at = loc,
        },
    }, true
}

// Release the mapping on a Staging buffer. Must be called before doing any copy() operations on the buffer.
unmap :: proc(ptr: ^ptr) {
    _unmap(&ptr.native)
}

// Copies src data into dst
copy :: proc(dst, src: ptr) {
    _copy(dst, src)
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
    // assert(_mapped(arena.ptr)) IF staging buffer
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

// Sets shader's parameter block to be used for the next draw call.
use_parameter_block :: proc(block: ^Parameter_Block, destination: Parameter_Block_Destination = .Graphics) {
    _use_parameter_block(block, destination)
}

// Ends before stage
barrier :: proc(before: Stage, after: Stage) {
    _barrier(before, after)
}

semaphore :: proc(value: u64) -> Timeline_Semaphore {
    return _semaphore(value)
}

semaphore_wait :: proc(semaphore: Timeline_Semaphore, value: u64) -> bool {
    return _semaphore_wait(semaphore, value)
}


bit_set_to_another :: proc(input: $T/bit_set[$TT; $TI], $Out: typeid, interop: proc(TT) -> $O) -> (result: Out) {
    for f in input { result |= {interop(f)} }
    return
}

from_4xu8_to_4xf64_color :: proc(input: [4]u8) -> [4]f64 {
    return [4]f64 {
        f64(input[0]) / 255.0,
        f64(input[1]) / 255.0,
        f64(input[2]) / 255.0,
        f64(input[3]) / 255.0,
    }
}
