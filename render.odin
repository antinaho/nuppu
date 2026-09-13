package nuppu

import "core:math"
import "gpu"
import "bit_array"
import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:slice"
import glm "core:math/linalg/glsl"
import "core:log"

Built_in_texture :: enum u32 {
    Depth,
    Swapchain,
}

get_built_in_mesh :: proc(built_in_mesh: Built_In_Mesh) -> (^Mesh, bool) #optional_ok {
    return get_mesh(_state.mesh_library.built_in_lookup[built_in_mesh])
}

built_in_mesh_handle :: proc(built_in_mesh: Built_In_Mesh) -> Mesh_Handle {
    return _state.mesh_library.built_in_lookup[built_in_mesh]
}

get_mesh :: proc(handle: Mesh_Handle) -> (^Mesh, bool) #optional_ok {
    return get_resource(&_state.mesh_library.meshes, handle)
}

// ============================================================================
// Instance layout
//
// The base instance is pure transform + up to 6 material handles + an entity
// id. All non-transform per-object data lives in materials. The batcher only
// copies transforms and handles; the shader fetches the material records and
// their parameters.
// ============================================================================

#assert(size_of(Instance) == 64)
Instance :: struct #all_or_none #align(16) {
    position_pack: [4]f32, // xyz = position
    scale_pack:    [4]f32, // xyz = scale
    rotation_pack: [3]f32, // xyz = rotation
    data_offset:   u32,    // byte offset into instance_data_buffer; 0 = none
    materials:     [3]u32, // 6 x u16 Material_Handle
    entity_id:     u32,    // user tag the shader switches on
}
MAX_INSTANCES_PER_FRAME :: 1 << 16

#assert(CONFIG.max_instance_data_bytes > 0, "CONFIG.max_instance_data_bytes must be > 0")
#assert(CONFIG.max_instance_data_bytes % 16 == 0, "CONFIG.max_instance_data_bytes must be a multiple of 16")
#assert(offset_of(Instance, data_offset) == 44, "data_offset must stay at byte 44 to match the shader layout")

// One frame region holds MAX_INSTANCES_PER_FRAME entries plus 16 reserved bytes
// so byte offset 0 can mean "no instance data".
INSTANCE_DATA_REGION_SIZE :: MAX_INSTANCES_PER_FRAME * CONFIG.max_instance_data_bytes + 16
#assert(FRAMES_IN_FLIGHT * INSTANCE_DATA_REGION_SIZE <= int(max(u32)), "instance data buffer exceeds u32 address space")

// ============================================================================
// Draw batcher
//
// Pipeline:
//   submit / gather -> flat Submission list (transform + material handles + mesh)
//   cull(frame): frustum-test + compact
//   finish_instance_upload(frame): sort by mesh, write the instance blob, emit
//     Draw_Command runs
//   draw_all_instances(frame): one draw per mesh run
// ============================================================================

Submission :: struct {
    base: Instance,
    mesh: Mesh_Handle,
}

Draw_Command :: struct {
    mesh:           Mesh_Handle,
    base_instance:  u32, // index into instance_base_buffer
    instance_count: u32,
}

Draw_Batcher :: struct {
    submissions:   [dynamic]Submission,
    sorted:        [dynamic]int,
    draw_commands: [dynamic]Draw_Command,

    instance_base_buffer: gpu.ptr,

    // Per-frame arena for arbitrary per-entity shader data. `Instance.data_offset`
    // points into this buffer. Offset 0 is reserved as the nil sentinel.
    instance_data_buffer:     gpu.ptr,
    instance_data_cursor:     uint,
    instance_data_region_end: uint,

    allocator: runtime.Allocator,
    is_init:   bool,
}

