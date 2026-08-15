package nuppu

import "core:log"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "core:time"
import "core:mem"

MTL_RENDERER_API :: GPU_API {
    init = MTL_init,
    deinit = MTL_deinit,
    resize_swapchain = MTL_resize_swapchain,

    free = MTL_free,
    malloc = MTL_malloc,
    mem_copy_to_texture = MTL_mem_copy_to_texture,
    temp_malloc = MTL_temp_malloc,

    signal_init = MTL_signal_init,
    signal_deinit = MTL_signal_deinit,
    signal_wait_for = MTL_signal_wait_for,

    begin_commands = MTL_begin_commands,
    end_commands = MTL_end_commands,
    cmd_present = MTL_cmd_present,
    acquire_next_swapchain = MTL_acquire_next_swapchain,
    cmd_begin_render_pass = MTL_cmd_begin_render_pass,
    cmd_end_render_pass = MTL_cmd_end_render_pass,
    cmd_mem_copy = MTL_cmd_mem_copy,
    cmd_barrier = MTL_cmd_barrier,
    cmd_blit_texture = MTL_cmd_blit_texture,

    shader_init = MTL_shader_init,
    kernel_init = MTL_kernel_init,
    shader_deinit = MTL_shader_deinit,

    pipeline_init = MTL_pipeline_init,
    pipeline_deinit = MTL_pipeline_deinit,
    cmd_set_pipeline = MTL_cmd_set_graphics_pipeline,

    cmd_draw_indiced_primitives = MTL_cmd_draw_indiced_primitives,
    cmd_draw_primitives = MTL_cmd_draw_primitives,
    cmd_set_scissor_rect = MTL_cmd_set_scissor_rect,
    cmd_use_resources = MTL_use_resources,

    depth_stencil_state_init = MTL_depth_stencil_state_init,
    depth_stencil_state_deinit = MTL_depth_stencil_state_deinit,
    cmd_set_depth_stencil_state = MTL_cmd_set_depth_stencil_state,

    texture_init = MTL_texture_init,
    texture_deinit = MTL_texture_deinit,

    cmd_set_cull_mode = MTL_cmd_set_cull_mode,
    cmd_set_front_face_winding = MTL_cmd_set_front_face_winding,

    cmd_set_compute_pipeline = MTL_cmd_set_compute_pipeline,
    cmd_set_texture = MTL_cmd_set_texture,
    cmd_dispatch = MTL_cmd_dispatch,
    max_total_threads_per_threadgroup = MTL_max_total_threads_per_threadgroup,
    cmd_set_textures = MTL_cmd_set_textures,

    cmd_set_buffer = MTL_cmd_set_buffer,
    cmd_set_buffers = MTL_cmd_set_buffers,

    texture_size = MTL_texture_size,
    texture_format = MTL_texture_format,
    texture_type = MTL_texture_type,
    remake_texture = MTL_remake_texture,
}

MTL_State :: struct {
    device: ^MTL.Device,
    queue: ^MTL.CommandQueue,
    metal_layer: ^CA.MetalLayer,

    command_buffers: Resource_Library(16, MTL_Command_Buffer_Impl, Command_Buffer),
    textures: Resource_Library(1 << 16, MTL_Texture_Impl, Texture)
}

MTL_Texture_Impl :: struct {
    texture: ^MTL.Texture,
    drawable: ^CA.MetalDrawable,
}

MTL_Command_Buffer_Impl :: struct {
    pool: ^NS.AutoreleasePool,
    command_buffer: ^MTL.CommandBuffer,
    pass_descriptor: ^MTL.RenderPassDescriptor,
    
    render_command_encoder: ^MTL.RenderCommandEncoder,
    blit_command_encoder: ^MTL.BlitCommandEncoder,
    compute_command_encoder: ^MTL.ComputeCommandEncoder,

    depth_format: Pixel_Format,
    signal_fence: ^MTL.Fence,
    presentable: Texture,
}

@(private="file")
state: ^MTL_State

MTL_init :: proc() -> GPU_API_State {
    state = new(MTL_State)
    
    native_window := cast(^NS.Window)(native_window())
    scale := pixel_scale()

    state.device = MTL.CreateSystemDefaultDevice()

    metal_layer := CA.MetalLayer.layer()
    
    metal_layer->setDevice(state.device)
    metal_layer->setPixelFormat(.BGRA8Unorm_sRGB)
    // framebufferOnly = false: the swapchain drawable must be usable as a blit
    // destination (e.g. when displaying an offscreen render target via
    // `cmd_blit_texture`). Apple's recommended value is `true` for slightly
    // better tile compression when the swapchain is only used as a render
    // target, but that disables the documented render-to-texture workflow.
    metal_layer->setFramebufferOnly(false)
    metal_layer->setFrame(native_window->frame())
    metal_layer->setContentsScale(NS.Float(scale.x))
    state.metal_layer = metal_layer

    native_window->contentView()->setLayer(metal_layer)
    native_window->setOpaque(true)
    native_window->setBackgroundColor(nil)
    
    state.queue = state.device->newCommandQueue()

    resource_library_init(&state.command_buffers)
    resource_library_init(&state.textures)

    return GPU_API_State(state)
}

