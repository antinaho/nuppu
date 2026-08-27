#+vet explicit-allocators shadowing unused
package nuppu_gpu

import "base:runtime"
import "core:mem"
import "core:log"
import hm "core:container/handle_map"
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

FRAMES_IN_FLIGHT :: 3
FRAME_ARENA_SIZE :: 4 * 1024 * 1024

// Resources inside arrays need to be declared in the same order
// as they are in the shader
Parameter_Block :: struct {
    constants           : [MAX_CONSTANTS]ptr,
    read_resources      : [MAX_READ_RESOURCE]Parameter_Resource,
    read_write_resources: [MAX_READ_WRITE_RESOURCES]Parameter_Resource,
    samplers            : [MAX_SAMPLERS]Sampler,
}

Parameter_Resource :: union {
    ptr,
    Texture,
}

Parameter_Destination :: enum {
    Graphics,
    Compute,
}

use_parameter_block :: proc(block: ^Parameter_Block, destination: Parameter_Destination = .Graphics) {
    _use_parameter_block(block, destination)
}

// Limits based of WGSL https://www.w3.org/TR/WGSL/#limits
// Should be good for rest of the APIs?

MAX_STORAGE_BUFFERS :: 8 // Shared between read + read_write
READ_TEXTURES :: 16
READ_WRITE_TEXTURES :: 4

MAX_CONSTANTS :: 12
MAX_READ_RESOURCE :: MAX_STORAGE_BUFFERS + READ_TEXTURES
MAX_READ_WRITE_RESOURCES :: MAX_STORAGE_BUFFERS + READ_WRITE_TEXTURES
MAX_SAMPLERS :: 16

MAX_LAYOUT_BINDINGS :: MAX_CONSTANTS + MAX_STORAGE_BUFFERS + READ_TEXTURES + READ_WRITE_TEXTURES + MAX_SAMPLERS

State :: struct #align(64) {
    using impl: _State,

    ctx: runtime.Context,
    is_init: bool,

    frame_semaphore: Semaphore,
    frame_arenas: [dynamic; FRAMES_IN_FLIGHT]^Arena,
    frame_n: u64,

    depth_texture: Texture,
}

Depth_Stencil_Handle :: distinct hm.Handle16
MAX_DEPTH_STENCIL_STATES :: 8

_state: ^State


Metadata :: struct
{
    name: string,
    created_at: runtime.Source_Code_Location,
}

Shader :: struct {
    using native: _Shader,
}

depth :: proc() -> Texture {
    return _state.depth_texture
}

init :: proc(state: ^State, native_window: rawptr) -> bool {
    if _state != nil {
        return true
    }

    _state = state
    _state.ctx = context
    _state.frame_n = 1

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

resize_depth :: proc(width, height: u32) {
    _resize_depth_texture(width, height)
}


Pixel_Format :: enum u8 {
    None,
    BGRA8Unorm,
    Depth32Float,
}



MAX_TEXTURE_SIZE :: 4096



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





Shader_Stage :: enum u8 {
    Vertex,
    Fragment,
    Compute,
}

// CPU side copy
copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
    _copy_to_texture(texture, origin, size, level, data, bytes_per_row)
}

Color_Attachment :: struct {
    clear_color: Color,
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
    resolve_texture: Texture,
}

Shader_IR :: struct {
    shader: Shader,
    entry_point: string,
}

Pipeline_Descriptor :: struct {
    color_format: Pixel_Format,
    depth_format: Pixel_Format,
}

    // multisample: Multisample_State,
    // blend: Blend_State,
    // primitive: Primitive_State,
    // buffers: [8]ptr,
    // textures: [8]Texture,
    // samplers: [8]Sampler,
    // index_buffer: ptr,

Depth_Stencil_State :: struct {
    using native: _Depth_Stencil_State,
}   

