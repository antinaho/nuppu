#+build js
#+vet explicit-allocators shadowing unused

package nuppu_gpu

import "vendor:wgpu"
import "core:fmt"
import "core:log"
import "core:strings"
import "base:runtime"

when GPU_BACKEND == GPU_BACKEND_WGPU {

    DEFAULT_PIPELINE_SETTINGS :: _Pipeline_Settings {
        multisample = {
            count = 1,
            mask = 0xFFFFFFFF,
        },
        blend = {
            alpha = {
                srcFactor = .SrcAlpha,
                dstFactor = .OneMinusSrcAlpha,
                operation = .Add,
            },
            color = {
                srcFactor = .SrcAlpha,
                dstFactor = .OneMinusSrcAlpha,
                operation = .Add,
            },
        },
        primitive = {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CCW,
        }
    }

    _ptr :: struct {
        buffer: wgpu.Buffer,
        offset: uint, // Byte offset of this view into `buffer` (0 for top-level allocations)
        capacity: uint, // Capacity of the ptr, NOT the buffer
        index_bytes: u8,
        is_mapped: bool,
        min_alignment: u32,
        binding_type: wgpu.BufferBindingType,
    }

    _Shader :: struct {
        module: wgpu.ShaderModule,
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
    }

    _Depth_Stencil_State :: wgpu.DepthStencilState

    _Compute_Pipeline :: struct {
        shader: Shader,
        entry: string,
    }

    _Pipeline :: struct {
        vertex_shader: Shader,
        vertex_function: string,
        fragment_shader: Shader,
        fragment_function: string,
        
        color_format: Pixel_Format,
        depth_format: Pixel_Format,
    }

    _Pipeline_Settings :: struct {
        multisample: wgpu.MultisampleState,
        blend: wgpu.BlendState,
        primitive: wgpu.PrimitiveState,
    }

    MAX_BG_LAYOUT_CACHE_ENTRIES :: 32
    MAX_PIPELINE_CACHE_ENTRIES  :: 32

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

    // Render pipeline cache key includes everything that affects the
    // generated wgpu.RenderPipeline: the bind group layout, the pipeline
    // descriptor (shaders, entry points, target formats), the depth stencil
    // state, the pipeline settings, and the color write mask.
    _Render_Pipeline_Cache_Entry :: struct {
        bg_layout:     wgpu.BindGroupLayout,
        meta:          Pipeline,
        depth_stencil: wgpu.DepthStencilState,
        settings:      _Pipeline_Settings,
        write_mask:    wgpu.ColorWriteMaskFlags,
        pipeline:      wgpu.RenderPipeline,
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

        curr_pipeline: Pipeline,
        curr_compute_pipeline: Compute_Pipeline,
        curr_depth_stencil_state: Depth_Stencil_State,


        settings: _Pipeline_Settings,

        // Fixed-capacity caches with circular overwrite on full. Empty
        // slots are detected by nil resource handles, so we don't need a
        // count field.
        bg_layout_cache:        [MAX_BG_LAYOUT_CACHE_ENTRIES]_BG_Layout_Cache_Entry,
        bg_layout_cache_next:   u32,

        render_pipeline_cache:      [MAX_PIPELINE_CACHE_ENTRIES]_Render_Pipeline_Cache_Entry,
        render_pipeline_cache_next: u32,

        compute_pipeline_cache:      [MAX_PIPELINE_CACHE_ENTRIES]_Compute_Pipeline_Cache_Entry,
        compute_pipeline_cache_next: u32,
    }

    _init :: proc(native_window: rawptr) -> bool {

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
            context = _state.ctx

            if status != .Success || adapter == nil {
                fmt.panicf("request adapter failure: [%v] %s", status, message)
            }

            _state.adapter = adapter
            wgpu.AdapterRequestDevice(adapter, nil, { callback = _handle_request_device, mode = .AllowProcessEvents })
        }

        _handle_request_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1, userdata2: rawptr) {
            context = _state.ctx
            
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
            _state.settings = DEFAULT_PIPELINE_SETTINGS

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

    _release_render_pipeline :: proc(e: ^_Render_Pipeline_Cache_Entry) {
        if e.pipeline != nil {
            wgpu.RenderPipelineRelease(e.pipeline)
            e.pipeline = nil
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
        for i in 0..<MAX_PIPELINE_CACHE_ENTRIES   do _release_render_pipeline(&_state.render_pipeline_cache[i])
        for i in 0..<MAX_PIPELINE_CACHE_ENTRIES   do _release_compute_pipeline(&_state.compute_pipeline_cache[i])
        _state.bg_layout_cache_next      = 0
        _state.render_pipeline_cache_next = 0
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

    _resize_depth_texture :: proc(width, height: u32) {
        if _state.depth_texture.native.view == nil {
            _state.depth_texture = texture_depth_init({width, height}, .Depth32Float)    
        } else {
            wgpu.TextureViewRelease(_state.depth_texture.native.view)
            wgpu.TextureRelease(_state.depth_texture.native.texture)
            _state.depth_texture = texture_depth_init({width, height}, .Depth32Float)    
        }
    }

    _copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
        destination := wgpu.TexelCopyTextureInfo {
            texture  = texture.native.texture,
            mipLevel = level,
            origin   = wgpu.Origin3D { u32(origin.x), u32(origin.y), u32(origin.z) },
            aspect   = .All,
        }
        layout := wgpu.TexelCopyBufferLayout {
            offset       = 0,
            bytesPerRow  = bytes_per_row,
            rowsPerImage = u32(size.y),
        }
        write_size := wgpu.Extent3D {
            width              = u32(size.x),
            height             = u32(size.y),
            depthOrArrayLayers = u32(size.z),
        }
        data_size := uint(bytes_per_row) * uint(size.y) * uint(max(size.z, 1))

        wgpu.QueueWriteTexture(_state.queue, &destination, data, data_size, &layout, &write_size)
    }

    _depth_stencil_state_init :: proc(depth_descriptor: Depth_Stencil_State_Descriptor) -> _Depth_Stencil_State {
        optional_bool: wgpu.OptionalBool
        switch depth_descriptor.write_enabled {
        case true:
            optional_bool = .True
        case false:
            optional_bool = .False
        }

        dpso: wgpu.DepthStencilState
        dpso.depthWriteEnabled = optional_bool
        dpso.depthCompare = _compare_function_interop(depth_descriptor.compare)

        return dpso
    }

    _shader_init :: proc(name: string, code: []u8) -> _Shader {
        module := wgpu.DeviceCreateShaderModule(_state.device, &{
            nextInChain = &wgpu.ShaderSourceWGSL {
                sType = .ShaderSourceWGSL,
                code = string(code),
            }
        })

        result := _Shader {
            module = module,
        }

        return result
    }

    _pipeline_init :: proc(vertex, fragment: Shader_IR, pipeline_descriptor: Pipeline_Descriptor) -> _Pipeline {
        result := _Pipeline {
            vertex_shader = vertex.shader,
            vertex_function = strings.clone(vertex.entry_point, context.allocator),
            fragment_shader = fragment.shader,
            fragment_function = strings.clone(fragment.entry_point, context.allocator),
            color_format = pipeline_descriptor.color_format,
            depth_format = pipeline_descriptor.depth_format,
        }

        return result
    }

    _compute_pipeline_init :: proc(shader: Shader, entry_point: string) -> _Compute_Pipeline {
        return _Compute_Pipeline {
            shader = shader,
            entry  = strings.clone(entry_point, context.allocator),
        }
    }

    _begin_commands :: proc() {
        _state.command_encoder = wgpu.DeviceCreateCommandEncoder(_state.device, nil)
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

    _end_frame :: proc() {
        finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
        defer {
            wgpu.CommandBufferRelease(finished)
            wgpu.CommandEncoderRelease(_state.command_encoder)
        }
        wgpu.QueueSubmit(_state.queue, []wgpu.CommandBuffer{finished})
        _state.command_encoder = nil
    
        wgpu.SurfacePresent(_state.surface)
    }

    _acquire_next_swapchain :: proc() -> _Texture {
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

        result := _Texture {
            surface_texture = surface_texture,
            view = view,
        }

        return result
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

    _set_pipeline :: proc(pipeline: Pipeline) {
        _state.curr_pipeline = pipeline
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
        desc: wgpu.TextureDescriptor
        desc.size = {texture_descriptor.dimensions.x, texture_descriptor.dimensions.y, 1}
        desc.mipLevelCount = 1
        desc.sampleCount = 1
        desc.dimension = _texture_type_interop(texture_descriptor.type)
        desc.format = _pixel_format_interop(texture_descriptor.format)
        desc.usage = _texture_usage_interop(texture_descriptor.usage, texture_descriptor.storage)

        texture := wgpu.DeviceCreateTexture(_state.device, &desc)
        if texture == nil {
            log.panic("gpu_wgpu.odin: MTL_texture_init: failed to create texture")
        }

        view := wgpu.TextureCreateView(texture, nil)

        return _Texture {
            texture = texture,
            view = view,
            access = _texture_access_interop(texture_descriptor.usage),
        }
    }

    _set_depth_stencil_state :: proc(depth_stencil_state: Depth_Stencil_State) {
        _state.curr_depth_stencil_state = depth_stencil_state
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
    }

    _end_render_pass :: proc() {
        wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
        wgpu.RenderPassEncoderRelease(_state.render_pass_encoder)
    }

    _set_cull_mode :: proc(cull_mode: Cull_Mode) {
    }

    _set_front_face_winding :: proc(winding: Front_Face) {   
    }

    _draw_indiced_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
        pipeline := _state.curr_pipeline

        bg_layout, pso_layout := _get_or_create_bg_layout()
        pso := _get_or_create_render_pipeline(
            bg_layout, pso_layout, pipeline,
            _state.curr_depth_stencil_state.native, _state.settings,
        )

        frame_bg := wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
            layout     = bg_layout,
            entryCount = uint(_state.parameter_count),
            entries    = raw_data(_state.bg_entries[:_state.parameter_count]),
        })

        wgpu.RenderPassEncoderSetPipeline(_state.render_pass_encoder, pso)
        wgpu.RenderPassEncoderSetBindGroup(_state.render_pass_encoder, /* bind group index */ 0, frame_bg, nil)

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

        wgpu.BindGroupRelease(frame_bg)
    }

    _malloc :: proc(
        type: Buffer_Type,
        #any_int el_count: uint,
        #any_int el_size: uint,
        #any_int alignment: uint,
        name: string
    ) -> _ptr {
        bytes := runtime.align_forward_uint(el_count * el_size, alignment)

        usage: wgpu.BufferUsageFlags
        binding_type: wgpu.BufferBindingType
        min_alignment: u32

        switch type {
        case .Staging:
            usage  = {.CopySrc, .MapWrite}
            binding_type = .ReadOnlyStorage
            min_alignment = 4
        case .GPU_Storage:
            usage  = {.CopyDst, .Storage}
            binding_type = .ReadOnlyStorage
            bytes = runtime.align_forward_uint(bytes, uint(_state.storage_offset_align))
            min_alignment = _state.storage_offset_align
        case .GPU_Constant:
            usage  = {.CopyDst, .Uniform}
            binding_type = .Uniform
            bytes = runtime.align_forward_uint(bytes, uint(_state.uniform_offset_align))
            min_alignment = _state.uniform_offset_align
        case .GPU_Index:
            usage  = {.CopyDst, .Index}
            binding_type = .ReadOnlyStorage
            bytes = runtime.align_forward_uint(bytes, uint(_state.index_offset_align))
            min_alignment = _state.index_offset_align
        case .Readback:
            usage  = {.CopyDst, .MapRead}
            binding_type = .ReadOnlyStorage
            panic("not implemented")
        }

        buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
            label = name,
            usage = usage,
            size = u64(bytes),
            mappedAtCreation = type == .Staging,
        })

        return _ptr {
            buffer = buffer,
            offset = 0,
            is_mapped = bool(type == .Staging),
            capacity = uint(bytes),
            binding_type = binding_type,
            index_bytes = u8(el_size) if type == .GPU_Index else 0,
            min_alignment = min_alignment,
        }
    }

    _capacity :: proc(ptr: _ptr) -> uint {
        return ptr.capacity
    }

    _min_alignment :: proc(ptr: _ptr) -> u32 {
        return ptr.min_alignment
    }

    _unmap :: proc(ptr: ^_ptr) {
        if !ptr.is_mapped {
            return
        }

        wgpu.BufferUnmap(ptr.buffer)
        ptr.is_mapped = false
    }

    _copy :: proc(dst, src: ptr) {
        wgpu.CommandEncoderCopyBufferToBuffer(
            _state.command_encoder,
            src.native.buffer,
            u64(src.native.offset),
            dst.native.buffer,
            u64(dst.native.offset),
            u64(src.capacity),
        )
    }

    _cpu_address :: proc(p: _ptr) -> rawptr {
        assert(p.is_mapped)
        return wgpu.RawBufferGetMappedRange(p.buffer, 0, p.capacity)
    }

    _gpu_address :: proc(p: _ptr) -> rawptr {
        return nil
    }

    _mapped :: proc(ptr: ptr) -> bool {
        return ptr.is_mapped
    }

    _frame_arena :: proc() -> ^Arena {
        if len(_state.frame_arenas) == 0 {
            new_arena := new(Arena, context.allocator)
            new_arena^ = arena_init()
            return new_arena
        } else {
            arena := pop(&_state.frame_arenas)
            arena.ptr.is_mapped = true
            arena.ptr.cpu = _cpu_address(arena.ptr.native)
            arena.offset = 0
            return arena
        }
    }

    _recycle_frame_arena :: proc(arena: ^Arena) {

        //BufferMapCallback :: #type proc "c" (status: MapAsyncStatus, message: StringView, userdata1: rawptr, userdata2: rawptr)
        callback_ :: proc "c" (status: wgpu.MapAsyncStatus, message: wgpu.StringView, userdata1: rawptr, userdata2: rawptr) {
            context = _state.ctx
            if status != .Success {
                log.errorf("gpu_frame_arena_deinit: failed to map arena %v", message)
                return
            }
            arena := (^Arena)(userdata1)
            append(&_state.frame_arenas, arena)
        }

        _unmap(&arena.ptr.native)

        wgpu.BufferMapAsync(arena.ptr.buffer, {.Write}, 0, arena.ptr.capacity, wgpu.BufferMapCallbackInfo {
            mode = .AllowProcessEvents,
            callback = callback_,
            userdata1 = arena,
        })
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
                offset  = u64(C.offset),
                size    = max(u64(C.capacity), u64(_state.uniform_offset_align)),
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
                    offset  = u64(res.offset),
                    size    = u64(res.capacity),
                }

                count += 1
            case Texture:
                if res.native.texture == nil { continue }

                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding = u32(count),
                    visibility = {.Vertex, .Fragment, .Compute},
                    texture = wgpu.TextureBindingLayout{
                        sampleType = .Float,
                        viewDimension = ._2D,
                        multisampled = false,
                    },
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
                    offset  = u64(res.offset),
                    size    = u64(res.capacity),
                }

                count += 1
            case Texture:
                if res.native.texture == nil { continue }

                bg_layout_entries[count] = wgpu.BindGroupLayoutEntry{
                    binding = u32(count),
                    visibility = {.Vertex, .Fragment} if destination == .Graphics else {.Compute},
                    storageTexture = wgpu.StorageTextureBindingLayout{
                        access = res.native.access,
                        format = wgpu.TextureGetFormat(res.native.texture),
                        viewDimension = ._2D,
                    },
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

    _semaphore :: proc(value: u64) -> Semaphore {
        /* no op */
        return {}
    }

    _semaphore_wait :: proc(semaphore: Semaphore, value: u64) -> bool {
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

    _render_pipeline_entry_equal :: proc(a, b: ^_Render_Pipeline_Cache_Entry) -> bool {
        return a.bg_layout     == b.bg_layout     &&
               a.meta          == b.meta          &&
               a.depth_stencil == b.depth_stencil &&
               a.settings      == b.settings      &&
               a.write_mask    == b.write_mask
    }

    _get_or_create_render_pipeline :: proc(
        bg_layout:     wgpu.BindGroupLayout,
        pso_layout:    wgpu.PipelineLayout,
        meta:          Pipeline,
        depth_stencil: wgpu.DepthStencilState,
        settings:      _Pipeline_Settings,
    ) -> wgpu.RenderPipeline {
        write_mask := wgpu.ColorWriteMaskFlags_All
        key := _Render_Pipeline_Cache_Entry {
            bg_layout     = bg_layout,
            meta          = meta,
            depth_stencil = depth_stencil,
            settings      = settings,
            write_mask    = write_mask,
        }

        for i in 0..<MAX_PIPELINE_CACHE_ENTRIES {
            e := &_state.render_pipeline_cache[i]
            if e.pipeline == nil { continue }
            if _render_pipeline_entry_equal(e, &key) {
                return e.pipeline
            }
        }

        // Local copy of settings so we can take the address of fields for
        // descriptor pointers; Odin does not let you take the address of a
        // parameter's field directly.
        settings_local := settings
        target := wgpu.ColorTargetState{
            format    = _pixel_format_interop(meta.color_format),
            blend     = &settings_local.blend,
            writeMask = write_mask,
        }

        v_state := wgpu.VertexState{
            module      = meta.vertex_shader.module,
            entryPoint  = meta.vertex_function,
            bufferCount = 0,
            buffers     = nil,
        }
        f_state := wgpu.FragmentState{
            module      = meta.fragment_shader.module,
            entryPoint  = meta.fragment_function,
            targetCount = 1,
            targets     = &target,
        }

        depth_format_wgpu := _pixel_format_interop(meta.depth_format)
        dpso: wgpu.DepthStencilState
        if depth_format_wgpu != .Undefined {
            dpso = depth_stencil
            dpso.format = depth_format_wgpu
        }

        pso := wgpu.DeviceCreateRenderPipeline(_state.device, &wgpu.RenderPipelineDescriptor{
            layout       = pso_layout,
            vertex       = v_state,
            primitive    = settings_local.primitive,
            multisample  = settings_local.multisample,
            fragment     = &f_state,
            depthStencil = nil if depth_format_wgpu == .Undefined else &dpso,
        })
        if pso == nil {
            return nil
        }
        key.pipeline = pso

        slot := int(_state.render_pipeline_cache_next)
        old := &_state.render_pipeline_cache[slot]
        _release_render_pipeline(old)
        old^ = key
        _state.render_pipeline_cache_next = u32((slot + 1) % MAX_PIPELINE_CACHE_ENTRIES)

        return pso
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
        case ._2D:
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

}