MTL_deinit :: proc() {
    state.metal_layer->release()
    state.queue->release()
    state.device->release()

    resource_library_deinit(&state.command_buffers)
    resource_library_deinit(&state.textures)

    free(state)
}

// ---------------------------------------------------------------------------
// Texture

MTL_texture_init :: proc(texture_descriptor: Texture_Descriptor) -> Texture {
    desc := MTL.TextureDescriptor.alloc()->init()
    defer desc->release()

    desc->setWidth(NS.UInteger(texture_descriptor.dimensions.x))
    desc->setHeight(NS.UInteger(texture_descriptor.dimensions.y))
    desc->setPixelFormat(mtl_pixel_format_interop[texture_descriptor.format])
    desc->setUsage(bit_set_to_another(texture_descriptor.usage, MTL.TextureUsage, mtl_texture_usage_interop))
    desc->setStorageMode(mtl_storage_mode_interop[texture_descriptor.storage_mode])
    desc->setTextureType(mtl_texture_type_interop[texture_descriptor.texture_type])

    texture := state.device->newTextureWithDescriptor(desc)
    if texture == nil {
        log.panic("gpu_MTL.odin: MTL_texture_init: failed to create texture")
    }

    handle := resource_library_add(&state.textures, MTL_Texture_Impl {
        texture      = texture,
    }, {})

    return handle
}

MTL_texture_deinit :: proc(texture: Texture) {
    texture_impl := resource_library_get(&state.textures, texture)
    
    if texture_impl.texture != nil {
        texture_impl.texture->release()
    }

    if texture_impl.drawable != nil {
        texture_impl.drawable->release()
    }

    resource_library_remove(&state.textures, texture)
    texture_impl^ = {}
}

MTL_resize_swapchain :: proc() {
    size := window_size_pixel()

    drawable_size := NS.Size {
        width  = NS.Float(size.x),
        height = NS.Float(size.y),
    }

    state.metal_layer->setDrawableSize(drawable_size)
}

// ---------------------------------------------------------------------------
// Memory

MTL_malloc :: proc(bytes: uint, align: uint, memory: Memory) -> ptr {
    bytes := mem.align_forward_uint(bytes, align)
    
    options := MTL.ResourceOptions{}
    switch memory {
    case .CPU_GPU:
        options = MTL.ResourceStorageModeShared
    case .GPU_Only:
        options = {.StorageModePrivate}
    }

    buffer := state->device->newBufferWithLength(
        length = NS.UInteger(bytes),
        options = options,
    )

    cpu_ptr: rawptr
    if .StorageModePrivate not_in options {
        cpu_ptr = buffer->contentsPointer()
    }
    gpu_ptr := buffer->gpuAddress()

    return {
        cpu = cpu_ptr,
        gpu = rawptr(uintptr(gpu_ptr)),
        _buffer_offset = 0,
        _data = buffer,
    }
}

MTL_temp_malloc :: proc(command_buffer: Command_Buffer, bytes: []u8, index: u32, shader_stage: Shader_Stage) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    switch shader_stage {
    case .Vertex:
        buffer_impl.render_command_encoder->setVertexBytes(bytes, NS.UInteger(index))
    case .Fragment:
        buffer_impl.render_command_encoder->setFragmentBytes(bytes, NS.UInteger(index))
    case .Compute:
        if buffer_impl.compute_command_encoder == nil {
            buffer_impl.compute_command_encoder = buffer_impl.command_buffer->computeCommandEncoder()
        }
        buffer_impl.compute_command_encoder->setBytes(bytes, NS.UInteger(index))
    }
}

MTL_free :: proc(ptr: ptr) {
    buffer := (^MTL.Buffer)(ptr._data)
    buffer->release()
    buffer^ = {}
}

// ---------------------------------------------------------------------------
// 

MTL_texture_size :: proc(texture: Texture) -> [3]i32 {
    texture_impl := resource_library_get(&state.textures, texture)
    return {i32(texture_impl.texture->width()), i32(texture_impl.texture->height()), i32(texture_impl.texture->depth())}
}


MTL_texture_format :: proc(texture: Texture) -> Pixel_Format {
    texture_impl := resource_library_get(&state.textures, texture)
    px_format := texture_impl.texture->pixelFormat()
    return mtl_texture_format_interop_reverse[px_format]
}

MTL_texture_type :: proc(texture: Texture) -> Texture_Type {
    texture_impl := resource_library_get(&state.textures, texture)
    tex_type := texture_impl.texture->textureType()
    return mtl_texture_type_interop_reverse[tex_type]
}

MTL_remake_texture :: proc(texture: Texture, descriptor: Texture_Descriptor) {
    texture_impl := resource_library_get(&state.textures, texture)

    if texture_impl.texture != nil {
        texture_impl.texture->release()
    }

    if texture_impl.drawable != nil {
        texture_impl.drawable->release()
    }

    desc := MTL.TextureDescriptor.alloc()->init()
    defer desc->release()

    desc->setWidth(NS.UInteger(descriptor.dimensions.x))
    desc->setHeight(NS.UInteger(descriptor.dimensions.y))
    desc->setPixelFormat(mtl_pixel_format_interop[descriptor.format])
    desc->setUsage(bit_set_to_another(descriptor.usage, MTL.TextureUsage, mtl_texture_usage_interop))
    desc->setStorageMode(mtl_storage_mode_interop[descriptor.storage_mode])
    desc->setTextureType(mtl_texture_type_interop[descriptor.texture_type])

    texture := state.device->newTextureWithDescriptor(desc)
    if texture == nil {
        log.panic("gpu_MTL.odin: MTL_texture_init: failed to create texture")
    }

    texture_impl.texture      = texture
}

