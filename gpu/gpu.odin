#+vet explicit-allocators shadowing unused
package nuppu_gpu

import "base:runtime"
import "core:mem"
import "core:log"
import hm "core:container/handle_map"
//import "core:slice"
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

MAX_RESOURCES :: 1 << 16 - 2

MAX_PIPELINES :: 64
MAX_SHADERS :: 64

Shader_Handle :: distinct hm.Handle32
Pipeline_Handle :: distinct hm.Handle32

State :: struct #align(64) {
    using impl: _State,

    ctx: runtime.Context,
    is_init: bool,

    frame_arenas: [dynamic; FRAMES_IN_FLIGHT]^Arena,
    frame_n: u64,

    resources: Resource_Library(MAX_RESOURCES),

    pipelines: hm.Static_Handle_Map(MAX_PIPELINES, Pipeline_Descriptor, Pipeline_Handle),    
    shaders: hm.Static_Handle_Map(MAX_SHADERS, Shader, Shader_Handle),
}

_state: ^State


/*
Resource = Generally anything that gets stored in GPU memory

API gives and recieves Resource_Handles and their specialications
*/

Resource_Handle :: distinct hm.Handle32

Resource_Library :: struct($N: uint)
{
    is_init: bool,
    resources: hm.Static_Handle_Map(N, Resource, Resource_Handle),
}

Resource :: struct
{
    using info: _Resource,
    handle: Resource_Handle,
    meta: Metadata,
    kind: Resource_Kind,
}

Resource_Kind :: enum u8 {
    Index_Buffer,
    Buffer,
}

Metadata :: struct
{
    name: string,
    created_at: runtime.Source_Code_Location,
}

resource_library_init :: proc(library: ^Resource_Library($N)) {
    library.is_init = true
}

@(require_results)
resource_add :: proc(library: ^Resource_Library($N), res: Resource) -> (handle: Resource_Handle, ok: bool) #optional_ok {
    handle, ok = hm.static_add(&library.resources, res)
    return
}

resource_remove :: proc(library: ^Resource_Library($N), handle: $T/Resource_Handle) -> (ok: bool) {
    ok = hm.static_remove(&library.resources, Resource_Handle(handle))
    return
}

@(require_results)
resource_get :: proc(library: ^Resource_Library($N), handle: $T/Resource_Handle) -> (result: ^Resource, ok: bool) #optional_ok {
    result, ok = hm.static_get(&library.resources, Resource_Handle(handle))
    return
}

/////

// Linear bump arena

// Linear bump arena used in rendering loop. Automatically recycled after use
// Should only be used in the render loop
@(deferred_out=recycle_frame_arena)
frame_arena :: proc() -> ^Arena {
    return _frame_arena()
}

recycle_frame_arena :: proc(arena: ^Arena) {
    _recycle_frame_arena(arena)
}

// 'Allocates' slice from upload or frame arena.
// Just moves arena's offset forward and return slice to the slice that was allocated
// Returned slice's raw data points to cpu pointer given by the arena's buffer


// destroy_arena :: proc(arena: ^Arena) {
//     destroy_res(arena.handle)
//     arena^ = {}
// }


