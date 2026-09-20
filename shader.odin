#+vet unused shadowing using-param style semicolon cast explicit-allocators

package nuppu

import "gpu"
import "base:runtime"
import "core:log"

_ :: log

SHADER_HANDLE_RAW :: u16

Shader_Handle     :: distinct Handle(SHADER_HANDLE_RAW)
Shader_Handle_Nil :: Shader_Handle{}

SHADER_INDEX_MASK :: MAX_SHADERS - 1
#assert(MAX_SHADERS > 0 && (MAX_SHADERS & (MAX_SHADERS-1)) == 0, "MAX_SHADERS must be a power of two")

Draw_State         :: gpu.Draw_State
DEFAULT_DRAW_STATE :: gpu.DEFAULT_DRAW_STATE

// Parameter block slots in a registered shader's `binding_blocks`:
// 0 engine constants, 1 instance + material, 2 shader-local, 3 material.
SHADER_BLOCK_ENGINE   :: 0
SHADER_BLOCK_GRAPHICS :: 1
SHADER_BLOCK_LOCAL    :: 2
SHADER_BLOCK_MATERIAL :: 3

Shader_Library :: struct {
    table: Resource_Table(gpu.Shader), // slot 0 is the nil sentinel

    __shader_handles: [dynamic]Shader_Handle, // debug-only, for leak reports
}

Resource_Handle :: union {
    Texture_Handle,
    Sampler_Handle,
    Buffer_Handle,
}

Shader_Desc :: struct {
    vertex_code:    string,
    vertex_entry:   string,
    fragment_code:  string,
    fragment_entry: string,

    color_format: gpu.Pixel_Format,
    depth_format: gpu.Pixel_Format,

    blend:       gpu.Blend_State,
    multisample: gpu.Multisample_State,
    topology:    gpu.Primitive,

    shader_resources: []Resource_Handle,
}


NUPPU_shader_lib_init :: proc(lib: ^Shader_Library, allocator := context.allocator) -> (err: runtime.Allocator_Error) {
    err = resource_table_init(&lib.table, MAX_SHADERS, allocator)
    if err != nil { return }

    when ODIN_DEBUG {
        lib.__shader_handles = make([dynamic]Shader_Handle, 0, 64, context.allocator)
    }

    return
}

NUPPU_shader_lib_deinit :: proc(lib: ^Shader_Library) {
    it := bit_mask_array_iterator_init(&lib.table.occupied)
    for index in bit_mask_array_iterator_next(&it) {
        if index == 0 { continue } // sentinel
        shader := &lib.table.items[index]
        delete(shader.desc.binding_blocks, lib.table.allocator)
        shader.desc.binding_blocks = nil
        gpu.shader_deinit(shader)
    }
    resource_table_destroy(&lib.table)

    when ODIN_DEBUG {
        delete(lib.__shader_handles)
    }
    lib^ = {}
}

material_binding_block :: proc(material: Material_Handle, allocator: runtime.Allocator) -> gpu.Resource_Block {
    block: gpu.Resource_Block
    handles := material_bindings_of(material)
    
    block.resources = make([]gpu.Resource, len(handles), allocator = allocator)

    for H, i in handles {
        switch r in H {
        case Texture_Handle:
            tex, ok := get_texture(r)
            assert(ok, "material_binding_block: invalid texture handle")
            block.resources[i] = tex^
        case Buffer_Handle:
            buf, ok := buffer_get(r)
            assert(ok, "material_binding_block: invalid buffer handle")
            block.resources[i] = buf^
        case Sampler_Handle:
            panic("Cant be per material material")
        }
    }

    return block
}

// Composes a shader's local block (set 1) must match the shader file
shader_constant_block :: proc(
    resource_handles: []Resource_Handle,
) -> gpu.Resource_Block {
    block: gpu.Resource_Block
    block.resources = make([]gpu.Resource, len(resource_handles), allocator = context.allocator)

    for RH, i in resource_handles {
        switch h in RH {
        case Texture_Handle:
            tex, ok := get_texture(h)
            assert(ok, "shader_local_block: invalid texture handle")
            block.resources[i] = tex^
        case Sampler_Handle:
            s, ok := sampler_get(h)
            assert(ok, "shader_local_block: invalid sampler handle")
            block.resources[i] = s^
        case Buffer_Handle:
            buf, ok := buffer_get(h)
            assert(ok, "shader_local_block: invalid buffer handle")
            block.resources[i] = buf^
        }
    }

    return block
}


