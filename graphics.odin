package nuppu

import "core:math"
import "core:mem"
import "gpu"
import "bit_array"
import "base:intrinsics"
import "base:runtime"
import "core:slice"

#assert(size_of(Vertex) == 32)
Vertex :: struct #align(16) {
    position: [3]f32,
    uv:       [2]u16,

    color:    [4]u8,
    normal:   [3]f32,
}

Vertex_Index :: u16


Mesh :: struct #all_or_none {
    vertex_count:   u32,
    index_count:    u32,
    verts:          gpu.ptr,
    indices:        gpu.ptr,
}

Built_in_mesh :: enum u32 {
    Quad,
    Cube,
}

@(require_results)
push_mesh_zeroed :: proc(
    vertex_count: u32,
    index_count: u32,
    loc := #caller_location,
) -> bit_array.Handle {

    handle := add_resource(&_state.meshes, Mesh {
        vertex_count = vertex_count,
        index_count = index_count,
        verts = gpu.arena_alloc(&_state.vertex, Vertex, uint(vertex_count)),
        indices = gpu.arena_alloc_raw(&_state.index, size_of(Vertex_Index), uint(index_count), 4)
        }, {
            name = "Mesh",
            created_at = loc,
        })
        
    return handle
}

get_built_in_mesh :: proc(built_in_mesh: Built_in_mesh) -> (^Mesh, bool) #optional_ok {
    return get_mesh(_state.built_in_meshes[built_in_mesh])
}

get_mesh :: proc(handle: bit_array.Handle) -> (^Mesh, bool) { return get_resource(&_state.meshes, handle) }

draw_sprite :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    uv_min:       [2]f32 = {0, 0},
    uv_size:      [2]f32 = {1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [2]f32 = {1, 1},
    material_idx: u32    = 0,
) {

    base_instance := Instance {
        kind = .Sprite,
        material_idx = .Default,
        extra_data = {},
    }
    sprite_instance := pack_sprite_instance(position, color, uv_min, uv_size, rotation, scale, material_idx)

    push_to_batch(sprite_batch(), base_instance, slice.bytes_from_ptr(&sprite_instance, size_of(Sprite_Instance)))
}

draw_cube :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [3]f32 = {1, 1, 1},
    material_idx: u32    = 0,
) {

    base_instance := Instance {
        kind = .Mesh,
        material_idx = .Default,
        extra_data = {},
    }

    mesh_instance := pack_mesh_instance(position, color, rotation, scale, material_idx)

    push_to_batch(mesh_batch(), base_instance, slice.bytes_from_ptr(&mesh_instance, size_of(Mesh_Instance)))
}

Instance_Kind :: enum u16 {
    Sprite = 0,
    Mesh,
}

Material_Kind :: enum u16 {
    Default = 0,
}

#assert(size_of(Instance) == 8)
Instance :: struct #align(8) {
    kind: Instance_Kind,
    material_idx: Material_Kind,

    extra_data: u32,
}


#assert(size_of(Mesh_Instance) == 32)
Mesh_Instance :: struct #all_or_none #align(16) {
    position: [3]f32,
    color:    [4]u8,

    scale: [3]u16,
    turns: [3]u8,
    material_index: u8,
    _pad: [3]u8,
}

Batcher :: struct {
    batches:              [dynamic; 32]Batch,

    instance_offset:      u32,
    instance_data_offset: u32,

    instance_bucket:      gpu.Bucket_Arena(BATCH_STAGING_BUCKETS),
    data_bucket:          gpu.Bucket_Arena(BATCH_STAGING_BUCKETS),
}

BATCH_STAGING_BUCKETS    :: 4
BATCH_STAGING_BUCKET_BYTES :: uint(1 * mem.Megabyte)

Batch :: struct {
    identifier: string,

    len: u32,
    cap: u32,
    last_len: u32,

    instances: [^]Instance,

    instance_data_size: u32,
    instance_data: [^]u8,
}

