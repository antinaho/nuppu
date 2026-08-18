package nuppu_gpu

import "vendor:wgpu"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:mem"
import "base:intrinsics"

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
        curr_pipeline: Pipeline,
    }
    _Shader :: struct {
        module: wgpu.ShaderModule,
    }

    _Pipeline :: struct {
        vertex_state: wgpu.VertexState,
        fragment_state: wgpu.FragmentState,
        primitive_state: wgpu.PrimitiveState,
        multisample_state: wgpu.MultisampleState,
        depth_pso: wgpu.DepthStencilState,
    }

    _Texture :: struct {
        T: union {
            wgpu.SurfaceTexture,
            wgpu.Texture,
        },
        view: wgpu.TextureView,
    }
    _Buffer :: struct {
        buf: wgpu.Buffer,
        written: u64,
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

            _state.is_init = true
        }
    }

    _texture_init :: proc(td: Texture_Descriptor) -> Resource {return {}}


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

    _shader_init :: proc(name: string, code: []u8) -> Resource {
        module := wgpu.DeviceCreateShaderModule(_state.device, &{
            nextInChain = &wgpu.ShaderSourceWGSL {
                sType = .ShaderSourceWGSL,
                code = string(code),
            }
        })

        idx := _state.shaders.current
        result := Resource {
            name = "SHADER",
            idx = idx,
            shader = Shader {
                module = module,
            }
        }
        _state.shaders.current += 1

        return result
    }

    _set_pipeline :: proc(pipeline: Pipeline) {
        _state.curr_pipeline = pipeline
    }

    _set_buffers :: proc(buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
        assert(len(buffers) > 0)
        assert(len(buffers) == int(range.length))
        assert(len(offsets) == int(range.length))
        assert(len(buffers) == len(offsets))

        for slot in range.location ..< range.location + range.length {
            switch stage {
            case .Vertex:

                write_start := offsets[slot - range.location] + buffers[slot - range.location].offset
                write_end := buffers[slot - range.location].buffer.written
                size := write_end - u64(write_start)
                wgpu.RenderPassEncoderSetVertexBuffer(_state.render_pass_encoder, slot, buffers[slot - range.location].buffer.buf, u64(offsets[slot - range.location]), size)
            case .Compute, .Fragment:

            }
        }
    }

    _draw_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, vertex_count: u32, vertex_start: u32) {
        
        //wgpu.RenderPassEncoderSetBindGroup(r.curr_pass, 0, r.bind_group)
        //wgpu.RenderPassEncoderSetPipeline(_state.render_pass_encoder, _state.curr_pipeline.pso)
        wgpu.RenderPassEncoderSetIndexBuffer(_state.render_pass_encoder, index_buffer.buffer.buf, .Uint32, u64(index_buffer.offset), index_buffer.buffer.written)
        wgpu.RenderPassEncoderDraw(_state.render_pass_encoder, vertex_count, 1, vertex_start, 0)
    }


    _buffer_init :: proc(bytes, align: uint, memory: Memory) -> ptr {
        bytes := mem.align_forward_uint(bytes, align)
        buffer := wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor{
            usage = {},
            size = u64(bytes),
            mappedAtCreation = false,
        })

        return ptr {
            cpu = nil,
            gpu = nil,
            offset = 0,
            buffer = Buffer { buf = buffer, written = 0 },
        }
    }

    _ptr_fill_slice :: proc(dst: ^ptr, data: rawptr, size, count: int) {
        wgpu.QueueWriteBuffer(_state.queue, dst.buffer.buf, u64(dst.offset), data, uint(size * count))
        // mapping := wgpu.RawBufferGetMappedRange(dst.buffer.buf, offset = dst.offset, size = uint(size * count))
        // intrinsics.mem_copy_non_overlapping(mapping, data, size * count)
        // wgpu.BufferUnmap(dst.buffer.buf)
        dst.buffer.written += u64(size * count)
    }

    _upload_one_shot :: proc(items: []struct {dst: ^ptr, src: ptr, bytes: uint}) {
        _state.command_encoder = wgpu.DeviceCreateCommandEncoder(_state.device, nil)
        for item in items {    
            wgpu.CommandEncoderCopyBufferToBuffer(_state.command_encoder, item.src.buffer.buf, u64(item.src.offset), item.dst.buffer.buf, u64(item.dst.offset), u64(item.bytes))
            item.dst.buffer.written += u64(item.bytes)
        }
        finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
        defer {
            wgpu.CommandBufferRelease(finished)
            wgpu.CommandEncoderRelease(_state.command_encoder)
        }
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

    _pipeline_init :: proc(vertex_shader: Resource, vertex_function_entry: string, fragment_shader: Resource, fragment_function_entry: string, format: Pixel_Format) -> Resource {
        desc: wgpu.RenderPipelineDescriptor

        target_count := 1
        targets := []wgpu.ColorTargetState {

        }

        depth_pso := wgpu.DepthStencilState {}

        primitive_state := wgpu.PrimitiveState {
            topology = .TriangleList,
            cullMode = .None,
            frontFace = .CCW,
        }

        multisample_state := wgpu.MultisampleState {
            count = 1,
            mask = 0xFFFFFFFF,
        }

        v_state := wgpu.VertexState {
            module = vertex_shader.shader.module,
            entryPoint = strings.clone(vertex_function_entry),
            
            bufferCount = 0,
            buffers = nil,

            constantCount = 0,
            constants = nil,
        }

        f_state := wgpu.FragmentState {
            module = fragment_shader.shader.module,
            entryPoint = strings.clone(fragment_function_entry),

            targetCount = 0,
            targets = nil,

            constantCount = 0,
            constants = nil,
        }

        idx := _state.pipelines.current
        result := Resource {
            name = "PIPELINE",
            idx = idx,
            pipeline = Pipeline {
                vertex_state = v_state,
                fragment_state = f_state,
                primitive_state = primitive_state,
                multisample_state = multisample_state,
                depth_pso = depth_pso,
            },
        }
        _state.pipelines.current += 1
        
        return result
    }

    _present :: proc(texture: Texture) {
        finished := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
        defer {
            wgpu.CommandBufferRelease(finished)
            wgpu.CommandEncoderRelease(_state.command_encoder)
        }

        wgpu.QueueSubmit(_state.queue, []wgpu.CommandBuffer{finished})
        wgpu.SurfacePresent(_state.surface)
    }

    _end_frame :: proc() {

    }
}