init_draw_batcher :: proc(batcher: ^Draw_Batcher, allocator := context.allocator) {
    if batcher.is_init { return }
    batcher.is_init   = true
    batcher.allocator = allocator

    INITIAL_CAP :: 16
    batcher.submissions   = make([dynamic]Submission,   0, INITIAL_CAP, allocator)
    batcher.sorted        = make([dynamic]int,          0, INITIAL_CAP, allocator)
    batcher.draw_commands = make([dynamic]Draw_Command, 0, INITIAL_CAP, allocator)

    base_bytes := u32(MAX_INSTANCES_PER_FRAME * FRAMES_IN_FLIGHT * size_of(Instance))
    base_ptr, base_ok := gpu.malloc(base_bytes, u32(align_of(Instance)), .Staging, "Instance Base Staging")
    assert(base_ok, "draw_batcher: failed to alloc instance base buffer")
    batcher.instance_base_buffer = base_ptr

    data_bytes := u32(FRAMES_IN_FLIGHT * INSTANCE_DATA_REGION_SIZE)
    data_ptr, data_ok := gpu.malloc(data_bytes, 16, .Staging, "Instance Data Staging")
    assert(data_ok, "draw_batcher: failed to alloc instance data buffer")
    batcher.instance_data_buffer = data_ptr
}

destroy_draw_batcher :: proc(batcher: ^Draw_Batcher) {
    if !batcher.is_init { return }
    gpu.release_ptr(&batcher.instance_base_buffer)
    gpu.release_ptr(&batcher.instance_data_buffer)
    delete(batcher.submissions)
    delete(batcher.sorted)
    delete(batcher.draw_commands)
    batcher^ = {}
}

// Explicit submission path. Uses the global batcher. Instances submitted here
// carry no per-entity data (data_offset stays 0, shaders use their defaults).
submit_instance :: proc(
    mesh: Mesh_Handle,
    position, scale, rotation: [3]f32,
    materials: [CONFIG.entity_max_materials]Material_Handle,
    entity_id: u32 = 0,
) {
    batcher := &_state.draw_batcher
    if len(batcher.submissions) >= MAX_INSTANCES_PER_FRAME {
        panic("draw_batcher: max instances per frame exceeded")
    }
    append(&batcher.submissions, Submission {
        base = make_instance(position, scale, rotation, materials, entity_id),
        mesh = mesh,
    })
}

batcher_reset :: proc(frame: Frame, batcher: ^Draw_Batcher) {
    clear(&batcher.submissions)
    clear(&batcher.draw_commands)

    // Each frame owns a region of the data arena; the first 16 bytes of every
    // region are reserved so offset 0 always means "no instance data".
    f := uint(frame.n % FRAMES_IN_FLIGHT)
    region_size := uint(INSTANCE_DATA_REGION_SIZE)
    batcher.instance_data_cursor     = f * region_size + 16
    batcher.instance_data_region_end = (f + 1) * region_size
}

// Copies `size` bytes of per-entity data into the current frame's arena region
// and returns the 16-byte-aligned byte offset. Offset 0 is never returned.
_push_instance_data :: proc(batcher: ^Draw_Batcher, src: rawptr, size: int) -> u32 {
    if size <= 0 { return 0 }

    offset := mem.align_forward_uint(batcher.instance_data_cursor, 16)
    if offset + uint(size) > batcher.instance_data_region_end {
        panic("draw_batcher: instance data arena overflow")
    }

    intrinsics.mem_copy(rawptr(uintptr(batcher.instance_data_buffer.cpu) + uintptr(offset)), src, size)
    batcher.instance_data_cursor = offset + mem.align_forward_uint(uint(size), 16)
    return u32(offset)
}

// ----------------------------------------------------------------------------
// Entity gather
// ----------------------------------------------------------------------------

_gather_entity_submissions :: proc(batcher: ^Draw_Batcher, em: ^Entity_Manager) {
    for v in 0 ..< len(em.variants) {
        if .Has_Mesh not_in em.flags[v] { continue }

        iter := Entity_Iterator {
            manager     = em,
            variant_idx = ENTITY_VARIANT(v),
        }

        data_offset := em.instance_data_offsets[v]
        data_size   := em.instance_data_sizes[v]

        for entity, variant in _iter_next_slot(&iter) {
            if entity.mesh.handle == bit_array.NIL_HANDLE { continue }
            if entity.materials[0] == MATERIAL_NIL { 
                log.warnf("draw_batcher: entity %v has no material in slot 0", u32(entity.handle.variant))
            }

            if len(batcher.submissions) >= MAX_INSTANCES_PER_FRAME {
                panic("draw_batcher: max instances per frame exceeded")
            }
            
            base := make_instance(
                entity.position, entity.scale, entity.rotation,
                entity.materials, u32(entity.handle.variant),
            )
            if data_size > 0 {
                src := rawptr(uintptr(variant) + uintptr(data_offset))
                base.data_offset = _push_instance_data(batcher, src, data_size)
            }

            append(&batcher.submissions, Submission {
                base = base,
                mesh = entity.mesh,
            })
        }
    }
}

