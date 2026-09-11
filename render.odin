package nuppu

import "core:math"
import "core:mem"
import "gpu"
import "bit_array"
import "base:intrinsics"
import "base:runtime"
import "core:slice"
import "core:log"
import glm "core:math/linalg/glsl"

#assert(size_of(GPU_Material) == 8)
GPU_Material :: struct #align(8) {
    idx: u16, // this
    user_data_1: u16,
    param_offset: u32, // into global material parameter buffer
}

CPU_Material :: struct {
    paramater_type: typeid,
    instance_type: typeid,
    pipeline: gpu.Pipeline,
}

Material_Library :: struct {
    top: int,
    parameter_buffer: gpu.Arena,
}






#assert(size_of(Vertex) == 32)
Vertex :: struct #align(16) {
    position: [3]f32,
    uv:       [2]u16,
    color:    [4]u8,
    normal:   [3]f32,
}

Vertex_Index :: u16

Mesh :: struct #all_or_none {
    vertex_count: u32,
    index_count:  u32,
    vertex_base:  u32, // offset into the global buffer 
    index_base:   u32, // offset into the global buffer
    verts:        gpu.ptr, // view into global
    indices:      gpu.ptr, // view into global
}

Built_in_mesh :: enum u32 {
    Quad,
    Cube,
}

Built_in_texture :: enum u32 {
    Depth,
    Swapchain,
}

@(require_results)
push_mesh_zeroed :: proc(
    vertex_count: u32,
    index_count: u32,
    loc := #caller_location,
) -> Mesh_Handle {
    verts_view   := gpu.arena_alloc(&_state.g_vertex, Vertex, uint(vertex_count))
    indices_view := gpu.arena_alloc_raw(&_state.g_index, size_of(Vertex_Index), uint(index_count), 4)

    handle := add_resource(&_state.meshes, Mesh {
        vertex_count = vertex_count,
        index_count  = index_count,
        vertex_base  = verts_view.byte_offset / size_of(Vertex),
        index_base   = indices_view.byte_offset / size_of(Vertex_Index),
        verts        = verts_view,
        indices      = indices_view,
    })

    return handle
}

get_built_in_mesh :: proc(built_in_mesh: Built_in_mesh) -> (^Mesh, bool) #optional_ok {
    return get_mesh(_state.built_in_meshes[built_in_mesh])
}

built_in_mesh_handle :: proc(built_in_mesh: Built_in_mesh) -> Mesh_Handle {
    return _state.built_in_meshes[built_in_mesh]
}

get_mesh :: proc(handle: Mesh_Handle) -> (^Mesh, bool) #optional_ok {
    return get_resource(&_state.meshes, handle)
}

// ============================================================================
// Instance layout
//
// Base Instance lives in the gpu instance_base_buffer and holds the bits every
// kind needs: pos/scale/rot, the instance variant, material_idx, and an offset
// into the gpu instance_data blob where the per-kind payload lives.
//
// Instance payloads (Sprite_Instance / Mesh_Instance / ...) live in the gpu
// instance_data blob. Their layout is consumed by the shader — see the WGSL /
// Metal files in examples/AppleLearnCPP/3-Instancing_camera/.
//
// The batcher is type-erased: it only knows (typeid, size) per registered
// instance type and treats payloads as opaque bytes.
// ============================================================================

#assert(size_of(Instance) == 64)
Instance :: struct #all_or_none #align(16) {
    position_pack:   [4]f32,  // xyz = position
    scale_pack:      [4]f32,  // xyz = scale
    rotation_pack:   [4]f32,  // xyz = rotation
    offset_kind_mat: [4]u32,  // x = payload byte offset, y = variant | (material<<16), zw unused
}

#assert(size_of(Sprite_Instance) == 16)
Sprite_Instance :: struct #all_or_none #align(16) {
    // x = color packed u32, y = uv_min packed u32, z = uv_size packed u32, w unused
    color_uv_min_size: [4]u32,
}

#assert(size_of(Mesh_Instance) == 16)
Mesh_Instance :: struct #all_or_none #align(16) {
    // x = color packed u32, yzw unused
    color_pad: [4]u32,
}

