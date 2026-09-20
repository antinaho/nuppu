#+build js
#+vet explicit-allocators shadowing unused

package nuppu_gpu

import "vendor:wgpu"
import "core:fmt"
import "core:log"
import "core:strings"
import "base:runtime"



_ptr :: struct {
    buffer:   wgpu.Buffer,
    capacity: uint,
    // Persistent host shadow for .Staging buffers. Writes land here; `_flush`
    // pushes them into `buffer` with QueueWriteBuffer.
    shadow:   rawptr,
    index_bytes: u8,
}

_Shader_Module :: struct {
    module: wgpu.ShaderModule,
}

MAX_SHADER_VARIANTS :: 8

// A pipeline variant for a distinct dynamic Draw_State. WGPU bakes cull,
// front-face and depth into the pipeline, so changing them means selecting a
// (cached) variant rather than an encoder call
_Shader_Variant :: struct {
    state:    Draw_State,
    pipeline: wgpu.RenderPipeline,
}

_Shader :: struct {
    vertex:   _Shader_Module,
    fragment: _Shader_Module,
    entry_v:  string,
    entry_f:  string,

    // One layout + bind group per binding block, bound at slots 0..N. A dirty
    // block's bind group is rebuilt on the next `_set_shader`.
    block_layouts: []wgpu.BindGroupLayout,
    block_bgs:     []wgpu.BindGroup,
    pipeline_layout: wgpu.PipelineLayout,

    variants:      [MAX_SHADER_VARIANTS]_Shader_Variant,
    variant_count: u32,
}

_Sampler :: struct {
    s: wgpu.Sampler,
}

_Texture :: struct {
    texture:      wgpu.Texture,
    view:         wgpu.TextureView,
    storage_view: wgpu.TextureView, // non-nil when the texture is also used as storage
    view_dim:     wgpu.TextureViewDimension,
    access:       Texture_Access,
    samples:      u32,
}

_Compute_Pipeline :: struct {
    shader: _Shader_Module,
    entry:  string,
}

MAX_BG_LAYOUT_CACHE_ENTRIES :: 64
MAX_PIPELINE_CACHE_ENTRIES  :: 64

// Captures the full description of a bind group layout: the entry count
// plus the entries themselves. Two signatures compare equal iff they
// describe identical layouts.
_BG_Layout_Signature :: struct {
    count:   u32,
    entries: [MAX_LAYOUT_BINDINGS]wgpu.BindGroupLayoutEntry,
}

_BG_Layout_Cache_Entry :: struct {
    sig:             _BG_Layout_Signature,
    layout:          wgpu.BindGroupLayout,
    pipeline_layout: wgpu.PipelineLayout,
}

_Compute_Pipeline_Cache_Entry :: struct {
    bg_layout: wgpu.BindGroupLayout,
    meta:      Compute_Pipeline,
    pipeline:  wgpu.ComputePipeline,
}

_State :: struct {
    instance: wgpu.Instance,
    surface: wgpu.Surface,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    config: wgpu.SurfaceConfiguration,
    queue: wgpu.Queue,

    uniform_offset_align: uint,
    storage_offset_align: uint,
    index_offset_align: uint,
    //

    bg_layout_entries: [MAX_LAYOUT_BINDINGS]wgpu.BindGroupLayoutEntry,
    bg_entries: [MAX_LAYOUT_BINDINGS]wgpu.BindGroupEntry,
    parameter_count: u32,

    command_encoder: wgpu.CommandEncoder,
    render_pass_encoder: wgpu.RenderPassEncoder,
    compute_pass_encoder: wgpu.ComputePassEncoder,

    curr_compute_pipeline: Compute_Pipeline,

    curr_shader:       rawptr,
    curr_shader_valid: bool,
    curr_draw_state:   Draw_State,
    draw_state_valid:  bool,
    pipeline_dirty:    bool,

    // Fixed-capacity caches with circular overwrite on full. Empty
    // slots are detected by nil resource handles
    bg_layout_cache:        [MAX_BG_LAYOUT_CACHE_ENTRIES]_BG_Layout_Cache_Entry,
    bg_layout_cache_next:   u32,

    compute_pipeline_cache:      [MAX_PIPELINE_CACHE_ENTRIES]_Compute_Pipeline_Cache_Entry,
    compute_pipeline_cache_next: u32,
}

_init :: proc(native_window: rawptr, swapchain_format: Pixel_Format) -> bool {

    _state.instance = wgpu.CreateInstance(nil)
    if _state.instance == nil {
        fmt.panicf("Failed to create wgpu instance")
    }
    _state.surface = _get_wgpu_surface(_state.instance)
    if _state.surface == nil {
        fmt.panicf("Failed to create wgpu surface")
    }

    wgpu.InstanceRequestAdapter(_state.instance, &{ compatibleSurface = _state.surface }, { callback = _handle_request_adapter, mode = .AllowProcessEvents })

    return true

    _handle_request_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1, userdata2: rawptr) {
        context = _state.init_context

        if status != .Success || adapter == nil {
            fmt.panicf("request adapter failure: [%v] %s", status, message)
        }

        _state.adapter = adapter
        wgpu.AdapterRequestDevice(adapter, nil, { callback = _handle_request_device, mode = .AllowProcessEvents })
    }

    _handle_request_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1, userdata2: rawptr) {
        context = _state.init_context
        
        if status != .Success || device == nil {
            fmt.panicf("request device failure: [%v] %s", status, message)
        }

        _state.device = device
        _state.queue = wgpu.DeviceGetQueue(_state.device)

        limits, limits_status := wgpu.DeviceGetLimits(_state.device)
        switch limits_status {
        case .Success:
        case .Error:
            panic("Failed to get limits")
        }

        _state.uniform_offset_align = uint(limits.minUniformBufferOffsetAlignment)
        _state.storage_offset_align = uint(limits.minStorageBufferOffsetAlignment)
        _state.index_offset_align = 4

        _state.is_init = true
    }
}