MTL_acquire_next_swapchain :: proc(cmd_buffer: Command_Buffer) -> Texture {
    drawable := state.metal_layer->nextDrawable()
    if drawable == nil {
        panic("MTL_acquire_next_swapchain: no drawable")
    }

    drawable_texture := drawable->texture()

    handle := resource_library_add(&state.textures, MTL_Texture_Impl {
        texture      = drawable_texture,
        drawable     = drawable,
        // format       = .BGRA8Unorm_sRGB,
        // texture_type = .Type2D,
    }, {})
        
    return handle
}

MTL_begin_commands :: proc() -> Command_Buffer {
    pool := NS.AutoreleasePool.alloc()->init()

    buffer_desc := MTL.CommandBufferDescriptor.alloc()->init()
    defer buffer_desc->release()
    buffer_desc->setErrorOptions({.EncoderExecutionStatus})
    
    handle := resource_library_add(&state.command_buffers, MTL_Command_Buffer_Impl {
        command_buffer = state.queue->commandBufferWithDescriptor(buffer_desc),
        pool = pool,
    }, {})

    return handle
}

MTL_cmd_set_depth_stencil_state :: proc(command_buffer: Command_Buffer, depth: Depth_Stencil_State) {
    depth := (^MTL.DepthStencilState)(depth)
    buffer_info := resource_library_get(&state.command_buffers, command_buffer)
    buffer_info.render_command_encoder->setDepthStencilState(depth)
}

_MTL_clear_color :: proc(color: Color) -> MTL.ClearColor {
    return MTL.ClearColor {
        red   = f64(color.x) / 255.0,
        green = f64(color.y) / 255.0,
        blue  = f64(color.b) / 255.0,
        alpha = f64(color.w) / 255.0,
    }
}

MTL_cmd_begin_render_pass :: proc(command_buffer: Command_Buffer, color_attachments: []Color_Attachment, depth_attachment: Depth_Attachment) {

    buffer_info := resource_library_get(&state.command_buffers, command_buffer)

    when ODIN_DEBUG {
        assert(buffer_info.render_command_encoder == nil,
            "cmd_begin_render_pass: a render pass is already active; call cmd_end_render_pass first")
        assert(buffer_info.blit_command_encoder == nil,
            "cmd_begin_render_pass: blit encoder still active; call cmd_barrier(.Transfer, .All) first")
    }

    pass_descriptor := MTL.RenderPassDescriptor.renderPassDescriptor()
       
    for attachment, I in color_attachments {
        color_attachment := pass_descriptor->colorAttachments()->object(NS.UInteger(I))
        texture_impl := resource_library_get(&state.textures, attachment.texture)
        color_attachment->setClearColor(_MTL_clear_color(attachment.clear_color))
        color_attachment->setLoadAction(mtl_load_action_interop[attachment.load_action])
        color_attachment->setStoreAction(mtl_store_action_interop[attachment.store_action])
        color_attachment->setTexture(texture_impl.texture)

        // Optional resolve texture: when set, Metal will perform an automatic
        // multisample resolve from `attachment.texture` into `attachment.resolve_texture`
        // at the end of the render pass.
        if attachment.resolve_texture != Texture_nil {
            when ODIN_DEBUG {
                assert(attachment.store_action == .MultisampleResolve ||
                       attachment.store_action == .StoreAndMultisampleResolve,
                       "cmd_begin_render_pass: resolve_texture set but store_action is not a resolve action")
                assert(attachment.resolve_texture != attachment.texture,
                    "cmd_begin_render_pass: resolve_texture must differ from texture")
                assert(texture_type(attachment.resolve_texture) != .Type2DMultisample &&
                       texture_type(attachment.resolve_texture) != .Type2DMultisampleArray,
                    "cmd_begin_render_pass: resolve_texture must be a single-sample texture")
            }
            resolve_impl := resource_library_get(&state.textures, attachment.resolve_texture)
            color_attachment->setResolveTexture(resolve_impl.texture)
        }
    }

    if depth_attachment.texture != Texture_nil {
        pass_depth := pass_descriptor->depthAttachment()

        pass_depth->setLoadAction(mtl_load_action_interop[depth_attachment.load_action])
        pass_depth->setStoreAction(mtl_store_action_interop[depth_attachment.store_action])
        pass_depth->setClearDepth(depth_attachment.clear_depth)

        texture_impl := resource_library_get(&state.textures, depth_attachment.texture)
        pass_depth->setTexture(texture_impl.texture)

        // Optional depth resolve texture.
        if depth_attachment.resolve_texture != Texture_nil {
            when ODIN_DEBUG {
                assert(depth_attachment.store_action == .MultisampleResolve ||
                       depth_attachment.store_action == .StoreAndMultisampleResolve,
                       "cmd_begin_render_pass: depth resolve_texture set but store_action is not a resolve action")
                assert(depth_attachment.resolve_texture != depth_attachment.texture,
                    "cmd_begin_render_pass: depth resolve_texture must differ from depth texture")
                assert(texture_type(depth_attachment.resolve_texture) != .Type2DMultisample &&
                       texture_type(depth_attachment.resolve_texture) != .Type2DMultisampleArray,
                    "cmd_begin_render_pass: depth resolve_texture must be a single-sample texture")
            }
            resolve_impl := resource_library_get(&state.textures, depth_attachment.resolve_texture)
            pass_depth->setResolveTexture(resolve_impl.texture)
        }
    }

    buffer_info.pass_descriptor = pass_descriptor
    render_encoder := buffer_info.command_buffer->renderCommandEncoderWithDescriptor(pass_descriptor)
    
    buffer_info.render_command_encoder = render_encoder
}