batcher_free_all :: proc(batcher: ^Batcher) {
    for &batch in batcher.batches {
        batch.len = 0
        batch.cap = 0
    }
    batcher.instance_offset      = 0
    batcher.instance_data_offset = 0
}

batch_init :: proc(identifier: string, instance_data_size: u32) -> Batch {
    return Batch {
        identifier = identifier,
        len = 0,
        cap = 0,
        last_len = 0,
        instances = nil,
        instance_data_size = instance_data_size,
        instance_data = nil,
    }
}

// Stage a single batch into the bucket arenas.
//
// IMPORTANT: call this BEFORE `nuppu.batches_finish()`. Calling it after,
// in the same frame, will — on Metal — overwrite staging memory that the
// recorded blit hasn't yet read from (Metal `blitCommandEncoder` reads its
// source at submit-time, not queue-time). The assumed-per-frame shape is:
//
//     flush(...)           // any number of times
//     flush(...)
//     batches_finish()     // closes & copies this frame's chunks
//     ...rendering...      // no flush() calls in here
//     end_frame()          // command buffer submits; blit reads staged data
//
// On WGPU this is enforced by `kick_remap` keeping buckets `.Locked` until
// the remap callback fires; on Metal the convention is unenforced.

flush :: proc(batch: ^Batch) {
    if batch.len == 0 { return }

    i_view := gpu.bucket_arena_alloc(
        &_state.batcher.instance_bucket,
        size_of(Instance), uint(batch.len), align_of(Instance),
    )
    i_size := gpu._capacity(i_view)
    d_view := gpu.bucket_arena_alloc(
        &_state.batcher.data_bucket,
        uint(batch.instance_data_size), uint(batch.len), uint(batch.instance_data_size),
    )
    d_size := gpu._capacity(d_view)

    intrinsics.mem_copy_non_overlapping(i_view.cpu, batch.instances, i_size)
    intrinsics.mem_copy_non_overlapping(d_view.cpu, batch.instance_data, d_size)

    _state.batcher.instance_offset      += u32(i_size)
    _state.batcher.instance_data_offset += u32(d_size)

    batch.len = 0
}

// Commit every chunk this frame's `flush()` calls staged to the GPU:
//   1. `_finish` both bucket arenas (unmap written chunks; they land in
//      `dirty`).
//   2. For each dirty chunk, gpu.copy its region into the global GPU
//      storage buffer starting at offset 0. A single batch can have
//      spilled across N chunks, so we copy each chunk independently and
//      advance a local running offset by `chunk.cursor` bytes.
//   3. Move each dirty chunk into `locked` (past frames, awaiting
//      remap), then `recall` both arenas — kicks the async remap on
//      WGPU; no-op on Metal.
//
// No `flush` calls should happen after this in the same frame; see `flush`.

batches_finish :: proc() {
    gpu.bucket_arena_finish(&_state.batcher.instance_bucket)
    gpu.bucket_arena_finish(&_state.batcher.data_bucket)

    // Per-frame GPU-side offsets start at 0; chunks are copied contiguously.
    inst_off: u32
    data_off: u32

    for &bucket in _state.batcher.instance_bucket.buckets {
        if bucket.state != .Unmapped { continue }
        view := gpu.sub_alloc(bucket.buffer, 0, bucket.cursor)
        gpu.copy(instances(), view, inst_off)
        inst_off += u32(bucket.cursor)
        bucket.state = .Locked
    }

    for &bucket in _state.batcher.data_bucket.buckets {
        if bucket.state != .Unmapped { continue }
        view := gpu.sub_alloc(bucket.buffer, 0, bucket.cursor)
        gpu.copy(instances_data(), view, data_off)
        data_off += u32(bucket.cursor)
        bucket.state = .Locked
    }

    gpu.bucket_arena_recall(&_state.batcher.instance_bucket)
    gpu.bucket_arena_recall(&_state.batcher.data_bucket)

    // Reset per-frame tallies so `flush` starts from 0 next frame.
    _state.batcher.instance_offset      = 0
    _state.batcher.instance_data_offset = 0
}