INSTANCE_DATA_ALIGNMENT :: 16
MAX_INSTANCES_PER_FRAME  :: 1 << 16
INSTANCE_DATA_BYTES_PER_FRAME :: 16 * mem.Megabyte

// ============================================================================
// Draw batcher
//
// Pipeline:
//   submit (entity packers + explicit submit_instance)
//     -> flat Submission list + payload_blob
//   cull(frame): frustum-test + compact
//   finish_instance_upload(frame): sort by (variant, mesh, material), write into
//     the frame region of the two gpu blobs, emit Draw_Command runs
//   draw_all_instances(frame): one draw per run
// ============================================================================

Submission :: struct {
    base:           Instance,
    variant_idx:    u16,
    mesh:           Mesh_Handle,
    payload_offset: u32, // into payload_blob
    payload_size:   u32,
}

Draw_Command :: struct {
    variant_idx:    u16,
    mesh:           Mesh_Handle,
    base_instance:  u32, // index into instance_base_buffer
    instance_count: u32,
}

// Type-erased packer: `pack` is the user's `proc(e: ^E) -> I`, `out` receives
// the payload bytes.
Entity_Packer :: #type proc(pack: rawptr, variant_data: rawptr, out: rawptr)

Entity_Draw_Binding :: struct {
    inst_idx:   int,
    pack:       rawptr,
    trampoline: Entity_Packer,
}

Draw_Batcher :: struct {
    instance_types:  [dynamic]typeid,
    instance_sizes:  [dynamic]int,
    entity_bindings: [dynamic]Entity_Draw_Binding, // parallel to entity manager variants

    submissions:     [dynamic]Submission,
    payload_blob:    [dynamic]u8, // CPU side transient store for payloads
    sorted:          [dynamic]int,
    draw_commands:   [dynamic]Draw_Command,

    instance_base_buffer: gpu.ptr,
    instance_data_buffer: gpu.ptr,

    allocator: runtime.Allocator,
    is_init:   bool,
}

init_draw_batcher :: proc(batcher: ^Draw_Batcher, allocator := context.allocator) {
    if batcher.is_init { return }
    batcher.is_init   = true
    batcher.allocator = allocator

    INITIAL_CAP :: 16
    batcher.instance_types  = make([dynamic]typeid, 0, INITIAL_CAP, allocator)
    batcher.instance_sizes  = make([dynamic]int,    0, INITIAL_CAP, allocator)
    batcher.entity_bindings = make([dynamic]Entity_Draw_Binding, 0, INITIAL_CAP, allocator)
    batcher.submissions     = make([dynamic]Submission,          0, INITIAL_CAP, allocator)
    batcher.payload_blob    = make([dynamic]u8,                  0, INSTANCE_DATA_BYTES_PER_FRAME, allocator)
    batcher.sorted          = make([dynamic]int,                 0, INITIAL_CAP, allocator)
    batcher.draw_commands   = make([dynamic]Draw_Command,        0, INITIAL_CAP, allocator)

    base_bytes := u32(MAX_INSTANCES_PER_FRAME * FRAMES_IN_FLIGHT * size_of(Instance))
    data_bytes := u32(INSTANCE_DATA_BYTES_PER_FRAME * FRAMES_IN_FLIGHT)

    base_ptr, base_ok := gpu.malloc(base_bytes, align_of(Instance), .Staging, "Instance Base Staging")
    assert(base_ok, "draw_batcher: failed to alloc instance base buffer")
    batcher.instance_base_buffer = base_ptr

    data_ptr, data_ok := gpu.malloc(data_bytes, INSTANCE_DATA_ALIGNMENT, .Staging, "Instance Data Staging")
    assert(data_ok, "draw_batcher: failed to alloc instance data buffer")
    batcher.instance_data_buffer = data_ptr
}