_release_bg_layout :: proc(e: ^_BG_Layout_Cache_Entry) {
    if e.layout != nil {
        wgpu.BindGroupLayoutRelease(e.layout)
        e.layout = nil
    }
    if e.pipeline_layout != nil {
        wgpu.PipelineLayoutRelease(e.pipeline_layout)
        e.pipeline_layout = nil
    }
}

_release_compute_pipeline :: proc(e: ^_Compute_Pipeline_Cache_Entry) {
    if e.pipeline != nil {
        wgpu.ComputePipelineRelease(e.pipeline)
        e.pipeline = nil
    }
}

_deinit :: proc() {
    for i in 0..<MAX_BG_LAYOUT_CACHE_ENTRIES  do _release_bg_layout(&_state.bg_layout_cache[i])
    for i in 0..<MAX_PIPELINE_CACHE_ENTRIES   do _release_compute_pipeline(&_state.compute_pipeline_cache[i])
    _state.bg_layout_cache_next      = 0
    _state.compute_pipeline_cache_next = 0

    wgpu.QueueRelease(_state.queue)
    wgpu.DeviceRelease(_state.device)
    wgpu.AdapterRelease(_state.adapter)
    wgpu.SurfaceRelease(_state.surface)
    wgpu.InstanceRelease(_state.instance)
}



_resize_swapchain :: proc(width, height: u32) -> bool {
    _state.config = wgpu.SurfaceConfiguration {
        device = _state.device,
        usage = {.RenderAttachment},
        format = .BGRA8Unorm,
        width = u32(width),
        height = u32(height),
        presentMode = .Fifo,
        alphaMode = .Opaque,
    }
    wgpu.SurfaceConfigure(_state.surface, &_state.config)

    if _state.surface == nil {
        return false
    }

    return true
}

_release_texture :: proc(texture: ^Texture) {
    if texture.native.storage_view != nil {
        wgpu.TextureViewRelease(texture.native.storage_view)
        texture.native.storage_view = nil
    }
    if texture.native.view != nil {
        wgpu.TextureViewRelease(texture.native.view)
        texture.native.view = nil
    }
    if texture.native.texture != nil {
        wgpu.TextureRelease(texture.native.texture)
        texture.native.texture = nil
    }
}

_release_sampler :: proc(sampler: ^Sampler) {
    if sampler.native.s != nil {
        wgpu.SamplerRelease(sampler.native.s)
        sampler.native.s = nil
    }
}

_release_ptr :: proc(ptr: ^ptr) {
    if ptr.native.shadow != nil {
        runtime.mem_free(ptr.native.shadow, context.allocator)
        ptr.native.shadow = nil
    }
    ptr.cpu = nil
    if ptr.native.buffer != nil {
        wgpu.BufferRelease(ptr.native.buffer)
        ptr.native.buffer = nil
    }
}

_copy_to_texture :: proc(texture: Texture, origin, size: [3]uint, level: uint, data: rawptr, bytes_per_row: uint) {
    destination := wgpu.TexelCopyTextureInfo {
        texture  = texture.native.texture,
        mipLevel = u32(level),
        origin   = wgpu.Origin3D { u32(origin.x), u32(origin.y), u32(origin.z) },
        aspect   = .All,
    }
    layout := wgpu.TexelCopyBufferLayout {
        offset       = 0,
        bytesPerRow  = u32(bytes_per_row),
        rowsPerImage = u32(size.y),
    }
    write_size := wgpu.Extent3D {
        width              = u32(size.x),
        height             = u32(size.y),
        depthOrArrayLayers = 1,
    }
    data_size := bytes_per_row * size.y

    wgpu.QueueWriteTexture(_state.queue, &destination, data, data_size, &layout, &write_size)
}

_copy_buffer_to_texture :: proc(src: ptr, texture: ^Texture, origin, size: [3]uint, level: uint, bytes_per_row: uint, bytes_per_image: uint) {
    if src.cpu == nil { return }

    rows_per_image := bytes_per_image / max(bytes_per_row, 1)

    destination := wgpu.TexelCopyTextureInfo {
        texture  = texture.native.texture,
        mipLevel = u32(level),
        origin   = wgpu.Origin3D { u32(origin.x), u32(origin.y), u32(origin.z) },
        aspect   = .All,
    }
    layout := wgpu.TexelCopyBufferLayout {
        offset       = 0,
        bytesPerRow  = u32(bytes_per_row),
        rowsPerImage = u32(rows_per_image),
    }
    write_size := wgpu.Extent3D {
        width              = u32(size.x),
        height             = u32(size.y),
        depthOrArrayLayers = u32(size.z),
    }

    // `writeTexture` has no bytesPerRow alignment requirement, so the padded
    // rows laid out by the upload scope are accepted directly.
    wgpu.QueueWriteTexture(_state.queue, &destination, src.cpu, uint(src.total_capacity_bytes), &layout, &write_size)
}

_shader_module_init :: proc(name: string, code: []u8) -> _Shader_Module {
    module := wgpu.DeviceCreateShaderModule(_state.device, &{
        nextInChain = &wgpu.ShaderSourceWGSL {
            sType = .ShaderSourceWGSL,
            code = string(code),
        }
    })
    assert(module != nil, "_shader_module_init: failed to create shader module")

    return _Shader_Module {
        module = module,
    }
}

