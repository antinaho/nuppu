#+vet explicit-allocators shadowing unused
package nuppu_gpu

import "base:runtime"
import "core:log"
import "core:strings"
import "core:mem"
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

// Bump these if you need more 
MAX_CONSTANT_BUFFERS      :: 4
MAX_BUFFERS               :: 6
MAX_SAMPLED_TEXTURES      :: 4
MAX_READ_WRITE_TEXTURES   :: 4
MAX_SAMPLERS              :: 4

MAX_READ_RESOURCE         :: MAX_BUFFERS + MAX_SAMPLED_TEXTURES
MAX_READ_WRITE_RESOURCES  :: MAX_BUFFERS + MAX_READ_WRITE_TEXTURES

// Buffers may appear in both read and read_write, so account for the full
// read + read_write capacity, not just the distinct resource counts.
MAX_LAYOUT_BINDINGS       :: MAX_CONSTANT_BUFFERS + MAX_READ_RESOURCE + MAX_READ_WRITE_RESOURCES + MAX_SAMPLERS

#assert(MAX_CONSTANT_BUFFERS <= __MAX_CONSTANT_BUFFERS)
#assert(MAX_BUFFERS <= __MAX_BUFFERS)
#assert(MAX_SAMPLED_TEXTURES <= __MAX_SAMPLED_TEXTURES)
#assert(MAX_READ_WRITE_TEXTURES <= __MAX_READ_WRITE_TEXTURES)
#assert(MAX_SAMPLERS <= __MAX_SAMPLERS)
#assert(MAX_READ_RESOURCE <= __MAX_READ_RESOURCE)
#assert(MAX_READ_WRITE_RESOURCES <= __MAX_READ_WRITE_RESOURCES)
#assert(MAX_LAYOUT_BINDINGS <= __MAX_LAYOUT_BINDINGS)

MAX_2D_TEXTURE_SIZE :: 4096

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

_state: ^State

State :: struct #align(64) {
    using impl: _State,

    init_context: runtime.Context,
    is_init: bool,

    // Backing store for buffer debug names, maybe slot arena type thing later?
    name_arena: mem.Dynamic_Arena,
}

// Mimics ParameterBlock from slang. `dirty` marks array contents changed since
// the last bind; set by `update_parameter_block`, cleared by `set_shader`.
Parameter_Block :: struct {
    constants           : [MAX_CONSTANT_BUFFERS]ptr,
    read_resources      : [MAX_READ_RESOURCE]Parameter_Resource,
    read_write_resources: [MAX_READ_WRITE_RESOURCES]Parameter_Resource,
    samplers            : [MAX_SAMPLERS]Sampler,

    // Minimum bytes a read resource must bind, per slot; 0 means unspecified.
    // WGPU bakes this into the bind group layout's `minBindingSize`.
    read_resource_min_sizes: [MAX_READ_RESOURCE]uint,

    dirty: bool,
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
    cpu                 : rawptr,
    gpu                 : rawptr,

    flags               : Buffer_Usage,
    alignment           : uint,
    total_capacity_bytes: uint,
    byte_offset         : uint,

    meta                : Metadata,

    using native        : _ptr,
}

Buffer_Usage :: enum u32 {
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

Shader_Module :: struct {
    using native: _Shader_Module,
}

Shader_Desc :: struct {
    vertex_code:    string,
    vertex_entry:   string,
    fragment_code:  string,
    fragment_entry: string,

    color_format: Pixel_Format,
    depth_format: Pixel_Format,

    blend:       Blend_State,
    multisample: Multisample_State,
    topology:    Primitive,

    // Parameter blocks bound at backend slots 0..N, in order.
    binding_blocks: []Parameter_Block,
}

#assert(u16(Cull_Mode.Back) <= 0b11)
#assert(u16(Compare_Function.Always) <= 0b111)
#assert(u16(Front_Face.CW) <= 0b1)

Shader :: struct {
    using native: _Shader,
    desc: Shader_Desc,
}

// True when any of the shader's parameter blocks changed since the last bind.
shader_blocks_dirty :: proc(shader: ^Shader) -> bool {
    for block in shader.desc.binding_blocks {
        if block.dirty { return true }
    }
    return false
}

Draw_State :: struct #packed {
    cull_mode:     Cull_Mode,
    front_face:    Front_Face,
    depth_compare: Compare_Function,
    depth_write:   bool,
}
#assert(size_of(Draw_State) == 4)

DEFAULT_DRAW_STATE :: Draw_State {
    cull_mode     = .None,
    front_face    = .CCW,
    depth_compare = .Less,
    depth_write   = true,
}