// Single source of truth: _state.batcher.batches holds the batches by value.
// Helpers return pointers to the slots populated in _ready_up so call sites
// don't need to know the storage order.
sprite_batch :: proc() -> ^Batch {
    return &_state.batcher.batches[0]
}

mesh_batch :: proc() -> ^Batch {
    return &_state.batcher.batches[1]
}

push_to_batch :: proc(batch: ^Batch, instance: Instance, instance_data: []u8) {
    if batch.len >= batch.cap {
        batch.cap = math.max(batch.last_len + 64, batch.cap * 2)
        
        instances := make([^]Instance, len = batch.cap, allocator = context.temp_allocator)
        instance_data := make([^]u8, len = batch.cap * batch.instance_data_size, allocator = context.temp_allocator)
        
        if batch.len > 0 {
            intrinsics.mem_copy_non_overlapping(rawptr(instance_data), batch.instance_data, batch.instance_data_size * batch.len)
            intrinsics.mem_copy_non_overlapping(rawptr(instances), batch.instances, size_of(Instance) * batch.len)
        }

        batch.instances = instances
        batch.instance_data = instance_data
    }
    
    batch.instances[batch.len] = instance
    intrinsics.mem_copy_non_overlapping(
        &batch.instance_data[batch.len * batch.instance_data_size],
        &instance_data[0],
        batch.instance_data_size,
    )
    batch.len += 1
    batch.last_len = max(batch.last_len, batch.len)
}

draw_mesh_builtin :: proc(mesh_type: Built_in_mesh, instance_count: u32 = 1, base_instance: u32 = 0) {

    mesh := get_built_in_mesh(mesh_type)

    base_vertex := u32(mesh.verts.offset / size_of(Vertex))
    first_index := u32(mesh.indices.offset / size_of(Vertex_Index))

    _state.built_in_block.read_resources[0] = _state.vertex.ptr //mesh.verts

    gpu.draw_indiced_primitives(
        &_state.built_in_block,
        _state.index.ptr,
        mesh.index_count,
        first_index,
        instance_count,
        base_vertex,
        base_instance
    )
}

draw_mesh_ex :: proc(mesh: ^Mesh, parameter_block: ^gpu.Parameter_Block, instance_count: u32) {
    base_vertex := u32(mesh.verts.offset / size_of(Vertex))
    first_index := u32(mesh.indices.offset / size_of(Vertex_Index))
    base_instance :u32= 0

    gpu.draw_indiced_primitives(
        parameter_block,
        _state.index.ptr,
        mesh.index_count,
        first_index,
        instance_count,
        base_vertex,
        base_instance
    )
}

create_built_in_meshes :: proc() {
    
    {
        // Quad
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

        upload := gpu.arena_init()
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
        // Cube
        s :: 0.5
        VERTEX_COUNT :: 24
        INDEX_COUNT :: 36
        v := [VERTEX_COUNT]Vertex {
            // Front (+Z)
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 0, 1 } ),

            // Right (+X)
            pack_vertex( position = { +s, -s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 0, 1 } ),

            // Back (-Z)
            pack_vertex( position = { +s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { -s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 0, 1 } ),

            // Left (-X)
            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { -s, +s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 } ),

            // Top (+Y)
            pack_vertex( position = { -s, +s, +s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, +s, +s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, +s, -s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, +s, -s }, uv = { 0, 1 } ),

            // Bottom (-Y)
            pack_vertex( position = { -s, -s, -s }, uv = { 0, 0 } ),
            pack_vertex( position = { +s, -s, -s }, uv = { 1, 0 } ),
            pack_vertex( position = { +s, -s, +s }, uv = { 1, 1 } ),
            pack_vertex( position = { -s, -s, +s }, uv = { 0, 1 } ),
        }

        i := [INDEX_COUNT]Vertex_Index {
            0,  1,  2,  2,  3,  0,    /* front  */
            4,  5,  6,  6,  7,  4,    /* right  */
            8,  9, 10, 10, 11,  8,    /* back   */
            12, 13, 14, 14, 15, 12,   /* left   */
            16, 17, 18, 18, 19, 16,   /* top    */
            20, 21, 22, 22, 23, 20,   /* bottom */
        }

        upload := gpu.arena_init()
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