// Builds one layout + bind group per binding block (slots 0..N) and the pipeline
// layout. Blocks are bound by index, so block 0 is the engine block.
_shader_build_bindings :: proc(shader: ^_Shader, desc: ^Shader_Desc) {
    block_count := len(desc.binding_blocks)
    shader.block_layouts = make([]wgpu.BindGroupLayout, block_count, context.allocator)
    shader.block_bgs     = make([]wgpu.BindGroup, block_count, context.allocator)

    for i in 0 ..< block_count {
        b := desc.binding_blocks[i]
        _use_parameter_block(b, .Graphics, uint(i))
        count := _state.parameter_count

        layout := wgpu.DeviceCreateBindGroupLayout(_state.device, &{
            entryCount = uint(count),
            entries    = raw_data(_state.bg_layout_entries[:count]),
        })
        assert(layout != nil, "_shader_build_bindings: failed to create block bind group layout")

        shader.block_layouts[i] = layout
        shader.block_bgs[i]     = _create_bind_group(layout, count, raw_data(_state.bg_entries[:count]))
    }

    layouts := make([]wgpu.BindGroupLayout, block_count, context.temp_allocator)
    for layout, i in shader.block_layouts {
        layouts[i] = layout
    }

    shader.pipeline_layout = wgpu.DeviceCreatePipelineLayout(_state.device, &{
        bindGroupLayoutCount = uint(len(layouts)),
        bindGroupLayouts     = raw_data(layouts),
    })
    assert(shader.pipeline_layout != nil, "_shader_build_bindings: failed to create pipeline layout")
}

_create_bind_group :: proc(layout: wgpu.BindGroupLayout, count: u32, entries: [^]wgpu.BindGroupEntry) -> wgpu.BindGroup {
    bg := wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
        layout     = layout,
        entryCount = uint(count),
        entries    = entries,
    })
    assert(bg != nil, "_create_bind_group: failed to create bind group")
    return bg
}

_shader_create_pipeline :: proc(shader: ^_Shader, desc: ^Shader_Desc, state: Draw_State) -> wgpu.RenderPipeline {
    primitive := wgpu.PrimitiveState {
        topology  = _primitive_type_interop(desc.topology),
        cullMode  = _cull_mode_interop(state.cull_mode),
        frontFace = _front_face_winding_interop(state.front_face),
    }
    multisample := wgpu.MultisampleState {
        count = desc.multisample.count,
        mask  = desc.multisample.mask,
    }
    blend := wgpu.BlendState {
        color = wgpu.BlendComponent {
            operation = _blend_operation_interop(desc.blend.color.op),
            srcFactor = _blend_factor_interop(desc.blend.color.src),
            dstFactor = _blend_factor_interop(desc.blend.color.dst),
        },
        alpha = wgpu.BlendComponent {
            operation = _blend_operation_interop(desc.blend.alpha.op),
            srcFactor = _blend_factor_interop(desc.blend.alpha.src),
            dstFactor = _blend_factor_interop(desc.blend.alpha.dst),
        },
    }
    target := wgpu.ColorTargetState {
        format    = _pixel_format_interop(desc.color_format),
        blend     = &blend,
        writeMask = wgpu.ColorWriteMaskFlags_All,
    }
    v_state := wgpu.VertexState {
        module      = shader.vertex.module,
        entryPoint  = shader.entry_v,
        bufferCount = 0,
        buffers     = nil,
    }
    f_state := wgpu.FragmentState {
        module      = shader.fragment.module,
        entryPoint  = shader.entry_f,
        targetCount = 1,
        targets     = &target,
    }

    depth_format := _pixel_format_interop(desc.depth_format)
    dpso: wgpu.DepthStencilState
    if depth_format != .Undefined {
        dpso.format = depth_format
        dpso.depthWriteEnabled = .True if state.depth_write else .False
        dpso.depthCompare = _compare_function_interop(state.depth_compare)
    }

    pso := wgpu.DeviceCreateRenderPipeline(_state.device, &wgpu.RenderPipelineDescriptor{
        layout       = shader.pipeline_layout,
        vertex       = v_state,
        primitive    = primitive,
        multisample  = multisample,
        fragment     = &f_state,
        depthStencil = nil if depth_format == .Undefined else &dpso,
    })
    assert(pso != nil, "_shader_create_pipeline: failed to create render pipeline")
    return pso
}

// Returns the cached pipeline variant for `state`, creating it on first use.
// This is the WGPU "immediate mode": a cull/depth change only picks another
// variant that shares the module + bind group, it never recompiles.
_shader_variant :: proc(shader: ^_Shader, desc: ^Shader_Desc, state: Draw_State) -> wgpu.RenderPipeline {
    for i in 0 ..< shader.variant_count {
        if shader.variants[i].state == state {
            return shader.variants[i].pipeline
        }
    }
    assert(shader.variant_count < MAX_SHADER_VARIANTS, "_shader_variant: variant cache full")

    pso := _shader_create_pipeline(shader, desc, state)
    shader.variants[shader.variant_count] = _Shader_Variant { state = state, pipeline = pso }
    shader.variant_count += 1
    return pso
}

_shader_init :: proc(desc: Shader_Desc) -> _Shader {
    d := desc
    shader := _Shader {
        vertex   = _shader_module_init("vs", transmute([]u8)d.vertex_code),
        fragment = _shader_module_init("fs", transmute([]u8)d.fragment_code),
        entry_v  = strings.clone(d.vertex_entry, context.allocator),
        entry_f  = strings.clone(d.fragment_entry, context.allocator),
    }

    _shader_build_bindings(&shader, &d)
    // Pipelines are created on first draw, once the lazy set-2 layout exists.
    shader.variant_count = 0

    return shader
}

_shader_deinit :: proc(shader: ^Shader) {
    for i in 0 ..< shader.variant_count {
        wgpu.RenderPipelineRelease(shader.variants[i].pipeline)
    }
    shader.variant_count = 0

    if shader.pipeline_layout != nil {
        wgpu.PipelineLayoutRelease(shader.pipeline_layout)
        shader.pipeline_layout = nil
    }
    for bg in shader.block_bgs {
        wgpu.BindGroupRelease(bg)
    }
    for layout in shader.block_layouts {
        wgpu.BindGroupLayoutRelease(layout)
    }
    if shader.block_bgs != nil {
        delete(shader.block_bgs, context.allocator)
        shader.block_bgs = nil
    }
    if shader.block_layouts != nil {
        delete(shader.block_layouts, context.allocator)
        shader.block_layouts = nil
    }
    if shader.vertex.module != nil {
        wgpu.ShaderModuleRelease(shader.vertex.module)
        shader.vertex.module = nil
    }
    if shader.fragment.module != nil {
        wgpu.ShaderModuleRelease(shader.fragment.module)
        shader.fragment.module = nil
    }
}