destroy_res :: proc(handle: $T/Resource_Handle) {
    res := resource_get(&_state.resources, handle)
    _destroy_res(res.info, res.kind)
    resource_remove(&_state.resources, handle)
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

init :: proc(state: ^State, native_window: rawptr) -> bool {
    if _state != nil {
        return true
    }

    _state = state
    _state.ctx = context

    resource_library_init(&_state.resources)

    return _init(native_window)
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



acquire_next_swapchain :: proc() -> Texture {
    return _acquire_next_swapchain()
}

begin_render_pass :: proc(color_attachment: Color_Attachment) {
    _begin_render_pass(color_attachment)
}

end_render_pass :: proc() {
    _end_render_pass()
}



resize_swapchain :: proc(width, height: i32) -> bool {
    return _resize_swapchain(width, height)
}

when ODIN_OS != .JS {
temp_malloc :: proc(bytes: []u8, buffer_index: u32, shader_stage: Shader_Stage) {
    _temp_malloc(bytes, buffer_index, shader_stage)       
}

use_resources :: proc(resource_list: []Shader_Resource) {
    _use_resources(resource_list)
}
}

bit_set_to_another :: proc(input: $T/bit_set[$TT; $TI], $Out: typeid, interop: proc(TT) -> $O) -> (result: Out) {
    for f in input { result |= {interop(f)} }
    return
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

pipeline_init :: proc(vertex_shader: Shader_Handle, vertex_function: string, fragment_shader: Shader_Handle, fragment_function: string, format: Pixel_Format) -> Pipeline_Handle {
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
    handle: Shader_Handle,
    using impl: _Shader,
}



Shader_Stage :: enum u8 {
    Vertex,
    Fragment,
    Compute,
}

Render_Stage :: enum u8 {
    Vertex,
    Fragment,
    Tile,
    Object,
    Mesh,
}
Render_Stages :: distinct bit_set[Render_Stage; u8]

shader_init :: proc(name: string, code: []u8) -> Shader_Handle {
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


// Note cut into Desctiptor + implementation later
Pipeline_Descriptor :: struct {
    handle: Pipeline_Handle,

    vertex_shader:   Shader_Handle, vertex_function:   string,
    fragment_shader: Shader_Handle, fragment_function: string, 
  
    multisample: Multisample_State,

    blend: Blend_State,
    
    format: Pixel_Format,

    primitive: Primitive_State,

    buffers: [8]ptr,

    index_buffer: ptr,
}

Primitive_State :: struct {
    topology: Primitive_Type,
    cull_mode: Cull_Mode,
    front_face: Front_Face,
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





set_pipeline :: proc(pipeline: Pipeline_Handle) {
    _set_pipeline(pipeline)
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

set_buffers :: proc(buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
    _set_buffers(buffers, offsets, range, stage)
}

draw_indiced_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
    _draw_indiced_primitives(primitive, index_buffer, index_count, index_offset, instance_count, base_vertex, base_instance)
}

/*********************/

commit :: proc() {
    _commit()
}

begin_frame_or_commands :: proc() {
    _begin_frame()
}

end_frame :: proc() {
    _end_frame()
}


    Role :: enum u8 {
        Default,
        Index,
    }

    Memory :: enum u8 {
        Default,
        GPU,
        Readback,
    }

copy :: proc(dst, src: ptr) {
    _mem_copy(
            dst = dst,
            src = src,
    )
}


barrier :: proc(before: Stage, after: Stage) {
when GPU_BACKEND != GPU_BACKEND_WGPU {
    _barrier(before, after)
// Not needed on WGPU
}
}

// reserve (create gpu only buffer with bytes + align)
// view (current ptr approach, view into a reserve buffer)

Mem :: enum u8 {
    Default,  // CPU visible exposed cpu ptr. Used as staging on copy source into GPU buffers or copy destination with Readback
    GPU,      // GPU private, data can be copied into this buffer
    Readback, // GPU private, data can be copied into cpu array from from buffer
}

    Buffer_Kind :: enum u8 {
        Buffer,
        Index_Buffer,
    }

malloc :: proc {
    malloc_raw,
    malloc_T,
}

malloc_T :: proc($T: typeid, el_count: int, m: Mem, name: string = {}, loc := #caller_location) -> ptr {
    alignment := align_of(T)
    return malloc_raw(size_of(T), el_count, alignment, m, name, loc)
}

malloc_raw :: proc(el_size, el_count, alignment: int, m: Mem, name: string = {}, loc := #caller_location) -> ptr {
    size := runtime.align_forward_int(el_size * el_count, alignment)
    
    _ptr := _malloc(size, alignment, m, name)
    
    return ptr {
        cpu = nil,
        gpu = nil,
        native = _ptr,
        kind = .Buffer,
        meta = Metadata {
            name = strings.clone(name, context.allocator),
            created_at = loc,
        }
    }
}

Index_Type :: enum u8 {
    Uint16,
    Uint32,
}

malloc_index :: proc(el_count: int, type: Index_Type, name: string = {}, loc := #caller_location) -> ptr {
    el_size: int
    switch type {
    case .Uint16:
        el_size = 2
    case .Uint32:
        el_size = 4
    }

    _ptr := _malloc_index(uint(el_count), uint(el_size), name, loc)

    return ptr {
        cpu = nil,
        gpu = nil,
        native = _ptr,
        kind = .Index_Buffer,
        meta = Metadata {
            name = strings.clone(name, context.allocator),
            created_at = loc,
        }
    }
}

// Mapped buffer

malloc_mapped :: proc {
    malloc_raw_mapped,
    malloc_mapped_T,
}

// Malloc Default buffer that is returned in mapped state. You must unmap before copying data out of it!
malloc_mapped_T :: proc($T: typeid, el_count: int, name: string = {}, loc := #caller_location) -> ptr {
    alignment := align_of(T)
    malloc_raw_mapped(size_of(T), el_count, alignment, name, loc)
}

malloc_raw_mapped :: proc(
    el_size, el_count, alignment: int, 
    name: string = {}, 
    loc := #caller_location
) -> ptr {
    size := runtime.align_forward_int(el_size * el_count, alignment)

    _ptr := _malloc_mapped(size, alignment, name, loc)
    cpu_ptr, gpu_ptr := _map_range(_ptr, uint(size))

    return ptr {
        native = _ptr,
        cpu = cpu_ptr,
        gpu = gpu_ptr,
        kind = .Buffer,
        meta = Metadata {
            name = strings.clone(name, context.allocator),
            created_at = loc,
        }
    }
}

unmap :: proc(ptr: ptr) {
    assert(ptr.kind == .Buffer || ptr.kind == .Index_Buffer)
    _unmap(ptr.native)
}

// Arena

Arena :: struct {
    ptr: ptr,
    is_mapped: bool,
    offset: uint,
    capacity: uint,
}

ptr :: struct #all_or_none {
    cpu: rawptr,
    gpu: rawptr,

    kind: Buffer_Kind,
    meta: Metadata,

    using native: _ptr,
}

arena :: proc(
    #any_int size: uint      = 4 * 1024 * 1024,
    #any_int alignment: uint = 16,
    loc:                     = #caller_location
) -> Arena {
    arena: Arena

    bytes := runtime.align_forward_uint(size, alignment)
    _ptr := _malloc_mapped(bytes, alignment, "ARENA", loc)
    cpu_ptr, gpu_ptr := _map_range(_ptr, bytes)

    arena.ptr = {
        meta = Metadata {
            name = "ARENA",
            created_at = loc,
        },
        kind = .Buffer,
        native = _ptr,
        cpu = cpu_ptr,
        gpu = gpu_ptr,
    }
    arena.is_mapped = true
    arena.offset = 0
    arena.capacity = bytes

    return arena
}

arena_alloc_raw :: proc(arena: ^Arena, el_size, el_count, alignment: uint) -> ptr {
    assert(arena.is_mapped)
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

arena_alloc :: proc(arena: ^Arena, $T: typeid, el_count: uint = 1) -> ptr {
    assert(arena.is_mapped)

    temp := arena_alloc_raw(arena, size_of(T), el_count, align_of(T))

    // []T from aligned offset before bytes are added in
    // s := slice.from_ptr((^T)(temp.cpu), int(el_count))
    
    return temp
}