draw_state_key :: proc "contextless" (state: Draw_State) -> u32 {
    return transmute(u32)state
}

BLEND_NONE :: Blend_State {
    color = {
        src = .One,
        dst = .Zero,
        op = .Add,
    },
    alpha = {
        src = .One,
        dst = .Zero,
        op = .Add,
    },
}

ALPHA_BLEND :: Blend_State {
    alpha = {
        src = .SrcAlpha,
        dst = .OneMinusSrcAlpha,
        op = .Add,
    },
    color = {
        src = .SrcAlpha,
        dst = .OneMinusSrcAlpha,
        op = .Add,
    }
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

Texture :: struct #all_or_none {
    concrete: Texture_Concrete,
    using native: _Texture,
}

Texture_Usage_1D_Flag :: enum u8 {
    Sampled,
    Storage_Read,
    Storage_Write,
}
Texture_Usage_1D :: bit_set[Texture_Usage_1D_Flag; u8]

Texture_Usage_2D_Flag :: enum u8 {
    Sampled,
    Storage_Read,
    Storage_Write,
    Color_Attachment,
    Depth_Attachment,
}
Texture_Usage_2D :: bit_set[Texture_Usage_2D_Flag; u8]

Texture_Usage_3D_Flag :: enum u8 {
    Sampled,
    Storage_Read,
    Storage_Write,
    Color_Attachment,
}
Texture_Usage_3D :: bit_set[Texture_Usage_3D_Flag; u8]

Texture_Usage_Cube_Flag :: enum u8 {
    Sampled,
    Storage_Read,
    Storage_Write,
    Color_Attachment,
    Depth_Attachment,
}
Texture_Usage_Cube :: bit_set[Texture_Usage_Cube_Flag; u8]

Texture_Type :: union {
    Texture_Type_1D,
    Texture_Type_2D,
    Texture_Type_3D,
    Texture_Type_Cube,
}

Texture_Type_1D :: struct {
    width: uint,
    usage: Texture_Usage_1D,
}

Texture_Type_2D :: struct {
    dimensions: [2]uint,
    array_length: uint, // 0 == 1
    usage: Texture_Usage_2D,
    sample_count: uint, // 0 == 1
}

Texture_Type_3D :: struct {
    dimensions: [3]uint,
    usage: Texture_Usage_3D,
}

Texture_Type_Cube :: struct {
    dimensions: [2]uint,
    array_length: uint, // 0 == 1
    usage: Texture_Usage_Cube,
}

Texture_Descriptor :: struct {
    type: Texture_Type,
    format: Pixel_Format,
    mip_levels: uint, // 0 == 1
    storage: Storage_Mode,
}

// Where the texture's memory lives. `Shared` is CPU-visible and required by the
// CPU-side `copy_to_texture`; `Private` is GPU-only. The GPU upload scope
// (`texture_upload_scope`) works with either.
Storage_Mode :: enum u8 {
    Shared,
    Private,
}

// The dimension a texture is bound as, derived from its type.
Texture_View :: enum u8 {
    _1D,
    _2D,
    _2D_Array,
    _3D,
    Cube,
    Cube_Array,
}

// Backend-agnostic view of the requested usages. Each backend projects this
// onto its native usage flags.
Texture_Usage_Info :: struct {
    sampled:          bool,
    storage_read:     bool,
    storage_write:    bool,
    color_attachment: bool,
    depth_attachment: bool,
}

// Fully resolved texture description: the union has been switched on and the
// "0 == 1" defaults applied. This is what the backends consume.
Texture_Concrete :: struct {
    view:       Texture_View,
    size:       [3]uint, // width, height, depth (depth is 1 unless 3D)
    layers:     uint,    // effective, >= 1; for Cube/Cube_Array the cubemap count
    samples:    uint,    // effective, >= 1
    mip_levels: uint,    // effective, >= 1
    format:     Pixel_Format,
    usage:      Texture_Usage_Info,
}

