#+build js
package nuppu_gpu

import "vendor:wgpu"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:mem"
import "base:intrinsics"
import "base:runtime"

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
        uniform_offset_align: u32,
    }

    _Shader :: struct {
        module: wgpu.ShaderModule,
    }

    _Resource :: struct #raw_union {
        index_buffer : struct {
            el_count: int,
            el_size: int,
            buf: wgpu.Buffer,
        },
        using _ : struct {
            ptr: ptr,
            capacity: uint,
            buffer: wgpu.Buffer,
        },
    }



    _ptr :: struct {
        buffer: wgpu.Buffer,
        capacity: uint, // Capacity of the ptr, NOT the buffer
        index_bytes: u8,
    }

    _sub_alloc :: proc(parent: ptr, offset, length: uint) -> ptr {
        assert(offset < parent.capacity)
        assert(length <= parent.capacity - offset)

        result := parent
        result.cpu = rawptr(uintptr(parent.cpu) + uintptr(offset))
        result.gpu = rawptr(uintptr(parent.gpu) + uintptr(offset))
        result.capacity = length
        
        return result
    }

    _Pipeline :: struct {
        vs_module, fs_module: wgpu.ShaderModule,
        vs_entry, fs_entry:   string,
        color_target_format:  wgpu.TextureFormat,
        primitive_state:      wgpu.PrimitiveState,
        multisample_state:    wgpu.MultisampleState,
        blend_state:          wgpu.BlendState,
    }

    _Texture :: struct {
        T: union {
            wgpu.SurfaceTexture,
            wgpu.Texture,
        },
        view: wgpu.TextureView,
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

    _begin_frame :: proc() {
        _state.command_encoder = wgpu.DeviceCreateCommandEncoder(_state.device, nil)
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

    _set_pipeline :: proc(pipeline: Pipeline_Handle) {
        _state.curr_pipeline = pipeline
    }

    _set_buffers :: proc(buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
        assert(len(buffers) > 0)
        assert(len(buffers) == int(range.length))
        assert(len(offsets) == int(range.length))
        assert(len(buffers) == len(offsets))

        pipe_desc := hm.static_get(&_state.pipelines, _state.curr_pipeline)

        for slot in range.location ..< range.location + range.length {
            i := slot - range.location

            ptr := buffers[i]
            assert(ptr.kind == .Buffer || ptr.kind == .Index_Buffer)

            pipe_desc.buffers[i] = buffers[i]
        }
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
                    type             = .ReadOnlyStorage,
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

        construct_primitive_state :: proc(p: Primitive_State) -> wgpu.PrimitiveState {
            result: wgpu.PrimitiveState

            switch p.topology {
            case .Triangle:
                result.topology = .TriangleList
            }

            switch p.cull_mode {
            case .None:
                result.cullMode = .None
            case .Front:
                result.cullMode = .Front
            case .Back:
                result.cullMode = .Back
            }

            switch p.front_face {
            case .CCW:
                result.frontFace = .CCW
            case .CW:
                result.frontFace = .CW
            }
            
            return result
        }

        primitive_state := construct_primitive_state(pipe_desc.primitive)

        construct_multisample_state :: proc(p: Multisample_State) -> wgpu.MultisampleState {
            result: wgpu.MultisampleState

            result.count = p.count
            result.mask = p.mask

            return result
        }

        multisample_state := construct_multisample_state(pipe_desc.multisample)

        pso := wgpu.DeviceCreateRenderPipeline(_state.device, &wgpu.RenderPipelineDescriptor{
            layout       = pso_layout,
            vertex       = v_state,
            primitive    = primitive_state,
            multisample  = multisample_state,
            fragment     = &f_state,
            depthStencil = nil,
        })

        // _state.frame_dummy = wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor{
        //     usage = {.Storage, .CopyDst},
        //     size  = 16,
        // })

        bg_entries: [8]wgpu.BindGroupEntry
        for B, I in pipe_desc.buffers {
            if B == {} {
                continue
            }

            assert(B.kind == .Buffer || B.kind == .Index_Buffer)
            
            bg_entries[I] = wgpu.BindGroupEntry{
                binding = u32(I),
                buffer  = B.buffer,
                offset  = 0,
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
        
        assert(index_buffer.kind == .Index_Buffer)

        wgpu.RenderPassEncoderSetIndexBuffer(
            _state.render_pass_encoder,
            index_buffer.buffer, .Uint32,
            0, u64(index_buffer.capacity),
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

    _begin_render_pass :: proc(attachment: Color_Attachment) {
        from_4xu8_to_4xf64_color :: proc(input: [4]u8) -> [4]f64 {
            return [4]f64 {
                f64(input[0]) / 255.0,
                f64(input[1]) / 255.0,
                f64(input[2]) / 255.0,
                f64(input[3]) / 255.0,
            }
        }

        res: wgpu.RenderPassColorAttachment
        res.view = attachment.texture.view
        res.storeOp = _store_action_interop(attachment.store_action)
        res.loadOp = _load_action_interop(attachment.load_action)
        res.clearValue = from_4xu8_to_4xf64_color(attachment.clear_color)
        res.depthSlice = wgpu.DEPTH_SLICE_UNDEFINED

        desc := wgpu.RenderPassDescriptor {
            colorAttachmentCount = 1,
            colorAttachments = &res,
        }

        _state.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(_state.command_encoder, &desc)
    }

    _end_render_pass :: proc() {
        wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
        wgpu.RenderPassEncoderRelease(_state.render_pass_encoder)
    }

    _pixel_format_interop :: proc(format: Pixel_Format) -> wgpu.TextureFormat {
        switch format {
        case .BGRA8Unorm:
            return .BGRA8Unorm
        case .Depth32Float:
            return .Depth32Float
        }
        unreachable()
    }

    _pipeline_init :: proc(vertex_shader: Shader_Handle, vertex_function_entry: string, fragment_shader: Shader_Handle, fragment_function_entry: string, format: Pixel_Format) -> Pipeline_Handle {

        vertex_shader_m := hm.static_get(&_state.shaders, vertex_shader)
        fragment_shader_m := hm.static_get(&_state.shaders, fragment_shader)

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
                    cull_mode = .None,
                    front_face = .CCW,
                },
                
                format = format,
            }
        )

        _state.curr_pipeline = handle
        
        return handle
    }

    _commit :: proc() {
        finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
        defer {
            wgpu.CommandBufferRelease(finished)
            wgpu.CommandEncoderRelease(_state.command_encoder)
        }
        wgpu.QueueSubmit(_state.queue, []wgpu.CommandBuffer{finished})
    }

    
    
    
    
    
    
    _end_frame :: proc() {
        wgpu.SurfacePresent(_state.surface)
    }

//////////
    _Buffer :: wgpu.Buffer


    

    // _destroy_res :: proc(res: _Resource, kind: Resource_Kind) {
    //     switch kind {
    //     case .Buffer, .Index_Buffer:
    //         wgpu.BufferRelease(res.buffer)
    //     }
    // }

    // _default_buffer :: proc(
    //     name: string,
    //     #any_int size: uint,
    //     #any_int alignment: uint
    // ) -> _Resource {
        
    //     bytes := runtime.align_forward_uint(size, alignment)

    //     buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
    //         label = name,
    //         usage = {.CopySrc, .MapWrite},
    //         size = u64(bytes),
    //         mappedAtCreation = true,
    //     })

    //     cpu := wgpu.RawBufferGetMappedRange(buffer, 0, uint(size))

    //     return _Resource {
    //         ptr = ptr {
    //             cpu = cpu,
    //             gpu = nil,
    //         },
    //         capacity = uint(size),
    //         buffer = buffer,
    //     }
    // }

    // _gpu_buffer :: proc(
    //     #any_int size: uint,
    //     #any_int alignment: uint,
    //     role: Role = .Default
    // ) -> _Resource {

    //     role_usage: wgpu.BufferUsage
    //     switch role {
    //     case .Default:
    //         role_usage = .Storage
    //     case .Index:
    //         role_usage = .Index
    //     }

    //     buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
    //         usage = {.CopyDst} + {role_usage},
    //         size = u64(size),
    //         mappedAtCreation = false,
    //     })

    //     return _Resource {
    //         ptr = ptr {
    //             cpu = nil,
    //             gpu = nil,
    //         },
    //         capacity = uint(size),
    //         buffer = buffer,
    //     }
    // }

    // _readback_buffer :: proc(
    //     size: u64
    // ) -> _Resource {
    //     buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
    //         usage = {.CopyDst, .MapRead},
    //         size = size,
    //         mappedAtCreation = false,
    //     })

    //     return _Resource {
    //         ptr = ptr {
    //             cpu = nil,
    //             gpu = nil,
    //         },
    //         capacity = uint(size),
    //         buffer = buffer,
    //     }
    // }
//////////

    _mem_copy :: proc(dst, src: ptr) {
        fmt.println(dst)
        fmt.println(src)
        wgpu.CommandEncoderCopyBufferToBuffer(_state.command_encoder, src.buffer, 0, dst.buffer, 0, u64(src.capacity))
    }

    _frame_arena :: proc() -> ^Arena {
        if len(_state.frame_arenas) == 0 {
            new_arena := new(Arena, context.allocator)
            new_arena^ = arena()
            return new_arena
        } else {
            arena := pop(&_state.frame_arenas)

            arena.ptr.cpu = wgpu.RawBufferGetMappedRange(arena.ptr.buffer, 0, arena.ptr.capacity) // Remap CPU ptr
            arena.is_mapped = true
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

        if arena.is_mapped {
            _unmap(arena.ptr.native)
        }

        
        wgpu.BufferMapAsync(arena.ptr.buffer, {.Write}, 0, arena.ptr.capacity, wgpu.BufferMapCallbackInfo {
            mode = .AllowProcessEvents,
            callback = callback_,
            userdata1 = arena,
        })
    }






    _map_range :: proc(ptr: _ptr, length: uint, offset: uint = 0) -> (cpu: rawptr, gpu: rawptr) {
        assert(offset % 8 == 0)
        
        assert(length > 0)
        assert((length - offset) > 0)
        assert((length - offset) % 4 == 0)
        assert((length <= ptr.capacity))
        
        cpu = wgpu.RawBufferGetMappedRange(ptr.buffer, offset, length)
        gpu = nil
        return
    }

    _malloc :: proc(
        #any_int size: uint,
        #any_int alignment: uint,
        m: Mem,
        name: string,
    ) -> _ptr {
        bytes := runtime.align_forward_uint(size, alignment)
    
        buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
            label = name,
            usage = {.CopyDst, .Storage},
            size = u64(bytes),
            mappedAtCreation = false,
        })

        return _ptr {
            buffer = buffer,
            capacity = uint(bytes),
        }
    }


    _malloc_mapped :: proc(
        #any_int size: uint,
        #any_int alignment: uint,
        name: string,
        loc := #caller_location
    ) -> _ptr {
        bytes := runtime.align_forward_uint(size, alignment)

        buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
            label = name,
            usage = {.CopySrc, .MapWrite},
            size = u64(bytes),
            mappedAtCreation = true,
        })

        return _ptr {
            buffer = buffer,
            capacity = uint(bytes),
        }
    }

    _malloc_index :: proc(
        el_count: uint, el_size: uint,
        name: string = {},
        loc := #caller_location
    ) -> _ptr {

        bytes := el_count * el_size

        buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor {
            label = name,
            usage = {.CopyDst, .Index},
            size = u64(bytes),
            mappedAtCreation = false,
        })

        return _ptr {
            buffer = buffer,
            capacity = uint(bytes),
            index_bytes = u8(el_size),
        }
    }

    _unmap :: proc(ptr: _ptr) {
        wgpu.BufferUnmap(ptr.buffer)
    }


}
import hm "core:container/handle_map"