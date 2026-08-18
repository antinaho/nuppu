#+build darwin
package nuppu_gpu

import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "core:log"
import "core:fmt"
import "core:mem"

when GPU_BACKEND == GPU_BACKEND_METAL {

    _State :: struct {
        device: ^MTL.Device,
        metal_layer: ^CA.MetalLayer,
        queue: ^MTL.CommandQueue,

        //

        frame_pool: ^NS.AutoreleasePool,
        command_buffer: ^MTL.CommandBuffer,

        render_pass_descriptor: ^MTL.RenderPassDescriptor,
        render_command_encoder: ^MTL.RenderCommandEncoder,
        blit_command_encoder: ^MTL.BlitCommandEncoder,
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

    _begin_frame :: proc() {
        _state.frame_pool = NS.AutoreleasePool.alloc()->init()

        buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
        defer buffer_desc->release()
        buffer_desc->setErrorOptions({.EncoderExecutionStatus})

        _state.command_buffer = _state.queue->commandBufferWithDescriptor(buffer_desc)
    }

    _end_frame :: proc() {
        _state.frame_pool->drain()
    }

    _Texture :: struct {
        T : union {
            ^MTL.Texture,
            ^CA.MetalDrawable,
        }
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

        return Texture {
            T = drawable,
        }
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

    Stage :: enum u64 {
        Transfer         = 0,
        Compute          = 1,
        All              = 6,
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

    _present :: proc(texture: Texture) {
        _barrier(.All, .All)
        drawable := texture.T.(^CA.MetalDrawable)
        _state.command_buffer->presentDrawable(drawable)
        _state.command_buffer->commit()
    }

    _Shader :: struct {
        library: ^MTL.Library,
    }

    _shader_init :: proc(name: string, code: []u8) -> Resource {
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

        idx := _state.shaders.current
        result := Resource {
            name = "SHADER",
            idx = idx,
            shader = Shader {
                library = library,
            }
        }
        _state.shaders.current += 1

        return result
    }

    _Pipeline :: struct {
        pso: ^MTL.RenderPipelineState
    }

    _upload_one_shot :: proc(items: []struct {dst: ^ptr, src: ptr, bytes: uint}) {
        pool := NS.AutoreleasePool.alloc()->init()
        defer pool->drain()

        buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
        defer buffer_desc->release()
        buffer_desc->setErrorOptions({.EncoderExecutionStatus})

        _state.command_buffer = _state.queue->commandBufferWithDescriptor(buffer_desc)
        _state.blit_command_encoder = _state.command_buffer->blitCommandEncoder()

        for item in items {
            src_buffer := item.src.buffer.buf
            dst_buffer := item.dst.buffer.buf

            src_offset := NS.UInteger(item.src.offset)
            dst_offset := NS.UInteger(item.dst.offset)

            _state.blit_command_encoder->copyFromBuffer(
                src_buffer, src_offset,
                dst_buffer, dst_offset,
                NS.UInteger(item.bytes),
            )
        }

        _state.blit_command_encoder->endEncoding()
        _state.blit_command_encoder = nil
        _state.command_buffer->commit()
    }


    _pipeline_init :: proc(vertex_shader: Resource, vertex_function_entry: string, fragment_shader: Resource, fragment_function_entry: string, format: Pixel_Format) -> Resource {
        desc := MTL.RenderPipelineDescriptor.alloc()->init()
	    defer desc->release()

        vertex_entry := NS.String.alloc()->initWithOdinString(vertex_function_entry)
        defer vertex_entry->release()
        fragment_entry := NS.String.alloc()->initWithOdinString(fragment_function_entry)
        defer fragment_entry->release()

        vertex_function := vertex_shader.shader.library->newFunctionWithName(vertex_entry)
        defer vertex_function->release()
        fragment_function := fragment_shader.shader.library->newFunctionWithName(fragment_entry)
        defer fragment_function->release()

        desc->setVertexFunction(vertex_function)
        desc->setFragmentFunction(fragment_function)
        desc->colorAttachments()->object(0)->setPixelFormat(_pixel_format_interop(format))

        pso, err := _state.device->newRenderPipelineStateWithDescriptor(desc)
        if err != nil {
            log.panicf("Failed to create pipeline state: %v", err->localizedDescription()->odinString())
        }

        idx := _state.pipelines.current
        result := Resource {
            name = "PIPELINE",
            idx = idx,
            pipeline = Pipeline {
                pso = pso,
            },
        }
        _state.pipelines.current += 1

        return result
    }

    _pixel_format_interop :: proc(format: Pixel_Format) -> MTL.PixelFormat {
        switch format {
        case .BGRA8Unorm:
            return .BGRA8Unorm_sRGB
        case .Depth32Float:
            return .Depth32Float
        }
        unreachable()
    }

    _Buffer :: struct {
        buf: ^MTL.Buffer,
    }

    _buffer_init :: proc(bytes: uint, align: uint, memory: Memory) -> ptr {
        bytes := mem.align_forward_uint(bytes, align)
        
        options := MTL.ResourceOptions{}
        switch memory {
        case .CPU_GPU:
            options = MTL.ResourceStorageModeShared
        case .GPU_Only:
            options = {.StorageModePrivate}
        }
                
        buffer := _state->device->newBufferWithLength(
            length = NS.UInteger(bytes),
            options = options,
        )                

        cpu_ptr: rawptr
        if .StorageModePrivate not_in options {
            cpu_ptr = buffer->contentsPointer()
        }
        gpu_ptr := buffer->gpuAddress()

        result := ptr {
            cpu = cpu_ptr,
            gpu = rawptr(uintptr(gpu_ptr)),
            offset = 0,
            buffer = Buffer { buf = buffer},
        }

        return result
    }

    _texture_init :: proc(td: Texture_Descriptor) -> Resource {
        desc := MTL.TextureDescriptor.alloc()->init()
        defer desc->release()

        desc->setWidth(NS.UInteger(td.dimensions.x))
        desc->setHeight(NS.UInteger(td.dimensions.y))
        desc->setPixelFormat(_pixel_format_interop(td.format))

        texture := _state.device->newTextureWithDescriptor(desc)
        if texture == nil {
            log.panic("gpu_Metal.odin: _texture_init: failed to create texture")
        }

        idx := _state.textures.current
        result := Resource {
            name = "TEXTURE",
            idx = idx,
            texture = Texture {
                T = texture
            }
        }
        _state.textures.current += 1

        return result
    }

    _set_pipeline :: proc(pipeline: Pipeline) {
        _state.render_command_encoder->setRenderPipelineState(pipeline.pso)
    }

    _set_buffers :: proc(buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
        assert(len(buffers) > 0)
        assert(len(buffers) == int(range.length))
        assert(len(offsets) == int(range.length))
        assert(len(buffers) == len(offsets))

        mtl_buffers := make([]^MTL.Buffer, len=len(buffers), allocator=context.temp_allocator)
        buffer_offsets := make([]uint, len=len(buffers), allocator=context.temp_allocator)
        for b, I in buffers {
            mtl_buffers[I] = b.buffer.buf
            buffer_offsets[I] = b.offset + offsets[I]
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

    _draw_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, vertex_count: u32, vertex_start: u32) {
        _state.render_command_encoder->drawPrimitives(_primitive_type_interop(primitive), NS.UInteger(vertex_start), NS.UInteger(vertex_count))
    }

    _ptr_fill_slice :: proc(dst: ^ptr, data: rawptr, size, count: int) {
        if dst.cpu == nil {
            log.error("gpu_ptr_fill_slice: dst must have CPU ptr set. Is ptr GPU private?")
            return
        }
        mem.copy(rawptr(uintptr(dst.cpu) + uintptr(dst.offset)), data, size * count)
    }
}