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

    bg_layout:       wgpu.BindGroupLayout,
    pipeline_layout: wgpu.PipelineLayout,
    bind_group:      wgpu.BindGroup,

    layout_count: u32,
    layout_sig:   [MAX_LAYOUT_BINDINGS]wgpu.BindGroupLayoutEntry,

    variants:      [MAX_SHADER_VARIANTS]_Shader_Variant,
    variant_count: u32,
}

_Sampler :: struct {
    s: wgpu.Sampler,
}

_Texture :: struct {
    using _ : struct #raw_union {
        surface_texture: wgpu.SurfaceTexture,
        texture: wgpu.Texture,
    },
    view:   wgpu.TextureView,
    access: wgpu.StorageTextureAccess,
    type:   Texture_Type,
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

    uniform_offset_align: u32,
    storage_offset_align: u32,
    index_offset_align: u32,
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

        _state.uniform_offset_align = limits.minUniformBufferOffsetAlignment
        _state.storage_offset_align = limits.minStorageBufferOffsetAlignment
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
    if texture.native.view != nil {
        wgpu.TextureViewRelease(texture.native.view)
        texture.native.view = nil
    }
    if texture.native.texture != nil {
        wgpu.TextureRelease(texture.native.texture)
        texture.native.texture = nil
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

_copy_to_texture :: proc(texture: Texture, origin, size: [3]u32, level: u32, data: rawptr, bytes_per_row: u32) {
    destination := wgpu.TexelCopyTextureInfo {
        texture  = texture.native.texture,
        mipLevel = level,
        origin   = wgpu.Origin3D { origin.x, origin.y, origin.z },
        aspect   = .All,
    }
    layout := wgpu.TexelCopyBufferLayout {
        offset       = 0,
        bytesPerRow  = bytes_per_row,
        rowsPerImage = size.y,
    }
    write_size := wgpu.Extent3D {
        width              = size.x,
        height             = size.y,
        depthOrArrayLayers = 1,
    }
    data_size := uint(bytes_per_row) * uint(size.y)

    wgpu.QueueWriteTexture(_state.queue, &destination, data, data_size, &layout, &write_size)
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

// Builds/rebuilds the bind group layout, pipeline layout and bind group from
// the block. Called at shader_init and again on set_parameter_block.
_shader_build_bindings :: proc(shader: ^_Shader, block: Parameter_Block) {
    b := block
    _use_parameter_block(&b, .Graphics)
    count := _state.parameter_count

    shader.layout_count = count
    for i in 0 ..< int(count) {
        shader.layout_sig[i] = _state.bg_layout_entries[i]
    }

    shader.bg_layout = wgpu.DeviceCreateBindGroupLayout(_state.device, &{
        entryCount = uint(count),
        entries    = raw_data(_state.bg_layout_entries[:count]),
    })
    assert(shader.bg_layout != nil, "_shader_build_bindings: failed to create bind group layout")

    shader.pipeline_layout = wgpu.DeviceCreatePipelineLayout(_state.device, &{
        bindGroupLayoutCount = 1,
        bindGroupLayouts     = &shader.bg_layout,
    })
    assert(shader.pipeline_layout != nil, "_shader_build_bindings: failed to create pipeline layout")

    shader.bind_group = _create_bind_group(shader.bg_layout, count)
}

_create_bind_group :: proc(layout: wgpu.BindGroupLayout, count: u32) -> wgpu.BindGroup {
    bg := wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
        layout     = layout,
        entryCount = uint(count),
        entries    = raw_data(_state.bg_entries[:count]),
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

    _shader_build_bindings(&shader, d.block)
    pso := _shader_create_pipeline(&shader, &d, DEFAULT_DRAW_STATE)
    shader.variants[0] = _Shader_Variant { state = DEFAULT_DRAW_STATE, pipeline = pso }
    shader.variant_count = 1

    return shader
}

_shader_deinit :: proc(shader: ^Shader) {
    for i in 0 ..< shader.variant_count {
        wgpu.RenderPipelineRelease(shader.variants[i].pipeline)
    }
    shader.variant_count = 0

    if shader.bind_group != nil {
        wgpu.BindGroupRelease(shader.bind_group)
        shader.bind_group = nil
    }
    if shader.pipeline_layout != nil {
        wgpu.PipelineLayoutRelease(shader.pipeline_layout)
        shader.pipeline_layout = nil
    }
    if shader.bg_layout != nil {
        wgpu.BindGroupLayoutRelease(shader.bg_layout)
        shader.bg_layout = nil
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
        surface_texture = surface_texture,
        view = view,
        type = ._2D,
    }

    return Texture {
        dimensions = { _state.config.width, _state.config.height, 1 },
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

    if _state.curr_shader_valid && _state.curr_shader == rawptr(shader) {
        return
    }
    _state.curr_shader = rawptr(shader)
    _state.curr_shader_valid = true
    _state.pipeline_dirty = true

    wgpu.RenderPassEncoderSetBindGroup(_state.render_pass_encoder, 0, shader.bind_group, nil)
}

_set_draw_state :: proc(state: Draw_State) {
    if _state.draw_state_valid && _state.curr_draw_state == state {
        return
    }
    _state.curr_draw_state = state
    _state.draw_state_valid = true
    _state.pipeline_dirty = true
}

_set_parameter_block :: proc(shader: ^Shader, block: ^Parameter_Block) {
    shader.desc.block = block^

    b := block^
    _use_parameter_block(&b, .Graphics)
    new_count := _state.parameter_count

    same_layout := new_count == shader.native.layout_count
    if same_layout {
        for i in 0 ..< int(new_count) {
            if shader.native.layout_sig[i] != _state.bg_layout_entries[i] {
                same_layout = false
                break
            }
        }
    }

    if same_layout {
        // Fast path: only the resource references changed, so destroy and
        // recreate the bind group against the existing layout. Pipelines
        // stay valid because the layout is identical.
        if shader.bind_group != nil {
            wgpu.BindGroupRelease(shader.bind_group)
        }
        shader.bind_group = _create_bind_group(shader.bg_layout, new_count)
    } else {
        // Layout changed: rebuild layout, pipelines and bind group.
        for i in 0 ..< shader.variant_count {
            wgpu.RenderPipelineRelease(shader.variants[i].pipeline)
        }
        shader.variant_count = 0
        if shader.bind_group != nil {
            wgpu.BindGroupRelease(shader.bind_group)
            shader.bind_group = nil
        }
        if shader.pipeline_layout != nil {
            wgpu.PipelineLayoutRelease(shader.pipeline_layout)
            shader.pipeline_layout = nil
        }
        if shader.bg_layout != nil {
            wgpu.BindGroupLayoutRelease(shader.bg_layout)
            shader.bg_layout = nil
        }

        _shader_build_bindings(&shader.native, b)
        pso := _shader_create_pipeline(&shader.native, &shader.desc, _state.curr_draw_state)
        shader.variant_count = 1
        shader.variants[0] = _Shader_Variant { state = _state.curr_draw_state, pipeline = pso }
    }

    if _state.curr_shader_valid && _state.curr_shader == rawptr(shader) {
        _state.pipeline_dirty = true
        wgpu.RenderPassEncoderSetBindGroup(_state.render_pass_encoder, 0, shader.bind_group, nil)
    }
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

_texture_init :: proc(texture_descriptor: Texture_Descriptor) -> _Texture {
    layers := max(texture_descriptor.layer_count, 1)
    mip_levels := max(texture_descriptor.mip_levels, 1)

    desc: wgpu.TextureDescriptor
    desc.size = {texture_descriptor.dimensions.x, texture_descriptor.dimensions.y, layers}
    desc.mipLevelCount = mip_levels
    desc.sampleCount = 1
    desc.dimension = _texture_type_interop(texture_descriptor.type)
    desc.format = _pixel_format_interop(texture_descriptor.format)
    desc.usage = _texture_usage_interop(texture_descriptor.usage, texture_descriptor.storage)

    texture := wgpu.DeviceCreateTexture(_state.device, &desc)
    if texture == nil {
        log.panic("gpu_wgpu.odin: MTL_texture_init: failed to create texture")
    }

    switch texture_descriptor.type {
    case ._2D:
        return _Texture {
            texture = texture,
            view = wgpu.TextureCreateView(texture, nil),
            access = _texture_access_interop(texture_descriptor.usage),
            type = ._2D,
        }
    case ._2D_Array:
        view_desc := wgpu.TextureViewDescriptor {
            dimension = ._2DArray,
            mipLevelCount = mip_levels,
            arrayLayerCount = layers,
        }
        return _Texture {
            texture = texture,
            view = wgpu.TextureCreateView(texture, &view_desc),
            access = _texture_access_interop(texture_descriptor.usage),
            type = ._2D_Array,
        }
    }
    unreachable()
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

_draw_indexed :: proc(index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
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
        indexCount    = index_count,
        instanceCount = instance_count,
        firstIndex    = 0,
        baseVertex    = i32(base_vertex),
        firstInstance = base_instance,
    )
}

_malloc :: proc(
    #any_int bytes: uint,
    alignment: u32,
    flags: Buffer_Flag,
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
        shadow_bytes, err := runtime.mem_alloc(int(aligned_bytes), 16, context.allocator)
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

_min_alignment :: proc(flags: Buffer_Flag) -> u32 {
    switch flags {
    case .Staging:  return 4
    case .Default:  return _state.storage_offset_align
    case .Constant: return _state.uniform_offset_align
    case .Index:    return _state.index_offset_align
    }
    unreachable()
}

_copy :: proc(dst, src: ptr) {
    if src.flags == .Staging {
        if src.cpu == nil { return }

        rel := uint(0) // rel := uint(max(offset, 0))
        length := -1
        len := uint(src.total_capacity_bytes) - rel if length < 0 else uint(length)

        if len == 0 { return }

        assert(rel % 4 == 0 && len % 4 == 0, "_flush: QueueWriteBuffer offset/size must be 4-byte aligned")

        wgpu.QueueWriteBuffer(
            _state.queue,
            src.native.buffer,
            u64(uint(src.byte_offset) + rel),
            rawptr(uintptr(src.cpu) + uintptr(rel)),
            len,
        )
    }

    wgpu.CommandEncoderCopyBufferToBuffer(
        _state.command_encoder,
        src.native.buffer,
        u64(uint(src.byte_offset)),
        dst.native.buffer,
        u64(uint(dst.byte_offset)),
        u64(src.total_capacity_bytes),
    )
}

_cpu_address :: proc(p: _ptr) -> rawptr {
    return p.shadow
}

_gpu_address :: proc(p: _ptr) -> rawptr {
    return nil
}

_use_parameter_block :: proc(block: ^Parameter_Block, destination: Parameter_Block_Destination) {
    bg_layout_entries := &_state.bg_layout_entries
    bg_entries := &_state.bg_entries
    count: u32

    for C in block.constants {
        if C.native.buffer == nil { continue }

        bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
            binding    = u32(count),
            visibility = {.Vertex, .Fragment, .Compute},
            buffer = wgpu.BufferBindingLayout{
                type             = .Uniform,
                hasDynamicOffset = false,
                minBindingSize   = 0,
            },
        }

        bg_entries[count] = wgpu.BindGroupEntry{
            binding = u32(count),
            buffer  = C.buffer,
            offset  = u64(C.byte_offset),
            size    = max(u64(C.total_capacity_bytes), u64(_state.uniform_offset_align)),
        }

        count += 1
    }

    for R in block.read_resources {
        switch res in R {
        case ptr:
            if res.native.buffer == nil { continue }

            bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                binding    = u32(count),
                visibility = {.Vertex, .Fragment, .Compute},
                buffer = wgpu.BufferBindingLayout{
                    type             = .ReadOnlyStorage,
                    hasDynamicOffset = false,
                    minBindingSize   = 0,
                },
            }

            bg_entries[count] = wgpu.BindGroupEntry{
                binding = u32(count),
                buffer  = res.buffer,
                offset  = u64(res.byte_offset),
                size    = u64(res.total_capacity_bytes),
            }

            count += 1
        case Texture:
            if res.native.texture == nil { continue }

            switch res.native.type {
            case ._2D:
                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding = u32(count),
                    visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
                    texture = wgpu.TextureBindingLayout{
                        sampleType = .Float,
                        viewDimension = ._2D,
                        multisampled = false,
                    },
                }
            case ._2D_Array:
                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding = u32(count),
                    visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
                    texture = wgpu.TextureBindingLayout{
                        sampleType = .Float,
                        viewDimension = ._2DArray,
                        multisampled = false,
                    },
                }
            }

            bg_entries[count] = wgpu.BindGroupEntry{
                binding = u32(count),
                textureView = res.native.view,
            }

            count += 1
        }
    }

    for RW in block.read_write_resources {
        switch res in RW {
        case ptr:
            if res.native.buffer == nil { continue }

            bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                binding    = u32(count),
                visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
                buffer = wgpu.BufferBindingLayout{
                    type             = .Storage,
                    hasDynamicOffset = false,
                    minBindingSize   = 0,
                },
            }

            bg_entries[count] = wgpu.BindGroupEntry{
                binding = u32(count),
                buffer  = res.buffer,
                offset  = u64(res.byte_offset),
                size    = u64(res.total_capacity_bytes),
            }

            count += 1
        case Texture:
            if res.native.texture == nil { continue }

            switch res.native.type {
            case ._2D:
                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding = u32(count),
                    visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
                    storageTexture = wgpu.StorageTextureBindingLayout{
                        access = res.native.access,
                        format = wgpu.TextureGetFormat(res.native.texture),
                        viewDimension = ._2D,
                    },
                }
            case ._2D_Array:
                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding = u32(count),
                    visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
                    storageTexture = wgpu.StorageTextureBindingLayout{
                        access = res.native.access,
                        format = wgpu.TextureGetFormat(res.native.texture),
                        viewDimension = ._2DArray,
                    },
                }
            }

            bg_entries[count] = wgpu.BindGroupEntry{
                binding = u32(count),
                textureView = res.native.view,
            }

            count += 1
        }
    }
    
    for S in block.samplers {
        if S.native.s == nil { continue }

        bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
            binding = u32(count),
            visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
            sampler = wgpu.SamplerBindingLayout{
                type = .Filtering,
            },
        }

        bg_entries[count] = wgpu.BindGroupEntry{
            binding = u32(count),
            sampler = S.native.s,
        }

        count += 1
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

_texture_type_interop :: proc(texture_type: Texture_Type) -> wgpu.TextureDimension {
    switch texture_type {
    case ._2D, ._2D_Array:
        return ._2D
    }
    unreachable()
}

_texture_usage_interop :: proc(usage: Texture_Usage, storage: StorageMode) -> wgpu.TextureUsageFlags {
    flags: wgpu.TextureUsageFlags
    if .Sampled          in usage { flags += {.TextureBinding} }
    if .Read             in usage { flags += {.StorageBinding} }
    if .Write            in usage { flags += {.StorageBinding} }
    if .Color_Attachment in usage { flags += {.RenderAttachment, .TextureBinding} }
    if .Depth_Attachment in usage { flags += {.RenderAttachment} }
    if storage == .Shared && (.Sampled in usage || .Read in usage || .Write in usage) {
        flags += {.CopyDst}
    }
    return flags
}

_texture_access_interop :: proc(usage: Texture_Usage) -> wgpu.StorageTextureAccess {
    read  := .Read in usage
    write := .Write in usage
    switch {
    case read && write:  return .ReadWrite
    case write:          return .WriteOnly
    case read:           return .ReadOnly
    }
    return .WriteOnly
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

