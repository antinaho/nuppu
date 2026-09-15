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


_ptr :: struct {
    buffer: ^MTL.Buffer,
}

_Shader_Module :: struct {
    library: ^MTL.Library,
}

_Shader :: struct {
    vertex_library:   ^MTL.Library,
    fragment_library: ^MTL.Library,
    pipeline:         ^MTL.RenderPipelineState,

    resource_table: [MAX_LAYOUT_BINDINGS]uintptr,
    resource_count: u32,
}

_Sampler :: ^MTL.SamplerState

_Texture :: struct #all_or_none {
    type: Texture_Type,
    usage: Texture_Usage,
    texture: ^MTL.Texture,
}

_Depth_Stencil_State :: ^MTL.DepthStencilState

_Compute_Pipeline :: ^MTL.ComputePipelineState

MAX_DEPTH_STATES :: 16

Depth_State_Cache :: struct {
    compare: Compare_Function,
    write:   bool,
    state:   ^MTL.DepthStencilState,
}

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

    curr_shader:       rawptr,
    curr_shader_valid: bool,

    curr_draw_state:  Draw_State,
    draw_state_valid: bool,

    curr_compute_pipeline: Compute_Pipeline,

    depth_states:      [MAX_DEPTH_STATES]Depth_State_Cache,
    depth_state_count: u32,

    present_min_duration: MTL.CFTimeInterval,

    presentation_handler: ^NS.Block,
}

// Present timing is written from a QuartzCore dispatch queue (the drawable's
// presented handler), which can outlive the GPU state during teardown. It must
// therefore live in process-lifetime storage, never inside `_State`.
_Present_Timing :: struct {
    prev_presented_time: MTL.CFTimeInterval, // in seconds
    present_duration:    MTL.CFTimeInterval, // in seconds
}
_present_timing: _Present_Timing

_present_handler :: proc "c" (user_data: rawptr, drawable: ^CA.MetalDrawable) {
    _ = user_data
    src := drawable->presentedTime()

    _present_timing.present_duration    = src - _present_timing.prev_presented_time
    _present_timing.prev_presented_time = src
}

_init :: proc(
    native_window   : rawptr,
    swapchain_format: Pixel_Format,
) -> bool {

    native_window := cast(^NS.Window)(native_window)

    _state.device = MTL.CreateSystemDefaultDevice()

    metal_layer := CA.MetalLayer.layer()
    metal_layer->retain()
    metal_layer->setDevice(_state.device)
    metal_layer->setPixelFormat(_pixel_format_interop(swapchain_format))
    metal_layer->setFramebufferOnly(false)
    metal_layer->setFrame(native_window->frame())
    metal_layer->setContentsScale(native_window->backingScaleFactor())
    _state.metal_layer = metal_layer

    native_window->contentView()->setLayer(metal_layer)
    native_window->setOpaque(true)
    native_window->setBackgroundColor(nil)

    _state.queue = _state.device->newCommandQueue()

    _state.present_min_duration = 0
    _present_timing = {}

    _state.presentation_handler = NS.Block.createLocalWithParam(
        user_data = nil,
        user_proc = _present_handler,
    )
    if _state.presentation_handler == nil {
        log.panic("gpu_metal_darwin: _init: failed to create presented handler block")
    }

    _state.is_init = true

    return true
}