_compute_pipeline_init :: proc(module: Shader_Module, entry_point: string) -> _Compute_Pipeline {
    return _Compute_Pipeline {
        shader = module,
        entry  = strings.clone(entry_point, context.allocator),
    }
}

_begin_commands :: proc() {
    _state.command_encoder = wgpu.DeviceCreateCommandEncoder(_state.device, &{
        label = "encoder"
    })
}

_commit_commands :: proc() {
    finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
    defer {
        wgpu.CommandBufferRelease(finished)
        wgpu.CommandEncoderRelease(_state.command_encoder)
    }
    wgpu.QueueSubmit(_state.queue, []wgpu.CommandBuffer{finished})
}

_begin_frame :: proc() {
    _begin_commands()
}

_end_frame :: proc(semaphore: Timeline_Semaphore, frame_n: u64) {
    finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
    defer {
        wgpu.CommandBufferRelease(finished)
        wgpu.CommandEncoderRelease(_state.command_encoder)
    }
    wgpu.QueueSubmit(_state.queue, []wgpu.CommandBuffer{finished})
    _state.command_encoder = nil

    wgpu.SurfacePresent(_state.surface)
}

_acquire_next_swapchain :: proc() -> Texture {
    surface_texture := wgpu.SurfaceGetCurrentTexture(_state.surface)
    switch surface_texture.status {
    case .SuccessOptimal, .SuccessSuboptimal:
    // All good, could handle suboptimal here.
    case .Timeout, .Outdated, .Lost:
        // if tex.texture != nil {
        // 	wgpu.TextureRelease(tex.texture)
        // }
        // r_resize()
        return {}
    case .Occluded:
        // Window is occluded (e.g. minimized), skip this frame.
        return {}
    case .Error:
        fmt.panicf("get_current_texture status=%v", surface_texture.status)
    }

    view := wgpu.TextureCreateView(surface_texture.texture, nil)

    native := _Texture {
        texture      = surface_texture.texture,
        view         = view,
        storage_view = nil,
        view_dim     = ._2D,
        access       = .Write,
        samples      = 1,
    }

    return Texture {
        concrete = texture_concrete({
            type = Texture_Type_2D {
                dimensions = { uint(_state.config.width), uint(_state.config.height) },
                usage      = {.Color_Attachment},
            },
            format = .None,
        }),
        native = native,
    }
}

_compute_dispatch :: proc(num_groups: [3]u32, num_threads_per_group: [3]u32) {
    pipeline := _state.curr_compute_pipeline

    bg_layout, pso_layout := _get_or_create_bg_layout()
    pso := _get_or_create_compute_pipeline(bg_layout, pso_layout, pipeline)

    bg := wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
        layout     = bg_layout,
        entryCount = uint(_state.parameter_count),
        entries    = raw_data(_state.bg_entries[:_state.parameter_count]),
    })

    pass := _compute_pass_encoder()
    wgpu.ComputePassEncoderSetPipeline(pass, pso)
    wgpu.ComputePassEncoderSetBindGroup(pass, 0, bg, nil)
    wgpu.ComputePassEncoderDispatchWorkgroups(pass, num_groups.x, num_groups.y, num_groups.z)

    wgpu.ComputePassEncoderEnd(pass)
    wgpu.ComputePassEncoderRelease(pass)
    wgpu.BindGroupRelease(bg)
    _state.compute_pass_encoder = nil
}

_set_compute_pipeline :: proc(pipeline: Compute_Pipeline) {
    _state.curr_compute_pipeline = pipeline
}

_set_shader :: proc(shader: ^Shader) {
    assert(_state.render_pass_encoder != nil, "_set_shader: no render pass is active")

    same_shader := _state.curr_shader_valid && _state.curr_shader == rawptr(shader)
    if same_shader && !shader_blocks_dirty(shader) {
        return
    }
    _state.curr_shader = rawptr(shader)
    _state.curr_shader_valid = true
    if !same_shader {
        _state.pipeline_dirty = true
    }

    enc := _state.render_pass_encoder

    // Bind groups are immutable, so dirty blocks get fresh bind groups.
    for i in 0 ..< len(shader.block_bgs) {
        if !shader.desc.binding_blocks[i].dirty { continue }
        b := shader.desc.binding_blocks[i]
        _use_parameter_block(b, .Graphics, uint(i))
        count := _state.parameter_count
        wgpu.BindGroupRelease(shader.block_bgs[i])
        shader.block_bgs[i] = _create_bind_group(shader.block_layouts[i], count, raw_data(_state.bg_entries[:count]))
    }
    for bg, i in shader.block_bgs {
        wgpu.RenderPassEncoderSetBindGroup(enc, u32(i), bg, nil)
    }
}

_set_draw_state :: proc(state: Draw_State) {
    if _state.draw_state_valid && _state.curr_draw_state == state {
        return
    }
    _state.curr_draw_state = state
    _state.draw_state_valid = true
    _state.pipeline_dirty = true
}