// ----------------------------------------------------------------------------
// Frustum culling
// ----------------------------------------------------------------------------

Frustum :: [6][4]f32


_camera_view_proj :: proc() -> (vp: matrix[4,4]f32, ok: bool) {
    cam, cok := entity_get_typed(_state.entity_manager, _state.main_camera, Camera)
    if !cok { return {}, false }
    perspective := glm.mat4Perspective(glm.radians_f32(cam.fovy), cam.aspect_ratio, cam.near, cam.far)
    world       := glm.mat4Translate(-cam.position)
    return perspective * world, true
}

// Gribb–Hartmann plane extraction. `m` maps world -> clip for column vectors
// (clip = m * world); Odin's m[i, j] is row i, column j.

_frustum_from_view_proj :: proc(m: matrix[4,4]f32) -> Frustum {
    r0 := [4]f32{m[0,0], m[0,1], m[0,2], m[0,3]}
    r1 := [4]f32{m[1,0], m[1,1], m[1,2], m[1,3]}
    r2 := [4]f32{m[2,0], m[2,1], m[2,2], m[2,3]}
    r3 := [4]f32{m[3,0], m[3,1], m[3,2], m[3,3]}
    return {
        _normalize_plane(_add4(r3, r0)), // left
        _normalize_plane(_sub4(r3, r0)), // right
        _normalize_plane(_add4(r3, r1)), // bottom
        _normalize_plane(_sub4(r3, r1)), // top
        _normalize_plane(_add4(r3, r2)), // near
        _normalize_plane(_sub4(r3, r2)), // far
    }
}


_add4 :: proc(a, b: [4]f32) -> [4]f32 { return {a[0]+b[0], a[1]+b[1], a[2]+b[2], a[3]+b[3]} }

_sub4 :: proc(a, b: [4]f32) -> [4]f32 { return {a[0]-b[0], a[1]-b[1], a[2]-b[2], a[3]-b[3]} }


_normalize_plane :: proc(p: [4]f32) -> [4]f32 {
    n := math.sqrt(p[0]*p[0] + p[1]*p[1] + p[2]*p[2])
    if n == 0 { return p }
    return {p[0]/n, p[1]/n, p[2]/n, p[3]/n}
}


_sphere_in_frustum :: proc(planes: Frustum, center: [3]f32, radius: f32) -> bool {
    for p in planes {
        d := p[0]*center.x + p[1]*center.y + p[2]*center.z + p[3]
        if d < -radius { return false }
    }
    return true
}


_cull_submissions :: proc(batcher: ^Draw_Batcher) {
    vp, ok := _camera_view_proj()
    if !ok { return }
    planes := _frustum_from_view_proj(vp)

    keep := 0
    for i in 0 ..< len(batcher.submissions) {
        s := batcher.submissions[i]
        center := [3]f32{s.base.position_pack.x, s.base.position_pack.y, s.base.position_pack.z}
        sx := s.base.scale_pack.x
        sy := s.base.scale_pack.y
        sz := s.base.scale_pack.z
        radius := 0.5 * math.sqrt(sx*sx + sy*sy + sz*sz)
        if _sphere_in_frustum(planes, center, radius) {
            batcher.submissions[keep] = s
            keep += 1
        }
    }
    resize(&batcher.submissions, keep)
}

// Gather entity draws and cull everything outside the camera frustum.
cull :: proc(frame: Frame) {
    batcher := &_state.draw_batcher
    _gather_entity_submissions(batcher, _state.entity_manager)
    _cull_submissions(batcher)
}

// ----------------------------------------------------------------------------
// Sort + upload
// ----------------------------------------------------------------------------


_submission_index_less :: proc(a, b: int, user: rawptr) -> bool {
    s := (^Draw_Batcher)(user)
    return s.submissions[a].mesh.handle < s.submissions[b].mesh.handle
}

