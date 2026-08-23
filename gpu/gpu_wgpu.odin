#+build js
package nuppu_gpu

import "vendor:wgpu"
import "core:fmt"
import "core:log"
import "core:strings"
import "base:runtime"
import hm "core:container/handle_map"

when GPU_BACKEND == GPU_BACKEND_WGPU {

    _State :: struct {
        instance: wgpu.Instance,
        surface: wgpu.Surface,
        adapter: wgpu.Adapter,
        device: wgpu.Device,
        config: wgpu.SurfaceConfiguration,
        queue: wgpu.Queue,

        //

        command_encoder: wgpu.CommandEncoder,
        render_pass_encoder: wgpu.RenderPassEncoder,

        curr_pipeline: Pipeline_Handle,
        curr_depth_stencil_state: Depth_Stencil_Handle,
        uniform_offset_align: u32,
        curr_cull_mode: Cull_Mode,
        winding: Front_Face,
    }

    _Shader :: struct {
        module: wgpu.ShaderModule,
    }

    _ptr :: struct {
        buffer: wgpu.Buffer,
        offset: uint, // Byte offset of this view into `buffer` (0 for top-level allocations)
        capacity: uint, // Capacity of the ptr, NOT the buffer
        index_bytes: u8,
        is_mapped: bool,
        binding_type: wgpu.BufferBindingType, // .Uniform for .GPU_Constant, .ReadOnlyStorage otherwise
    }

    _Pipeline :: struct {
        // vs_module, fs_module: wgpu.ShaderModule,
        // vs_entry, fs_entry:   string,
        // color_target_format:  wgpu.TextureFormat,
        // primitive_state:      wgpu.PrimitiveState,
        // multisample_state:    wgpu.MultisampleState,
        // blend_state:          wgpu.BlendState,
    }

    _Texture :: struct {
        T: union {
            wgpu.SurfaceTexture,
            wgpu.Texture,
        },
        view: wgpu.TextureView,
    }

    _resize_depth_texture :: proc(width, height: i32) {
        x, y := _state.config.width, _state.config.height
        texture_impl := hm.static_get(&_state.textures, _state.depth_texture)

        wgpu.TextureViewRelease(texture_impl.view)
        wgpu.TextureRelease(texture_impl.T.(wgpu.Texture))

        hm.static_remove(&_state.textures, _state.depth_texture)

        _state.depth_texture = texture_depth_init({u32(x), u32(y)}, .Depth32Float)
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

            _state.is_init = true
        }
    }

    _resize_swapchain :: proc(width, height: i32) -> bool {
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

    _deinit :: proc() {

    }

    _acquire_next_swapchain :: proc() -> Texture {
        tex := wgpu.SurfaceGetCurrentTexture(_state.surface)
        switch tex.status {
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
            fmt.panicf("get_current_texture status=%v", tex.status)
        }

        view := wgpu.TextureCreateView(tex.texture, nil)

        result := Texture {
            T = tex,
            view = view,
        }

        return result
    }

    //////////////////////////////////////////////////////////////
    // Render primitive initialization

    _shader_init :: proc(name: string, code: []u8) -> Shader_Handle {
        module := wgpu.DeviceCreateShaderModule(_state.device, &{
            nextInChain = &wgpu.ShaderSourceWGSL {
                sType = .ShaderSourceWGSL,
                code = string(code),
            }
        })

        handle := hm.static_add(&_state.shaders, Shader {
            module = module,
        })

        return handle
    }

    _pipeline_init :: proc(vertex_shader: Shader_Handle, vertex_function_entry: string, fragment_shader: Shader_Handle, fragment_function_entry: string, format: Pixel_Format, depth_format: Pixel_Format = .Depth32Float) -> Pipeline_Handle {

        handle := hm.static_add(&_state.pipelines, Pipeline_Descriptor {
                vertex_shader = vertex_shader,
                vertex_function = strings.clone(vertex_function_entry),
                
                fragment_shader = fragment_shader,
                fragment_function = strings.clone(fragment_function_entry),

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
                    topology = .Triangle,
                },
                
                depth_format = depth_format,
                format = format,
            }
        )

        _state.curr_pipeline = handle
        
        return handle
    }

    //////////////////////////////////////////////////////////////
    // Render loop commands

    _begin_frame :: proc() {
        _state.command_encoder = wgpu.DeviceCreateCommandEncoder(_state.device, nil)
    }

    _semaphore :: proc(value: u64) -> Semaphore {
        /* no op */
        return {}
    }

    _semaphore_wait :: proc(semaphore: Semaphore, value: u64) -> bool {
        /* no op */
        return true
    }

    _end_frame :: proc() {
        wgpu.SurfacePresent(_state.surface)
    }

    _set_front_face_winding :: proc(winding: Front_Face) {
        _state.winding = winding
    }

    _begin_render_pass :: proc(c_attachment: Color_Attachment, d_attachment: Depth_Attachment) {

        res: wgpu.RenderPassColorAttachment
        res.view = c_attachment.texture.view
        res.storeOp = _store_action_interop(c_attachment.store_action)
        res.loadOp = _load_action_interop(c_attachment.load_action)
        res.clearValue = from_4xu8_to_4xf64_color(c_attachment.clear_color)
        res.depthSlice = wgpu.DEPTH_SLICE_UNDEFINED

        depth: wgpu.RenderPassDepthStencilAttachment
        if d_attachment.texture != NIL_TEXTURE_HANDLE {
            texture_impl := hm.static_get(&_state.textures, d_attachment.texture)
            depth.view = texture_impl.view
            depth.depthClearValue = 1
            depth.depthLoadOp = _load_action_interop(d_attachment.load_action)
            depth.depthStoreOp = _store_action_interop(d_attachment.store_action)
        }
        
	// depthClearValue: f32,
	// depthReadOnly: b32,
	// stencilLoadOp: LoadOp,
	// stencilStoreOp: StoreOp,
	// stencilClearValue: u32,
	// stencilReadOnly: b32,

        desc := wgpu.RenderPassDescriptor {
            colorAttachmentCount = 1,
            colorAttachments = &res,
            depthStencilAttachment = nil if d_attachment.texture == NIL_TEXTURE_HANDLE else &depth,
        }

        _state.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(_state.command_encoder, &desc)
    }

    _end_render_pass :: proc() {
        wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
        wgpu.RenderPassEncoderRelease(_state.render_pass_encoder)
    }

        _set_pipeline :: proc(pipeline: Pipeline_Handle) {
        _state.curr_pipeline = pipeline
    }

    _set_depth_stencil_state :: proc(depth_stencil_state: Depth_Stencil_Handle) {
        _state.curr_depth_stencil_state = depth_stencil_state
    }

    _set_cull_mode :: proc(cull_mode: Cull_Mode) {
        _state.curr_cull_mode = cull_mode
    }

    _set_buffers :: proc(buffers: []ptr, range: Range, stage: Shader_Stage) {
        assert(len(buffers) > 0)
        assert(len(buffers) == int(range.length))

        pipe_desc := hm.static_get(&_state.pipelines, _state.curr_pipeline)

        for slot in range.location ..< range.location + range.length {
            i := slot - range.location

            ptr := buffers[i]
            assert(ptr.index_bytes == 0) // index buffers go through SetIndexBuffer, not bind groups

            pipe_desc.buffers[i] = buffers[i]
        }
    }

    _Depth_Stencil_State :: wgpu.DepthStencilState

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

    _texture_usage_interop :: proc(usage: Texture_Usage_Flags) -> wgpu.TextureUsage {
        switch usage {
        case .ShaderRead:
            return .StorageBinding
        case .ShaderWrite:
            return .StorageBinding
        case .RenderTarget:
            return .RenderAttachment
        }
        unreachable()
    }
    
    _texture_init :: proc(texture_descriptor: Texture_Descriptor) -> _Texture {
        desc: wgpu.TextureDescriptor
        desc.size = {texture_descriptor.dimensions.x, texture_descriptor.dimensions.y, 1}
        desc.mipLevelCount = 1
        desc.sampleCount = 1
        desc.dimension = _texture_type_interop(texture_descriptor.type)
        desc.format = _pixel_format_interop(texture_descriptor.format)
        desc.usage = bit_set_to_another(texture_descriptor.usage, wgpu.TextureUsageFlags, _texture_usage_interop)

        texture := wgpu.DeviceCreateTexture(_state.device, &desc)
        if texture == nil {
            log.panic("gpu_wgpu.odin: MTL_texture_init: failed to create texture")
        }

        view := wgpu.TextureCreateView(texture, nil)

        return _Texture {
            T = texture,
            view = view,
        }
    }

    _depth_stencil_state_init :: proc(depth_descriptor: Depth_Stencil_State_Descriptor) -> _Depth_Stencil_State {
//         DepthStencilState :: struct {
// 	nextInChain: ^ChainedStruct,
// 	format: TextureFormat,
// 	stencilFront: StencilFaceState,
// 	stencilBack: StencilFaceState,
// 	stencilReadMask: u32,
// 	stencilWriteMask: u32,
// 	depthBias: i32,
// 	depthBiasSlopeScale: f32,
// 	depthBiasClamp: f32,
// }
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


    _draw_indiced_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
        p := _state.curr_pipeline
        
        pipe_desc := hm.static_get(&_state.pipelines, _state.curr_pipeline)
        
        entry_count := 0
        bg_layout_entries: [8]wgpu.BindGroupLayoutEntry
        for B, I in pipe_desc.buffers {
            if B == {} {
                continue
            }

            bg_layout_entries[I] = wgpu.BindGroupLayoutEntry{
                binding    = u32(I),
                visibility = {.Vertex},
                buffer = wgpu.BufferBindingLayout{
                    type             = B.binding_type,
                    hasDynamicOffset = false,
                    minBindingSize   = 0,
                },
            }

            entry_count += 1
        }
        // loop for other resources

        bg_layout := wgpu.DeviceCreateBindGroupLayout(_state.device, &wgpu.BindGroupLayoutDescriptor{
            entryCount = uint(entry_count),
            entries    = raw_data(bg_layout_entries[:entry_count]),
        })

        pso_layout := wgpu.DeviceCreatePipelineLayout(_state.device, &wgpu.PipelineLayoutDescriptor{
            bindGroupLayoutCount = 1,
            bindGroupLayouts    = &bg_layout,
        })

        color_format := _pixel_format_interop(pipe_desc.format)
        blend_state := transmute(wgpu.BlendState)pipe_desc.blend

        target := wgpu.ColorTargetState{
            format    = color_format,
            blend     = &blend_state,
            writeMask = wgpu.ColorWriteMaskFlags_All,
        }

        v_shader := hm.static_get(&_state.shaders, pipe_desc.vertex_shader)
        f_shader := hm.static_get(&_state.shaders, pipe_desc.fragment_shader)

        v_state := wgpu.VertexState{
            module      = v_shader.module,
            entryPoint  = pipe_desc.vertex_function,
            bufferCount = 0,
            buffers     = nil,
        }
        f_state := wgpu.FragmentState{
            module      = f_shader.module,
            entryPoint  = pipe_desc.fragment_function,
            targetCount = 1,
            targets     = &target,
        }

        construct_primitive_state :: proc(p: Primitive_State, c: Cull_Mode, w: Front_Face) -> wgpu.PrimitiveState {
            result: wgpu.PrimitiveState

            switch p.topology {
            case .Triangle:
                result.topology = .TriangleList
            }

            switch c {
            case .None:
                result.cullMode = .None
            case .Front:
                result.cullMode = .Front
            case .Back:
                result.cullMode = .Back
            }

            switch w {
            case .CCW:
                result.frontFace = .CCW
            case .CW:
                result.frontFace = .CW
            }
            
            return result
        }

        primitive_state := construct_primitive_state(pipe_desc.primitive, _state.curr_cull_mode, _state.winding)

        construct_multisample_state :: proc(p: Multisample_State) -> wgpu.MultisampleState {
            result: wgpu.MultisampleState

            result.count = p.count
            result.mask = p.mask

            return result
        }

        multisample_state := construct_multisample_state(pipe_desc.multisample)
        depth_stencil_state_impl, depth_set := hm.static_get(&_state.depth_stencil_states, _state.curr_depth_stencil_state)

        dpso: wgpu.DepthStencilState
        if depth_set {
            dpso = depth_stencil_state_impl.native
            dpso.format = _pixel_format_interop(pipe_desc.depth_format)
        } 

        pso := wgpu.DeviceCreateRenderPipeline(_state.device, &wgpu.RenderPipelineDescriptor{
            layout       = pso_layout,
            vertex       = v_state,
            primitive    = primitive_state,
            multisample  = multisample_state,
            fragment     = &f_state,
            depthStencil = nil if !depth_set else &dpso,
        })

        bg_entries: [8]wgpu.BindGroupEntry
        for B, I in pipe_desc.buffers {
            if B == {} {
                continue
            }

            assert(B.index_bytes == 0) // index buffers go through SetIndexBuffer, not bind groups

            bg_entries[I] = wgpu.BindGroupEntry{
                binding = u32(I),
                buffer  = B.buffer,
                offset  = u64(B.offset),
                size    = u64(B.capacity),
            }
        }

        frame_bg := wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
            layout     = bg_layout,
            entryCount = uint(entry_count),
            entries    = raw_data(bg_entries[:entry_count]),
        })

        wgpu.RenderPassEncoderSetPipeline(_state.render_pass_encoder, pso)
        wgpu.RenderPassEncoderSetBindGroup(_state.render_pass_encoder, /* bind group index */ 0, frame_bg, nil)

        pipe_desc.index_buffer = index_buffer

        assert(index_buffer.index_bytes != 0) // must be an index buffer

        index_format: wgpu.IndexFormat
        switch index_buffer.native.index_bytes {
        case 2:
            index_format = .Uint16
        case 4:
            index_format = .Uint32
        case: panic("Index buffer format not supported")
        }

        wgpu.RenderPassEncoderSetIndexBuffer(
            _state.render_pass_encoder,
            index_buffer.buffer, index_format,
            u64(index_buffer.offset), u64(index_buffer.capacity),
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

    //////////////////////////////////////////////////////////////
    // Memory

    _malloc :: proc(
        type: Buffer_Type,
        #any_int size: uint,
        #any_int alignment: uint,
        name: string,
    ) -> _ptr {
        bytes := runtime.align_forward_uint(size, alignment)

        usage: wgpu.BufferUsageFlags
        mapped: b32
        binding_type: wgpu.BufferBindingType

        switch type {
        case .Staging:
            usage  = {.CopySrc, .MapWrite}
            mapped = true
            binding_type = .ReadOnlyStorage
        case .GPU_Storage:
            usage  = {.CopyDst, .Storage}
            mapped = false
            binding_type = .ReadOnlyStorage
        case .GPU_Constant:
            usage  = {.CopyDst, .Uniform}
            mapped = false
            binding_type = .Uniform
        case .GPU_Index:
            usage  = {.CopyDst, .Index}
            mapped = false
            binding_type = .ReadOnlyStorage
        case .Readback:
            usage  = {.CopyDst, .MapRead}
            mapped = false
            binding_type = .ReadOnlyStorage
        }

        buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
            label = name,
            usage = usage,
            size = u64(bytes),
            mappedAtCreation = mapped,
        })

        return _ptr {
            buffer = buffer,
            offset = 0,
            is_mapped = bool(mapped),
            capacity = uint(bytes),
            binding_type = binding_type,
        }
    }

    _unmap :: proc(ptr: ^_ptr) {
        if !ptr.is_mapped {
            return
        }

        wgpu.BufferUnmap(ptr.buffer)
        ptr.is_mapped = false
    }

    _sub_alloc :: proc(parent: ptr, offset, length: uint) -> ptr {
        result := parent
        result.cpu      = rawptr(uintptr(parent.cpu) + uintptr(offset))
        result.gpu      = rawptr(uintptr(parent.gpu) + uintptr(offset))
        result.offset   = offset
        result.capacity = length

        return result
    }

    _map :: proc(ptr: ^_ptr) -> (cpu: rawptr, gpu: rawptr) {
        cpu = wgpu.RawBufferGetMappedRange(ptr.buffer, 0, ptr.capacity)
        gpu = nil
        ptr.is_mapped = true
        return
    }

    _mapped :: proc(ptr: ptr) -> bool {
        return ptr.is_mapped
    }

    _gpu_address :: proc(p: _ptr) -> rawptr {
        return nil
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

    //////////////////////////////////////////////////////////////
    // Arena

    _frame_arena :: proc() -> ^Arena {
        if len(_state.frame_arenas) == 0 {
            new_arena := new(Arena, context.allocator)
            new_arena^ = arena()
            return new_arena
        } else {
            arena := pop(&_state.frame_arenas)
            arena.ptr.cpu, arena.ptr.gpu = _map(&arena.ptr.native)
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

    //////////////////////////////////////////////////////////////
    // Synchronization

    _commit :: proc() {
        finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
        defer {
            wgpu.CommandBufferRelease(finished)
            wgpu.CommandEncoderRelease(_state.command_encoder)
        }
        wgpu.QueueSubmit(_state.queue, []wgpu.CommandBuffer{finished})
    }

    _barrier :: proc(before: Stage, after: Stage) { /* no op */ }

    //////////////////////////////////////////////////////////////
    // Type interop

    _pixel_format_interop :: proc(format: Pixel_Format) -> wgpu.TextureFormat {
        switch format {
        case .None:
            return .Undefined
        case .BGRA8Unorm:
            return .BGRA8Unorm
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