_sampler_init :: proc(desc: Sampler_Descriptor) -> _Sampler {
    address_mode_interop :: proc(m: Sampler_Address_Mode) -> wgpu.AddressMode {
        switch m {
        case .ClampToEdge:  return .ClampToEdge
        case .MirrorRepeat: return .MirrorRepeat
        case .Repeat:       return .Repeat
        }
        unreachable()
    }

    filter_mode_interop :: proc(m: Sampler_Min_Mag_Filter) -> wgpu.FilterMode {
        switch m {
        case .Nearest: return .Nearest
        case .Linear:  return .Linear
        }
        unreachable()
    }

    mip_filter_interop :: proc(m: Sampler_Mip_Filter) -> wgpu.MipmapFilterMode {
        switch m {
        case .NotMipmapped: return .Nearest
        case .Nearest:      return .Nearest
        case .Linear:       return .Linear
        }
        unreachable()
    }

    wgpu_desc := wgpu.SamplerDescriptor {
        addressModeU  = address_mode_interop(desc.wrap_s),
        addressModeV  = address_mode_interop(desc.wrap_t),
        addressModeW  = address_mode_interop(desc.wrap_r),
        magFilter     = filter_mode_interop(desc.mag_filter),
        minFilter     = filter_mode_interop(desc.min_filter),
        mipmapFilter  = mip_filter_interop(desc.mip_filter),
        lodMinClamp   = 0,
        lodMaxClamp   = 32,
        maxAnisotropy = 1,
    }

    sampler := wgpu.DeviceCreateSampler(_state.device, &wgpu_desc)

    return _Sampler {
        s = sampler,
    }
}

_texture_init :: proc(concrete: Texture_Concrete, texture_descriptor: Texture_Descriptor, access: Texture_Access) -> _Texture {
    depth_or_layers := concrete.layers
    switch concrete.view {
    case ._1D:
        depth_or_layers = 1
    case ._3D:
        depth_or_layers = concrete.size.z
    case .Cube, .Cube_Array:
        depth_or_layers = concrete.layers * 6
    case ._2D, ._2D_Array:
        // concrete.layers
    }

    desc: wgpu.TextureDescriptor
    desc.dimension     = _texture_dimension_interop(concrete.view)
    desc.size          = {u32(concrete.size.x), u32(concrete.size.y), u32(depth_or_layers)}
    desc.sampleCount   = u32(concrete.samples)
    desc.mipLevelCount = u32(concrete.mip_levels)
    desc.format        = _pixel_format_interop(texture_descriptor.format)
    desc.usage         = _texture_usage_interop(concrete.usage)

    texture := wgpu.DeviceCreateTexture(_state.device, &desc)
    if texture == nil {
        log.panic("gpu_wgpu.odin: _texture_init: failed to create texture")
    }

    view_dim := _texture_view_dimension_interop(concrete.view)

    array_layers: u32 = 1
    switch concrete.view {
    case ._2D_Array:
        array_layers = u32(concrete.layers)
    case .Cube:
        array_layers = 6
    case .Cube_Array:
        array_layers = u32(concrete.layers * 6)
    case ._1D, ._2D, ._3D:
        // 1
    }

    view := wgpu.TextureCreateView(texture, &wgpu.TextureViewDescriptor{
        dimension       = view_dim,
        mipLevelCount   = u32(concrete.mip_levels),
        arrayLayerCount = array_layers,
    })

    // Storage bindings require a view with exactly one mip level, and a cube
    // view cannot be bound as storage at all. Create a dedicated view when the
    // texture is also used as storage.
    storage_view: wgpu.TextureView
    if concrete.usage.storage_read || concrete.usage.storage_write {
        storage_dim    := view_dim
        storage_layers := array_layers
        #partial switch view_dim {
        case .Cube, .CubeArray:
            storage_dim    = ._2DArray
            storage_layers = u32(concrete.layers * 6)
        }
        storage_view = wgpu.TextureCreateView(texture, &wgpu.TextureViewDescriptor{
            dimension       = storage_dim,
            mipLevelCount   = 1,
            arrayLayerCount = storage_layers,
        })
    }

    return _Texture {
        texture      = texture,
        view         = view,
        storage_view = storage_view,
        view_dim     = view_dim,
        access       = access,
        samples      = u32(concrete.samples),
    }
}

_begin_render_pass :: proc(c_attachment: Color_Attachment, d_attachment: Depth_Attachment) {

    res: wgpu.RenderPassColorAttachment
    res.view = c_attachment.texture.view
    res.storeOp = _store_action_interop(c_attachment.store_action)
    res.loadOp = _load_action_interop(c_attachment.load_action)
    res.clearValue = from_4xu8_to_4xf64_color(c_attachment.clear_color)
    res.depthSlice = wgpu.DEPTH_SLICE_UNDEFINED

    depth: wgpu.RenderPassDepthStencilAttachment
    if d_attachment.texture.native.view != nil {
        depth.view = d_attachment.texture.native.view
        depth.depthClearValue = 1
        depth.depthLoadOp = _load_action_interop(d_attachment.load_action)
        depth.depthStoreOp = _store_action_interop(d_attachment.store_action)
    }

    desc := wgpu.RenderPassDescriptor {
        colorAttachmentCount = 1,
        colorAttachments = &res,
        depthStencilAttachment = nil if d_attachment.texture.native.view == nil else &depth,
    }

    _state.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(_state.command_encoder, &desc)

    // A new encoder starts with no pipeline bound.
    _state.curr_shader_valid = false
    _state.draw_state_valid  = false
    _state.pipeline_dirty    = true
}

_end_render_pass :: proc() {
    wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
    wgpu.RenderPassEncoderRelease(_state.render_pass_encoder)
}