connect_materials_to_shader :: proc(mats: []Material_Handle, shader: Shader_Handle) {
    mat_lib := &_state.material_library
    for mat in mats {
        idx, ok := material_handle_unpack(mat)
        if !ok { continue }
        rec, got := resource_table_get(&mat_lib.table, int(idx))
        if !got { continue }
        rec.shader = shader
    }
}

@(require_results)
shader_register :: proc(
    desc: Shader_Desc, 
    $I: typeid, 
    base_material: Material_Handle, 
    name: string = "", 
    loc := #caller_location
) -> (Shader_Handle, bool) #optional_ok {
    lib := &_state.shader_library

    // Base material used as a interface on creating the shaders bindings
    assert(is_base_material(base_material), "shader_register: material must be a base material")
    assert(size_of(I) % INSTANCE_SIZE_ALIGN == 0, "shader_register: instance layout must be a multiple of 16 bytes")
    
    material_block := material_binding_block(base_material, context.allocator)
    local_block := shader_constant_block(desc.shader_resources)

    // Instance + material block (set 1). The instance type registers this
    // layout's buffer so WGPU can build the block from a concrete resource,
    // the same way the material block is built from the base material.
    resources := make([]gpu.Resource, 2, allocator = context.allocator)
    resources[0] = _batcher_layout_buffer(I)
    resources[1] = _state.material_library.private_material_buffer
    graphics_block := gpu.Resource_Block {
        resources = resources,
        _resource_size = { uint(size_of(I)) },
    }

    binding_blocks := make([dynamic]gpu.Resource_Block, allocator = context.allocator)
    append(&binding_blocks, _state.engine_block, graphics_block, local_block, material_block)

    shader := gpu.shader_init(gpu.Shader_Desc {
        vertex_code    = desc.vertex_code,
        vertex_entry   = desc.vertex_entry,
        fragment_code  = desc.fragment_code,
        fragment_entry = desc.fragment_entry,
        color_format   = desc.color_format,
        depth_format   = desc.depth_format,
        blend          = desc.blend,
        multisample    = desc.multisample,
        topology       = desc.topology,
        binding_blocks = binding_blocks[:],
    })

    index, ok := resource_table_acquire(&lib.table)
    assert(ok, "shader_register: out of shader slots, raise CONFIG.max_shaders")

    lib.table.items[index] = shader

    handle := Shader_Handle { handle = u16(index) }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
        append(&lib.__shader_handles, handle)
    }
    return handle, true
}

@(require_results)
get_shader :: proc(handle: Shader_Handle) -> (^gpu.Shader, bool) #optional_ok {
    index, ok := shader_handle_unpack(handle)
    if !ok { return nil, false }
    return resource_table_get(&_state.shader_library.table, index)
}

shader_free :: proc(handle: Shader_Handle) {
    lib := &_state.shader_library
    index, ok := shader_handle_unpack(handle)
    if !ok { return }
    shader, got := resource_table_get(&lib.table, index)
    if !got { return }

    delete(shader.desc.binding_blocks, lib.table.allocator)
    shader.desc.binding_blocks = nil
    gpu.shader_deinit(shader)
    resource_table_release(&lib.table, index)

    when ODIN_DEBUG {
        for h, i in lib.__shader_handles {
            if h == handle {
                unordered_remove(&lib.__shader_handles, i)
                break
            }
        }
    }
}

shader_handle_unpack :: proc "contextless" (handle: Shader_Handle) -> (idx: SHADER_HANDLE_RAW, ok: bool) #optional_ok {
    idx = handle.handle & SHADER_INDEX_MASK
    if idx == 0 || idx >= MAX_SHADERS { return 0, false }
    return idx, true
}
