#+build darwin
package nuppu_gpu

import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "core:log"
import "base:runtime"
import hm "core:container/handle_map"

when GPU_BACKEND == GPU_BACKEND_METAL {

    _State :: struct {
        device: ^MTL.Device,
        metal_layer: ^CA.MetalLayer,
        queue: ^MTL.CommandQueue,

        //
        curr_swapchain: Texture,

        frame_pool: ^NS.AutoreleasePool,
        command_buffer: ^MTL.CommandBuffer,

        render_pass_descriptor: ^MTL.RenderPassDescriptor,
        render_command_encoder: ^MTL.RenderCommandEncoder,
        blit_command_encoder: ^MTL.BlitCommandEncoder,

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

        for _ in 0 ..< FRAMES_IN_FLIGHT {
            frame_arena := new(Arena, context.allocator)
            frame_arena^ = arena()
            append(&_state.frame_arenas, frame_arena)
        }

        _state.is_init = true

        return true
    }

    _deinit :: proc() {
        _state.metal_layer->release()
        _state.queue->release()
        _state.device->release()
    }

    _begin_frame :: proc() {
        _state.frame_pool = NS.AutoreleasePool.alloc()->init()

        buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
        defer buffer_desc->release()
        buffer_desc->setErrorOptions({.EncoderExecutionStatus})

        _state.command_buffer = _state.queue->commandBufferWithDescriptor(buffer_desc)
    }

    _commit :: proc() {
        if drawable, ok := _state.curr_swapchain.T.(^CA.MetalDrawable); ok {
            _state.command_buffer->presentDrawable(drawable)
        }
        _state.command_buffer->commit()
    }

    _end_frame :: proc() {
        _state.frame_pool->drain()
        if _state.curr_swapchain.T == nil {
            log.error("gpu_end_frame: no swapchain is active, did you call next_swapchain()?")
        }
        _state.curr_swapchain.T = nil
    }

    _Texture :: struct {
        T : union {
            ^MTL.Texture,
            ^CA.MetalDrawable,
        }
    }

    _map_range :: proc(ptr: _ptr) -> (cpu: rawptr, gpu: rawptr) {
        assert(ptr.offset % 8 == 0)
        assert(ptr.capacity > 0)
        assert(ptr.capacity % 4 == 0)

        cpu = ptr.buffer->contentsPointer()
        gpu = rawptr(uintptr(ptr.buffer->gpuAddress()))

        return
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

    _load_action_interop := [Load_Action]MTL.LoadAction {
        .Dont_Care = .DontCare,
        .Clear     = .Clear,
        .Load      = .Load,
    }

    _store_action_interop := [Store_Action]MTL.StoreAction {
        .Dont_Care                  = .DontCare,
        .Store                      = .Store,
    }

    _acquire_next_swapchain :: proc() -> Texture {
        drawable := _state.metal_layer->nextDrawable()
        if drawable == nil {
            panic("_acquire_next_swapchain: no drawable")
        }

        result := Texture {
            T = drawable
        }

        _state.curr_swapchain = result

        return result
    }

    _begin_render_pass :: proc(attachment: Color_Attachment) {
        pass_descriptor := MTL.RenderPassDescriptor.renderPassDescriptor()

        color_attachment := pass_descriptor->colorAttachments()->object(0)
        color_attachment->setClearColor(_to_clear_color(attachment.clear_color))
        color_attachment->setLoadAction(_load_action_interop[attachment.load_action])
        color_attachment->setStoreAction(_store_action_interop[attachment.store_action])
        switch t in attachment.texture.T {
        case ^MTL.Texture:
            color_attachment->setTexture(t)
        case ^CA.MetalDrawable:
            color_attachment->setTexture(t->texture())
        }

        _state.render_pass_descriptor = pass_descriptor
        _state.render_command_encoder = _state.command_buffer->renderCommandEncoderWithDescriptor(_state.render_pass_descriptor)
    }

    _end_render_pass :: proc() {
        when ODIN_DEBUG {
            assert(_state.render_command_encoder != nil, "_end_render_pass: no render pass is active")
        }

        if _state.render_command_encoder != nil {
            _state.render_command_encoder->endEncoding()
            _state.render_command_encoder = nil
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

            // if _state.compute_command_encoder != nil {
            //     _state.compute_command_encoder->endEncoding()
            //     _state.compute_command_encoder = nil
            // }

        case .Compute:
            // if _state.compute_command_encoder != nil {
            //     _state.compute_command_encoder->endEncoding()
            //     _state.compute_command_encoder = nil
            // }
        }

        _ = after
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

    _pipeline_init :: proc(vertex_shader: Shader_Handle, vertex_function_entry: string, fragment_shader: Shader_Handle, fragment_function_entry: string, format: Pixel_Format) -> Pipeline_Handle {
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
        desc->colorAttachments()->object(0)->setPixelFormat(_pixel_format_interop(format))

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

    _unmap :: proc(ptr: _ptr) { /* no op in Metal */ }

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
        arena.is_mapped = true
        return arena
    }

    _recycle_frame_arena :: proc(arena: ^Arena) {
        arena.is_mapped = false
        //Signal and wait in _frame_arena
    }

    _sub_alloc :: proc(parent: ptr, offset, length: uint) -> ptr {
        result := parent
        result.cpu      = rawptr(uintptr(parent.cpu) + uintptr(offset))
        result.gpu      = rawptr(uintptr(parent.gpu) + uintptr(offset))
        result.offset   = offset
        result.capacity = length

        return result
    }

    _mem_copy :: proc(dst, src: ptr) {
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
}