#+vet unused shadowing using-param style semicolon cast explicit-allocators

/*
Shaders are the main draw object materials reference. A `gpu.Shader` bakes the
whole immutable draw state (modules, formats, blend, multisample, topology) plus
the resource set into one bindable object, so switching material is one bind.

`Draw_State` (cull / front-face / depth) stays dynamic: Metal applies it with
encoder calls, WGPU selects a cached pipeline variant. Neither duplicates the
shader.

Engine-global buffers always occupy the first read-resource slots; a shader's
own textures/samplers follow.
*/

package nuppu

import "gpu"
import "bit_array"
import "base:runtime"
import "core:log"

_ :: log

#assert(CONFIG.max_shaders > 0, "CONFIG.max_shaders must be > 0")
#assert(CONFIG.max_shaders % 64 == 0, "CONFIG.max_shaders must be a multiple of 64 (bit_array bucket)")
#assert(CONFIG.max_shaders < (1 << 23), "CONFIG.max_shaders exceeds bit_array index space")

Shader_Handle     :: Handle(bit_array.Handle)
Shader_Handle_Nil :: Shader_Handle{}

Draw_State         :: gpu.Draw_State
DEFAULT_DRAW_STATE :: gpu.DEFAULT_DRAW_STATE

// Number of engine-global read-resource slots a shader block always starts
// with: frame uniforms live in `constants`; these are the buffer bindings.
SHADER_ENGINE_BUFFER_SLOTS :: 5

// Engine-level shader description. Mirrors `gpu.Shader_Desc` but takes engine
// texture handles and no block; `shader_register` resolves them and composes
// the full parameter block.
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

    textures: []Texture_Handle, // bound after the engine buffers, in order
    samplers: []gpu.Sampler,    // defaults to the engine sampler when empty
}

Shader_Library :: struct {
    shaders:   bit_array.Bit_Array(Resource(gpu.Shader, Shader_Handle), u64(CONFIG.max_shaders), Shader_Handle),
    allocator: runtime.Allocator,
    is_init:   bool,
}

_shader_lib_init :: proc(lib: ^Shader_Library, allocator := context.allocator) {
    if lib.is_init { return }
    lib.is_init   = true
    lib.allocator = allocator
    bit_array.init(&lib.shaders)
}

_shader_lib_deinit :: proc(lib: ^Shader_Library) {
    it := bit_array.iterator_init(&lib.shaders)
    for {
        shader, ok := bit_array.iterator_next(&it)
        if !ok { break }
        gpu.shader_deinit(&shader.data)
    }
    lib^ = {}
}

// Composes the engine-global part of a shader's parameter block and appends the
// given textures/samplers. Public so callers can rebuild a block at runtime and
// hand it to `shader_set_parameter_block` to swap resources (e.g. textures).
shader_block :: proc(textures: []Texture_Handle, samplers: []gpu.Sampler) -> gpu.Parameter_Block {
    block: gpu.Parameter_Block

    block.constants[0] = _state.frame_uniform

    block.read_resources[0] = _state.mesh_library.vertex_arena.ptr
    block.read_resources[1] = _state.draw_batcher.instance_base_buffer
    block.read_resources[2] = _state.material_library.private_material_buffer
    block.read_resources[3] = _state.material_library.private_params_buffer
    block.read_resources[4] = _state.draw_batcher.instance_data_buffer

    assert(
        len(textures) <= gpu.MAX_READ_RESOURCE - SHADER_ENGINE_BUFFER_SLOTS,
        "shader_block: too many textures",
    )
    for tex_handle, i in textures {
        tex, ok := get_resource(&_state.textures, tex_handle)
        assert(ok, "shader_block: invalid texture handle")
        block.read_resources[SHADER_ENGINE_BUFFER_SLOTS + i] = tex^
    }

    assert(len(samplers) <= gpu.MAX_SAMPLERS, "shader_block: too many samplers")
    if len(samplers) == 0 {
        block.samplers[0] = _state.sampler
    } else {
        for s, i in samplers {
            block.samplers[i] = s
        }
    }

    return block
}

@(require_results)
shader_register :: proc(desc: Shader_Desc, name: string = "", loc := #caller_location) -> (Shader_Handle, bool) #optional_ok {
    lib := &_state.shader_library
    assert(lib.is_init, "shader_register: shader library not initialized")

    block := shader_block(desc.textures, desc.samplers)

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
        block          = block,
    })

    return add_resource(&lib.shaders, shader, name, loc), true
}

@(require_results)
get_shader :: proc(handle: Shader_Handle) -> (^gpu.Shader, bool) #optional_ok {
    return get_resource(&_state.shader_library.shaders, handle)
}

// Runtime resource swap. Rebuild a block with `shader_block` and pass it here.
shader_set_parameter_block :: proc(handle: Shader_Handle, block: ^gpu.Parameter_Block) {
    shader, ok := get_shader(handle)
    if !ok { return }
    gpu.set_parameter_block(shader, block)
}