MTL_cmd_set_cull_mode :: proc(command_buffer: Command_Buffer, cull_mode: Cull_Mode) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    buffer_impl.render_command_encoder->setCullMode(mtl_cull_mode_interop[cull_mode])
}

MTL_cmd_set_front_face_winding :: proc(command_buffer: Command_Buffer, front_face_winwing: Winding) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    buffer_impl.render_command_encoder->setFrontFacingWinding(mtl_front_face_winding_interop[front_face_winwing])
}

MTL_depth_stencil_state_init :: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State {
    ds_desc := MTL.DepthStencilDescriptor.alloc()->init()
    defer ds_desc->release()
    ds_desc->setDepthCompareFunction(mtl_compare_function_interop[desc.compare_func])
    ds_desc->setDepthWriteEnabled(desc.depth_write)
    
    depth_state := state.device->newDepthStencilState(ds_desc)
    if depth_state == nil {
        log.panic("mtl_init: failed to create depth stencil state")
    }

    return Depth_Stencil_State(depth_state)
}

MTL_depth_stencil_state_deinit :: proc(depth: Depth_Stencil_State) {
    depth := (^MTL.DepthStencilState)(depth)
    depth->release()
    depth^ = {}
}

MTL_cmd_end_render_pass :: proc(command_buffer: Command_Buffer) {
    buffer_info := resource_library_get(&state.command_buffers, command_buffer)

    when ODIN_DEBUG {
        assert(buffer_info.render_command_encoder != nil,
            "cmd_end_render_pass: no render pass is active")
    }

    if buffer_info.render_command_encoder != nil {
        buffer_info.render_command_encoder->endEncoding()
        buffer_info.render_command_encoder = nil
    }
}

MTL_cmd_present :: proc(command_buffer: Command_Buffer, texture: Texture) {
    command_buffer := resource_library_get(&state.command_buffers, command_buffer)
    command_buffer.presentable = texture
}

Frame_Pass :: struct {
    signal: Signal,
    value: u64,
}

MTL_end_commands :: proc(command_buffer: Command_Buffer, frame_pass: Frame_Pass) {
    command_buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    defer {
        command_buffer_impl.pool->drain()
        command_buffer_impl^ = {}
    }

    MTL_cmd_barrier(command_buffer, .All, .All)

    if command_buffer_impl.presentable != {} {
        texture_impl := resource_library_get(&state.textures, command_buffer_impl.presentable)
        command_buffer_impl.command_buffer->presentDrawable(texture_impl.drawable)
        // Drop the swapchain texture from the resource library so the handle slot
        // can be reused next frame. The drawable itself is autoreleased when the
        // command buffer is committed below.
        resource_library_remove(&state.textures, command_buffer_impl.presentable)
    }

    if frame_pass.signal != nil {
        event := (^MTL.SharedEvent)(frame_pass.signal)
        command_buffer_impl.command_buffer->encodeSignalEvent(event, frame_pass.value)
    }
    command_buffer_impl.command_buffer->commit()

    if command_buffer_impl.signal_fence != nil {
        command_buffer_impl.signal_fence->release()
        command_buffer_impl.signal_fence = nil
    }

    resource_library_remove(&state.command_buffers, command_buffer)
}

MTL_signal_init :: proc(value: u64) -> Signal {
    event := state.device->newSharedEvent()
    event->setSignaledValue(value)
    return Signal(event)
}

MTL_signal_deinit :: proc(signal: Signal) {
    signal := (^MTL.SharedEvent)(signal)
    signal->release()
}

MTL_signal_wait_for :: proc(signal: Signal, value: u64, timeout_milliseconds: time.Duration) -> bool {    
    signal := (^MTL.SharedEvent)(signal)
    if signal->signaledValue() >= value {
        return true
    }
    
    timestamp := time.now()
    has_deadline := timeout_milliseconds != time.MAX_DURATION

    for {
        if signal->signaledValue() >= value {
            return true
        }

        if has_deadline && time.diff(timestamp, time.now()) >= timeout_milliseconds {
            return false
        }

        time.sleep(1 * time.Millisecond)
    }
}

MTL_cmd_mem_copy :: proc(command_buffer: Command_Buffer, dst, src: ptr, size: u64) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    if buffer_impl.blit_command_encoder == nil {
        buffer_impl.blit_command_encoder = buffer_impl.command_buffer->blitCommandEncoder()
    }

    src_buffer := (^MTL.Buffer)(src._data)
    dst_buffer := (^MTL.Buffer)(dst._data)

    buffer_impl.blit_command_encoder->copyFromBuffer(
        src_buffer, NS.UInteger(src._buffer_offset),
        dst_buffer, NS.UInteger(dst._buffer_offset),
        NS.UInteger(size),
    )
}