_draw_indexed :: proc(index_buffer: ptr, index_count: uint, index_offset: uint, instance_count: uint, base_vertex: uint, base_instance: uint) {
    if instance_count == 0 {
        return
    }

    assert(_state.curr_shader_valid, "_draw_indexed: no shader bound; call set_shader first")
    shader := (^Shader)(_state.curr_shader)

    // Deferred variant bind: both set_shader and set_draw_state only mark the
    // pipeline dirty, so a shader+state change costs exactly one SetPipeline.
    if _state.pipeline_dirty {
        pso := _shader_variant(&shader.native, &shader.desc, _state.curr_draw_state)
        wgpu.RenderPassEncoderSetPipeline(_state.render_pass_encoder, pso)
        _state.pipeline_dirty = false
    }

    index_format: wgpu.IndexFormat
    switch index_buffer.native.index_bytes {
    case 2:
        index_format = .Uint16
    case 4:
        index_format = .Uint32
    case: panic("Index buffer format not supported")
    }

    offset_bytes := u64(index_offset) * u64(index_buffer.native.index_bytes)
    assert(offset_bytes <= u64(index_buffer.native.capacity), "index_offset past end of index buffer")
    wgpu.RenderPassEncoderSetIndexBuffer(
        _state.render_pass_encoder,
        index_buffer.native.buffer, index_format,
        offset_bytes, u64(index_buffer.native.capacity) - offset_bytes,
    )

    wgpu.RenderPassEncoderDrawIndexed(
        _state.render_pass_encoder,
        indexCount    = u32(index_count),
        instanceCount = u32(instance_count),
        firstIndex    = 0,
        baseVertex    = i32(base_vertex),
        firstInstance = u32(base_instance),
    )
}

_malloc :: proc(
    #any_int bytes: uint,
    alignment: uint,
    flags: Buffer_Usage,
    name: string,
    loc := #caller_location,
) -> _ptr {
    usage: wgpu.BufferUsageFlags
    aligned_bytes := runtime.align_forward_uint(uint(bytes), uint(alignment))

    switch flags {
    case .Staging:
        usage         = {.CopySrc, .CopyDst}
    case .Default:
        usage         = {.CopyDst, .CopySrc, .Storage}
        aligned_bytes = runtime.align_forward_uint(aligned_bytes, uint(_state.storage_offset_align))
    case .Constant:
        usage         = {.CopyDst, .Uniform}
        aligned_bytes = runtime.align_forward_uint(aligned_bytes, uint(_state.uniform_offset_align))
    case .Index:
        usage         = {.CopyDst, .Index}
        aligned_bytes = runtime.align_forward_uint(aligned_bytes, uint(_state.index_offset_align))
    }

    buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
        label = name,
        usage = usage,
        size = u64(aligned_bytes),
    })

    shadow: rawptr
    if flags == .Staging {
        shadow_bytes, err := runtime.mem_alloc(int(aligned_bytes), int(alignment), context.allocator)
        assert(err == nil, "_malloc: failed to allocate staging shadow")
        shadow = raw_data(shadow_bytes)
    }

    return _ptr {
        buffer      = buffer,
        shadow      = shadow,
        capacity    = aligned_bytes,
        index_bytes = 2 if flags == .Index else 0,
    }
}

_min_alignment :: proc(flags: Buffer_Usage) -> uint {
    switch flags {
    case .Staging:  return 4
    case .Default:  return _state.storage_offset_align
    case .Constant: return _state.uniform_offset_align
    case .Index:    return _state.index_offset_align
    }
    unreachable()
}

_copy :: proc(
    dst, src: ptr,
    #any_int dst_offset: uint = 0,
    #any_int src_offset: uint = 0,
    #any_int length_override: uint = 0,
) {
    assert(src_offset <= src.total_capacity_bytes, "_copy: src_offset exceeds source capacity")
    assert(dst_offset <= dst.total_capacity_bytes, "_copy: dst_offset exceeds destination capacity")

    length := length_override if length_override != 0 else src.total_capacity_bytes - src_offset
    if length == 0 { return }

    assert(src_offset + length <= src.total_capacity_bytes, "_copy: source range exceeds capacity")
    assert(dst_offset + length <= dst.total_capacity_bytes, "_copy: destination range exceeds capacity")

    if src.flags == .Staging && src.cpu != nil {
        assert((src.byte_offset + src_offset) % 4 == 0 && length % 4 == 0,
            "_copy: QueueWriteBuffer offset/size must be 4-byte aligned")
        wgpu.QueueWriteBuffer(
            _state.queue,
            src.native.buffer,
            u64(src.byte_offset + src_offset),
            rawptr(uintptr(src.cpu) + uintptr(src_offset)),
            length,
        )
    }

    wgpu.CommandEncoderCopyBufferToBuffer(
        _state.command_encoder,
        src.native.buffer, u64(src.byte_offset + src_offset),
        dst.native.buffer, u64(dst.byte_offset + dst_offset),
        u64(length),
    )
}

_cpu_address :: proc(p: _ptr) -> rawptr {
    return p.shadow
}

_gpu_address :: proc(p: _ptr) -> rawptr {
    return nil
}