// Registers a payload type. The batcher treats it as opaque bytes of size_of(I).
// The returned index is the instance variant written to offset_kind_mat.y.
register_instance_type :: proc($T: typeid) -> int {
    batcher := &_state.draw_batcher
    for inst_T, i in batcher.instance_types {
        if inst_T == T { return i }
    }
    assert(align_of(T) % 4 == 0, "register_instance_type: payload must be 4-byte aligned")
    assert(size_of(T)  % 4 == 0, "register_instance_type: payload size must be a multiple of 4")
    append(&batcher.instance_types, T)
    append(&batcher.instance_sizes, size_of(T))
    return len(batcher.instance_types) - 1
}

@(private="file")
_instance_idx :: proc(batcher: ^Draw_Batcher, $I: typeid) -> int {
    for t, i in batcher.instance_types {
        if t == I { return i }
    }
    panic("draw_batcher: instance type not registered")
}

// Generates the plain (non-closure) trampoline for a typed packer. `pack` is
// passed through as a rawptr and cast back, the same idiom core:slice uses.
@(private="file")
_packer_for :: proc($E: typeid, $I: typeid) -> Entity_Packer {

}

// Maps entity variant E -> instance payload I with a typed packer. The base
// Instance is derived from the shared Entity; the packer only produces payload.
// The entity type must already be registered in the entity manager and flagged
// with .Has_Mesh; otherwise this logs an error and does nothing.
register_entity_to_instance_mapping :: proc(
    $E: typeid,
    $I: typeid,
    pack_proc: proc(e: ^E) -> I,
) {
    em := _state.entity_manager

    found: bool
    entity_idx, instance_idx: int
    
    entity_idx, found = slice.linear_search(em.types[:], E)
    if !found {
        log.errorf("register_drawable: entity type %v is not registered in the entity manager", typeid_of(E))
        return
    }
    if .Has_Mesh not_in em.flags[entity_idx] {
        log.errorf("register_drawable: entity type %v does not have the .Has_Mesh flag", typeid_of(E))
        return
    }

    batcher := &_state.draw_batcher
    instance_idx, found = slice.linear_search(batcher.instance_types[:], I)
    if !found {
        log.errorf("register_entity_to_instance_mapping: instance type %v is not registered in the draw batcher", typeid_of(I))
        return
    }

    // Make sure we have same amount of entity bindings as 
    // entity manager has registered types.
    // Currently registering even if that entity doesnt have .Has_Mesh flag
    delta := len(em.variants) - len(batcher.entity_bindings)
    for _ in 0 ..< delta {
        append(&batcher.entity_bindings, Entity_Draw_Binding{})
    }

    batcher.entity_bindings[entity_idx] = Entity_Draw_Binding {
        inst_idx   = instance_idx,
        pack       = rawptr(pack_proc),
        trampoline = proc(pack_proc: rawptr, variant_data: rawptr, out: rawptr) {
            f := cast(proc(e: ^E) -> I)pack_proc
            (cast(^I)out)^ = f(cast(^E)variant_data)
        },
    }
}

// ----------------------------------------------------------------------------
// Submission
// ----------------------------------------------------------------------------

// Explicit submission path. `payload`'s type selects the registered instance
// variant; the base's payload offset, variant and material are filled in by the
// batcher. Uses the global batcher.
submit_instance :: proc(mesh: Mesh_Handle, material: u16, base: Instance, payload: $I) {
    batcher := &_state.draw_batcher
    idx := _instance_idx(batcher, I)
    _submit(batcher, mesh, material, base, u16(idx), _value_bytes(&payload))
}

@(private="file")
_value_bytes :: proc(v: ^$T) -> []u8 {
    return ([^]u8)(rawptr(v))[:size_of(T)]
}

@(private="file")
_submit :: proc(
    batcher: ^Draw_Batcher,
    mesh: Mesh_Handle,
    base: Instance,
    variant_idx: u16,
    payload: []u8,
) {
    size := batcher.instance_sizes[variant_idx]
    assert(len(payload) == size, "submit_instance: payload size mismatch")

    off, dst := _reserve_payload(batcher, size)
    if len(dst) > 0 {
        mem.copy(raw_data(dst), raw_data(payload), len(dst))
    }
    _append_submission(batcher, base, variant_idx, mesh, off, u32(size))
}