texture_concrete :: proc(desc: Texture_Descriptor) -> Texture_Concrete {
    c := Texture_Concrete {
        samples    = 1,
        layers     = 1,
        mip_levels = max(desc.mip_levels, 1),
        format     = desc.format,
    }

    switch t in desc.type {
    case Texture_Type_1D:
        c.view                = ._1D
        c.size                = {t.width, 1, 1}
        c.usage.sampled       = .Sampled in t.usage
        c.usage.storage_read  = .Storage_Read in t.usage
        c.usage.storage_write = .Storage_Write in t.usage

    case Texture_Type_2D:
        c.layers                 = max(t.array_length, 1)
        c.samples                = max(t.sample_count, 1)
        c.size                   = {t.dimensions.x, t.dimensions.y, 1}
        c.view                   = c.samples > 1 ? ._2D : (c.layers > 1 ? ._2D_Array : ._2D)
        c.usage.sampled          = .Sampled in t.usage
        c.usage.storage_read     = .Storage_Read in t.usage
        c.usage.storage_write    = .Storage_Write in t.usage
        c.usage.color_attachment = .Color_Attachment in t.usage
        c.usage.depth_attachment = .Depth_Attachment in t.usage

    case Texture_Type_3D:
        c.view                   = ._3D
        c.size                   = t.dimensions
        c.usage.sampled          = .Sampled in t.usage
        c.usage.storage_read     = .Storage_Read in t.usage
        c.usage.storage_write    = .Storage_Write in t.usage
        c.usage.color_attachment = .Color_Attachment in t.usage

    case Texture_Type_Cube:
        assert(t.dimensions.x == t.dimensions.y, "texture_concrete: cube textures must be square")
        c.layers                 = max(t.array_length, 1)
        c.size                   = {t.dimensions.x, t.dimensions.y, 1}
        c.view                   = c.layers > 1 ? .Cube_Array : .Cube
        c.usage.sampled          = .Sampled in t.usage
        c.usage.storage_read     = .Storage_Read in t.usage
        c.usage.storage_write    = .Storage_Write in t.usage
        c.usage.color_attachment = .Color_Attachment in t.usage
        c.usage.depth_attachment = .Depth_Attachment in t.usage
    }

    assert(!(c.samples > 1 && c.layers > 1), "texture_concrete: multisampled arrays are unsupported")
    assert(!(c.samples > 1 && (c.usage.storage_read || c.usage.storage_write)), "texture_concrete: multisampled textures cannot be storage")
    assert(!(c.samples > 1 && c.mip_levels > 1), "texture_concrete: multisampled textures cannot have mipmaps")
    assert(!(c.samples > 1 && !(c.usage.color_attachment || c.usage.depth_attachment)), "texture_concrete: multisampled textures must be render attachments")

    if c.mip_levels > 1 {
        max_dim := max(c.size.x, max(c.size.y, c.size.z))
        max_mips: uint
        for d := max_dim; d > 0; d >>= 1 { max_mips += 1 }
        assert(c.mip_levels <= max_mips, "texture_concrete: mip_levels exceeds the maximum for this size")
        assert(c.view != ._1D, "texture_concrete: 1D textures cannot have mipmaps")
    }

    return c
}

Clear_Color :: [4]u8

Pixel_Format :: enum u8 {
    None,
    BGRA8Unorm,
    RGBA8Unorm,
    RGBA32Float,
    Depth32Float,
}

pixel_format_bytes :: proc(format: Pixel_Format) -> uint {
    switch format {
    case .None:         return 0
    case .BGRA8Unorm:   return 4
    case .RGBA8Unorm:   return 4
    case .RGBA32Float:  return 16
    case .Depth32Float: return 4
    }
    return 0
}

Timeline_Semaphore :: distinct rawptr

Stage :: enum u8 {
    Transfer         = 0,
    Compute          = 1,
    All              = 6,
}

