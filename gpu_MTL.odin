package nuppu

import "core:log"
import MTL "vendor:darwin/Metal"
import MTK "vendor:darwin/MetalKit"
import CA "vendor:darwin/QuartzCore"
import NS "core:sys/darwin/Foundation"
import "core:os"
import "core:time"
import "core:fmt"
import "core:mem"
import "core:container/handle_map"
import vmem "core:mem/virtual"
import "base:intrinsics"
import "core:strings"
import "core:slice"


MTL_RENDERER_API :: Renderer_API {
    init = MTL_init,
    deinit = MTL_deinit,
    resize_swapchain = MTL_resize_swapchain,

    free = MTL_free,
    malloc = MTL_malloc,
    temp_malloc = MTL_temp_malloc,
    gpu_address = MTL_gpu_address,

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

    shader_init = MTL_shader_init,
    shader_deinit = MTL_shader_deinit,

    pipeline_init = MTL_pipeline_init,
    pipeline_deinit = MTL_pipeline_deinit,
    cmd_set_pipeline = MTL_cmd_set_pipeline,

    cmd_draw_indiced_primitives = MTL_cmd_draw_indiced_primitives,
    cmd_draw_primitives = MTL_cmd_draw_primitives,
    cmd_use_resources = MTL_use_resources,

    depth_stencil_state_init = MTL_depth_stencil_state_init,
    depth_stencil_state_deinit = MTL_depth_stencil_state_deinit,

    sampler_init = MTL_sampler_init,
    sampler_deinit = MTL_sampler_deinit,

    texture_init = MTL_texture_init,
    texture_deinit = MTL_texture_deinit,
}

Sampler_Min_Mag_Filter :: enum u64 {
	Nearest = 0,
	Linear  = 1,
}

@(rodata)
mtl_filter := [Sampler_Min_Mag_Filter]MTL.SamplerMinMagFilter {
    .Nearest = .Nearest,
    .Linear  = .Linear,
}

Sampler_Mip_Filter :: enum u64 {
	NotMipmapped = 0,
	Nearest      = 1,
	Linear       = 2,
}

@(rodata)
mtl_sample_mip_filter := [Sampler_Mip_Filter]MTL.SamplerMipFilter {
    .NotMipmapped = .NotMipmapped,
    .Nearest      = .Nearest,
    .Linear       = .Linear,
}

Sampler_Address_Mode :: enum u64 {
	ClampToEdge        = 0,
	MirrorClampToEdge  = 1,
	Repeat             = 2,
	MirrorRepeat       = 3,
	ClampToZero        = 4,
	ClampToBorderColor = 5,
}

mtl_sampler_addres_mode := [Sampler_Address_Mode]MTL.SamplerAddressMode {
    .ClampToEdge        = .ClampToEdge,
    .MirrorClampToEdge  = .MirrorClampToEdge,
    .Repeat             = .Repeat,
    .MirrorRepeat       = .MirrorRepeat,
    .ClampToZero        = .ClampToZero,
    .ClampToBorderColor = .ClampToBorderColor,
}

MTL_sampler_init :: proc(desc: Sampler_Descriptor) -> Sampler {
    mtl_desc := MTL.SamplerDescriptor.alloc()->init()

    mtl_desc->setMinFilter(mtl_filter[desc.min_filter])
    mtl_desc->setMagFilter(mtl_filter[desc.mag_filter])
    mtl_desc->setMipFilter(mtl_sample_mip_filter[desc.mip_filter])
    mtl_desc->setRAddressMode(mtl_sampler_addres_mode[desc.address_mode[0]])
    mtl_desc->setSAddressMode(mtl_sampler_addres_mode[desc.address_mode[1]])
    mtl_desc->setTAddressMode(mtl_sampler_addres_mode[desc.address_mode[2]])

    sampler := state.device->newSamplerState(mtl_desc)
    if sampler == nil {
        log.panic("gpu_MTL.odin: MTL_sampler_init: failed to create sampler")
    }

    return Sampler(sampler)
}

MTL_sampler_deinit :: proc(sampler: Sampler) {
    sampler := (^MTL.SamplerState)(sampler)
    sampler->release()
    sampler^ = {}
}