Depth_Stencil_State_Descriptor :: struct {
	write_enabled: bool,
	compare: Compare_Function,
	// stencilFront: StencilFaceState,
	// stencilBack: StencilFaceState,
	// stencilReadMask: u32,
	// stencilWriteMask: u32,
	// depthBias: i32,
	// depthBiasSlopeScale: f32,
	// depthBiasClamp: f32,
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

Primitive_State :: struct {
    topology: Primitive_Type,
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

depth_stencil_state_init :: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State {
    _depth_pso := _depth_stencil_state_init(desc)

    return Depth_Stencil_State {
        native = _depth_pso,
    }
}

Stage :: enum u8 {
    Transfer         = 0,
    Compute          = 1,
    All              = 6,
}

Range :: struct {
    location: u32,
    length:  u32,
}

Primitive_Type :: enum u8 {
    Triangle      = 3,
}

Buffer_Type :: enum u8 {
    Staging,       // CPU visible, mapped at creation; GPU reads as copy source
    GPU_Storage,   // Device-local; bindable as storage buffer
    GPU_Constant,  // Device-local; bindable as uniform buffer
    GPU_Index,     // Device-local; bindable as index buffer
    Readback,      // CPU visible; GPU writes via copy; CPU reads after fence
}

Index_Type :: enum u8 {
    Uint16,
    Uint32,
}

Arena :: struct {
    ptr: ptr,
    offset: uint,
    capacity: uint,
}

ptr :: struct #all_or_none {
    cpu: rawptr,
    gpu: rawptr,

    meta: Metadata,

    using native: _ptr,
}

//////////////////////////////////////////////////////////////
// Render primitive initialization

shader_init :: proc(name: string, code: []u8) -> Shader {
    native := _shader_init(name, code)

    return Shader {
        native = native,
    }
}

compute_shader_init :: proc(name: string, code: []u8) -> Shader {
    return shader_init(name, code)
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

Pipeline :: struct {
    using native: _Pipeline,
}


Compute_Pipeline :: struct {
    using native: _Compute_Pipeline,
}

compute_pipeline_init :: proc(shader: Shader, entry_point: string) -> Compute_Pipeline {
    native := _compute_pipeline_init(shader, entry_point)

    result := Compute_Pipeline {
        native = native,
    }

    return result
}

//////////////////////////////////////////////////////////////
// Command flow (init, runtime uploads): no swapchain interaction

begin_commands :: proc() {
    _begin_commands()
}

commit_commands :: proc() {
    _commit_commands()
}

//////////////////////////////////////////////////////////////
// Frame flow (render loop): owns the swapchain present

begin_frame :: proc() {
    _begin_frame()
}

end_frame :: proc() {
    _end_frame()
    _state.frame_n += 1
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

Sampler :: struct {
    using native: _Sampler,
}

Sampler_Min_Mag_Filter :: enum u8 {
	Nearest = 0,
	Linear  = 1,
}

Sampler_Mip_Filter :: enum u8 {
	NotMipmapped = 0,
	Nearest      = 1,
	Linear       = 2,
}

Sampler_Address_Mode :: enum u8 {
	ClampToEdge  = 0,
	MirrorRepeat = 1,
	Repeat       = 2,
}

Sampler_Descriptor :: struct {
    min_filter: Sampler_Min_Mag_Filter,
    mag_filter: Sampler_Min_Mag_Filter,
    mip_filter: Sampler_Mip_Filter,
    wrap_s: Sampler_Address_Mode,
    wrap_t: Sampler_Address_Mode,
    wrap_r: Sampler_Address_Mode,
}

sampler_init :: proc(desc: Sampler_Descriptor) -> Sampler {
    native := _sampler_init(desc)
    
    return Sampler {
        native = native,
    }
}

Depth_Attachment :: struct {
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
}

Texture_Descriptor :: struct #all_or_none {
    dimensions: [2]u32,
    format: Pixel_Format,
    storage: StorageMode,
    usage: Texture_Usage,
    type: Texture_Type,
}

StorageMode :: enum u8 {
	Shared     = 0,
	Private    = 2,
}

Texture_Usage :: enum u8 {
    Sampled,
    Storage,
    Color_Attachment,
    Depth_Attachment,
}

Texture :: struct {
    using native: _Texture,
}

Texture_Type :: enum u8 {
    _2D,
}

texture_depth_init :: proc(dimensions: [2]u32, format: Pixel_Format) -> Texture {
    desc := Texture_Descriptor {
        dimensions = dimensions,
        format = format,
        usage = .Depth_Attachment,
        storage = .Private,
        type = ._2D,
    }
    return texture_init(desc)
}

texture_init :: proc(desc: Texture_Descriptor) -> Texture {
    native := _texture_init(desc)

    tex := Texture { native = native }

    return tex
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

draw_indiced_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
    _draw_indiced_primitives(primitive, index_buffer, index_count, index_offset, instance_count, base_vertex, base_instance)
}

//////////////////////////////////////////////////////////////
// Memory

// Allocate a buffer of the given type.
//   - .Staging     returns ptr with valid .cpu; caller fills data then calls copy() + unmap()
//   - .GPU_*       returns ptr with .cpu=nil; receive data via copy() from a Staging buffer
//   - .Readback    returns ptr with .cpu=nil; receive data via copy()

when ODIN_OS == .Darwin {
    BUFFER_PTR :: true
} else {
    BUFFER_PTR :: false
}

malloc :: proc(
    type:        Buffer_Type,
    el_count:    int,
    el_size:     int        = 1,
    alignment:   int        = 1,
    name:        string     = "",
    loc:                    = #caller_location,
) -> ptr {
    _ptr := _malloc(type, el_count, el_size, alignment, name)

    if type == .Staging {
        cpu_ptr, gpu_ptr := _map(&_ptr)
        return ptr {
            native = _ptr,
            cpu    = cpu_ptr,
            gpu    = gpu_ptr,
            meta   = Metadata {
                name = strings.clone(name, context.allocator),
                created_at = loc,
            },
        }
    }

    result := ptr {
        native = _ptr,
        cpu    = nil,
        gpu    = _gpu_address(_ptr),
        meta   = Metadata {
            name = strings.clone(name, context.allocator),
            created_at = loc,
        },
    }

    return result
}

// Helper for creating index buffer
malloc_index :: proc(el_count: int, type: Index_Type, name: string = {}, loc := #caller_location) -> ptr {
    el_size: int
    switch type {
    case .Uint16:
        el_size = 2
    case .Uint32:
        el_size = 4
    }

    return malloc(.GPU_Index, el_count, el_size, el_size, name, loc)
}

// Release the mapping on a Staging buffer. Must be called before doing any copy() operations on the buffer.
unmap :: proc(ptr: ^ptr) {
    _unmap(&ptr.native)
}

// Copies src data into dst
copy :: proc(dst, src: ptr) {
    _copy(
        dst,
        src,
    )
}

//////////////////////////////////////////////////////////////
// Arena

/*
Linear bump arena that allocates staging buffer. Helps if multiple types of staging data is needed to be copied simultaneously.
*/

arena :: proc(
    #any_int size: uint      = 4 * 1024 * 1024,
    #any_int alignment: uint = 16,
    loc:                     = #caller_location
) -> Arena {
    arena: Arena

    bytes := runtime.align_forward_uint(size, alignment)
    _ptr := _malloc(.Staging, 1, bytes, alignment, "ARENA")
    cpu_ptr, gpu_ptr := _map(&_ptr)

    arena.ptr = {
        meta = Metadata {
            name = "ARENA",
            created_at = loc,
        },
        native = _ptr,
        cpu = cpu_ptr,
        gpu = gpu_ptr,
    }
    arena.offset = 0
    arena.capacity = bytes

    return arena
}

// Returns ptr with correct field values.
arena_alloc_raw :: proc(arena: ^Arena, el_size, el_count, alignment: uint) -> ptr {
    assert(_mapped(arena.ptr))
    assert(arena.ptr.cpu != nil)
    bytes := el_size * el_count
    assert(bytes >= 0 && alignment > 0)
    bytes_aligned := runtime.align_forward_uint(uint(bytes), uint(alignment))

    if uintptr(arena.ptr.cpu) % uintptr(alignment) != uintptr(arena.ptr.gpu) % uintptr(alignment) {
        panic("Could not satisfy alignment requirements in GPU arena allocation.")
    }

    arena.offset = mem.align_forward_uint(arena.offset, uint(alignment))
    temp := arena.offset
    if arena.offset + bytes_aligned > arena.capacity {
        panic("Arena: out of space")
    }
    arena.offset += bytes_aligned

    ptr := _sub_alloc(arena.ptr, temp, bytes_aligned)

    return ptr
}

// Helper for arena alloc
arena_alloc :: proc(arena: ^Arena, $T: typeid, el_count: uint = 1) -> ptr {
    assert(_mapped(arena.ptr))
    temp := arena_alloc_raw(arena, size_of(T), el_count, align_of(T))

    // []T from aligned offset before bytes are added in
    // s := slice.from_ptr((^T)(temp.cpu), int(el_count))
    
    return temp
}

// Same as arena() with automatic recycling after use. Always get mapped buffer for render frame.
// Must be unmapped before copy, just like normal arena.
@(deferred_out=recycle_frame_arena)
frame_arena :: proc() -> ^Arena {
    return _frame_arena()
}

recycle_frame_arena :: proc(arena: ^Arena) {
    _recycle_frame_arena(arena)
}

//////////////////////////////////////////////////////////////
// Synchronization

// Ends before stage
barrier :: proc(before: Stage, after: Stage) {
    _barrier(before, after)
}

Semaphore :: distinct rawptr

semaphore :: proc(value: u64) -> Semaphore {
    return _semaphore(value)
}

semaphore_wait :: proc(semaphore: Semaphore, value: u64) -> bool {
    return _semaphore_wait(semaphore, value)
}

//////////////////////////////////////////////////////////////
// Misc

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