_reserve_payload :: proc(batcher: ^Draw_Batcher, size: int) -> (off: u32, dst: []u8) {
    off_i := int(mem.align_forward_uint(uint(len(batcher.payload_blob)), INSTANCE_DATA_ALIGNMENT))
    if off_i + size > INSTANCE_DATA_BYTES_PER_FRAME {
        // NOTE: grow+copy point. Realloc instance_data_buffer and update
        // _state.built_in_block.read_resources[2] when this becomes dynamic.
        panic("draw_batcher: instance data capacity exceeded")
    }
    resize(&batcher.payload_blob, off_i + size) // bump len so slice works. fix later
    return u32(off_i), batcher.payload_blob[off_i:off_i + size]
}

_append_submission :: proc(
    batcher: ^Draw_Batcher,
    base: Instance,
    variant_idx: u16,
    mesh: Mesh_Handle,
    off: u32,
    size: u32,
) {
    if len(batcher.submissions) >= MAX_INSTANCES_PER_FRAME {
        // NOTE: grow+copy point. Realloc instance_base_buffer and update
        // _state.built_in_block.read_resources[1] when this becomes dynamic.
        panic("draw_batcher: max instances per frame exceeded")
    }

    b := base
    b.offset_kind_mat[1] = u32(variant_idx)
    append(&batcher.submissions, Submission {
        base           = b,
        variant_idx    = variant_idx,
        mesh           = mesh,
        payload_offset = off,
        payload_size   = size,
    })
}

batcher_reset :: proc(frame: Frame, batcher: ^Draw_Batcher) {
    clear(&batcher.submissions)
    clear(&batcher.payload_blob)
    clear(&batcher.draw_commands)
}

// ----------------------------------------------------------------------------
// Entity gather
// ----------------------------------------------------------------------------

_gather_entity_submissions :: proc(batcher: ^Draw_Batcher, em: ^Entity_Manager) {
    delta := len(em.variants) - len(batcher.entity_bindings)
    for _ in 0 ..< delta {
        append(&batcher.entity_bindings, Entity_Draw_Binding{})
    }

    // Only walk entities with .Has_Mesh flag
    ent_idx_with_mesh := make([dynamic]int, allocator = context.temp_allocator)
    for f, I in em.flags {
        if .Has_Mesh in f {
            append(&ent_idx_with_mesh, I)
        }
    }

    for v in ent_idx_with_mesh {
        binding := batcher.entity_bindings[v]
        assert(binding.trampoline != nil)

        size := batcher.instance_sizes[binding.inst_idx]
        iter := Entity_Iterator {
            manager     = em,
            variant_idx = ENTITY_VARIANT(v),
        }

        for entity, variant_data in _iter_next_slot(&iter) {
            if entity.mesh.handle == bit_array.NIL_HANDLE { continue }

            off, dst := _reserve_payload(batcher, size)
            binding.trampoline(binding.pack, variant_data, rawptr(raw_data(dst)))

            base := make_base_instance(entity.position, entity.scale, entity.rotation)
            _append_submission(
                batcher, base, u16(binding.inst_idx), entity.mesh,
                off, u32(size),
            )
        }
    }
}

// ----------------------------------------------------------------------------
// Frustum culling
// ----------------------------------------------------------------------------

Frustum :: [6][4]f32

@(private="file")
_camera_view_proj :: proc() -> (vp: matrix[4,4]f32, ok: bool) {
    cam, cok := entity_get_typed(_state.entity_manager, _state.main_camera, Camera)
    if !cok { return {}, false }
    perspective := glm.mat4Perspective(glm.radians_f32(cam.fovy), cam.aspect_ratio, cam.near, cam.far)
    world       := glm.mat4Translate(-cam.position)
    return perspective * world, true
}

// Gribb–Hartmann plane extraction. `m` maps world -> clip for column vectors
// (clip = m * world); Odin's m[i, j] is row i, column j.
@(private="file")
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

@(private="file")
_add4 :: proc(a, b: [4]f32) -> [4]f32 { return {a[0]+b[0], a[1]+b[1], a[2]+b[2], a[3]+b[3]} }
@(private="file")
_sub4 :: proc(a, b: [4]f32) -> [4]f32 { return {a[0]-b[0], a[1]-b[1], a[2]-b[2], a[3]-b[3]} }