_deinit :: proc() {
    _state.presentation_handler->release()

    for i in 0 ..< _state.depth_state_count {
        _state.depth_states[i].state->release()
    }
    _state.depth_state_count = 0

    // `nextDrawable` returns an autoreleased (+0) drawable owned by the frame
    // pool; do not release it here.
    _state.curr_drawable = nil

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

_copy_to_texture :: proc(texture: Texture, origin, size: [3]u32, level: u32, data: rawptr, bytes_per_row: u32) {
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

_shader_module_init :: proc(name: string, code: []u8) -> _Shader_Module {
    code_ns := NS.String.alloc()->initWithBytesNoCopy(raw_data(code), NS.UInteger(len(code)), .UTF8, false)
    defer code_ns->release()

    compile_options := MTL.CompileOptions.alloc()->init()
    defer compile_options->release()
    compile_options->setLanguageVersion(.Version3_0)

    library, err := _state.device->newLibraryWithSource(code_ns, compile_options)
    if err != nil {
        log.panicf("Failed to create shader library '%s': %v", name, err->localizedDescription()->odinString())
    }

    return _Shader_Module {
        library = library,
    }
}

// Compiles both stages, bakes the immutable pipeline (formats + blend), and
// precomputes the parameter-block resource table.
_shader_init :: proc(desc: Shader_Desc) -> _Shader {
    vmod := _shader_module_init("vs", transmute([]u8)desc.vertex_code)
    fmod := _shader_module_init("fs", transmute([]u8)desc.fragment_code)

    pso_desc := MTL.RenderPipelineDescriptor.alloc()->init()
    defer pso_desc->release()

    vertex_entry := NS.String.alloc()->initWithOdinString(desc.vertex_entry)
    defer vertex_entry->release()
    vertex_function := vmod.library->newFunctionWithName(vertex_entry)
    defer vertex_function->release()

    fragment_entry := NS.String.alloc()->initWithOdinString(desc.fragment_entry)
    defer fragment_entry->release()
    fragment_function := fmod.library->newFunctionWithName(fragment_entry)
    defer fragment_function->release()

    assert(vertex_function != nil, "shader_init: vertex entry point not found")
    assert(fragment_function != nil, "shader_init: fragment entry point not found")

    pso_desc->setVertexFunction(vertex_function)
    pso_desc->setFragmentFunction(fragment_function)
    pso_desc->setDepthAttachmentPixelFormat(_pixel_format_interop(desc.depth_format))

    color_attachment := pso_desc->colorAttachments()->object(0)
    color_attachment->setPixelFormat(_pixel_format_interop(desc.color_format))
    _set_blend(color_attachment, desc.blend)

    if desc.multisample.count > 1 {
        pso_desc->setRasterSampleCount(NS.UInteger(desc.multisample.count))
    }

    pso, err := _state.device->newRenderPipelineStateWithDescriptor(pso_desc)
    if err != nil {
        log.panicf("Failed to create pipeline state: %v", err->localizedDescription()->odinString())
    }

    result := _Shader {
        vertex_library   = vmod.library,
        fragment_library = fmod.library,
        pipeline         = pso,
    }
    result.resource_table, result.resource_count = _resource_table(desc.block)

    return result
}

_shader_deinit :: proc(shader: ^Shader) {
    if shader.pipeline != nil {
        shader.pipeline->release()
        shader.pipeline = nil
    }
    if shader.vertex_library != nil {
        shader.vertex_library->release()
        shader.vertex_library = nil
    }
    if shader.fragment_library != nil {
        shader.fragment_library->release()
        shader.fragment_library = nil
    }
}

_compute_pipeline_init :: proc(module: Shader_Module, entry_point: string) -> _Compute_Pipeline {
    entry_ns_str := NS.String.alloc()->initWithOdinString(entry_point)
    defer entry_ns_str->release()

    function := module.library->newFunctionWithName(entry_ns_str)
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
    defer {
        _state.frame_pool->drain()
        _state.frame_pool = nil
    }
    if _state.present_min_duration > 0 {
        _state.command_buffer->presentDrawableAfterMinimumDuration(_state.curr_drawable, _state.present_min_duration)
    } else {
        _state.command_buffer->presentDrawable(_state.curr_drawable)
    }
    _state.command_buffer->encodeSignalEvent((^MTL.SharedEvent)(semaphore), frame_n)
    _state.command_buffer->commit()

    _state.command_buffer = {}
    _state.curr_drawable = {}
    _state.render_command_encoder = {}
}

_acquire_next_swapchain :: proc() -> Texture {
    drawable := _state.metal_layer->nextDrawable()
    if drawable == nil {
        panic("In gpu_Metal.odin: _acquire_next_swapchain: Couldn't acquire next drawable")
    }

    drawable->addPresentedHandler(_state.presentation_handler)

    native := _Texture {
        type = ._2D,
        texture = drawable->texture(),
        usage = {.Color_Attachment},
    }
    
    _state.curr_drawable = drawable
    
    return Texture {
        dimensions = {u32(native.texture->width()), u32(native.texture->height()), 1},
        native = native,
    }
}

_frame_interval_ns :: proc() -> u64 {
    return u64(time.Duration(_present_timing.present_duration * MTL.CFTimeInterval(time.Second)))
}

_set_hz :: proc(hz: u32) {
    _state.present_min_duration = 0
    if hz > 0 {
        _state.present_min_duration = MTL.CFTimeInterval(1) / MTL.CFTimeInterval(hz)
    }
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

_set_shader :: proc(shader: ^Shader) {
    assert(_state.render_command_encoder != nil, "_set_shader: no render pass is active")

    if _state.curr_shader_valid && _state.curr_shader == rawptr(shader) {
        return
    }
    _state.curr_shader = rawptr(shader)
    _state.curr_shader_valid = true

    _state.render_command_encoder->setRenderPipelineState(shader.pipeline)
    _bind_parameter_block(&shader.desc.block, shader.resource_table[:], shader.resource_count)
}

_get_depth_stencil_state :: proc(compare: Compare_Function, write: bool) -> ^MTL.DepthStencilState {
    for i in 0 ..< _state.depth_state_count {
        e := &_state.depth_states[i]
        if e.compare == compare && e.write == write {
            return e.state
        }
    }

    assert(_state.depth_state_count < MAX_DEPTH_STATES, "_get_depth_stencil_state: cache full")
    ds_desc := MTL.DepthStencilDescriptor.alloc()->init()
    defer ds_desc->release()
    ds_desc->setDepthCompareFunction(_compare_function_interop(compare))
    ds_desc->setDepthWriteEnabled(write)

    state := _state.device->newDepthStencilState(ds_desc)
    assert(state != nil, "_get_depth_stencil_state: failed to create depth stencil state")

    i := _state.depth_state_count
    _state.depth_states[i] = Depth_State_Cache {
        compare = compare,
        write   = write,
        state   = state,
    }
    _state.depth_state_count += 1
    return state
}

_set_draw_state :: proc(state: Draw_State) {
    assert(_state.render_command_encoder != nil, "_set_draw_state: no render pass is active")

    if _state.draw_state_valid && _state.curr_draw_state == state {
        return
    }
    _state.curr_draw_state = state
    _state.draw_state_valid = true

    encoder := _state.render_command_encoder
    encoder->setCullMode(_cull_mode_interop(state.cull_mode))
    encoder->setFrontFacingWinding(_front_face_winding_interop(state.front_face))
    encoder->setDepthStencilState(_get_depth_stencil_state(state.depth_compare, state.depth_write))
}

_set_parameter_block :: proc(shader: ^Shader, block: ^Parameter_Block) {
    shader.desc.block = block^
    shader.resource_table, shader.resource_count = _resource_table(block^)

    // If this shader is currently bound, rebind immediately so the next draw
    // sees the new resources.
    if _state.curr_shader_valid && _state.curr_shader == rawptr(shader) {
        assert(_state.render_command_encoder != nil, "_set_parameter_block: no render pass is active")
        _bind_parameter_block(block, shader.resource_table[:], shader.resource_count)
    }
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
    
    mip_levels := max(texture_descriptor.mip_levels, 1)
    desc->setMipmapLevelCount(NS.UInteger(mip_levels))
    
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

_begin_render_pass :: proc(c_attachment: Color_Attachment, d_attachment: Depth_Attachment) {
    assert(_state.blit_command_encoder == nil, "_begin_render_pass: transfer encoder still open (missing gpu.barrier(.Transfer, .All) after uploads)")

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

    // A new encoder starts with default pipeline + dynamic state.
    _state.curr_shader_valid = false
    _state.draw_state_valid  = false
}

_end_render_pass :: proc() {
    when ODIN_DEBUG {
        assert(_state.render_command_encoder != nil, "_end_render_pass: no render pass is active")
    }

    _state.render_command_encoder->endEncoding()
    _state.render_command_encoder = nil
}

_draw_indexed :: proc(index_buffer: ptr, index_count: u32, index_offset: u32, instance_count: u32, base_vertex: u32, base_instance: u32) {
    if instance_count == 0 {
        return
    }

    assert(_state.curr_shader_valid, "_draw_indexed: no shader bound; call set_shader first")
    shader := (^Shader)(_state.curr_shader)

    // The engine only emits u16 indices (Vertex_Index).
    index_format := MTL.IndexType.UInt16
    index_bytes: NS.UInteger = 2

    _state.render_command_encoder->drawIndexPrimitivesWithBaseVertex(
        _primitive_type_interop(shader.desc.topology), NS.UInteger(index_count), index_format,
        index_buffer.native.buffer, NS.UInteger(index_offset * u32(index_bytes)), NS.UInteger(instance_count), NS.Integer(base_vertex), NS.UInteger(base_instance)
    )
}

_malloc :: proc(
    #any_int bytes: uint,
    alignment: u32,
    flags: Buffer_Flag,
    name: string,
    loc := #caller_location,
) -> _ptr {
    capacity := runtime.align_forward(bytes, uint(alignment))

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

_min_alignment :: proc(flags: Buffer_Flag) -> u32 {
    return 4
}

// Pure: builds the flat GPU-address table in binding order (constants, read,
// read/write, samplers). No encoder required, so it can run at shader_init.
_resource_table :: proc(block: Parameter_Block) -> ([MAX_LAYOUT_BINDINGS]uintptr, u32) {
    table: [MAX_LAYOUT_BINDINGS]uintptr
    n: u32

    for C in block.constants {
        if C.native.buffer == nil { continue }
        table[n] = uintptr(C.gpu)
        n += 1
    }

    for R in block.read_resources {
        switch res in R {
        case ptr:
            if res.native.buffer == nil { continue }
            table[n] = uintptr(res.gpu)
            n += 1
        case Texture:
            if res.native.texture == nil { continue }
            table[n] = uintptr(res.native.texture->gpuResourceID())
            n += 1
        }
    }

    for RW in block.read_write_resources {
        switch res in RW {
        case ptr:
            if res.native.buffer == nil { continue }
            table[n] = uintptr(res.gpu)
            n += 1
        case Texture:
            if res.native.texture == nil { continue }
            table[n] = uintptr(res.native.texture->gpuResourceID())
            n += 1
        }
    }

    for S in block.samplers {
        if S.native == nil { continue }
        table[n] = uintptr(S.native->gpuResourceID())
        n += 1
    }

    assert(n <= MAX_LAYOUT_BINDINGS, "_resource_table: too many bindings")
    return table, n
}

// Marks every resource resident for the current render encoder and pushes the
// precomputed address table with one call per stage.
_bind_parameter_block :: proc(block: ^Parameter_Block, table: []uintptr, count: u32) {
    assert(_state.render_command_encoder != nil, "_bind_parameter_block: no render pass is active")

    for C in block.constants {
        if C.native.buffer == nil { continue }
        _state.render_command_encoder->useResourceWithStages(C.native.buffer, {.Read}, {.Vertex, .Fragment})
    }

    for R in block.read_resources {
        switch res in R {
        case ptr:
            if res.native.buffer == nil { continue }
            _state.render_command_encoder->useResourceWithStages(res.native.buffer, {.Read}, {.Vertex, .Fragment})
        case Texture:
            if res.native.texture == nil { continue }
            _state.render_command_encoder->useResourceWithStages(res.native.texture, _texture_resource_usage_interop(res.native.usage), {.Vertex, .Fragment})
        }
    }

    for RW in block.read_write_resources {
        switch res in RW {
        case ptr:
            if res.native.buffer == nil { continue }
            _state.render_command_encoder->useResourceWithStages(res.native.buffer, {.Read, .Write}, {.Vertex, .Fragment})
        case Texture:
            if res.native.texture == nil { continue }
            _state.render_command_encoder->useResourceWithStages(res.native.texture, _texture_resource_usage_interop(res.native.usage), {.Vertex, .Fragment})
        }
    }

    assert(len(table) >= int(count), "_bind_parameter_block: table smaller than count")
    bytes := slice.bytes_from_ptr(raw_data(table), int(count) * size_of(uintptr))
    _temp_malloc(bytes, 0, .Vertex)
    _temp_malloc(bytes, 0, .Fragment)
}

// Low-level block bind used by the compute path. Graphics go through
// _set_shader / _bind_parameter_block.
_use_parameter_block :: proc(block: ^Parameter_Block, destination: Parameter_Block_Destination) {
    table, count := _resource_table(block^)

    if destination == .Graphics {
        _bind_parameter_block(block, table[:], count)
        return
    }

    for C in block.constants {
        if C.native.buffer == nil { continue }
        _compute_command_encoder()->useResource(C.native.buffer, {.Read})
    }

    for R in block.read_resources {
        switch res in R {
        case ptr:
            if res.native.buffer == nil { continue }
            _compute_command_encoder()->useResource(res.native.buffer, {.Read})
        case Texture:
            if res.native.texture == nil { continue }
            _compute_command_encoder()->useResource(res.native.texture, _texture_resource_usage_interop(res.native.usage))
        }
    }

    for RW in block.read_write_resources {
        switch res in RW {
        case ptr:
            if res.native.buffer == nil { continue }
            _compute_command_encoder()->useResource(res.native.buffer, {.Read, .Write})
        case Texture:
            if res.native.texture == nil { continue }
            _compute_command_encoder()->useResource(res.native.texture, _texture_resource_usage_interop(res.native.usage))
        }
    }

    bytes := slice.bytes_from_ptr(raw_data(table[:]), int(count) * size_of(uintptr))
    _temp_malloc(bytes, 0, .Compute)
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

_to_clear_color :: proc(color: Clear_Color) -> MTL.ClearColor {
    return MTL.ClearColor {
        red   = f64(color.x) / 255.0,
        green = f64(color.y) / 255.0,
        blue  = f64(color.z) / 255.0,
        alpha = f64(color.w) / 255.0,
    }
}

_set_blend :: proc(color_attachment: ^MTL.RenderPipelineColorAttachmentDescriptor, blend: Blend_State) {
    color_attachment->setBlendingEnabled(true)
    color_attachment->setRgbBlendOperation(_blend_operation_interop(blend.color.op))
    color_attachment->setSourceRGBBlendFactor(_blend_factor_interop(blend.color.src))
    color_attachment->setDestinationRGBBlendFactor(_blend_factor_interop(blend.color.dst))
    color_attachment->setAlphaBlendOperation(_blend_operation_interop(blend.alpha.op))
    color_attachment->setSourceAlphaBlendFactor(_blend_factor_interop(blend.alpha.src))
    color_attachment->setDestinationAlphaBlendFactor(_blend_factor_interop(blend.alpha.dst))
}

//////////////////////////////////////////////////////////////
// Interop

_blend_operation_interop :: proc(op: Blend_Operation) -> MTL.BlendOperation {
    switch op {
    case .Add:             return .Add
    case .Subtract:        return .Subtract
    case .ReverseSubtract: return .ReverseSubtract
    case .Min:             return .Min
    case .Max:             return .Max
    }
    unreachable()
}

_blend_factor_interop :: proc(f: Blend_Factor) -> MTL.BlendFactor {
    switch f {
    case .Undefined:         return .One
    case .Zero:              return .Zero
    case .One:               return .One
    case .Src:               return .SourceColor
    case .OneMinusSrc:       return .OneMinusSourceColor
    case .SrcAlpha:          return .SourceAlpha
    case .OneMinusSrcAlpha:  return .OneMinusSourceAlpha
    case .Dst:               return .DestinationColor
    case .OneMinusDst:       return .OneMinusDestinationColor
    case .DstAlpha:          return .DestinationAlpha
    case .OneMinusDstAlpha:  return .OneMinusDestinationAlpha
    case .SrcAlphaSaturated: return .SourceAlphaSaturated
    case .Constant:          return .BlendColor
    case .OneMinusConstant:  return .OneMinusBlendColor
    case .Src1:              return .Source1Color
    case .OneMinusSrc1:      return .OneMinusSource1Color
    case .Src1Alpha:         return .Source1Alpha
    case .OneMinusSrc1Alpha: return .OneMinusSource1Alpha
    }
    unreachable()
}

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

_primitive_type_interop :: proc(primitive: Primitive) -> MTL.PrimitiveType {
    switch primitive {
    case .Triangle:
        return .Triangle
    }
    unreachable()
}