_use_parameter_block :: proc(block: Resource_Block, destination: Parameter_Block_Destination, slot: uint) {
    _ = slot

    bg_layout_entries := &_state.bg_layout_entries
    bg_entries := &_state.bg_entries
    count: u32

    visibility: wgpu.ShaderStageFlags = {.Vertex, .Fragment}
    if destination == .Compute {
        visibility = {.Compute}
    }

    for R, res_idx in block.resources {
        switch r in R {
        case ptr:
            if r.native.buffer == nil { continue }

            is_uniform := r.flags == .Constant

            binding_type: wgpu.BufferBindingType = .Uniform
            min_size: u64
            if !is_uniform {
                binding_type = .Storage if r.access == .Read_Write else .ReadOnlyStorage
                if res_idx < len(block._resource_size) {
                    min_size = u64(block._resource_size[res_idx])
                }
            }

            bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                binding    = u32(count),
                visibility = visibility,
                buffer = wgpu.BufferBindingLayout{
                    type             = binding_type,
                    hasDynamicOffset = false,
                    minBindingSize   = min_size,
                },
            }

            size := r.total_capacity_bytes
            if is_uniform {
                size = max(size, uint(_state.uniform_offset_align))
            }

            bg_entries[count] = wgpu.BindGroupEntry{
                binding = u32(count),
                buffer  = r.buffer,
                offset  = u64(r.byte_offset),
                size    = u64(size),
            }

            count += 1

        case Texture:
            if r.native.texture == nil { continue }

            if r.concrete.usage.storage_read || r.concrete.usage.storage_write {
                storage_view := r.native.storage_view
                storage_dim  := r.native.view_dim
                if storage_view != nil {
                    #partial switch r.native.view_dim {
                    case .Cube, .CubeArray:
                        storage_dim = ._2DArray
                    }
                } else {
                    storage_view = r.native.view
                }

                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding    = u32(count),
                    visibility = visibility,
                    storageTexture = wgpu.StorageTextureBindingLayout{
                        access        = _storage_access_interop(r.native.access),
                        format        = wgpu.TextureGetFormat(r.native.texture),
                        viewDimension = storage_dim,
                    },
                }

                bg_entries[count] = wgpu.BindGroupEntry{
                    binding     = u32(count),
                    textureView = storage_view,
                }
            } else {
                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding    = u32(count),
                    visibility = visibility,
                    texture = wgpu.TextureBindingLayout{
                        sampleType    = _texture_sample_type_interop(wgpu.TextureGetFormat(r.native.texture), r.native.samples),
                        viewDimension = r.native.view_dim,
                        multisampled  = r.native.samples > 1,
                    },
                }

                bg_entries[count] = wgpu.BindGroupEntry{
                    binding     = u32(count),
                    textureView = r.native.view,
                }
            }

            count += 1

        case Sampler:
            if r.native.s == nil { continue }

            bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                binding    = u32(count),
                visibility = visibility,
                sampler = wgpu.SamplerBindingLayout{
                    type = .Filtering,
                },
            }

            bg_entries[count] = wgpu.BindGroupEntry{
                binding = u32(count),
                sampler = r.native.s,
            }

            count += 1
        }
    }

    _state.parameter_count = count
}

_barrier :: proc(before: Stage, after: Stage) { /* no op */ }

_semaphore :: proc(value: u64) -> Timeline_Semaphore {
    /* no op */
    return {}
}

_semaphore_wait :: proc(semaphore: Timeline_Semaphore, value: u64) -> bool {
    /* no op */
    return true
}

//////////////////////////////////////////////////////////////

_compute_pass_encoder :: #force_inline proc "contextless" () -> wgpu.ComputePassEncoder {
    if _state.compute_pass_encoder == nil {
        _state.compute_pass_encoder = wgpu.CommandEncoderBeginComputePass(_state.command_encoder, nil)
    }
    return _state.compute_pass_encoder
}

//////////////////////////////////////////////////////////////
// Pipeline caches

_bg_layout_sig_equal :: proc(a, b: ^_BG_Layout_Signature) -> bool {
    if a.count != b.count do return false
    for i in 0..<int(a.count) {
        if a.entries[i] != b.entries[i] do return false
    }
    return true
}

// Returns (bind_group_layout, pipeline_layout) — both are cached. The
// pipeline layout has exactly one bind group layout in this design, so
// the two are stored together.
_get_or_create_bg_layout :: proc() -> (wgpu.BindGroupLayout, wgpu.PipelineLayout) {
    sig: _BG_Layout_Signature
    sig.count = _state.parameter_count
    for i in 0..<int(_state.parameter_count) {
        sig.entries[i] = _state.bg_layout_entries[i]
    }

    for i in 0..<MAX_BG_LAYOUT_CACHE_ENTRIES {
        e := &_state.bg_layout_cache[i]
        if e.layout == nil { continue }
        if _bg_layout_sig_equal(&e.sig, &sig) {

            return e.layout, e.pipeline_layout
        }
    }

    new_layout := wgpu.DeviceCreateBindGroupLayout(_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = uint(sig.count),
        entries    = raw_data(sig.entries[:sig.count]),
    })
    if new_layout == nil {
        return nil, nil
    }
    new_pso_layout := wgpu.DeviceCreatePipelineLayout(_state.device, &wgpu.PipelineLayoutDescriptor{
        bindGroupLayoutCount = 1,
        bindGroupLayouts    = &new_layout,
    })
    if new_pso_layout == nil {
        wgpu.BindGroupLayoutRelease(new_layout)
        return nil, nil
    }

    slot := int(_state.bg_layout_cache_next)
    old := &_state.bg_layout_cache[slot]
    _release_bg_layout(old)
    old^ = _BG_Layout_Cache_Entry {
        sig             = sig,
        layout          = new_layout,
        pipeline_layout = new_pso_layout,
    }
    _state.bg_layout_cache_next = u32((slot + 1) % MAX_BG_LAYOUT_CACHE_ENTRIES)

    return new_layout, new_pso_layout
}

_compute_pipeline_entry_equal :: proc(a, b: ^_Compute_Pipeline_Cache_Entry) -> bool {
    return a.bg_layout == b.bg_layout &&
            a.meta      == b.meta
}

_get_or_create_compute_pipeline :: proc(bg_layout: wgpu.BindGroupLayout, pso_layout: wgpu.PipelineLayout, meta: Compute_Pipeline) -> wgpu.ComputePipeline {
    key := _Compute_Pipeline_Cache_Entry {
        bg_layout = bg_layout,
        meta      = meta,
    }

    for i in 0..<MAX_PIPELINE_CACHE_ENTRIES {
        e := &_state.compute_pipeline_cache[i]
        if e.pipeline == nil { continue }
        if _compute_pipeline_entry_equal(e, &key) {
            return e.pipeline
        }
    }

    pso := wgpu.DeviceCreateComputePipeline(_state.device, &wgpu.ComputePipelineDescriptor{
        layout  = pso_layout,
        compute = wgpu.ComputeState {
            module     = meta.shader.module,
            entryPoint = meta.entry,
        },
    })
    if pso == nil {
        return nil
    }
    key.pipeline = pso

    slot := int(_state.compute_pipeline_cache_next)
    old := &_state.compute_pipeline_cache[slot]
    _release_compute_pipeline(old)
    old^ = key
    _state.compute_pipeline_cache_next = u32((slot + 1) % MAX_PIPELINE_CACHE_ENTRIES)

    return key.pipeline
}