Color_Attachment :: struct {
    clear_color: Clear_Color,
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

Compare_Function :: enum u8 {
    Never = 0,
    Less,
    Equal,
    LessEqual,
    Greater,
    NotEqual,
    GreaterEqual,
    Always,
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

Compute_Pipeline :: struct {
    using native: _Compute_Pipeline,
}

Front_Face :: enum u8 {
    CCW = 0,
    CW,
}

Cull_Mode :: enum u8 {
    None = 0,
	Front,
	Back,
}

Multisample_State :: struct {
    count: u32,
    mask: u32,
}

Primitive :: enum u8 {
    Triangle,
}

Blend_State :: struct {
    color: Blend_Component,
	alpha: Blend_Component,
}

Blend_Component :: struct {
	op: Blend_Operation,
	src: Blend_Factor,
	dst: Blend_Factor,
}

Blend_Operation :: enum i32 {
	Add,
	Subtract,
	ReverseSubtract,
	Min,
	Max,
}

Blend_Factor :: enum i32 {
	Undefined,
	Zero,
	One,
	Src,
	OneMinusSrc,
	SrcAlpha,
	OneMinusSrcAlpha,
	Dst,
	OneMinusDst,
	DstAlpha,
	OneMinusDstAlpha,
	SrcAlphaSaturated,
	Constant,
	OneMinusConstant,
	Src1,
	OneMinusSrc1,
	Src1Alpha,
	OneMinusSrc1Alpha,
}

init :: proc(
    state           : ^State,
    native_window   : rawptr,
    swapchain_format: Pixel_Format = .BGRA8Unorm,
) -> bool {
    if _state != nil { return true }

    _state = state
    _state.init_context = context
    mem.dynamic_arena_init(&_state.name_arena, context.allocator, context.allocator)

    return _init(native_window, swapchain_format)
}

is_init :: proc() -> bool { return _state.is_init }

deinit :: proc() {
    if _state == nil { return }
    
    _deinit()

    mem.dynamic_arena_destroy(&_state.name_arena)

    _state = nil
}

resize_swapchain : proc(width, height: u32) -> bool : _resize_swapchain

release_texture: proc(texture: ^Texture) : _release_texture
release_sampler: proc(sampler: ^Sampler) : _release_sampler
release_ptr :: _release_ptr

// CPU side copy
copy_to_texture : proc(texture: Texture, origin, size: [3]uint, level: uint, data: rawptr, bytes_per_row: uint) : _copy_to_texture

// GPU side copy from a staging buffer range into a texture subresource. Works
// for both shared and private target textures. `bytes_per_row`/`bytes_per_image`
// describe the layout inside `src`.
copy_buffer_to_texture : proc(src: ptr, texture: ^Texture, origin, size: [3]uint, level: uint, bytes_per_row: uint, bytes_per_image: uint) : _copy_buffer_to_texture

shader_module_init :: proc(identifier: string, code: []u8) -> Shader_Module {
    native := _shader_module_init(identifier, code)

    return Shader_Module {
        native = native,
    }
}

// Builds the immutable, bindable graphics object: modules + native pipeline +
// baked resource set. This is the "prebuilt" shader state.
shader_init :: proc(desc: Shader_Desc) -> Shader {
    assert(desc.vertex_code != "", "shader_init: vertex_code is empty")
    assert(desc.fragment_code != "", "shader_init: fragment_code is empty")
    assert(desc.vertex_entry != "", "shader_init: vertex_entry is empty")
    assert(desc.fragment_entry != "", "shader_init: fragment_entry is empty")
    assert(desc.color_format != .None, "shader_init: color_format must be set")
    native := _shader_init(desc)

    return Shader {
        native = native,
        desc   = desc,
    }
}

shader_deinit :: proc(shader: ^Shader) {
    _shader_deinit(shader)
}

compute_pipeline_init :: proc(module: Shader_Module, entry_point: string) -> Compute_Pipeline {
    native := _compute_pipeline_init(module, entry_point)

    result := Compute_Pipeline {
        native = native,
    }

    return result
}

begin_commands : proc() : _begin_commands
commit_commands : proc() : _commit_commands
begin_frame : proc() : _begin_frame
end_frame : proc(semaphore: Timeline_Semaphore, frame_n: u64) : _end_frame

acquire_next_swapchain : proc() -> Texture : _acquire_next_swapchain

// Frame interval between 2 swapchain presents.
frame_interval_ns : proc() -> u64 : _frame_interval_ns

// Set the target refresh rate used for presentation pacing (limits gpu presents to this rate)
set_hz : proc(hz: u32) : _set_hz

compute_dispatch : proc(num_groups: [3]u32, num_threads_per_group: [3]u32) : _compute_dispatch
set_compute_pipeline : proc(compute_pipeline: Compute_Pipeline) : _set_compute_pipeline

// Binds the prebuilt shader (pipeline + all binding blocks). The backend
// no-ops when the same shader is bound and no block is dirty.
set_shader :: proc(shader: ^Shader) {
    _set_shader(shader)
    for &block in shader.desc.binding_blocks {
        block.dirty = false
    }
}

// Overwrites the given arrays of `block` from the slices (nil leaves an array
// untouched) and marks it so the next `set_shader` rebinds. No-ops when the
// provided arrays already match.
update_parameter_block :: proc(
    block: ^Parameter_Block,
    read_resources: []Parameter_Resource = nil,
    constants: []ptr = nil,
    read_write_resources: []Parameter_Resource = nil,
    samplers: []Sampler = nil,
) {
    changed := false

    if read_resources != nil {
        assert(len(read_resources) <= MAX_READ_RESOURCE, "update_parameter_block: too many read resources")
        if _update_parameter_array(block.read_resources[:], read_resources) { changed = true }
    }
    if constants != nil {
        assert(len(constants) <= MAX_CONSTANT_BUFFERS, "update_parameter_block: too many constants")
        if _update_parameter_array(block.constants[:], constants) { changed = true }
    }
    if read_write_resources != nil {
        assert(len(read_write_resources) <= MAX_READ_WRITE_RESOURCES, "update_parameter_block: too many read-write resources")
        if _update_parameter_array(block.read_write_resources[:], read_write_resources) { changed = true }
    }
    if samplers != nil {
        assert(len(samplers) <= MAX_SAMPLERS, "update_parameter_block: too many samplers")
        if _update_parameter_array(block.samplers[:], samplers) { changed = true }
    }

    if changed {
        block.dirty = true
    }
}

// Copies `src` over `dst` when they differ, clearing dst's tail. Returns whether
// anything changed.
_update_parameter_array :: proc(dst: []$T, src: []T) -> bool {
    for v, i in src {
        if dst[i] != v {
            for &d in dst { d = {} }
            for s, j in src { dst[j] = s }
            return true
        }
    }
    return false
}

// Applies the cheap dynamic state (cull/front/depth). Metal: encoder calls.
// WGPU: selects a cached pipeline variant.
set_draw_state : proc(state: Draw_State) : _set_draw_state

sampler_init :: proc(desc: Sampler_Descriptor) -> Sampler {
    native := _sampler_init(desc)
    
    return Sampler {
        native = native,
    }
}

// Releases a sampler's native handle.
sampler_deinit :: proc(sampler: ^Sampler) {
    _release_sampler(sampler)
}

texture_init :: proc(desc: Texture_Descriptor) -> Texture {
    concrete := texture_concrete(desc)
    native := _texture_init(concrete, desc)

    return Texture {
        concrete = concrete,
        native   = native,
    }
}

// Helper for depth texture
texture_depth_init :: proc(dimensions: [2]uint, format: Pixel_Format) -> Texture {
    desc := Texture_Descriptor {
        type = Texture_Type_2D {
            dimensions = dimensions,
            usage = {.Depth_Attachment},
        },
        
        format = format,
        storage = .Private,
    }
    return texture_init(desc)
}

begin_render_pass : proc(color_attachment: Color_Attachment, depth_attachment: Depth_Attachment = {}) : _begin_render_pass
end_render_pass : proc() : _end_render_pass

when ODIN_OS != .JS {
// Push struct to buffer
temp_malloc : proc(bytes: []u8, buffer_index: uint, shader_stage: Shader_Stage) : _temp_malloc
}

draw_indexed :: proc(index_buffer: ptr, index_count: uint, index_offset: uint, instance_count: uint, base_vertex: uint, base_instance: uint) {
    _draw_indexed(index_buffer, index_count, index_offset, instance_count, base_vertex, base_instance)
}

malloc :: proc(
    #any_int bytes: uint,
    alignment:   uint,
    flag: Buffer_Usage,
    name:        string     = "",
    loc:                    = #caller_location,
) -> (ptr, bool) #optional_ok {

    if min_alignment := _min_alignment(flag); alignment < min_alignment {
        log.errorf("In malloc() passed in alignment %i is less than the minimum required for flags %v. Bump to %i", alignment, flag, min_alignment, location = loc)
        return {}, false
    }
    
    capacity := runtime.align_forward(bytes, uint(alignment))

    _ptr := _malloc(bytes, alignment, flag, name, loc)

    return ptr {
        native = _ptr,
        cpu    = _cpu_address(_ptr) if flag == .Staging else nil,
        gpu    = _gpu_address(_ptr),
        flags = flag,
        alignment = alignment,
        total_capacity_bytes = capacity,
        byte_offset = 0,
        meta   = Metadata {
            name = strings.clone(name, mem.dynamic_arena_allocator(&_state.name_arena)),
            created_at = loc,
        },
    }, true
}

// Copies src data into dst
copy :: _copy

// Low-level block bind. Graphics go through `set_shader`; this remains for the
// compute dispatch path. `slot` is the backend buffer or
// bind-group index to bind at.
use_parameter_block :: proc(
    block: ^Parameter_Block,
    destination: Parameter_Block_Destination = .Graphics,
    slot: uint = 0,
) {
    _use_parameter_block(block, destination, slot)
}

// Ends 'before' stage
barrier : proc(before: Stage, after: Stage) : _barrier
semaphore : proc(value: u64) -> Timeline_Semaphore : _semaphore
semaphore_wait : proc(semaphore: Timeline_Semaphore, value: u64) -> bool : _semaphore_wait

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