MTL_texture_init :: proc(texture_descriptor: Texture_Descriptor) -> Texture {
    desc := MTL.TextureDescriptor.alloc()->init()
    defer desc->release()
    desc->setWidth(NS.UInteger(texture_descriptor.dimensions.x))
    desc->setHeight(NS.UInteger(texture_descriptor.dimensions.y))
    desc->setPixelFormat(mtl_pixel_format[texture_descriptor.format])
    
    texture := state.device->newTextureWithDescriptor(desc)
    if texture == nil {
        log.panic("gpu_MTL.odin: MTL_texture_init: failed to create texture")
    }

    handle := resource_library_add(&state.textures, MTL_Texture_Impl {
        texture = texture,
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

MTL_State :: struct {
    device: ^MTL.Device,
    queue: ^MTL.CommandQueue,
    metal_layer: ^CA.MetalLayer,

    command_buffers: Resource_Library(15, MTL_Command_Buffer_Impl, Command_Buffer),
    textures: Resource_Library(1 << 16, MTL_Texture_Impl, Texture)
}

@(private="file")
state: ^MTL_State
MTL_init :: proc() -> Renderer_API_State {
    state = new(MTL_State)
    
    native_window := cast(^NS.Window)(native_window())
    scale  := pixel_scale()

    state.device = MTL.CreateSystemDefaultDevice()

    metal_layer := CA.MetalLayer.layer()
    
    metal_layer->setDevice(state.device)
    metal_layer->setPixelFormat(.BGRA8Unorm_sRGB)
    metal_layer->setFramebufferOnly(true)
    metal_layer->setFrame(native_window->frame())
    metal_layer->setContentsScale(NS.Float(scale.x))
    state.metal_layer = metal_layer

    native_window->contentView()->setLayer(metal_layer)
    native_window->setOpaque(true)
    native_window->setBackgroundColor(nil)
    
    state.queue = state.device->newCommandQueue()

    resource_library_init(&state.command_buffers)
    resource_library_init(&state.textures)

    return Renderer_API_State(state)
}

MTL_deinit :: proc() {
    state.metal_layer->release()
    state.queue->release()
    state.device->release()
    free(state)
}

MTL_resize_swapchain :: proc() {
    size := window_size_pixel()

    drawable_size := NS.Size {
        width  = NS.Float(size.x),
        height = NS.Float(size.y),
    }

    state.metal_layer->setDrawableSize(drawable_size)
}


MTL_malloc :: proc(bytes: int, align: int, memory: Memory) -> ptr {
    bytes := mem.align_forward_int(bytes, align)
    
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
        _data = {buffer, nil},
    }
}

MTL_malloc_T :: proc($T: typeid, count: int, memory: Memory) -> ptr_T(T) {
    bytes := count * size_of(T)
    ptr := MTL_malloc(bytes, align_of(T), memory)
    return transmute(ptr_T(T))ptr
}

MTL_gpu_address :: proc(ptr: ^ptr) {
    gpu := (^MTL.Buffer)(ptr._data[0])->gpuAddress()
    ptr.gpu = rawptr(uintptr(gpu)) 
}

MTL_free :: proc(ptr: ptr) {
    (^MTL.Buffer)(ptr._data[0])->release()
}

MTL_Texture_Impl :: struct {
    texture: ^MTL.Texture,
    drawable: ^CA.MetalDrawable,
}

MTL_acquire_next_swapchain :: proc(cmd_buffer: Command_Buffer) -> Texture {
    drawable := state.metal_layer->nextDrawable()
    if drawable == nil {
        panic("MTL_acquire_next_swapchain: no drawable")
    }

    drawable_texture := drawable->texture()

    handle := resource_library_add(&state.textures, MTL_Texture_Impl {
        texture = drawable_texture,
        drawable = drawable,
    }, {})
        
    return handle
}

MTL_Command_Buffer_Impl :: struct {
    pool: ^NS.AutoreleasePool,
    command_buffer: ^MTL.CommandBuffer,
    pass_descriptor: ^MTL.RenderPassDescriptor,
    
    render_command_encoder: ^MTL.RenderCommandEncoder,
    blit_command_encoder: ^MTL.BlitCommandEncoder,

    depth_format: Pixel_Format,
    signal_fence: ^MTL.Fence,
    presentable: Texture,
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

// ---------------------------------------------------------------------------
// MTL interop

@(rodata)
load_action_interop := [Load_Action]MTL.LoadAction {
    .Dont_Care = .DontCare,
    .Clear     = .Clear,
    .Load      = .Load,
}

@(rodata)
store_action_interop := [Store_Action]MTL.StoreAction {
    .Dont_Care = .DontCare,
    .Store     = .Store,
}

Color_Attachment :: struct {
    load_action: Load_Action,
    store_action: Store_Action,
    texture: Texture,
}

MTL_cmd_set_depth_stencil_state :: proc(command_buffer: Command_Buffer, depth: Depth_Stencil_State) {
    depth := (^MTL.DepthStencilState)(depth)
    buffer_info := resource_library_get(&state.command_buffers, command_buffer)
    buffer_info.render_command_encoder->setDepthStencilState(depth)
}

MTL_cmd_begin_render_pass :: proc(command_buffer: Command_Buffer, color_attachments: []Color_Attachment) {

    buffer_info := resource_library_get(&state.command_buffers, command_buffer)

    pass_descriptor := MTL.RenderPassDescriptor.renderPassDescriptor()
       
    for attachment, I in color_attachments {
        color_attachment := pass_descriptor->colorAttachments()->object(NS.UInteger(I))
        texture_impl := resource_library_get(&state.textures, attachment.texture)
        color_attachment->setClearColor(MTL.ClearColor{0.25, 0.5, 1.0, 1.0}) // *
        color_attachment->setLoadAction(load_action_interop[attachment.load_action])
        color_attachment->setStoreAction(store_action_interop[attachment.store_action])
        color_attachment->setTexture(texture_impl.texture)
    }

    // if depth != nil {
    //     depth_desc := pass_descriptor->depthAttachment()
    //     depth_desc->setLoadAction(.DontCare)
    //     depth_desc->setStoreAction(.DontCare)
    //     depth_desc->setClearDepth(1.0)
    //     // depth_desc->setTexture(texture)
    //     command_buffer.depth_format = .Depth32Float // *
    // } else {
    //     command_buffer.depth_format = .Invalid

    // }

    buffer_info.pass_descriptor = pass_descriptor
    render_encoder := buffer_info.command_buffer->renderCommandEncoderWithDescriptor(pass_descriptor)
    
    render_encoder->setFrontFacingWinding(.CounterClockwise) // *
    render_encoder->setCullMode(.None) // *
    
    buffer_info.render_command_encoder = render_encoder
}

@(rodata)
compare_function_to_mtl := [Compare_Function]MTL.CompareFunction {
    .Never        = .Never,
    .Less         = .Less,
    .Equal        = .Equal,
    .LessEqual    = .LessEqual,
    .Greater      = .Greater,
    .NotEqual     = .NotEqual,
    .GreaterEqual = .GreaterEqual,
    .Always       = .Always,
}

MTL_depth_stencil_state_init :: proc(desc: Depth_Stencil_State_Descriptor) -> Depth_Stencil_State {
    ds_desc := MTL.DepthStencilDescriptor.alloc()->init()
    defer ds_desc->release()
    ds_desc->setDepthCompareFunction(compare_function_to_mtl[desc.compare_func])
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
    buffer_info.render_command_encoder->endEncoding()
    buffer_info.render_command_encoder = nil
}

MTL_cmd_present :: proc(command_buffer: Command_Buffer, texture: Texture) {
    command_buffer := resource_library_get(&state.command_buffers, command_buffer)
    command_buffer.presentable = texture
}

Frame_Pass :: struct {
    signal: Signal,
    value: u64,
}

commit_blit :: proc(command_buffer: Command_Buffer) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    if buffer_impl.blit_command_encoder != nil {
        buffer_impl.blit_command_encoder->endEncoding()
        buffer_impl.blit_command_encoder = nil
    }
}

MTL_end_commands :: proc(command_buffer: Command_Buffer, frame_pass: Frame_Pass) {
    command_buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    defer {
        command_buffer_impl.pool->drain()
        command_buffer_impl^ = {}
    } 

    if command_buffer_impl.blit_command_encoder != nil {
        command_buffer_impl.blit_command_encoder->endEncoding()
        command_buffer_impl.blit_command_encoder = nil
    }
    else if command_buffer_impl.render_command_encoder != nil {
        command_buffer_impl.render_command_encoder->endEncoding()
        command_buffer_impl.render_command_encoder = nil
    }

    if command_buffer_impl.presentable != {} {
        texture_impl := resource_library_get(&state.textures, command_buffer_impl.presentable)
        command_buffer_impl.command_buffer->presentDrawable(texture_impl.drawable)
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

ptr_data_to_mtl :: proc(data: [2]rawptr) -> (^MTL.Buffer, NS.UInteger) {
    return (^MTL.Buffer)(data[0]), (NS.UInteger)(uintptr(data[1]))
}

MTL_cmd_mem_copy :: proc(command_buffer: Command_Buffer, dst, src: ptr, size: u64) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    if buffer_impl.blit_command_encoder == nil {
        buffer_impl.blit_command_encoder = buffer_impl.command_buffer->blitCommandEncoder()
    }

    src_buffer, src_offset := ptr_data_to_mtl(src._data)
    dst_buffer, dst_offset := ptr_data_to_mtl(dst._data)

    buffer_impl.blit_command_encoder->copyFromBuffer(
        src_buffer, src_offset,
        dst_buffer, dst_offset,
        NS.UInteger(size),
    )
}

// ---------------------------------------------------------------------------
// Shaders

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
    shader := (^MTL.Function)(shader)
    shader->release()
    shader^ = {}
}

@(rodata)
mtl_pixel_format := [Pixel_Format]MTL.PixelFormat {
    .Invalid = MTL.PixelFormat.Invalid,
    .RGBA8Unorm = MTL.PixelFormat.RGBA8Unorm,
    .BGRA8Unorm_sRGB = MTL.PixelFormat.BGRA8Unorm_sRGB,
    .Depth32Float = MTL.PixelFormat.Depth32Float,
}

MTL_pipeline_init :: proc(vertex_shader, fragment_shader: Shader, formats: []Pixel_Format, depth_format: Pixel_Format) -> Pipeline {
    desc := MTL.RenderPipelineDescriptor.alloc()->init()
	defer desc->release()

    desc->setVertexFunction((^MTL.Function)(vertex_shader))
    desc->setFragmentFunction((^MTL.Function)(fragment_shader))
    desc->setDepthAttachmentPixelFormat(mtl_pixel_format[depth_format])
    
    for format, I in formats {
        desc->colorAttachments()->object(NS.UInteger(I))->setPixelFormat(mtl_pixel_format[format])
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

MTL_cmd_set_pipeline :: proc(command_buffer: Command_Buffer, pipeline: Pipeline) {
    buffer_info := resource_library_get(&state.command_buffers, command_buffer)

    // assert render command encoder is active, not blit or compute
    // Should be case if used right after begin render pass
    
    buffer_info.render_command_encoder->setRenderPipelineState((^MTL.RenderPipelineState)(pipeline))
}



MTL_use_resources :: proc(command_buffer: Command_Buffer, resource_list: []Shader_Resource) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)
    // temp use of resource list before heap implementation
    for res in resource_list {
        res_buffer, _ := ptr_data_to_mtl(res.ptr._data)
        usage_flags := transmute(MTL.ResourceUsage)res.usage // only works now since bitsets are mirrored nuppu <> metal
        stages := transmute(MTL.RenderStages)res.stage // only works now since bitsets are mirrored nuppu <> metal
        buffer_impl.render_command_encoder->useResourceWithStages(
            res_buffer, usage_flags, stages,
        )
    }
}

MTL_cmd_draw_primitives :: proc(command_buffer: Command_Buffer, pairs: []ptr_index_pair, primitive: Primitive_Type, vertex_count: u32) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    for bind in pairs {
        buffer_impl.render_command_encoder->setVertexBuffer((^MTL.Buffer)(bind.ptr._data[0]), 0, NS.UInteger(bind.index))
    }

    buffer_impl.render_command_encoder->drawPrimitives(transmute(MTL.PrimitiveType)primitive, 0, NS.UInteger(vertex_count))
}

MTL_cmd_draw_indiced_primitives :: proc(command_buffer: Command_Buffer, pairs: []ptr_index_pair, primitive: Primitive_Type, index_buffer: ptr, instance_count: u32) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    for pair in pairs {
        buffer_impl.render_command_encoder->setVertexBuffer((^MTL.Buffer)(pair.ptr._data[0]), 0, NS.UInteger(pair.index))
    }

    index_buffer, _ := ptr_data_to_mtl(index_buffer._data)
    index_count := index_buffer->length() / size_of(u32)

    buffer_impl.render_command_encoder->drawIndexedPrimitivesWithInstanceCount(
        transmute(MTL.PrimitiveType)primitive, NS.UInteger(index_count), MTL.IndexType.UInt32,
        index_buffer, 0, NS.UInteger(instance_count)
    )
}

_MTL_argument_buffer_init :: proc(shader: Shader, index: u32, pairs: []ptr_index_pair) -> ptr {
    shader_fn := (^MTL.Function)(shader)
    argument_encoder := shader_fn->newArgumentEncoder(NS.UInteger(index))
    defer argument_encoder->release()

    ptr := MTL_malloc(int(argument_encoder->encodedLength()), 16, .CPU_GPU)
    argument_encoder->setArgumentBufferWithOffset((^MTL.Buffer)(ptr._data[0]), 0)

    for pair in pairs {
        argument_encoder->setBuffer((^MTL.Buffer)(pair.ptr._data[0]), 0, NS.UInteger(pair.index))
    }

    return ptr
}

MTL_temp_malloc :: proc(command_buffer: Command_Buffer, bytes: []u8, index: u32, shader_stage: Shader_Stage) {
    buffer_impl := resource_library_get(&state.command_buffers, command_buffer)

    switch shader_stage {
    case .Vertex:
        buffer_impl.render_command_encoder->setVertexBytes(bytes, NS.UInteger(index))
    case .Fragment:
        buffer_impl.render_command_encoder->setFragmentBytes(bytes, NS.UInteger(index))
    case .Compute:
        panic("Not implemented")
    }
}