MTL_cmd_blit_texture :: proc(command_buffer: Command_Buffer, src, dst: Texture) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    when ODIN_DEBUG {
        assert(buffer_impl.render_command_encoder == nil,
            "cmd_blit_texture: render encoder still active; call cmd_end_render_pass (and cmd_barrier(.Raster_Color_Out, .Transfer) if needed) first")
        assert(src != dst, "cmd_blit_texture: src and dst must be different textures")
    }

    if buffer_impl.blit_command_encoder == nil {
        buffer_impl.blit_command_encoder = buffer_impl.command_buffer->blitCommandEncoder()
    }

    src_impl := resource_library_get(&state.textures, src)
    dst_impl := resource_library_get(&state.textures, dst)

    when ODIN_DEBUG {
        assert(src_impl.texture != nil, "cmd_blit_texture: src texture is nil")
        assert(dst_impl.texture != nil, "cmd_blit_texture: dst texture is nil")
    }

    src_size := MTL.Size {
        width  = NS.Integer(src_impl.texture->width()),
        height = NS.Integer(src_impl.texture->height()),
        depth  = NS.Integer(1),
    }

    buffer_impl.blit_command_encoder->copyFromTextureWithDestinationOrigin(
        src_impl.texture,
        0, 0,
        MTL.Origin{0, 0, 0},
        src_size,
        dst_impl.texture,
        0, 0,
        MTL.Origin{0, 0, 0},
    )
}

MTL_cmd_barrier :: proc(command_buffer: Command_Buffer, before: Stage, after: Stage) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    switch before {
    case .Transfer:
        if buffer_impl.blit_command_encoder != nil {
            buffer_impl.blit_command_encoder->endEncoding()
            buffer_impl.blit_command_encoder = nil
        }

    case .Vertex_Shader, .Fragment_Shader, .Raster_Color_Out:
        if buffer_impl.render_command_encoder != nil {
            buffer_impl.render_command_encoder->endEncoding()
            buffer_impl.render_command_encoder = nil
        }

    case .All:
        if buffer_impl.blit_command_encoder != nil {
            buffer_impl.blit_command_encoder->endEncoding()
            buffer_impl.blit_command_encoder = nil
        }
        if buffer_impl.render_command_encoder != nil {
            buffer_impl.render_command_encoder->endEncoding()
            buffer_impl.render_command_encoder = nil
        }

        if buffer_impl.compute_command_encoder != nil {
            buffer_impl.compute_command_encoder->endEncoding()
            buffer_impl.compute_command_encoder = nil
        }

    case .Compute:
        if buffer_impl.compute_command_encoder != nil {
            buffer_impl.compute_command_encoder->endEncoding()
            buffer_impl.compute_command_encoder = nil
        }
    case .Build_BVH:
        // No-op on Metal.
    }

    _ = after
}

// ---------------------------------------------------------------------------
// Shaders

MTL_kernel_init :: proc(code: []u8, function_name: string) -> Shader {
    library: ^MTL.Library
    err: ^NS.Error

    code_ns := NS.String.alloc()->initWithBytesNoCopy(raw_data(code), NS.UInteger(len(code)), .UTF8, false)
    defer code_ns->release()

    compile_options := MTL.CompileOptions.alloc()->init()
    defer compile_options->release()
    compile_options->setLanguageVersion(.Version3_0)

    library, err = state.device->newLibraryWithSource(code_ns, compile_options) // Cache the library later
    if err != nil {
        log.panicf("Failed to create shader library: %v", err->localizedDescription()->odinString())
    }
    defer library->release()

    // If we had library already also check if we already have function with this name registered
    entry_ns_str := NS.String.alloc()->initWithOdinString(function_name)
    defer entry_ns_str->release()
    
    // functions are released by user manually when calling shader_deinit
    function := library->newFunctionWithName(entry_ns_str)
    defer function->release()

    kernel, k_err := state.device->newComputePipelineStateWithFunction(function)
    if k_err != nil {
        log.panicf("Failed to create pipeline state: %v", k_err->localizedDescription()->odinString())
    }

    return Shader(kernel)
}

MTL_cmd_dispatch :: proc(command_buffer: Command_Buffer, threads_per_grid, threads_per_thread_group: [3]int) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    size_grid := MTL.Size{NS.Integer(threads_per_grid.x), NS.Integer(threads_per_grid.y), NS.Integer(threads_per_grid.z)}
	size_group := MTL.Size{NS.Integer(threads_per_thread_group.x), NS.Integer(threads_per_thread_group.y), NS.Integer(threads_per_thread_group.z)}
    buffer_impl.compute_command_encoder->dispatchThreads(size_grid, size_group)
}