@(private="file")
_normalize_plane :: proc(p: [4]f32) -> [4]f32 {
    n := math.sqrt(p[0]*p[0] + p[1]*p[1] + p[2]*p[2])
    if n == 0 { return p }
    return {p[0]/n, p[1]/n, p[2]/n, p[3]/n}
}

@(private="file")
_sphere_in_frustum :: proc(planes: Frustum, center: [3]f32, radius: f32) -> bool {
    for p in planes {
        d := p[0]*center.x + p[1]*center.y + p[2]*center.z + p[3]
        if d < -radius { return false }
    }
    return true
}

@(private="file")
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

@(private="file")
_submission_index_less :: proc(a, b: int, user: rawptr) -> bool {
    s := (^Draw_Batcher)(user)
    x := &s.submissions[a]
    y := &s.submissions[b]
    if x.variant_idx != y.variant_idx { return x.variant_idx < y.variant_idx }
    return x.mesh.handle < y.mesh.handle
}

@(private="file")
_same_key :: proc(a, b: ^Submission) -> bool {
    return a.variant_idx == b.variant_idx &&
           a.mesh.handle == b.mesh.handle
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
    data_region := uintptr(batcher.instance_data_buffer.cpu) +
        uintptr(f) * uintptr(INSTANCE_DATA_BYTES_PER_FRAME)

    write_cursor := 0
    run_start := 0
    for i in 0 ..< n {
        s := &batcher.submissions[batcher.sorted[i]]

        write_cursor = int(mem.align_forward_uint(uint(write_cursor), INSTANCE_DATA_ALIGNMENT))
        if write_cursor + int(s.payload_size) > INSTANCE_DATA_BYTES_PER_FRAME {
            panic("draw_batcher: instance data capacity exceeded during upload")
        }
        // offset_kind_mat[0] is read by the shader from the base of the whole
        // data buffer, so it must include this frame's region offset.
        s.base.offset_kind_mat[0] = u32(uintptr(f)*uintptr(INSTANCE_DATA_BYTES_PER_FRAME) + uintptr(write_cursor))

        ([^]Instance)(rawptr(base_region))[i] = s.base
        if s.payload_size > 0 {
            mem.copy(
                rawptr(data_region + uintptr(write_cursor)),
                rawptr(&batcher.payload_blob[s.payload_offset]),
                int(s.payload_size),
            )
        }
        write_cursor += int(s.payload_size)

        is_last := i == n - 1
        if is_last || !_same_key(&batcher.submissions[batcher.sorted[i]], &batcher.submissions[batcher.sorted[i+1]]) {
            first := &batcher.submissions[batcher.sorted[run_start]]
            append(&batcher.draw_commands, Draw_Command {
                variant_idx    = first.variant_idx,
                mesh           = first.mesh,
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
            _state.g_index.ptr,
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

make_base_instance :: proc(
    position: [3]f32,
    scale:    [3]f32,
    rotation: [3]f32,
) -> Instance {
    return Instance {
        position_pack = {position.x, position.y, position.z, 0},
        scale_pack    = {scale.x,    scale.y,    scale.z,    0},
        rotation_pack = {rotation.x, rotation.y, rotation.z, 0},
        offset_kind_mat = {},
    }
}

a_entity :: proc($T: typeid) -> ^T {
    handle, ok := entity_add(_state.entity_manager, T)
    if !ok { return nil }
    entity, _ := entity_get_typed(_state.entity_manager, handle, T)
    return entity
}

// ============================================================================
// Built-in meshes
// ============================================================================

create_built_in_meshes :: proc() {
    {
        s :: 0.5
        VERTEX_COUNT :: 4
        INDEX_COUNT :: 6
        v := [VERTEX_COUNT]Vertex {
            pack_vertex( position = { -s, -s, 0 }, uv = { 0.0, 0.0 } ),
            pack_vertex( position = { +s, -s, 0 }, uv = { 1.0, 0.0 } ),
            pack_vertex( position = { +s, +s, 0 }, uv = { 1.0, 1.0 } ),
            pack_vertex( position = { -s, +s, 0 }, uv = { 0.0, 1.0 } ),
        }
        i := [INDEX_COUNT]Vertex_Index {
            0, 1, 2, 2, 3, 0
        }

        upload, _ := gpu.arena_init(4 * 1024 * 1024)
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        indices := gpu.arena_alloc_raw(&upload, size_of(Vertex_Index), INDEX_COUNT, 4)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))

        quad_handle := push_mesh_zeroed(VERTEX_COUNT, INDEX_COUNT)
        _state.built_in_meshes[.Quad] = quad_handle
        quad_mesh, _ := get_resource(&_state.meshes, quad_handle)

        gpu.unmap(&upload.ptr)
        gpu.begin_commands()
        gpu.copy(quad_mesh.verts, verts)
        gpu.copy(quad_mesh.indices, indices)
        gpu.barrier(.Transfer, .All)
        gpu.commit_commands()
    }

    {
        s :: 0.5
        VERTEX_COUNT :: 24
        INDEX_COUNT :: 36
        v := [VERTEX_COUNT]Vertex {
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 0, 1 } ),

            pack_vertex( position = { +s, -s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 0, 1 } ),

            pack_vertex( position = { +s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { -s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 0, 1 } ),

            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 } ),

            pack_vertex( position = { -s, +s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 } ),

            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 1 } ),
        }

        i := [INDEX_COUNT]Vertex_Index {
              0,  1,  2,  2,  3,  0,
              4,  5,  6,  6,  7,  4,
              8,  9, 10, 10, 11,  8,
             12, 13, 14, 14, 15, 12,
             16, 17, 18, 18, 19, 16,
             20, 21, 22, 22, 23, 20,
        }

        upload, _ := gpu.arena_init(4 * 1024 * 1024)
        verts := gpu.arena_alloc(&upload, Vertex, VERTEX_COUNT)
        intrinsics.mem_copy_non_overlapping(verts.cpu, &v, size_of(v))
        indices := gpu.arena_alloc(&upload, Vertex_Index, INDEX_COUNT)
        intrinsics.mem_copy_non_overlapping(indices.cpu, &i, size_of(i))

        cube_handle := push_mesh_zeroed(VERTEX_COUNT, INDEX_COUNT)
        _state.built_in_meshes[.Cube] = cube_handle
        cube_mesh, _ := get_resource(&_state.meshes, cube_handle)

        gpu.unmap(&upload.ptr)
        gpu.begin_commands()
        gpu.copy(cube_mesh.verts, verts)
        gpu.copy(cube_mesh.indices, indices)
        gpu.barrier(.Transfer, .All)
        gpu.commit_commands()
    }
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

