#+build darwin
package nuppu_gpu

import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "core:log"
import "base:runtime"
import hm "core:container/handle_map"
import "core:time"

when GPU_BACKEND == GPU_BACKEND_METAL {

    _State :: struct {
        device: ^MTL.Device,
        metal_layer: ^CA.MetalLayer,
        queue: ^MTL.CommandQueue,
        //
        frame_pool: ^NS.AutoreleasePool,
        command_buffer: ^MTL.CommandBuffer,
        curr_drawable: _Texture, // Swapchain
        render_command_encoder: ^MTL.RenderCommandEncoder,

        

        
        blit_command_encoder: ^MTL.BlitCommandEncoder,
        compute_command_encoder: ^MTL.ComputeCommandEncoder,

        curr_pipeline: Pipeline_Handle,
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

        for i in 0 ..< FRAMES_IN_FLIGHT {
            frame_arena := new(Arena, context.allocator)
            frame_arena^ = arena()
            append(&_state.frame_arenas, frame_arena)
        }

        _state.is_init = true

        return true
    }

    _resize_depth_texture :: proc(width, height: i32) {
        swapchain_dims := _state.metal_layer->drawableSize()
        _state.depth_texture.native.texture->release()
        _state.depth_texture = texture_depth_init({u32(swapchain_dims.width), u32(swapchain_dims.height)}, .Depth32Float)
    }

    _deinit :: proc() {
        _state.metal_layer->release()
        _state.queue->release()
        _state.device->release()
    }

    _begin_commands :: proc() {
        _state.frame_pool = NS.AutoreleasePool.alloc()->init()

        buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
        defer buffer_desc->release()
        buffer_desc->setErrorOptions({.EncoderExecutionStatus})

        _state.command_buffer = _state.queue->commandBufferWithDescriptor(buffer_desc)
    }

    _begin_frame :: proc() {
        if _state.frame_pool != nil {
            _state.frame_pool->drain()
            _state.frame_pool = nil  // pool itself is released by drain
        }
        _begin_commands()
    }

    _commit_commands :: proc() {
        _state.command_buffer->commit()
        _state.command_buffer = nil
        
        if _state.frame_pool != nil {
            _state.frame_pool->drain()
            _state.frame_pool = nil
        }
    }

    _end_frame :: proc() {
        // The render work (begin_frame -> render -> end_render_pass) was
        // recorded into the command buffer autoreleased into _state.frame_pool.
        // Now present + signal + commit it, then drain the pool. Metal
        // retains the buffer post-commit so the autorelease reference can
        // be safely released by the drain.
        _state.command_buffer->presentDrawable(_state.curr_drawable.drawable)
        _state.command_buffer->encodeSignalEvent((^MTL.SharedEvent)(_state.frame_semaphore), _state.frame_n)
        _state.command_buffer->commit()

        _state.command_buffer = {}
        _state.curr_drawable = {}
        _state.render_command_encoder = {}

        if _state.frame_pool != nil {
            _state.frame_pool->drain()
            _state.frame_pool = nil
        }
    }



    _Texture :: struct #raw_union {
        using _ : struct {
            texture: ^MTL.Texture,
            drawable: ^CA.MetalDrawable,
        }
    }

    _copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
        native := texture.native

        region := MTL.Region {
            origin = MTL.Origin {NS.Integer(origin.x), NS.Integer(origin.y), NS.Integer(origin.z)},
            size = MTL.Size {
                width = NS.Integer(size.x),
                height = NS.Integer(size.y),
                depth = NS.Integer(size.z),
            },
        }

        native.texture->replaceRegion(region, NS.UInteger(level), data, NS.UInteger(bytes_per_row))
    }

    _set_textures :: proc(textures: []Texture, range: Range, stage: Shader_Stage) {
        mtl_textures := make([]^MTL.Texture, len=len(textures), allocator=context.temp_allocator)
        for tex, I in textures {
            mtl_textures[I] = tex.native.texture
        }

        switch stage {
        case .Vertex:
            _state.render_command_encoder->setVertexTextures(mtl_textures, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
        case .Fragment:
            _state.render_command_encoder->setFragmentTextures(mtl_textures, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
        case .Compute:
            _state.compute_command_encoder->setTextures(mtl_textures, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
        }
    }

    _map :: proc(ptr: ^_ptr) -> (cpu: rawptr, gpu: rawptr) {
        assert(ptr.offset % 8 == 0)
        assert(ptr.capacity > 0)
        assert(ptr.capacity % 4 == 0)

        cpu = ptr.buffer->contentsPointer()
        gpu = rawptr(uintptr(ptr.buffer->gpuAddress()))

        return
    }

    _mapped :: proc(ptr: ptr) -> bool {
        return ptr.cpu != nil
    }

    _gpu_address :: proc(p: _ptr) -> rawptr {
        return rawptr(uintptr(p.buffer->gpuAddress()))
    }

    _resize_swapchain :: proc(width, height: i32) -> bool {
        drawable_size := NS.Size {
            width  = NS.Float(width),
            height = NS.Float(height),
        }

        _state.metal_layer->setDrawableSize(drawable_size)

        return true
    }

    _to_clear_color :: proc(color: Color) -> MTL.ClearColor {
        return MTL.ClearColor {
            red   = f64(color.x) / 255.0,
            green = f64(color.y) / 255.0,
            blue  = f64(color.z) / 255.0,
            alpha = f64(color.w) / 255.0,
        }
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
        }
        unreachable()
    }

    _texture_usage_interop :: proc(usage: Texture_Usage_Flags) -> MTL.TextureUsageFlag {
        switch usage {
        case .ShaderRead:
            return .ShaderRead
        case .ShaderWrite:
            return .ShaderWrite
        case .RenderTarget:
            return .RenderTarget
        }
        unreachable()
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

    _texture_init :: proc(texture_descriptor: Texture_Descriptor) -> _Texture {
        desc := MTL.TextureDescriptor.alloc()->init()
        defer desc->release()

        desc->setWidth(NS.UInteger(texture_descriptor.dimensions.x))
        desc->setHeight(NS.UInteger(texture_descriptor.dimensions.y))
        desc->setPixelFormat(_pixel_format_interop(texture_descriptor.format))
        desc->setUsage(bit_set_to_another(texture_descriptor.usage, MTL.TextureUsage, _texture_usage_interop))
        desc->setStorageMode(_storage_mode_interop(texture_descriptor.storage))
        desc->setTextureType(_texture_type_interop(texture_descriptor.type))

        texture := _state.device->newTextureWithDescriptor(desc)
        if texture == nil {
            log.panic("gpu_MTL.odin: MTL_texture_init: failed to create texture")
        }

        return _Texture { texture = texture }
    }

    _acquire_next_swapchain :: proc() -> _Texture {
        drawable := _state.metal_layer->nextDrawable()
        if drawable == nil {
            panic("In gpu_Metal.odin: _acquire_next_swapchain: Couldn't acquire next drawable")
        }

        native := _Texture { drawable = drawable, texture = drawable->texture() }
        
        _state.curr_drawable = native

        return native
    }

    _set_depth_stencil_state :: proc(depth_stencil_state: Depth_Stencil_Handle) {
        impl := hm.static_get(&_state.depth_stencil_states, depth_stencil_state)
        _state.render_command_encoder->setDepthStencilState(impl.native)
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

    



    _Shader :: struct {
        library: ^MTL.Library,
    }

    _shader_init :: proc(name: string, code: []u8) -> Shader_Handle {
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

        handle := hm.static_add(&_state.shaders, Shader {
            library = library,
        })

        return handle
    }

    _Pipeline :: struct {
        pso: ^MTL.RenderPipelineState
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

    _set_cull_mode :: proc(cull_mode: Cull_Mode) {
        _state.render_command_encoder->setCullMode(_cull_mode_interop(cull_mode))
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

    _set_front_face_winding :: proc(winding: Front_Face) {
        _state.render_command_encoder->setFrontFacingWinding(_front_face_winding_interop(winding))
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

    _Depth_Stencil_State :: ^MTL.DepthStencilState

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

    __Pipeline_Descriptor :: struct {
        handle: Pipeline_Handle,

        vertex_shader:   Shader_Handle, vertex_function:   string,
        fragment_shader: Shader_Handle, fragment_function: string, 
    
        multisample: Multisample_State,

        blend: Blend_State,
    
        depth_format: Pixel_Format,
        format: Pixel_Format,

        primitive: Primitive_State,

        buffers: [8]ptr,

        index_buffer: ptr,
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

    _pipeline_init :: proc(vertex_shader: Shader_Handle, vertex_function_entry: string, fragment_shader: Shader_Handle, fragment_function_entry: string, format: Pixel_Format, depth_format: Pixel_Format) -> Pipeline_Handle {
        desc := MTL.RenderPipelineDescriptor.alloc()->init()
	    defer desc->release()

        vertex_entry := NS.String.alloc()->initWithOdinString(vertex_function_entry)
        defer vertex_entry->release()
        fragment_entry := NS.String.alloc()->initWithOdinString(fragment_function_entry)
        defer fragment_entry->release()

        vertex_shader_m := hm.static_get(&_state.shaders, vertex_shader)
        fragment_shader_m := hm.static_get(&_state.shaders, fragment_shader)

        vertex_function := vertex_shader_m.library->newFunctionWithName(vertex_entry)
        defer vertex_function->release()
        fragment_function := fragment_shader_m.library->newFunctionWithName(fragment_entry)
        defer fragment_function->release()

        desc->setVertexFunction(vertex_function)
        desc->setFragmentFunction(fragment_function)
        desc->setDepthAttachmentPixelFormat(_pixel_format_interop(depth_format))

        color_attachment := desc->colorAttachments()->object(0)
        color_attachment->setPixelFormat(_pixel_format_interop(format))
        
        pso, err := _state.device->newRenderPipelineStateWithDescriptor(desc)
        if err != nil {
            log.panicf("Failed to create pipeline state: %v", err->localizedDescription()->odinString())
        }

        handle := hm.static_add(&_state.pipelines, Pipeline_Descriptor {
            native = _Pipeline {
                pso = pso
            }
        })

        return handle
    }

    _pixel_format_interop :: proc(format: Pixel_Format) -> MTL.PixelFormat {
        switch format {
        case .None:
            return .Invalid
        case .BGRA8Unorm:
            return .BGRA8Unorm
        case .Depth32Float:
            return .Depth32Float
        }
        unreachable()
    }

    _ptr :: struct {
        buffer: ^MTL.Buffer,
        offset: uint, // Byte offset of this view into `buffer` (0 for top-level allocations)
        capacity: uint, // Capacity of the ptr, NOT the buffer
        index_bytes: u8
    }

    _set_pipeline :: proc(pipeline: Pipeline_Handle) {
        _state.curr_pipeline = pipeline
    }

    _set_buffers :: proc(buffers: []ptr, range: Range, stage: Shader_Stage) {
        assert(len(buffers) > 0)
        assert(len(buffers) == int(range.length))

        mtl_buffers := make([]^MTL.Buffer, len=len(buffers), allocator=context.temp_allocator)
        buffer_offsets := make([]uint, len=len(buffers), allocator=context.temp_allocator)
        for b, I in buffers {
            mtl_buffers[I] = b.native.buffer
            buffer_offsets[I] = 0
        }

        switch stage {
        case .Vertex:
            _state.render_command_encoder->setVertexBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
        case .Fragment:
            _state.render_command_encoder->setFragmentBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
        case .Compute:
            //_state.compute_command_encoder->setBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
        }
    }

    _primitive_type_interop :: proc(primitive: Primitive_Type) -> MTL.PrimitiveType {
        switch primitive {
        case .Triangle:
            return .Triangle
        }
        unreachable()
    }

    _resource_usage_interop :: proc(flag: Resource_Usage_Flag) -> MTL.ResourceUsageFlag {
        switch flag {
        case .Read:
            return .Read
        case .Write:
            return .Write
        case .Sample:
            return .Sample
        }
        unreachable()
    }

    _render_stage_interop :: proc(state: Render_Stage) -> MTL.RenderStage {
        switch state {
        case .Vertex:
            return .Vertex
        case .Fragment:
            return .Fragment
        case .Tile:
            return .Tile
        case .Object:
            return .Object
        case .Mesh:
            return .Mesh
        }
        unreachable()
    }

    _unmap :: proc(ptr: ^_ptr) { /* no op in Metal */ }

    _use_resources :: proc(resource_list: []Shader_Resource) {
        for res in resource_list {
            usage_flags := bit_set_to_another(res.usage, MTL.ResourceUsage, _resource_usage_interop)
            stages := bit_set_to_another(res.stage, MTL.RenderStages, _render_stage_interop)
            _state.render_command_encoder->useResourceWithStages(
                res.ptr.native.buffer, usage_flags, stages,
            )
        }
    }

    _temp_malloc :: proc(bytes: []u8, index: u32, shader_stage: Shader_Stage) {
        switch shader_stage {
        case .Vertex:
            _state.render_command_encoder->setVertexBytes(bytes, NS.UInteger(index))
        case .Fragment:
            _state.render_command_encoder->setFragmentBytes(bytes, NS.UInteger(index))
        case .Compute:
            // if _state.compute_command_encoder == nil {
            //     _state.compute_command_encoder = _state.command_buffer->computeCommandEncoder()
            // }
            // _state.compute_command_encoder->setBytes(bytes, NS.UInteger(index))
        }
    }

    _draw_indiced_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
        pipeline := hm.static_get(&_state.pipelines, _state.curr_pipeline)
        _state.render_command_encoder->setRenderPipelineState(pipeline.pso)

        if instance_count == 0 {
            return
        }

        index_format: MTL.IndexType
        switch index_buffer.native.index_bytes {
        case 2:
            index_format = MTL.IndexType.UInt16
        case 4:
            index_format = MTL.IndexType.UInt32
        case: panic("Index buffer format not supported")
        }

        _state.render_command_encoder->drawIndexPrimitivesWithBaseVertex(
            _primitive_type_interop(primitive), NS.UInteger(index_count), index_format,
            index_buffer.native.buffer, NS.UInteger(index_offset * u32(index_buffer.native.index_bytes)), NS.UInteger(instance_count), NS.Integer(base_vertex), NS.UInteger(base_instance)
        )
    }


    _frame_arena :: proc() -> ^Arena {
        arena := _state.frame_arenas[_state.frame_n % FRAMES_IN_FLIGHT]
        arena.offset = 0
        return arena
    }

    _recycle_frame_arena :: proc(arena: ^Arena) {
        /* no op */
        // end frame signals the semaphore
    }

    _sub_alloc :: proc(parent: ptr, offset, length: uint) -> ptr {
        result := parent
        result.cpu      = rawptr(uintptr(parent.cpu) + uintptr(offset))
        result.gpu      = rawptr(uintptr(parent.gpu) + uintptr(offset))
        result.offset   = offset
        result.capacity = length

        return result
    }

    _copy :: proc(dst, src: ptr) {
        if _state.blit_command_encoder == nil {
            _state.blit_command_encoder = _state.command_buffer->blitCommandEncoder()
        }

        _state.blit_command_encoder->copyFromBuffer(
            src.native.buffer, NS.UInteger(src.offset),
            dst.native.buffer, NS.UInteger(dst.offset),
            NS.UInteger(src.capacity),
        )
    }

    _malloc :: proc(
        type: Buffer_Type,
        #any_int size: uint,
        #any_int alignment: uint,
        name: string,
    ) -> _ptr {
        bytes := runtime.align_forward_uint(size, alignment)

        options: MTL.ResourceOptions
        switch type {
        case .Staging:
            options = MTL.ResourceStorageModeShared
        case .GPU_Storage:
            options = {.StorageModePrivate}
        case .GPU_Constant:
            options = {.StorageModePrivate}
        case .GPU_Index:
            options = {.StorageModePrivate}
        case .Readback:
            options = MTL.ResourceStorageModeShared
        }

        buffer := _state->device->newBufferWithLength(
            length = NS.UInteger(bytes),
            options = options,
        )

        return _ptr {
            buffer = buffer,
            offset = 0,
            capacity = uint(bytes),
        }
    }

    //////////////////////////////////////////////////////////////
    // Synchronization

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

    _semaphore :: proc(value: u64) -> Semaphore {
        event := _state.device->newSharedEvent()
        event->setSignaledValue(value)
        return Semaphore(event)
    }

    _semaphore_wait :: proc(semaphore: Semaphore, value: u64) -> bool {
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
}