MTL_shader_init :: proc(code: []u8, entry_point: string, stage: Graphics_Stage) -> Shader {
    library: ^MTL.Library
    err: ^NS.Error

    code_ns := NS.String.alloc()->initWithBytesNoCopy(raw_data(code), NS.UInteger(len(code)), .UTF8, false)
    defer code_ns->release()

    compile_options := MTL.CompileOptions.alloc()->init()
    defer compile_options->release()
    compile_options->setLanguageVersion(.Version3_0)

    library, err = state.device->newLibraryWithSource(code_ns, compile_options) // Cache the library later
    if err != nil {
        log.panicf("Failed to create shader library: %v", err->localizedDescription()->odinString())
    }
    defer library->release()

    // If we had library already also check if we already have function with this name registered
    entry_ns_str := NS.String.alloc()->initWithOdinString(entry_point)
    defer entry_ns_str->release()
    
    // functions are released by user manually when calling shader_deinit
    function := library->newFunctionWithName(entry_ns_str)

    return Shader(function)
}

MTL_shader_deinit :: proc(shader: Shader) {
    shader := (^NS.Object)(shader)
    shader->release()
    shader^ = {}
}

MTL_pipeline_init :: proc(vertex_shader, fragment_shader: Shader, formats: []Pixel_Format, depth_format: Pixel_Format) -> Pipeline {
    desc := MTL.RenderPipelineDescriptor.alloc()->init()
	defer desc->release()

    desc->setVertexFunction((^MTL.Function)(vertex_shader))
    desc->setFragmentFunction((^MTL.Function)(fragment_shader))
    desc->setDepthAttachmentPixelFormat(mtl_pixel_format_interop[depth_format])
    
    for format, I in formats {
        desc->colorAttachments()->object(NS.UInteger(I))->setPixelFormat(mtl_pixel_format_interop[format])
    }

    pso, err := state.device->newRenderPipelineStateWithDescriptor(desc)
    if err != nil {
        log.panicf("Failed to create pipeline state: %v", err->localizedDescription()->odinString())
    }

    return Pipeline(pso)
}

MTL_pipeline_deinit :: proc(pipeline: Pipeline) {
    pipeline := (^MTL.RenderPipelineState)(pipeline)
    pipeline->release()
    pipeline^ = {}
}

MTL_cmd_set_graphics_pipeline :: proc(command_buffer: Command_Buffer, pipeline: Pipeline) {
    buffer_info := resource_library_get(&state.command_buffers, command_buffer)

    // assert render command encoder is active, not blit or compute
    // Should be case if used right after begin render pass
    
    buffer_info.render_command_encoder->setRenderPipelineState((^MTL.RenderPipelineState)(pipeline))
}

MTL_cmd_set_compute_pipeline :: proc(command_buffer: Command_Buffer, kernel: Shader) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    if buffer_impl.compute_command_encoder == nil {
        buffer_impl.compute_command_encoder = buffer_impl.command_buffer->computeCommandEncoder()
    }

    buffer_impl.compute_command_encoder->setComputePipelineState((^MTL.ComputePipelineState)(kernel))
}

MTL_use_resources :: proc(command_buffer: Command_Buffer, resource_list: []Shader_Resource) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    // temp use of resource list before heap implementation
    for res in resource_list {
        res_buffer := (^MTL.Buffer)(res.ptr._data)
        usage_flags := bit_set_to_another(res.usage, MTL.ResourceUsage, mtl_resource_usage_interop)
        stages := bit_set_to_another(res.stage, MTL.RenderStages, mtl_render_stage_interop)
        buffer_impl.render_command_encoder->useResourceWithStages(
            res_buffer, usage_flags, stages,
        )
    }
}

MTL_cmd_draw_primitives :: proc(command_buffer: Command_Buffer, primitive: Primitive_Type, vertex_count: u32, vertex_start: u32 = 0) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    buffer_impl.render_command_encoder->drawPrimitives(mtl_primitive_type_interop[primitive], NS.UInteger(vertex_start), NS.UInteger(vertex_count))
}

MTL_cmd_set_buffer :: proc(command_buffer: Command_Buffer, buffer: ptr, index: u32, stage: Shader_Stage, offset: uint = 0) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    switch stage {
    case .Vertex:
        buffer_impl.render_command_encoder->setVertexBuffer((^MTL.Buffer)(buffer._data), NS.UInteger(offset + buffer._buffer_offset), NS.UInteger(index))
    case .Fragment:
        buffer_impl.render_command_encoder->setFragmentBuffer((^MTL.Buffer)(buffer._data), NS.UInteger(offset + buffer._buffer_offset), NS.UInteger(index))
    case .Compute:
        buffer_impl.compute_command_encoder->setBuffer((^MTL.Buffer)(buffer._data), NS.UInteger(offset + buffer._buffer_offset), NS.UInteger(index))
    }
}

MTL_cmd_set_buffers :: proc(command_buffer: Command_Buffer, buffers: []ptr, offsets: []uint, range: Range, stage: Shader_Stage) {
    assert(len(buffers) > 0)
    assert(len(buffers) == int(range.length))
    assert(len(offsets) == int(range.length))
    assert(len(buffers) == len(offsets))

    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    mtl_buffers := make([]^MTL.Buffer, len=len(buffers), allocator=context.temp_allocator)
    buffer_offsets := make([]uint, len=len(buffers), allocator=context.temp_allocator)
    for b, I in buffers {
        mtl_buffers[I] = (^MTL.Buffer)(b._data)
        buffer_offsets[I] = b._buffer_offset + offsets[I]
    }

    switch stage {
    case .Vertex:
        buffer_impl.render_command_encoder->setVertexBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
    case .Fragment:
        buffer_impl.render_command_encoder->setFragmentBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
    case .Compute:
        buffer_impl.compute_command_encoder->setBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
    }
}