finish_instance_upload :: proc(frame: Frame) {
    batcher := &_state.draw_batcher
    f := int(frame.n % FRAMES_IN_FLIGHT)
    n := len(batcher.submissions)

    clear(&batcher.draw_commands)
    if n == 0 { return }

    resize(&batcher.sorted, n)
    for i in 0 ..< n { batcher.sorted[i] = i }
    slice.sort_by_with_data(batcher.sorted[:], _submission_index_less, rawptr(batcher))

    base_region := uintptr(batcher.instance_base_buffer.cpu) +
        uintptr(f) * uintptr(MAX_INSTANCES_PER_FRAME) * uintptr(size_of(Instance))

    run_start := 0
    for i in 0 ..< n {
        s := batcher.submissions[batcher.sorted[i]]
        ([^]Instance)(rawptr(base_region))[i] = s.base

        is_last := i == n - 1
        next_same_mesh := !is_last &&
            batcher.submissions[batcher.sorted[i+1]].mesh.handle == s.mesh.handle
        if is_last || !next_same_mesh {
            append(&batcher.draw_commands, Draw_Command {
                mesh           = s.mesh,
                base_instance  = u32(f * MAX_INSTANCES_PER_FRAME + run_start),
                instance_count = u32(i - run_start + 1),
            })
            run_start = i + 1
        }
    }
}

// ----------------------------------------------------------------------------
// Draw
// ----------------------------------------------------------------------------

draw_all_instances :: proc(frame: Frame) {
    for cmd in _state.draw_batcher.draw_commands {
        mesh, ok := get_mesh(cmd.mesh)
        if !ok { continue }
        if cmd.instance_count == 0 { continue }

        gpu.draw_indiced_primitives(
            &_state.built_in_block,
            _state.mesh_library.index_arena.ptr,
            mesh.index_count,
            mesh.index_base,
            cmd.instance_count,
            mesh.vertex_base,
            cmd.base_instance,
        )
    }
}

// ----------------------------------------------------------------------------
// Base instance + typed entity helpers
// ----------------------------------------------------------------------------

make_instance :: proc(
    position: [3]f32,
    scale:    [3]f32,
    rotation: [3]f32,
    materials: [CONFIG.entity_max_materials]Material_Handle,
    entity_id: u32,
) -> Instance {
    inst := Instance {
        position_pack = {position.x, position.y, position.z, 0},
        scale_pack    = {scale.x,    scale.y,    scale.z,    0},
        rotation_pack = {rotation.x, rotation.y, rotation.z},
        data_offset   = 0,
        materials     = {},
        entity_id     = entity_id,
    }
    for m, i in materials {
        inst.materials[i >> 1] |= u32(m.handle) << (u32(i & 1) * 16)
    }
    return inst
}

// ============================================================================
// Frame uniforms
// ============================================================================

Engine_Uniform :: struct #all_or_none #align(16) {
    cam_perspective_transform: matrix[4, 4]f32,
    cam_ortho_transform:       matrix[4, 4]f32,
    cam_world_transform:       matrix[4, 4]f32, // entity-world → camera-view in the current shader contract
    cam_position: [3]f32,
    _pad: f32,
}
#assert(size_of(Engine_Uniform) == 208)

// ============================================================================
// Pack helpers
// ============================================================================
@(require_results)
pack_color :: proc "contextless" (value: [4]f32) -> [4]u8 {
    return [4]u8{
        u8(math.round(value[0] * 255)),
        u8(math.round(value[1] * 255)),
        u8(math.round(value[2] * 255)),
        u8(math.round(value[3] * 255)),
    }
}

// Pack RGBA into a single u32 as RGBA-ordered bytes (low byte = r).
@(require_results)
pack_color_to_u32 :: proc "contextless" (value: [4]f32) -> u32 {
    c := pack_color(value)
    return u32(c[0]) | (u32(c[1]) << 8) | (u32(c[2]) << 16) | (u32(c[3]) << 24)
}

// Pack a [2]f32 uv into a u32 (low 16 = x, high 16 = y).
@(require_results)
pack_uv_to_u32 :: proc "contextless" (uv: [2]f32) -> u32 {
    return u32(pack_float01(uv.x)) | (u32(pack_float01(uv.y)) << 16)
}

@(require_results)
pack_float01 :: proc "contextless" (value: f32) -> u16 {
    result := math.clamp(value, 0.0, 1.0)
    return u16(math.round(result * (1 << 16 - 1)))
}

