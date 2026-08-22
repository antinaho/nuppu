#+build darwin
package nuppu_gpu

// import MTL "vendor:darwin/Metal"
// import CA "vendor:darwin/QuartzCore"
// import NS "core:sys/darwin/Foundation"
// import "core:log"
// import "core:fmt"
// import "core:mem"

when GPU_BACKEND == GPU_BACKEND_METAL {

//     _State :: struct {
//         device: ^MTL.Device,
//         metal_layer: ^CA.MetalLayer,
//         queue: ^MTL.CommandQueue,

//         //
//         curr_swapchain: Texture,

//         frame_pool: ^NS.AutoreleasePool,
//         command_buffer: ^MTL.CommandBuffer,

//         render_pass_descriptor: ^MTL.RenderPassDescriptor,
//         render_command_encoder: ^MTL.RenderCommandEncoder,
//         blit_command_encoder: ^MTL.BlitCommandEncoder,
//     }

//     _init :: proc(native_window: rawptr) -> bool {

//         native_window := cast(^NS.Window)(native_window)
//         scale := native_window->backingScaleFactor()

//         _state.device = MTL.CreateSystemDefaultDevice()

//         metal_layer := CA.MetalLayer.layer()
//         metal_layer->setDevice(_state.device)
//         metal_layer->setPixelFormat(.BGRA8Unorm)
//         metal_layer->setFramebufferOnly(false)
//         metal_layer->setFrame(native_window->frame())
//         metal_layer->setContentsScale(scale)
//         _state.metal_layer = metal_layer

//         native_window->contentView()->setLayer(metal_layer)
//         native_window->setOpaque(true)
//         native_window->setBackgroundColor(nil)
        
//         _state.queue = _state.device->newCommandQueue()

//         for _ in 0 ..< FRAMES_IN_FLIGHT {
//             arena := new(Arena, context.allocator)
//             arena^ = upload_arena()
//             append(&_state.frame_arenas, arena)
//         }

//         _state.is_init = true

//         return true
//     }

//     _deinit :: proc() {
//         _state.metal_layer->release()
//         _state.queue->release()
//         _state.device->release()
//     }

//     _begin_frame :: proc() {
//         _state.frame_pool = NS.AutoreleasePool.alloc()->init()

//         buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
//         defer buffer_desc->release()
//         buffer_desc->setErrorOptions({.EncoderExecutionStatus})

//         _state.command_buffer = _state.queue->commandBufferWithDescriptor(buffer_desc)
//     }

//     _commit :: proc() {
//         if drawable, ok := _state.curr_swapchain.T.(^CA.MetalDrawable); ok {
//             _state.command_buffer->presentDrawable(drawable)
//         }
//         _state.command_buffer->commit()
//     }

//     _end_frame :: proc() {
//         _state.frame_pool->drain()
//         if _state.curr_swapchain.T == nil {
//             log.error("gpu_end_frame: no swapchain is active, did you call next_swapchain()?")
//         }
//         _state.curr_swapchain.T = nil
//     }

//     _Texture :: struct {
//         T : union {
//             ^MTL.Texture,
//             ^CA.MetalDrawable,
//         }
//     }

//     _resize_swapchain :: proc(width, height: i32) -> bool {
//         drawable_size := NS.Size {
//             width  = NS.Float(width),
//             height = NS.Float(height),
//         }

//         _state.metal_layer->setDrawableSize(drawable_size)

//         return true
//     }

//     _to_clear_color :: proc(color: Color) -> MTL.ClearColor {
//         return MTL.ClearColor {
//             red   = f64(color.x) / 255.0,
//             green = f64(color.y) / 255.0,
//             blue  = f64(color.z) / 255.0,
//             alpha = f64(color.w) / 255.0,
//         }
//     }

//     _load_action_interop := [Load_Action]MTL.LoadAction {
//         .Dont_Care = .DontCare,
//         .Clear     = .Clear,
//         .Load      = .Load,
//     }

//     _store_action_interop := [Store_Action]MTL.StoreAction {
//         .Dont_Care                  = .DontCare,
//         .Store                      = .Store,
//     }

//     _acquire_next_swapchain :: proc() -> Texture {
//         drawable := _state.metal_layer->nextDrawable()
//         if drawable == nil {
//             panic("_acquire_next_swapchain: no drawable")
//         }

//         result := Texture {
//             T = drawable
//         }

//         _state.curr_swapchain = result

//         return result
//     }

//     _begin_render_pass :: proc(attachment: Color_Attachment) {
//         pass_descriptor := MTL.RenderPassDescriptor.renderPassDescriptor()

//         color_attachment := pass_descriptor->colorAttachments()->object(0)
//         color_attachment->setClearColor(_to_clear_color(attachment.clear_color))
//         color_attachment->setLoadAction(_load_action_interop[attachment.load_action])
//         color_attachment->setStoreAction(_store_action_interop[attachment.store_action])
//         switch t in attachment.texture.T {
//         case ^MTL.Texture:
//             color_attachment->setTexture(t)
//         case ^CA.MetalDrawable:
//             color_attachment->setTexture(t->texture())
//         }

//         _state.render_pass_descriptor = pass_descriptor
//         _state.render_command_encoder = _state.command_buffer->renderCommandEncoderWithDescriptor(_state.render_pass_descriptor)
//     }

//     _end_render_pass :: proc() {
//         when ODIN_DEBUG {
//             assert(_state.render_command_encoder != nil, "_end_render_pass: no render pass is active")
//         }

//         if _state.render_command_encoder != nil {
//             _state.render_command_encoder->endEncoding()
//             _state.render_command_encoder = nil
//         }
//     }

//     _barrier :: proc(before: Stage, after: Stage) {
//         switch before {
//         case .Transfer:
//             if _state.blit_command_encoder != nil {
//                 _state.blit_command_encoder->endEncoding()
//                 _state.blit_command_encoder = nil
//             }
//         case .All:
//             if _state.blit_command_encoder != nil {
//                 _state.blit_command_encoder->endEncoding()
//                 _state.blit_command_encoder = nil
//             }
//             if _state.render_command_encoder != nil {
//                 _state.render_command_encoder->endEncoding()
//                 _state.render_command_encoder = nil
//             }

//             // if _state.compute_command_encoder != nil {
//             //     _state.compute_command_encoder->endEncoding()
//             //     _state.compute_command_encoder = nil
//             // }

//         case .Compute:
//             // if _state.compute_command_encoder != nil {
//             //     _state.compute_command_encoder->endEncoding()
//             //     _state.compute_command_encoder = nil
//             // }
//         }

//         _ = after
//     }



//     _Shader :: struct {
//         library: ^MTL.Library,
//     }

//     _shader_init :: proc(name: string, code: []u8) -> Resource {
//         library: ^MTL.Library
//         err: ^NS.Error

//         code_ns := NS.String.alloc()->initWithBytesNoCopy(raw_data(code), NS.UInteger(len(code)), .UTF8, false)
//         defer code_ns->release()

//         compile_options := MTL.CompileOptions.alloc()->init()
//         defer compile_options->release()
//         compile_options->setLanguageVersion(.Version3_0)

//         // Could cache library
//         library, err = _state.device->newLibraryWithSource(code_ns, compile_options)
//         if err != nil {
//             log.panicf("Failed to create shader library: %v", err->localizedDescription()->odinString())
//         }

//         idx := _state.shaders.current
//         result := Resource {
//             name = "SHADER",
//             idx = idx,
//             shader = Shader {
//                 library = library,
//             }
//         }
//         _state.shaders.current += 1

//         return result
//     }

//     _Pipeline :: struct {
//         pso: ^MTL.RenderPipelineState
//     }

//     _pipeline_init :: proc(vertex_shader: Resource, vertex_function_entry: string, fragment_shader: Resource, fragment_function_entry: string, format: Pixel_Format) -> Resource {
//         desc := MTL.RenderPipelineDescriptor.alloc()->init()
// 	    defer desc->release()

//         vertex_entry := NS.String.alloc()->initWithOdinString(vertex_function_entry)
//         defer vertex_entry->release()
//         fragment_entry := NS.String.alloc()->initWithOdinString(fragment_function_entry)
//         defer fragment_entry->release()

//         vertex_function := vertex_shader.shader.library->newFunctionWithName(vertex_entry)
//         defer vertex_function->release()
//         fragment_function := fragment_shader.shader.library->newFunctionWithName(fragment_entry)
//         defer fragment_function->release()

//         desc->setVertexFunction(vertex_function)
//         desc->setFragmentFunction(fragment_function)
//         desc->colorAttachments()->object(0)->setPixelFormat(_pixel_format_interop(format))

//         pso, err := _state.device->newRenderPipelineStateWithDescriptor(desc)
//         if err != nil {
//             log.panicf("Failed to create pipeline state: %v", err->localizedDescription()->odinString())
//         }

//         idx := _state.pipelines.current
//         result := Resource {
//             name = "PIPELINE",
//             idx = idx,
//             pipeline = Pipeline {
//                 pso = pso,
//             },
//         }
//         _state.pipelines.current += 1

//         return result
//     }

//     _pixel_format_interop :: proc(format: Pixel_Format) -> MTL.PixelFormat {
//         switch format {
//         case .BGRA8Unorm:
//             return .BGRA8Unorm
//         case .Depth32Float:
//             return .Depth32Float
//         }
//         unreachable()
//     }

//     _Buffer :: struct {
//         buf: ^MTL.Buffer,
//     }

//     _texture_init :: proc(td: Texture_Descriptor) -> Resource {
//         desc := MTL.TextureDescriptor.alloc()->init()
//         defer desc->release()

//         desc->setWidth(NS.UInteger(td.dimensions.x))
//         desc->setHeight(NS.UInteger(td.dimensions.y))
//         desc->setPixelFormat(_pixel_format_interop(td.format))

//         texture := _state.device->newTextureWithDescriptor(desc)
//         if texture == nil {
//             log.panic("gpu_Metal.odin: _texture_init: failed to create texture")
//         }

//         idx := _state.textures.current
//         result := Resource {
//             name = "TEXTURE",
//             idx = idx,
//             texture = Texture {
//                 T = texture
//             }
//         }
//         _state.textures.current += 1

//         return result
//     }

//     _set_pipeline :: proc(pipeline: Pipeline) {
//         _state.render_command_encoder->setRenderPipelineState(pipeline.pso)
//     }

//     _set_buffers :: proc(buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
//         assert(len(buffers) > 0)
//         assert(len(buffers) == int(range.length))
//         assert(len(offsets) == int(range.length))
//         assert(len(buffers) == len(offsets))

//         mtl_buffers := make([]^MTL.Buffer, len=len(buffers), allocator=context.temp_allocator)
//         buffer_offsets := make([]uint, len=len(buffers), allocator=context.temp_allocator)
//         for b, I in buffers {
//             mtl_buffers[I] = b.buffer.buf
//             buffer_offsets[I] = offsets[I]
//         }

//         switch stage {
//         case .Vertex:
//             _state.render_command_encoder->setVertexBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
//         case .Fragment:
//             _state.render_command_encoder->setFragmentBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
//         case .Compute:
//             //_state.compute_command_encoder->setBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
//         }
//     }

//     _primitive_type_interop :: proc(primitive: Primitive_Type) -> MTL.PrimitiveType {
//         switch primitive {
//         case .Triangle:
//             return .Triangle
//         }
//         unreachable()
//     }

//     _Resource :: struct{}

//     _resource_usage_interop :: proc(flag: Resource_Usage_Flag) -> MTL.ResourceUsageFlag {
//         switch flag {
//         case .Read:
//             return .Read
//         case .Write:
//             return .Write
//         case .Sample:
//             return .Sample
//         }
//         unreachable()
//     }

//     _render_stage_interop :: proc(state: Render_Stage) -> MTL.RenderStage {
//         switch state {
//         case .Vertex:
//             return .Vertex
//         case .Fragment:
//             return .Fragment
//         case .Tile:
//             return .Tile
//         case .Object:
//             return .Object
//         case .Mesh:
//             return .Mesh
//         }
//         unreachable()
//     }

//     _frame_arena_deinit :: proc(arena: ^Arena) {
//         panic("no op")
//     }

//     _use_resources :: proc(resource_list: []Shader_Resource) {
//         for res in resource_list {
//             usage_flags := bit_set_to_another(res.usage, MTL.ResourceUsage, _resource_usage_interop)
//             stages := bit_set_to_another(res.stage, MTL.RenderStages, _render_stage_interop)
//             _state.render_command_encoder->useResourceWithStages(
//                 res.ptr.buffer.buf, usage_flags, stages,
//             )
//         }
//     }

//     _temp_malloc :: proc(bytes: []u8, index: u32, shader_stage: Shader_Stage) {
//         switch shader_stage {
//         case .Vertex:
//             _state.render_command_encoder->setVertexBytes(bytes, NS.UInteger(index))
//         case .Fragment:
//             _state.render_command_encoder->setFragmentBytes(bytes, NS.UInteger(index))
//         case .Compute:
//             // if _state.compute_command_encoder == nil {
//             //     _state.compute_command_encoder = _state.command_buffer->computeCommandEncoder()
//             // }
//             // _state.compute_command_encoder->setBytes(bytes, NS.UInteger(index))
//         }
//     }

//     _draw_indiced_primitives :: proc(primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
//         if instance_count == 0 {
//             return
//         }

//         _state.render_command_encoder->drawIndexPrimitivesWithBaseVertex(
//             _primitive_type_interop(primitive), NS.UInteger(index_count), MTL.IndexType.UInt32,
//             index_buffer.buffer.buf, NS.UInteger(index_offset) * NS.UInteger(size_of(u32)), NS.UInteger(instance_count), NS.Integer(base_vertex), NS.UInteger(base_instance)
//         )
//     }

//     _mem_free :: proc(ptr: ptr) {
//         ptr.buffer.buf->release()
//     }

//     _upload_finish :: proc(ptr: ptr) {}


//     _frame_arena :: proc() -> ^Arena {
//         arena := _state.frame_arenas[_state.frame_n % FRAMES_IN_FLIGHT]
//         arena.offset = 0
//         arena.is_mapped = true
//         return arena
//     }

//     _ptr_unmap :: proc(ptr: ptr) { /* no op in Metal */ }

//     _recycle_frame_arena :: proc(arena: ^Arena) {
//         arena.is_mapped = false
//         //Signal and wait in _frame_arena
//     }


//     _mem_copy :: proc(dst: ptr, dst_offset: u64, src: ptr, src_offset: u64, size: u64) {
//         if _state.blit_command_encoder == nil {
//             _state.blit_command_encoder = _state.command_buffer->blitCommandEncoder()
//         }

//         _state.blit_command_encoder->copyFromBuffer(
//             src.buffer.buf, NS.UInteger(src_offset),
//             dst.buffer.buf, NS.UInteger(dst_offset),
//             NS.UInteger(size),
//         )
//     }

//     _default_buffer :: proc(
//         size: u64
//     ) -> ptr {
//         buffer := _state->device->newBufferWithLength(
//             length = NS.UInteger(size),
//             options = MTL.ResourceStorageModeShared,
//         )
//         cpu_ptr := buffer->contentsPointer()
//         gpu_ptr := buffer->gpuAddress()

//         result := ptr {
//             cpu = cpu_ptr,
//             gpu = rawptr(uintptr(gpu_ptr)),
//             buffer = Buffer { buf = buffer, capacity = uint(size) },
//         }

//         return result
//     }

//     _gpu_buffer :: proc(
//         size: u64,
//         role: Role = .Default
//     ) -> ptr {
//         buffer := _state->device->newBufferWithLength(
//             length = NS.UInteger(size),
//             options = {.StorageModePrivate}
//         )

//         gpu_ptr := buffer->gpuAddress()

//         result := ptr {
//             cpu = nil,
//             gpu = rawptr(uintptr(gpu_ptr)),
//             buffer = Buffer { buf = buffer, capacity = uint(size) },
//         }

//         return result
//     }
//     _readback_buffer :: proc(size: u64) -> ptr {
//         panic("Metal: readback buffer not implemented")
//     }

//     _scoped_upload_buffer :: proc(bytes, align: uint) -> ptr {
//         bytes_aligned := mem.align_forward_uint(bytes, align)
        
//         options := MTL.ResourceStorageModeShared
                
//         buffer := _state->device->newBufferWithLength(
//             length = NS.UInteger(bytes_aligned),
//             options = options,
//         )                

//         cpu_ptr := buffer->contentsPointer()
//         gpu_ptr := buffer->gpuAddress()

//         result := ptr {
//             cpu = cpu_ptr,
//             gpu = rawptr(uintptr(gpu_ptr)),
//             buffer = Buffer { buf = buffer, capacity = bytes_aligned},
//         }

//         return result
//     }

//     _end_scoped_upload :: proc(buffer: ptr) {}
//     _free_mem :: proc(ptr: ptr) {
//         ptr.buffer.buf->release()
//     }
}
// import "core:slice"