MTL_cmd_draw_indiced_primitives :: proc(command_buffer: Command_Buffer, primitive: Primitive_Type, index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32) {
    if instance_count == 0 {
        return
    }

    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    index_buffer := (^MTL.Buffer)(index_buffer._data)
    
    buffer_impl.render_command_encoder->drawIndexPrimitivesWithBaseVertex(
        mtl_primitive_type_interop[primitive], NS.UInteger(index_count), MTL.IndexType.UInt32,
        index_buffer, NS.UInteger(index_offset), NS.UInteger(instance_count), 0, 0
    )
}

MTL_cmd_set_scissor_rect :: proc(command_buffer: Command_Buffer, x, y, width, height: u32) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    when ODIN_DEBUG {
        assert(buffer_impl.render_command_encoder != nil,
            "cmd_set_scissor_rect: no render pass is active")
        assert(width > 0 && height > 0,
            "cmd_set_scissor_rect: width and height must be > 0 (zero-area scissor renders nothing)")
    }

    buffer_impl.render_command_encoder->setScissorRect(
        MTL.ScissorRect {
            x      = NS.Integer(x),
            y      = NS.Integer(y),
            width  = NS.Integer(width),
            height = NS.Integer(height),
        },
    )
}

// Prefer passing by pointer instead of using argument buffers
@(deprecated="Use pointer approach")
__MTL_argument_buffer_init :: proc(shader: Shader, index: u32, buffers: []ptr, offsets: []uint, range: Range) -> ptr {
    shader_fn := (^MTL.Function)(shader)
    argument_encoder := shader_fn->newArgumentEncoder(NS.UInteger(index))
    defer argument_encoder->release()

    ptr := MTL_malloc(uint(argument_encoder->encodedLength()), 16, .CPU_GPU)
    argument_encoder->setArgumentBufferWithOffset((^MTL.Buffer)(ptr._data), 0)

    mtl_buffers := make([]^MTL.Buffer, len=len(buffers))
    buffer_offsets := make([]uint, len=len(buffers))
    for b, I in buffers {
        mtl_buffers[I] = (^MTL.Buffer)(b._data)
        buffer_offsets[I] = b._buffer_offset + offsets[I]
    }

    argument_encoder->setBuffers(mtl_buffers, transmute([]NS.UInteger)buffer_offsets, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})

    return ptr
}

MTL_mem_copy_to_texture :: proc(texture: Texture, origin, size: [3]int, level: u32, data: rawptr, bytes_per_row: u32) {
    
    texture_impl := resource_library_get(&state.textures, texture)

    region := MTL.Region {
        origin = MTL.Origin {NS.Integer(origin.x), NS.Integer(origin.y), NS.Integer(origin.z)},
        size = MTL.Size {
            width = NS.Integer(size.x),
            height = NS.Integer(size.y),
            depth = NS.Integer(size.z),
        },
    }

    texture_impl.texture->replaceRegion(region, NS.UInteger(level), data, NS.UInteger(bytes_per_row))
}

texture_index_pair :: struct {
    texture: Texture,
    index: u32,
}

Range :: struct {
    location: uint,
    length: uint,
}