/////////////////////////////////////////////////////

#assert(size_of(Engine_Uniform) == 208)
Engine_Uniform :: struct #all_or_none #align(16) {
    cam_perspective_transform: matrix[4, 4]f32,
    cam_ortho_transform: matrix[4, 4]f32,
    cam_view_transform: matrix[4, 4]f32,
    cam_position: [3]f32,
    _pad: f32,
}

SCALE_MAX :: 100.0

#assert(size_of(Sprite_Instance) == 32)
Sprite_Instance :: struct #all_or_none #align(16) {
    position: [3]f32,
    color:    [4]u8,
    // [4]f32

    uv_min: [2]u16,
    uv_size: [2]u16,
    // [2]f32

    scale: [2]u16,
    turns: [3]u8,
    material_index: u8,
}

#assert(size_of(Material) == 8)
Material :: struct {
    id: u16,
    user_data_1: u16,
    user_data_2: u32,
}

pack_mesh_instance :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [3]f32 = {1, 1, 1},
    material_idx: u32    = 0,
) -> Mesh_Instance {
    assert(material_idx < u32(max(u8) - 1))

    return Mesh_Instance {
        position = position,
        color    = pack_color(color),
        scale    = { pack_scale_f32(scale.x), pack_scale_f32(scale.y), pack_scale_f32(scale.z) },
        turns    = {
            pack_radians_turn(rotation.x),
            pack_radians_turn(rotation.y),
            pack_radians_turn(rotation.z),
        },
        material_index = u8(material_idx),
        _pad = {},
    }
} 

pack_sprite_instance :: proc(
    position:     [3]f32,
    color:        [4]f32 = {1, 1, 1, 1},
    uv_min:       [2]f32 = {0, 0},
    uv_size:      [2]f32 = {1, 1},
    rotation:     [3]f32 = {0, 0, 0},
    scale:        [2]f32 = {1, 1},
    material_idx: u32    = 0,
) -> Sprite_Instance {
    assert(material_idx < u32(max(u8) - 1))
    
    return Sprite_Instance {
        position = position,
        color    = pack_color(color),
        uv_min   = { pack_float01(uv_min.x), pack_float01(uv_min.y) },
        uv_size  = { pack_float01(uv_size.x), pack_float01(uv_size.y) },
        scale    = { pack_scale_f32(scale.x), pack_scale_f32(scale.y) },
        turns    = {
            pack_radians_turn(rotation.x),
            pack_radians_turn(rotation.y),
            pack_radians_turn(rotation.z),
        },
        material_index = u8(material_idx),
    }
}

pack_color :: proc(value: [4]f32) -> [4]u8 {
    return [4]u8{
        u8(math.round(value[0] * 255)),
        u8(math.round(value[1] * 255)),
        u8(math.round(value[2] * 255)),
        u8(math.round(value[3] * 255)),
    }
}

pack_scale_f32 :: proc(value: f32) -> u16 {
    c := math.clamp(value, 0.0, SCALE_MAX)
    return u16(math.round(c / SCALE_MAX * 65535))
}

pack_radians_turn :: proc(radians: f32) -> u8 {
    turns := math.mod(radians / (2 * math.PI), 1.0)
    if turns < 0 do turns += 1.0
    return u8(math.round(turns * 255))
}

/////////////////////////////////////////////////////

pack_float01 :: proc(value: f32) -> u16 {
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