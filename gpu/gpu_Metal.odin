#+build darwin
#+vet explicit-allocators shadowing unused

package nuppu_gpu

import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "base:runtime"
import "core:time"
import "core:slice"
import "core:log"
import "core:fmt"

_ :: log
_ :: fmt

when GPU_BACKEND == GPU_BACKEND_METAL {

    _ptr :: struct {
        buffer: ^MTL.Buffer,
    }

    _Shader :: struct {
        library: ^MTL.Library,
    }

    _Sampler :: ^MTL.SamplerState
    
    _Texture :: struct #all_or_none {
        type: Texture_Type,
        usage: Texture_Usage,
        texture: ^MTL.Texture,
    }

    _Depth_Stencil_State :: ^MTL.DepthStencilState

    _Compute_Pipeline :: ^MTL.ComputePipelineState
    
    _Pipeline :: ^MTL.RenderPipelineState

    _State :: struct {
        device: ^MTL.Device,
        metal_layer: ^CA.MetalLayer,
        queue: ^MTL.CommandQueue,
        //
        frame_pool: ^NS.AutoreleasePool,
        command_buffer: ^MTL.CommandBuffer,
        curr_drawable: ^CA.MetalDrawable, // Swapchain

        render_command_encoder: ^MTL.RenderCommandEncoder,
        blit_command_encoder: ^MTL.BlitCommandEncoder,
        compute_command_encoder: ^MTL.ComputeCommandEncoder,

        curr_pipeline: Pipeline,
        curr_compute_pipeline: Compute_Pipeline,
    }

    _init :: proc(native_window: rawptr) -> bool {

        native_window := cast(^NS.Window)(native_window)
        scale := native_window->backingScaleFactor()

        _state.device = MTL.CreateSystemDefaultDevice()

        metal_layer := CA.MetalLayer.layer()
        metal_layer->setDevice(_state.device)
        metal_layer->setPixelFormat(.BGRA8Unorm)
        metal_layer->setFramebufferOnly(false)
        metal_layer->setFrame(native_window->frame())
        metal_layer->setContentsScale(scale)
        _state.metal_layer = metal_layer

        native_window->contentView()->setLayer(metal_layer)
        native_window->setOpaque(true)
        native_window->setBackgroundColor(nil)
        
        _state.queue = _state.device->newCommandQueue()

        _state.is_init = true

        return true
    }

    _deinit :: proc() {
        _state.metal_layer->release()
        _state.queue->release()
        _state.device->release()
    }

    _resize_swapchain :: proc(width, height: u32) -> bool {
        drawable_size := NS.Size {
            width  = NS.Float(width),
            height = NS.Float(height),
        }

        _state.metal_layer->setDrawableSize(drawable_size)

        return true
    }

    _release_texture :: proc(texture: ^Texture) {
        if texture.native.texture != nil {
            texture.native.texture->release()
            texture.native.texture = nil
        }
    }

    _release_ptr :: proc(ptr: ^ptr) {
        if ptr.native.buffer != nil {
            ptr.native.buffer->release()
            ptr.native.buffer = nil
        }
    }

    _copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
        native := texture.native

        region := MTL.Region {
            origin = MTL.Origin {NS.Integer(origin.x), NS.Integer(origin.y), 0},
            size = MTL.Size {
                width  = NS.Integer(size.x),
                height = NS.Integer(size.y),
                depth  = 1,
            },
        }

        switch native.type {
        case ._2D:
            native.texture->replaceRegion(region, NS.UInteger(level), data, NS.UInteger(bytes_per_row))
        case ._2D_Array:
            bytes_per_image := NS.UInteger(bytes_per_row) * NS.UInteger(size.y)
            native.texture->replaceRegionWithLevel(region, NS.UInteger(level), NS.UInteger(origin.z), data, NS.UInteger(bytes_per_row), bytes_per_image)
        }
    }

    _depth_stencil_state_init :: proc(depth_descriptor: Depth_Stencil_State_Descriptor) -> _Depth_Stencil_State { 
        
        ds_desc := MTL.DepthStencilDescriptor.alloc()->init()
        defer ds_desc->release()
        ds_desc->setDepthCompareFunction(_compare_function_interop(depth_descriptor.compare))
        ds_desc->setDepthWriteEnabled(depth_descriptor.write_enabled)
    
        depth_state := _state.device->newDepthStencilState(ds_desc)
        if depth_state == nil {
            log.panic("_depth_stencil_state_init: failed to create depth stencil state")
        }

        return _Depth_Stencil_State(depth_state)
    }

    _shader_init :: proc(name: string, code: []u8) -> _Shader {
        library: ^MTL.Library
        err: ^NS.Error

        code_ns := NS.String.alloc()->initWithBytesNoCopy(raw_data(code), NS.UInteger(len(code)), .UTF8, false)
        defer code_ns->release()

        compile_options := MTL.CompileOptions.alloc()->init()
        defer compile_options->release()
        compile_options->setLanguageVersion(.Version3_0)

        // Could cache library
        library, err = _state.device->newLibraryWithSource(code_ns, compile_options)
        if err != nil {
            log.panicf("Failed to create shader library: %v", err->localizedDescription()->odinString())
        }

        result := _Shader {
            library = library,
        }

        return result
    }

    _pipeline_init :: proc(vertex, fragment: Shader_IR, pipeline_descriptor: Pipeline_Descriptor) -> _Pipeline {
        desc := MTL.RenderPipelineDescriptor.alloc()->init()
	    defer desc->release()

        vertex_entry := NS.String.alloc()->initWithOdinString(vertex.entry_point)
        defer vertex_entry->release()
        vertex_function := vertex.shader.library->newFunctionWithName(vertex_entry)
        defer vertex_function->release()

        fragment_entry := NS.String.alloc()->initWithOdinString(fragment.entry_point)
        defer fragment_entry->release()
        fragment_function := fragment.shader.library->newFunctionWithName(fragment_entry)
        defer fragment_function->release()

        desc->setVertexFunction(vertex_function)
        desc->setFragmentFunction(fragment_function)
        desc->setDepthAttachmentPixelFormat(_pixel_format_interop(pipeline_descriptor.depth_format))

        color_attachment := desc->colorAttachments()->object(0)
        color_attachment->setPixelFormat(_pixel_format_interop(pipeline_descriptor.color_format))
        
        pso, err := _state.device->newRenderPipelineStateWithDescriptor(desc)
        if err != nil {
            log.panicf("Failed to create pipeline state: %v", err->localizedDescription()->odinString())
        }

        return pso
    }

    _compute_pipeline_init :: proc(shader: Shader, entry_point: string) -> _Compute_Pipeline {
        entry_ns_str := NS.String.alloc()->initWithOdinString(entry_point)
        defer entry_ns_str->release()
    
        function := shader.library->newFunctionWithName(entry_ns_str)
        defer function->release()

        kernel, k_err := _state.device->newComputePipelineStateWithFunction(function)
        if k_err != nil {
            log.panicf("Failed to create pipeline state: %v", k_err->localizedDescription()->odinString())
        }

        return kernel
    }

    _begin_commands :: proc() {
        _state.frame_pool = NS.AutoreleasePool.alloc()->init()

        buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
        defer buffer_desc->release()
        buffer_desc->setErrorOptions({.EncoderExecutionStatus})

        _state.command_buffer = _state.queue->commandBufferWithDescriptor(buffer_desc)
    }

    _commit_commands :: proc() {
        defer {
            _state.frame_pool->drain()
            _state.frame_pool = nil
        } 
        _state.command_buffer->commit()
        _state.command_buffer = nil
    }

    _begin_frame :: proc() {
        _begin_commands()
    }

    
    _end_frame :: proc(semaphore: Timeline_Semaphore, frame_n: u64) {
        // The render work (begin_frame -> render -> end_render_pass) was
        // recorded into the command buffer autoreleased into _state.frame_pool.
        // Now present + signal + commit it, then drain the pool. Metal
        // retains the buffer post-commit so the autorelease reference can
        // be safely released by the drain.
        defer {
            _state.frame_pool->drain()
            _state.frame_pool = nil
        }
        _state.command_buffer->presentDrawable(_state.curr_drawable)
        _state.command_buffer->encodeSignalEvent((^MTL.SharedEvent)(semaphore), frame_n)
        _state.command_buffer->commit()

        _state.command_buffer = {}
        _state.curr_drawable = {}
        _state.render_command_encoder = {}
    }

    _acquire_next_swapchain :: proc() -> _Texture {
        drawable := _state.metal_layer->nextDrawable()
        if drawable == nil {
            panic("In gpu_Metal.odin: _acquire_next_swapchain: Couldn't acquire next drawable")
        }

        native := _Texture {
            type = ._2D,
            texture = drawable->texture(),
            usage = {.Color_Attachment},
        }
        
        _state.curr_drawable = drawable

        return native
    }

    _compute_dispatch :: proc(num_groups: [3]u32, num_threads_per_group: [3]u32) {
        size_grid := MTL.Size{NS.Integer(num_groups.x), NS.Integer(num_groups.y), NS.Integer(num_groups.z)}
	    size_group := MTL.Size{NS.Integer(num_threads_per_group.x), NS.Integer(num_threads_per_group.y), NS.Integer(num_threads_per_group.z)}
        
        _compute_command_encoder()->setComputePipelineState(_state.curr_compute_pipeline.native)
        _compute_command_encoder()->dispatchThreads(size_grid, size_group)
    }

    _set_compute_pipeline :: proc(compute_pipeline: Compute_Pipeline) {
        _state.curr_compute_pipeline = compute_pipeline
    }

    _set_pipeline :: proc(pipeline: Pipeline) {
        _state.curr_pipeline = pipeline
    }

    _sampler_init :: proc(desc: Sampler_Descriptor) -> _Sampler {
        sampler_desc := MTL.SamplerDescriptor.alloc()->init()
        defer sampler_desc->release()

        sampler_desc->setSupportArgumentBuffers(true)
        sampler_desc->setMinFilter(_sampler_filter_min_mag_interop(desc.min_filter))
        sampler_desc->setMagFilter(_sampler_filter_min_mag_interop(desc.mag_filter))
        sampler_desc->setMipFilter(_sampler_filter_mip_interop(desc.mip_filter))
        sampler_desc->setSAddressMode(_sampler_wrap_interop(desc.wrap_s))
        sampler_desc->setTAddressMode(_sampler_wrap_interop(desc.wrap_t))
        sampler_desc->setRAddressMode(_sampler_wrap_interop(desc.wrap_r))

        return _state.device->newSamplerState(sampler_desc)
    }

    _texture_init :: proc(texture_descriptor: Texture_Descriptor) -> _Texture {
        desc := MTL.TextureDescriptor.alloc()->init()
        defer desc->release()
        
        desc->setWidth(NS.UInteger(texture_descriptor.dimensions.x))
        desc->setHeight(NS.UInteger(texture_descriptor.dimensions.y))
        desc->setPixelFormat(_pixel_format_interop(texture_descriptor.format))
        desc->setUsage(_texture_usage_interop(texture_descriptor.usage))
        desc->setStorageMode(_storage_mode_interop(texture_descriptor.storage))
        desc->setTextureType(_texture_type_interop(texture_descriptor.type))
        
        layers := max(texture_descriptor.layer_count, 1)
        if texture_descriptor.type == ._2D_Array {
            desc->setArrayLength(NS.UInteger(layers))
        }

        texture := _state.device->newTextureWithDescriptor(desc)
        if texture == nil {
            log.panic("gpu_MTL.odin: MTL_texture_init: failed to create texture")
        }

        return _Texture {
            type = texture_descriptor.type,
            texture = texture,
            usage = texture_descriptor.usage,
        }
    }

    _set_depth_stencil_state :: proc(depth_stencil_state: Depth_Stencil_State) {
        _state.render_command_encoder->setDepthStencilState(depth_stencil_state)
    }

    _begin_render_pass :: proc(c_attachment: Color_Attachment, d_attachment: Depth_Attachment) {
        pass_descriptor := MTL.RenderPassDescriptor.renderPassDescriptor()

        color_attachment := pass_descriptor->colorAttachments()->object(0)
        color_attachment->setClearColor(_to_clear_color(c_attachment.clear_color))
        color_attachment->setLoadAction(_load_action_interop(c_attachment.load_action))
        color_attachment->setStoreAction(_store_action_interop(c_attachment.store_action))
        color_attachment->setTexture(c_attachment.texture.native.texture)

        if d_attachment.texture.native.texture != nil {
            depth_desc := pass_descriptor->depthAttachment()
            depth_desc->setLoadAction(_load_action_interop(d_attachment.load_action))
            depth_desc->setStoreAction(_store_action_interop(d_attachment.store_action))
            depth_desc->setTexture(d_attachment.texture.native.texture)
        }

        _state.render_command_encoder = _state.command_buffer->renderCommandEncoderWithDescriptor(pass_descriptor)
    }

    _end_render_pass :: proc() {
        when ODIN_DEBUG {
            assert(_state.render_command_encoder != nil, "_end_render_pass: no render pass is active")
        }

        _state.render_command_encoder->endEncoding()
        _state.render_command_encoder = nil
    }

    _set_cull_mode :: proc(cull_mode: Cull_Mode) {
        _state.render_command_encoder->setCullMode(_cull_mode_interop(cull_mode))
    }

    _set_front_face_winding :: proc(winding: Front_Face) {
        _state.render_command_encoder->setFrontFacingWinding(_front_face_winding_interop(winding))
    }

    _draw_indiced_primitives :: proc(parameter_block: ^Parameter_Block, primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32, t: Index_Buffer_Type) {
        _state.render_command_encoder->setRenderPipelineState(_state.curr_pipeline)

        _use_parameter_block(parameter_block, .Graphics)

        if instance_count == 0 {
            return
        }

        index_format: MTL.IndexType
        index_bytes: NS.UInteger
        switch t {
        case .Uint16:
            index_format = MTL.IndexType.UInt16
            index_bytes = 2
        case .Uint32:
            index_format = MTL.IndexType.UInt32
            index_bytes = 4
        case: panic("Index buffer format not supported")
        }

        _state.render_command_encoder->drawIndexPrimitivesWithBaseVertex(
            _primitive_type_interop(primitive), NS.UInteger(index_count), index_format,
            index_buffer.native.buffer, NS.UInteger(index_offset * u32(index_bytes)), NS.UInteger(instance_count), NS.Integer(base_vertex), NS.UInteger(base_instance)
        )
    }

    _malloc :: proc(
        bytes: u32,
        alignment: u32,
        flags: Buffer_Flag,
        name: string,
        loc := #caller_location,
    ) -> _ptr {
        capacity := runtime.align_forward(uint(bytes), uint(alignment))

        options: MTL.ResourceOptions
        switch flags {
        case .Staging:
            options = MTL.ResourceStorageModeShared
        case .Default, .Index, .Constant:
            options = {.StorageModePrivate}
        }
        
        buffer := _state->device->newBufferWithLength(
            length = NS.UInteger(capacity),
            options = options,
        )
        buffer->setLabel(NS.String.alloc()->initWithOdinString(name))

        return _ptr {
            buffer = buffer,
        }
    }

    _temp_malloc :: proc(bytes: []u8, index: u32, shader_stage: Shader_Stage) {
        switch shader_stage {
        case .Vertex:
            _state.render_command_encoder->setVertexBytes(bytes, NS.UInteger(index))
        case .Fragment:
            _state.render_command_encoder->setFragmentBytes(bytes, NS.UInteger(index))
        case .Compute:
            _compute_command_encoder()->setBytes(bytes, NS.UInteger(index))
        }
    }

    _cpu_address :: proc(p: _ptr) -> rawptr {
        return rawptr(uintptr(p.buffer->contentsPointer()))
    }

    _gpu_address :: proc(p: _ptr) -> rawptr {
        return rawptr(uintptr(p.buffer->gpuAddress()))
    }

    _unmap :: proc(ptr: ^_ptr) { /* no op in Metal */ }

    _copy :: proc(dst, src: ptr) {
        if _state.blit_command_encoder == nil {
            _state.blit_command_encoder = _state.command_buffer->blitCommandEncoder()
        }

        _state.blit_command_encoder->copyFromBuffer(
            src.native.buffer, NS.UInteger(src.byte_offset),
            dst.native.buffer, NS.UInteger(dst.byte_offset),
            NS.UInteger(src.total_capacity_bytes),
        )
    }

    _mapped :: proc(ptr: ptr) -> bool {
        return ptr.cpu != nil
    }

    // _bucket_arena_kick_remap :: proc(arena: ^Bucket_Arena($T)) {
    //     for &bucket in arena.buckets {
    //         if bucket.state != .Locked { continue }
    //         bucket.cursor = 0
    //         bucket.state = .Mapped
    //     }
    //     /* no op in Metal; staging buffers stay mapped for life */
    // }

    _min_alignment :: proc(flags: Buffer_Flag) -> u32 {
        return 4
    }

    _use_parameter_block :: proc(block: ^Parameter_Block, destination: Parameter_Block_Destination) {
        data := make([dynamic]uintptr, context.temp_allocator)
        
        for C in block.constants {
            if C.native.buffer == nil { continue }

            if destination == .Graphics {
                _state.render_command_encoder->useResourceWithStages(C.native.buffer, {.Read}, {.Vertex, .Fragment})
            } else {
                _compute_command_encoder()->useResource(C.native.buffer, {.Read})
            }

            append(&data, uintptr(C.gpu))
        }

        for R in block.read_resources {
            switch res in R {
            case ptr:
                if res.native.buffer == nil { continue }

                if destination == .Graphics {
                    _state.render_command_encoder->useResourceWithStages(res.native.buffer, {.Read}, {.Vertex, .Fragment})
                } else {
                    _compute_command_encoder()->useResource(res.native.buffer, {.Read})
                }
                
                append(&data, uintptr(res.gpu))
            case Texture:
                if res.native.texture == nil { continue }

                if destination == .Graphics {
                    _state.render_command_encoder->useResourceWithStages(res.native.texture, _texture_resource_usage_interop(res.native.usage), {.Vertex, .Fragment})
                } else {
                    _compute_command_encoder()->useResource(res.native.texture, _texture_resource_usage_interop(res.native.usage))
                }

                append(&data, uintptr(res.native.texture->gpuResourceID()))
            }
        }

        for RW in block.read_write_resources {
            switch res in RW {
            case ptr:
                if res.native.buffer == nil { continue }

                if destination == .Graphics {
                    _state.render_command_encoder->useResourceWithStages(res.native.buffer, {.Read, .Write}, {.Vertex, .Fragment})
                } else {
                    _compute_command_encoder()->useResource(res.native.buffer, {.Read, .Write})
                }

                append(&data, uintptr(res.gpu))
            case Texture:
                if res.native.texture == nil { continue }

                if destination == .Graphics {
                    _state.render_command_encoder->useResourceWithStages(res.native.texture, _texture_resource_usage_interop(res.native.usage), {.Vertex, .Fragment})
                } else {
                    _compute_command_encoder()->useResource(res.native.texture, _texture_resource_usage_interop(res.native.usage))
                }

                append(&data, uintptr(res.native.texture->gpuResourceID()))
            }
        }

        for S in block.samplers {
            if S.native == nil { continue }
            append(&data, uintptr(S.native->gpuResourceID()))
        }

        MAX_PUSH_BYTE_SIZE :: 64 * 64
        assert(len(data) <= 64)

        if destination == .Graphics {
            _temp_malloc(slice.bytes_from_ptr(raw_data(data), len(data) * size_of(uintptr)), 0, .Vertex)
            _temp_malloc(slice.bytes_from_ptr(raw_data(data), len(data) * size_of(uintptr)), 0, .Fragment)
        } else {
            _temp_malloc(slice.bytes_from_ptr(raw_data(data), len(data) * size_of(uintptr)), 0, .Compute)
        }
        
    }

    _barrier :: proc(before: Stage, after: Stage) {
        switch before {
        case .Transfer:
            if _state.blit_command_encoder != nil {
                _state.blit_command_encoder->endEncoding()
                _state.blit_command_encoder = nil
            }
        case .All:
            if _state.blit_command_encoder != nil {
                _state.blit_command_encoder->endEncoding()
                _state.blit_command_encoder = nil
            }
            if _state.render_command_encoder != nil {
                _state.render_command_encoder->endEncoding()
                _state.render_command_encoder = nil
            }

            if _state.compute_command_encoder != nil {
                _state.compute_command_encoder->endEncoding()
                _state.compute_command_encoder = nil
            }

        case .Compute:
            if _state.compute_command_encoder != nil {
                _state.compute_command_encoder->endEncoding()
                _state.compute_command_encoder = nil
            }
        }

        _ = after
    }

    _semaphore :: proc(value: u64) -> Timeline_Semaphore {
        event := _state.device->newSharedEvent()
        event->setSignaledValue(value)
        return Timeline_Semaphore(event)
    }

    _semaphore_wait :: proc(semaphore: Timeline_Semaphore, value: u64) -> bool {
        event := (^MTL.SharedEvent)(semaphore)
        
        if event->signaledValue() >= value {
            return true
        }
        
        // implement timeout later
        // timestamp := time.now()
        // has_deadline := timeout_milliseconds != time.MAX_DURATION

        for {
            if event->signaledValue() >= value {
                return true
            }

            // if has_deadline && time.diff(timestamp, time.now()) >= timeout_milliseconds {
            //     return false
            // }

            time.sleep(10 * time.Millisecond)
        }
    }
    
    //////////////////////////////////////////////////////////////

    _compute_command_encoder :: proc() -> ^MTL.ComputeCommandEncoder {
        if _state.compute_command_encoder == nil {
            _state.compute_command_encoder = _state.command_buffer->computeCommandEncoder()
        }
        return _state.compute_command_encoder
    }

    _to_clear_color :: proc(color: Color) -> MTL.ClearColor {
        return MTL.ClearColor {
            red   = f64(color.x) / 255.0,
            green = f64(color.y) / 255.0,
            blue  = f64(color.z) / 255.0,
            alpha = f64(color.w) / 255.0,
        }
    }

    _set_blend :: proc() {
        // color_attachment->setBlendingEnabled(true)
        // color_attachment->setRgbBlendOperation(_blend_operation_interop(desc.blend.color.operation))
        // color_attachment->setSourceRGBBlendFactor(_blend_factor_interop(desc.blend.color.srcFactor))
        // color_attachment->setDestinationRGBBlendFactor(_blend_factor_interop(desc.blend.color.dstFactor))
        // color_attachment->setAlphaBlendOperation(_blend_operation_interop(desc.blend.alpha.operation))
        // color_attachment->setSourceAlphaBlendFactor(_blend_factor_interop(desc.blend.alpha.srcFactor))
        // color_attachment->setDestinationAlphaBlendFactor(_blend_factor_interop(desc.blend.alpha.dstFactor))
    }

    //////////////////////////////////////////////////////////////
    // Interop

    _sampler_filter_min_mag_interop :: proc(filter: Sampler_Min_Mag_Filter) -> MTL.SamplerMinMagFilter {
        switch filter {
        case .Nearest:
            return .Nearest
        case .Linear:
            return .Linear
        }
        unreachable()
    }

    _sampler_filter_mip_interop :: proc(filter: Sampler_Mip_Filter) -> MTL.SamplerMipFilter {
        switch filter {
        case .NotMipmapped:
            return .NotMipmapped
        case .Nearest:
            return .Nearest
        case .Linear:
            return .Linear
        }
        unreachable()
    }

    _sampler_wrap_interop :: proc(wrap: Sampler_Address_Mode) -> MTL.SamplerAddressMode {
        switch wrap {
        case .ClampToEdge:
            return .ClampToEdge
        case .MirrorRepeat:
            return .MirrorRepeat
        case .Repeat:
            return .Repeat
        }
        unreachable()
    }

    _load_action_interop :: proc(action: Load_Action) -> MTL.LoadAction {
        switch action {
        case .Dont_Care:
            return .DontCare
        case .Clear:
            return .Clear
        case .Load:
            return .Load
        }
        unreachable()
    }

    _store_action_interop :: proc(action: Store_Action) -> MTL.StoreAction {
        switch action {
        case .Dont_Care:
            return .DontCare
        case .Store:
            return .Store
        }
        unreachable()

    }

    _texture_type_interop :: proc(texture_type: Texture_Type) -> MTL.TextureType {
        switch texture_type {
        case ._2D:
            return .Type2D
        case ._2D_Array:
            return .Type2DArray
        }
        unreachable()
    }

    _texture_usage_interop :: proc(usage: Texture_Usage) -> MTL.TextureUsage {
        flags: MTL.TextureUsage
        if .Sampled          in usage { flags += {.ShaderRead} }
        if .Read             in usage { flags += {.ShaderRead} }
        if .Write            in usage { flags += {.ShaderWrite} }
        if .Color_Attachment in usage { flags += {.RenderTarget, .ShaderRead} }
        if .Depth_Attachment in usage { flags += {.RenderTarget} }
        return flags
    }

    _texture_resource_usage_interop :: proc(usage: Texture_Usage) -> MTL.ResourceUsage {
        flags: MTL.ResourceUsage
        if .Sampled in usage { flags += {.Sample} }
        if .Read    in usage { flags += {.Read} }
        if .Write   in usage { flags += {.Write} }
        return flags
    }

    _storage_mode_interop :: proc(storage_mode: StorageMode) -> MTL.StorageMode {
        switch storage_mode {
        case .Shared:
            return .Shared
        case .Private:
            return .Private
        }
        unreachable()
    }
    
    _cull_mode_interop :: proc(cull_mode: Cull_Mode) -> MTL.CullMode {
        switch cull_mode {
        case .None:
            return .None
        case .Front:
            return .Front
        case .Back:
            return .Back
        }
        unreachable()
    }

    _front_face_winding_interop :: proc(winding: Front_Face) -> MTL.Winding {
        switch winding {
        case .CCW:
            return .CounterClockwise
        case .CW:
            return .Clockwise
        }
        unreachable()
    }

    _compare_function_interop :: proc(compare: Compare_Function) -> MTL.CompareFunction {
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

    _pixel_format_interop :: proc(format: Pixel_Format) -> MTL.PixelFormat {
        switch format {
        case .None:
            return .Invalid
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

    _primitive_type_interop :: proc(primitive: Primitive_Type) -> MTL.PrimitiveType {
        switch primitive {
        case .Triangle:
            return .Triangle
        }
        unreachable()
    }

}