//////////////////////////////////////////////////////////////
// Interop

_primitive_type_interop :: proc(primitive: Primitive) -> wgpu.PrimitiveTopology {
    switch primitive {
    case .Triangle: return .TriangleList
    }
    unreachable()
}

_cull_mode_interop :: proc(cull_mode: Cull_Mode) -> wgpu.CullMode {
    switch cull_mode {
    case .None:  return .None
    case .Front: return .Front
    case .Back:  return .Back
    }
    unreachable()
}

_front_face_winding_interop :: proc(winding: Front_Face) -> wgpu.FrontFace {
    switch winding {
    case .CCW: return .CCW
    case .CW:  return .CW
    }
    unreachable()
}

_blend_operation_interop :: proc(op: Blend_Operation) -> wgpu.BlendOperation {
    switch op {
    case .Add:             return .Add
    case .Subtract:        return .Subtract
    case .ReverseSubtract: return .ReverseSubtract
    case .Min:             return .Min
    case .Max:             return .Max
    }
    unreachable()
}

_blend_factor_interop :: proc(f: Blend_Factor) -> wgpu.BlendFactor {
    switch f {
    case .Undefined:         return .Undefined
    case .Zero:              return .Zero
    case .One:               return .One
    case .Src:               return .Src
    case .OneMinusSrc:       return .OneMinusSrc
    case .SrcAlpha:          return .SrcAlpha
    case .OneMinusSrcAlpha:  return .OneMinusSrcAlpha
    case .Dst:               return .Dst
    case .OneMinusDst:       return .OneMinusDst
    case .DstAlpha:          return .DstAlpha
    case .OneMinusDstAlpha:  return .OneMinusDstAlpha
    case .SrcAlphaSaturated: return .SrcAlphaSaturated
    case .Constant:          return .Constant
    case .OneMinusConstant:  return .OneMinusConstant
    case .Src1:              return .Src1
    case .OneMinusSrc1:      return .OneMinusSrc1
    case .Src1Alpha:         return .Src1Alpha
    case .OneMinusSrc1Alpha: return .OneMinusSrc1Alpha
    }
    unreachable()
}

_compare_function_interop :: proc(compare: Compare_Function) -> wgpu.CompareFunction {
    switch compare {
    case .Never:
        return .Never
    case .Less:
        return .Less
    case .Equal:
        return .Equal
    case .LessEqual:
        return .LessEqual
    case .Greater:
        return .Greater
    case .NotEqual:
        return .NotEqual
    case .GreaterEqual:
        return .GreaterEqual
    case .Always:
        return .Always
    }
    unreachable()
}

_texture_dimension_interop :: proc(view: Texture_View) -> wgpu.TextureDimension {
    switch view {
    case ._1D:
        return ._1D
    case ._3D:
        return ._3D
    case ._2D, ._2D_Array, .Cube, .Cube_Array:
        return ._2D
    }
    unreachable()
}

_texture_view_dimension_interop :: proc(view: Texture_View) -> wgpu.TextureViewDimension {
    switch view {
    case ._1D:
        return ._1D
    case ._2D:
        return ._2D
    case ._2D_Array:
        return ._2DArray
    case ._3D:
        return ._3D
    case .Cube:
        return .Cube
    case .Cube_Array:
        return .CubeArray
    }
    unreachable()
}

_texture_usage_interop :: proc(usage: Texture_Usage_Info) -> wgpu.TextureUsageFlags {
    // Copies are always permitted and require no user-facing flag.
    flags: wgpu.TextureUsageFlags = {.CopySrc, .CopyDst}
    if usage.sampled          { flags += {.TextureBinding} }
    if usage.storage_read     { flags += {.StorageBinding} }
    if usage.storage_write    { flags += {.StorageBinding} }
    if usage.color_attachment { flags += {.RenderAttachment} }
    if usage.depth_attachment { flags += {.RenderAttachment} }
    return flags
}

_storage_access_interop :: proc(access: Texture_Access) -> wgpu.StorageTextureAccess {
    switch access {
    case .Read:       return .ReadOnly
    case .Write:      return .WriteOnly
    case .Read_Write: return .ReadWrite
    }
    unreachable()
}

_texture_sample_type_interop :: proc(format: wgpu.TextureFormat, samples: u32) -> wgpu.TextureSampleType {
    #partial switch format {
    case .Depth16Unorm, .Depth24Plus, .Depth24PlusStencil8, .Depth32Float, .Depth32FloatStencil8:
        return .Depth
    case .RGBA32Float:
        // Not filterable without the float32-filterable feature.
        return .UnfilterableFloat
    }
    // MSAA sample types must not be filterable.
    if samples > 1 {
        return .UnfilterableFloat
    }
    return .Float
}

_pixel_format_interop :: proc(format: Pixel_Format) -> wgpu.TextureFormat {
    switch format {
    case .None:
        return .Undefined
    case .BGRA8Unorm:
        return .BGRA8Unorm
    case .RGBA8Unorm:
        return .RGBA8Unorm
    case .RGBA32Float:
        return .RGBA32Float
    case .Depth32Float:
        return .Depth32Float
    }
    unreachable()
}

_store_action_interop :: proc(action: Store_Action) -> wgpu.StoreOp {
    switch action {
    case .Dont_Care:
        return .Undefined
    case .Store:
        return .Store
    }
    unreachable()
}

_load_action_interop :: proc(action: Load_Action) -> wgpu.LoadOp {
    switch action {
    case .Dont_Care:
        return .Undefined
    case .Clear:
        return .Clear
    case .Load:
        return .Load
    }
    unreachable()
}

_frame_interval_ns :: proc() -> u64 {
    // No presentedTime equivalent in WebGPU; the engine falls back to its
    // default frame budget.
    return 0
}

_set_hz :: proc(hz: u32) {
    // Browsers pace rAF to vsync; nothing to do here.
}