pack_mesh_instance :: proc(color: [4]f32 = {1, 1, 1, 1}) -> Mesh_Instance {
    return Mesh_Instance {
        color_pad = { pack_color_to_u32(color), 0, 0, 0 },
    }
}

pack_sprite_instance :: proc(
    color:   [4]f32 = {1, 1, 1, 1},
    uv_min:  [2]f32 = {0, 0},
    uv_size: [2]f32 = {1, 1},
) -> Sprite_Instance {
    return Sprite_Instance {
        color_uv_min_size = {
            pack_color_to_u32(color),
            pack_uv_to_u32(uv_min),
            pack_uv_to_u32(uv_size),
            0,
        },
    }
}

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

pack_float01 :: proc "contextless" (value: f32) -> u16 {
    result := math.clamp(value, 0.0, 1.0)
    return u16(math.round(result * (1 << 16 - 1)))
}

pack_vertex :: proc(
    position: [3]f32,
    uv:       [2]f32 = {0, 0},
    color:    [4]u8  = {255, 255, 255, 255},
    normal:   [3]f32 = {0, 1, 0},
) -> Vertex {
    return Vertex {
        position = position,
        uv =       [2]u16{pack_float01(uv.x), pack_float01(uv.y)},
        color =    color,
        normal =   normal,
    }
}