MTL_cmd_set_textures :: proc(command_buffer: Command_Buffer, textures: []Texture, range: Range, stage: Shader_Stage) {
    assert(len(textures) > 0)
    assert(len(textures) == int(range.length))

    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    mtl_textures := make([]^MTL.Texture, len=len(textures), allocator=context.temp_allocator)
    for tex, I in textures {
        texture_impl := resource_library_get(&state.textures, tex)
        mtl_textures[I] = texture_impl.texture
    }

    switch stage {
    case .Vertex:
        buffer_impl.render_command_encoder->setVertexTextures(mtl_textures, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
    case .Fragment:
        buffer_impl.render_command_encoder->setFragmentTextures(mtl_textures, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
    case .Compute:
        buffer_impl.compute_command_encoder->setTextures(mtl_textures, NS.Range{NS.UInteger(range.location), NS.UInteger(range.length)})
    }
}

MTL_cmd_set_texture :: proc(command_buffer: Command_Buffer, pairs: []texture_index_pair, stage: Shader_Stage) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    for pair in pairs {
        texture_impl := resource_library_get(&state.textures, pair.texture)

        switch stage {
        case .Vertex:
            buffer_impl.render_command_encoder->setVertexTexture(texture_impl.texture, NS.UInteger(pair.index))
        case .Fragment:
            buffer_impl.render_command_encoder->setFragmentTexture(texture_impl.texture, NS.UInteger(pair.index))

        case .Compute:
            buffer_impl.compute_command_encoder->setTexture(texture_impl.texture, NS.UInteger(pair.index))
        }
    }
}



MTL_max_total_threads_per_threadgroup :: proc(kernel: Shader) -> int {
    res := (^MTL.ComputePipelineState)(kernel)->maxTotalThreadsPerThreadgroup()
    return int(res)
}


// ---------------------------------------------------------------------------
// Interop

@(rodata)
mtl_texture_type_interop := [Texture_Type]MTL.TextureType {
    .Type1D = .Type1D,
    .Type1DArray = .Type1DArray,
    .Type2D = .Type2D,
    .Type2DArray = .Type2DArray,
    .Type2DMultisample = .Type2DMultisample,
    .TypeCube = .TypeCube,
    .TypeCubeArray = .TypeCubeArray,
    .Type3D = .Type3D,
    .Type2DMultisampleArray = .Type2DMultisampleArray,
    .TypeTextureBuffer = .TypeTextureBuffer,
}


@(rodata)
mtl_compare_function_interop := [Compare_Function]MTL.CompareFunction {
    .Never        = .Never,
    .Less         = .Less,
    .Equal        = .Equal,
    .LessEqual    = .LessEqual,
    .Greater      = .Greater,
    .NotEqual     = .NotEqual,
    .GreaterEqual = .GreaterEqual,
    .Always       = .Always,
}

@(rodata)
mtl_load_action_interop := [Load_Action]MTL.LoadAction {
    .Dont_Care = .DontCare,
    .Clear     = .Clear,
    .Load      = .Load,
}

@(rodata)
mtl_store_action_interop := [Store_Action]MTL.StoreAction {
    .Dont_Care                  = .DontCare,
    .Store                      = .Store,
    .MultisampleResolve         = .MultisampleResolve,
    .StoreAndMultisampleResolve = .StoreAndMultisampleResolve,
}

@(rodata)
mtl_pixel_format_interop := [Pixel_Format]MTL.PixelFormat {
    .Invalid = MTL.PixelFormat.Invalid,
    .RGBA8Unorm = MTL.PixelFormat.RGBA8Unorm,
    .BGRA8Unorm_sRGB = MTL.PixelFormat.BGRA8Unorm_sRGB,
    .Depth32Float = MTL.PixelFormat.Depth32Float,
}

@(rodata)
mtl_sampler_addres_mode_interop := [Sampler_Address_Mode]MTL.SamplerAddressMode {
    .ClampToEdge        = .ClampToEdge,
    .MirrorClampToEdge  = .MirrorClampToEdge,
    .Repeat             = .Repeat,
    .MirrorRepeat       = .MirrorRepeat,
    .ClampToZero        = .ClampToZero,
    .ClampToBorderColor = .ClampToBorderColor,
}

@(rodata)
mtl_storage_mode_interop := [Storage_Mode]MTL.StorageMode {
    .Shared     = .Shared,
    .Managed    = .Managed,
    .Private    = .Private,
    .Memoryless = .Memoryless,
}

@(rodata)
mtl_texture_usage_interop := [Texture_Usage_Flags]MTL.TextureUsageFlag {
    .ShaderRead = .ShaderRead,
    .ShaderWrite = .ShaderWrite,
    .RenderTarget = .RenderTarget,
}

@(rodata)
mtl_min_mag_filter_interop := [Sampler_Min_Mag_Filter]MTL.SamplerMinMagFilter {
    .Nearest = .Nearest,
    .Linear  = .Linear,
}

@(rodata)
mtl_sample_mip_filter_interop := [Sampler_Mip_Filter]MTL.SamplerMipFilter {
    .NotMipmapped = .NotMipmapped,
    .Nearest      = .Nearest,
    .Linear       = .Linear,
}

@(rodata)
mtl_cull_mode_interop := [Cull_Mode]MTL.CullMode {
    .None  = .None,
    .Front = .Front,
    .Back  = .Back,
}

@(rodata)
mtl_front_face_winding_interop := [Winding]MTL.Winding {
    .Clockwise        = .Clockwise,
    .CounterClockwise = .CounterClockwise,
}

@(rodata)
mtl_primitive_type_interop := [Primitive_Type]MTL.PrimitiveType {
    .Point         = .Point,
    .Line          = .Line,
    .Line_Strip    = .LineStrip,
    .Triangle      = .Triangle,
    .Triangle_Strip = .TriangleStrip,
}

@(rodata)
mtl_resource_usage_interop := [Resource_Usage_Flag]MTL.ResourceUsageFlag {
    .Read   = .Read,
    .Write  = .Write,
    .Sample = .Sample,
}

@(rodata)
mtl_render_stage_interop := [Render_Stage]MTL.RenderStage {
    .Vertex   = .Vertex,
    .Fragment = .Fragment,
    .Tile     = .Tile,
    .Object   = .Object,
    .Mesh     = .Mesh,
}

// Add more to this if we happen to use something we don't have binded yet
@(rodata)
mtl_texture_format_interop_reverse := #partial #sparse [MTL.PixelFormat]Pixel_Format {
    .Invalid         = .Invalid,
    .BGRA8Unorm_sRGB = .BGRA8Unorm_sRGB,
    .RGBA8Unorm      = .RGBA8Unorm,
    .Depth32Float    = .Depth32Float,
}

@(rodata)
mtl_texture_type_interop_reverse := #partial #sparse [MTL.TextureType]Texture_Type {
    .Type1D                 = .Type1D,
    .Type1DArray            = .Type1DArray,
    .Type2D                 = .Type2D,
    .Type2DArray            = .Type2DArray,
    .Type2DMultisample      = .Type2DMultisample,
    .TypeCube               = .TypeCube,
    .TypeCubeArray          = .TypeCubeArray,
    .Type3D                 = .Type3D,
    .Type2DMultisampleArray = .Type2DMultisampleArray,
    .TypeTextureBuffer      = .TypeTextureBuffer,
}