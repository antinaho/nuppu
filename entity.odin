package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:log"
import "core:slice"

ENTITY_INDEX      :: u32
ENTITY_GENERATION :: u16
ENTITY_VARIANT    :: u16
ROOT_VARIANT_IDX  :: max(ENTITY_VARIANT)

PLATFORM_BITS :: 8*size_of(uint)
MAX_SHIFT :: PLATFORM_BITS>>1
_LOG2_PLATFORM_BITS :: intrinsics.constant_log2(PLATFORM_BITS)

CHUNK_CAP :: proc "contextless" (chunk_size: int, chunk_index: int) -> int { return chunk_size << uint(chunk_index) }
CHUNK_START :: proc "contextless" (chunk_size: int, chunk_index: int) -> int { return CHUNK_CAP(chunk_size, chunk_index) - chunk_size }
CHUNK_BITMASK_COUNT :: proc "contextless" (chunk_size: int, chunk_index: int) -> int { return chunk_size << uint(chunk_index) >> _LOG2_PLATFORM_BITS }

Entity :: struct {
    handle:       Entity_Handle, // this

    parent:       Entity_Handle,
    first_child:  Entity_Handle,
    next_sibling: Entity_Handle,
    prev_sibling: Entity_Handle,

    mesh:         Mesh_Handle,
    material_idx: u16,

    position:     [3]f32,
    prev_position:[3]f32,
    rotation:     [3]f32, // TODO: currently euler, switch to quaternion
    prev_rotation:[3]f32,
    scale:        [3]f32,
    prev_scale:   [3]f32,
}

NIL_ENTITY_HANDLE :: Entity_Handle {}

Entity_Flag  :: enum u32 {
    Interpolate,
    Has_Mesh,
}
Entity_Flags :: bit_set[Entity_Flag]

Entity_Handle :: struct {
    index:       ENTITY_INDEX,
    gen:         ENTITY_GENERATION,
    variant:     ENTITY_VARIANT,
}

// A contiguous run of slots. Chunks are never moved or freed while the
// container is alive, so &entities[i] stays valid for the element's lifetime.
//
// Occupancy is tracked with a bitmap owned by the container
Entity_Chunk :: struct {
    entities:  [^]Entity, // count base entities
    variants:  [^]byte,   // count * Entity_Data.elem_size specialization bytes
    occupied:  [^]u64,    // bitmesh: i set => slot i is live
    free_hint: int,       // first word that may contain a free bit
    live:      int,       // number of live slots
}

// One container per registered entity type. Slot 0 is a reserved sentinel.
//
// Storage is a chunked array: chunk k holds `chunk_size << k` slots and lives
// at a fixed address for the container's lifetime. The base Entity array is
// typed; the specialization data is type-erased bytes with a runtime stride.
Entity_Data :: struct {
    elem_size:  int,
    flags:      Entity_Flags,
    chunk_size: int, // power of two, >= 64
    chunk_shift:int, 

    chunks:     [dynamic]Entity_Chunk,

    len:        int, // high-water slot count (includes sentinel)
    cap:        int, // total allocated slots
    partial:    int, // lowest chunk index that has free slots; -1 = none
}

Entity_Manager :: struct
{
    types:         [dynamic]typeid,
    variants:      [dynamic]Entity_Data,

    root_data:     Entity,
    root:          Entity_Handle,
    is_init:       bool,

    allocator:     runtime.Allocator,
}

// ============================================================================
// Container internals
// ============================================================================

// Maps a global index to (chunk index, offset within chunk)
@(private="file")
_data_chunk_for :: proc "contextless" (data: ^Entity_Data, index: int) -> (ci: int, off: int) #no_bounds_check {
    j := u64(index) + u64(data.chunk_size)
    e := u64(63) - u64(intrinsics.count_leading_zeros(j))
    p := u64(1) << uint(e)
    ci  = int(e) - data.chunk_shift
    off = int(j - p)
    return
}

// Slot accessors so callers (e.g. the renderer) don't reach into chunks.
// `index` must be < data.len.
entity_data_entity :: proc "contextless" (data: ^Entity_Data, index: int) -> ^Entity #no_bounds_check {
    ci, off := _data_chunk_for(data, index)
    return &data.chunks[ci].entities[off]
}

entity_data_variant :: proc "contextless" (data: ^Entity_Data, index: int) -> rawptr #no_bounds_check {
    ci, off := _data_chunk_for(data, index)
    c := &data.chunks[ci]
    return rawptr(uintptr(c.variants) + uintptr(off * data.elem_size))
}

// Validates a handle against its container and returns the container plus the
// chunk/offset it maps to. Shared by entity_get, entity_get_typed and
// entity_remove so the validation lives in one place.
@(private="file")
_data_resolve :: proc "contextless" (manager: ^Entity_Manager, handle: Entity_Handle) -> (data: ^Entity_Data, ci: int, off: int, ok: bool) #no_bounds_check {
    if handle.index == 0 || handle.gen == 0 { return nil, 0, 0, false }
    if handle.variant >= ENTITY_VARIANT(len(manager.variants)) { return nil, 0, 0, false }

    data = &manager.variants[handle.variant]
    if handle.index >= ENTITY_INDEX(data.len) { return nil, 0, 0, false }

    ci, off = _data_chunk_for(data, int(handle.index))
    slot := &data.chunks[ci].entities[off]
    if slot.handle.gen != handle.gen { return nil, 0, 0, false }
    if slot.handle.index == 0 { return nil, 0, 0, false }
    return data, ci, off, true
}

@(private="file")
_chunk_free_slot :: proc "contextless" (c: ^Entity_Chunk, off: int) #no_bounds_check {
    w := off >> _LOG2_PLATFORM_BITS
    c.occupied[w] &~= u64(1) << uint(off & 63)
    c.live -= 1
    if w < c.free_hint {
        c.free_hint = w
    }
}

// ============================================================================
// Manager
// ============================================================================

entity_manager_init :: proc(
    manager: ^Entity_Manager,
    allocator := context.allocator
) {
    if manager.is_init { 
        log.warnf("entity_manager_init: already initialized")
        return 
    }

    manager.is_init    = true
    manager.allocator  = allocator

    INITIAL_CAPACITY :: 16
    manager.variants = make([dynamic]Entity_Data, len=0, cap=INITIAL_CAPACITY, allocator=allocator)
    manager.types    = make([dynamic]typeid, len=0, cap=INITIAL_CAPACITY, allocator=allocator)

    manager.root_data = Entity {
        parent       = NIL_ENTITY_HANDLE,
        first_child  = NIL_ENTITY_HANDLE,
        next_sibling = NIL_ENTITY_HANDLE,
        prev_sibling = NIL_ENTITY_HANDLE,
        handle = Entity_Handle {
            index       = 1,
            gen         = 1,
            variant = ROOT_VARIANT_IDX,
        },
        position = {0, 0, 0},
        scale    = {1, 1, 1},
        rotation = {0, 0, 0},
    }
    manager.root = manager.root_data.handle
}

entity_manager_add_variant :: proc(manager: ^Entity_Manager, $T: typeid, $SHIFT: uint, flags: Entity_Flags = {})
    where intrinsics.type_is_struct(T) && SHIFT >= 6 && SHIFT <= MAX_SHIFT
{
    assert(manager.is_init)

    for type in manager.types {
        if type == T {
            log.warnf("entity_manager_add_variant: type already registered")
            return
        }
    }

    size := 1 << SHIFT

    // First field of T must be a ^Entity back-pointer to its base slot.
    {
        ti  := runtime.type_info_core(type_info_of(T))^
        sti, ok := ti.variant.(runtime.Type_Info_Struct)
        if !ok {
            panic("All variants must be structs")
        }

        if sti.field_count < 1 || sti.offsets[0] != 0 || sti.types[0].id != typeid_of(^Entity) {
            panic("All variants must have a ^Entity member at offset 0")
        }
    }

    append(&manager.types, T)
    append(&manager.variants, Entity_Data {
        elem_size   = size_of(T),
        flags       = flags,
        chunk_size  = size,
        chunk_shift = int(SHIFT),
        partial     = -1,
    })

    // Reserve slot 0 as the nil sentinel.
    nil_entity_handle := entity_add(manager, T)
    assert(nil_entity_handle.index == 0)
    assert(nil_entity_handle.gen == 1)
}

entity_manager_destroy :: proc(
    manager: ^Entity_Manager,
    allocator := context.allocator,
) {
    if manager == nil { return }

    for &data in manager.variants {
        for &chunk, k in data.chunks {
            count := CHUNK_CAP(data.chunk_size, k)
            if chunk.entities != nil {
                mem.delete_slice(chunk.entities[:count], manager.allocator)
            }
            if chunk.variants != nil {
                mem.delete_slice(([^]byte)(chunk.variants)[:count * data.elem_size], manager.allocator)
            }
            if chunk.occupied != nil {
                mem.delete_slice(chunk.occupied[:CHUNK_BITMASK_COUNT(data.chunk_size, k)], manager.allocator)
            }
        }
        delete(data.chunks)
    }

    delete(manager.variants)
    delete(manager.types)
    mem.free(rawptr(manager), allocator)
}

@(require_results)
entity_add :: proc (
    manager: ^Entity_Manager,
    $T: typeid
) -> (Entity_Handle, bool) #optional_ok #no_bounds_check
{
    assert_contextless(manager.is_init)

    variant_idx, found := slice.linear_search(manager.types[:], T)
    assert_contextless(found, "entity_add: type not registered")

    data := &manager.variants[variant_idx]

    if data.partial < 0 {
        idx   := len(data.chunks)
        cap   := CHUNK_CAP(data.chunk_size, idx)
        masks := CHUNK_BITMASK_COUNT(data.chunk_size, idx)

        e_buf, _ := runtime.make_aligned([]Entity, cap, alignment=4096, allocator=manager.allocator)
        v_buf, _ := runtime.make_aligned([]byte, cap * data.elem_size, alignment=4096, allocator=manager.allocator)
        o_buf, _ := runtime.make_aligned([]u64, masks, alignment=4096, allocator=manager.allocator)
        assert(e_buf != nil && v_buf != nil && o_buf != nil, "_data_append_chunk: allocation failed")

        intrinsics.mem_zero(raw_data(e_buf), cap * size_of(Entity))
        intrinsics.mem_zero(raw_data(v_buf), cap * data.elem_size)
        intrinsics.mem_zero(raw_data(o_buf), masks * size_of(u64))

        append(&data.chunks, Entity_Chunk {
            entities  = raw_data(e_buf),
            variants  = raw_data(v_buf),
            occupied  = raw_data(o_buf),
            free_hint = 0,
            live      = 0,
        })
        data.cap += cap
        
        data.partial = len(data.chunks) - 1
    }

    ci := data.partial
    c  := &data.chunks[ci]
    
    index_within_chunk := -1
    for c.free_hint < CHUNK_BITMASK_COUNT(data.chunk_size, ci) {
        w := c.free_hint
        word := c.occupied[w]
        if word == ~u64(0) { // Skip full mask
            c.free_hint += 1
            continue
        }
        bit := int(intrinsics.count_trailing_zeros(~word))
        c.occupied[w] |= u64(1) << uint(bit)
        c.live += 1
        if c.occupied[w] == ~u64(0) {
            c.free_hint += 1
        }
        index_within_chunk = w * 64 + bit
        break
    }

    assert(index_within_chunk >= 0, "entity_add: partial chunk had no free slot")
    index := CHUNK_START(data.chunk_size, ci) + index_within_chunk

    if c.live == data.chunk_size << uint(ci) {
        // Chunk is full; advance to the next chunk that still has holes.
        data.partial = -1
        for j := ci + 1; j < len(data.chunks); j += 1 {
            if data.chunks[j].live < data.chunk_size << uint(j) {
                data.partial = j
                break
            }
        }
    }

    if index == data.len {
        data.len += 1
    }

    entity_ptr  := &c.entities[index_within_chunk]
    variant_ptr := rawptr(uintptr(c.variants) + uintptr(index_within_chunk * data.elem_size))

    prev_gen := entity_ptr.handle.gen

    intrinsics.mem_zero(rawptr(entity_ptr), size_of(Entity))
    intrinsics.mem_zero(variant_ptr, data.elem_size)

    entity_ptr.handle = {
        index       = ENTITY_INDEX(index),
        gen         = prev_gen == 0 ? 1 : prev_gen,
        variant     = ENTITY_VARIANT(variant_idx),
    }

    (^rawptr)(variant_ptr)^ = rawptr(entity_ptr)

    if entity_ptr.handle != manager.root {
        child_add(manager, manager.root, entity_ptr.handle)
    }

    return entity_ptr.handle, true
}

@(require_results)
entity_get :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle
) -> (^Entity, bool) #optional_ok #no_bounds_check {
    assert_contextless(manager.is_init)

    if handle.variant == ROOT_VARIANT_IDX {
        return &manager.root_data, true
    }

    data, ci, off, ok := _data_resolve(manager, handle)
    if !ok { return nil, false }
    return &data.chunks[ci].entities[off], true
}

@(require_results)
entity_get_typed :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle,
    $T: typeid,
) -> (^T, bool) #optional_ok #no_bounds_check {
    assert_contextless(manager.is_init)

    if handle.variant == ROOT_VARIANT_IDX {
        return {}, false
    }

    if manager.types[handle.variant] != T { return nil, false }
    
    data, ci, off, ok := _data_resolve(manager, handle)
    if !ok { return nil, false }

    c := &data.chunks[ci]
    return (^T)(rawptr(uintptr(c.variants) + uintptr(off * data.elem_size))), true
}

entity_remove :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle,
) -> bool #no_bounds_check {
    assert_contextless(manager.is_init)

    if handle == manager.root { return false }

    data, ci, off, ok := _data_resolve(manager, handle)
    if !ok { return false }

    c := &data.chunks[ci]
    slot := &c.entities[off]

    if slot.parent != NIL_ENTITY_HANDLE {
        _unlink_from_circle(manager, handle)
    }

    was_full := c.live == data.chunk_size << uint(ci)
    _chunk_free_slot(c, off)

    slot.handle.gen += 1
    slot.handle.index = 0

    // Prefer reusing the earliest chunk that has holes.
    if was_full && (data.partial == -1 || ci < data.partial) {
        data.partial = ci
    }

    return true
}

// ============================================================================
// Iterators
// ============================================================================

Entity_Iterator :: struct {
    manager:     ^Entity_Manager,
    variant_idx: ENTITY_VARIANT,
    chunk_idx:   int,
    offset:      int,
}

entity_iterator_init :: proc(
    manager: ^Entity_Manager,
    $T: typeid,
) -> Entity_Iterator {
    assert_contextless(manager.is_init)
    variant_idx, found := _linear_search_variant(manager, T)
    assert_contextless(found, "entity_iterator_init: type not registered")
    return Entity_Iterator {
        manager     = manager,
        variant_idx = ENTITY_VARIANT(variant_idx),
    }
}

// Walks chunks linearly and returns both slot views for the current position.
@(private="file")
_iter_next_slot :: proc "contextless" (iter: ^Entity_Iterator) -> (entity: ^Entity, variant: rawptr, ok: bool) #no_bounds_check {
    data := &iter.manager.variants[iter.variant_idx]

    for iter.chunk_idx < len(data.chunks) {
        c     := &data.chunks[iter.chunk_idx]
        count := CHUNK_CAP(data.chunk_size, iter.chunk_idx)
        start := CHUNK_START(data.chunk_size, iter.chunk_idx)
        for iter.offset < count {
            index := start + iter.offset
            off   := iter.offset
            iter.offset += 1

            if index >= data.len {
                return nil, nil, false
            }
            return &c.entities[off], rawptr(uintptr(c.variants) + uintptr(off * data.elem_size)), true
        }
        iter.chunk_idx += 1
        iter.offset = 0
    }
    return nil, nil, false
}

entity_variant_iterator_next :: proc "contextless" (iter: ^Entity_Iterator, $T: typeid) -> (^T, Entity_Handle, bool) #no_bounds_check {
    for {
        entity, variant, ok := _iter_next_slot(iter)
        if !ok { return nil, NIL_ENTITY_HANDLE, false }
        if entity.handle.index == 0 { continue }
        return (^T)(variant), entity.handle, true
    }
}

entity_iterator_next :: proc "contextless" (iter: ^Entity_Iterator) -> (^Entity, Entity_Handle, bool) #no_bounds_check {
    for {
        entity, _, ok := _iter_next_slot(iter)
        if !ok { return nil, NIL_ENTITY_HANDLE, false }
        if entity.handle.index == 0 { continue }
        return entity, entity.handle, true
    }
}

// ============================================================================
// Scene node hierarchy
// ============================================================================

@(private="file")
_unlink_from_circle :: proc "contextless" (
    manager: ^Entity_Manager,
    node: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)
    n, n_ok := entity_get(manager, node)
    if !n_ok || n.parent == NIL_ENTITY_HANDLE { return false }
    p, p_ok := entity_get(manager, n.parent)
    if !p_ok { return false }

    if n.next_sibling == node {
        p.first_child = NIL_ENTITY_HANDLE
    } else {
        prev_h, next_h := n.prev_sibling, n.next_sibling
        prev, prev_ok := entity_get(manager, prev_h)
        next, next_ok := entity_get(manager, next_h)
        if !prev_ok || !next_ok { return false }
        prev.next_sibling = next_h
        next.prev_sibling = prev_h
        if p.first_child == node {
            p.first_child = next_h
        }
    }

    n.parent       = NIL_ENTITY_HANDLE
    n.next_sibling = NIL_ENTITY_HANDLE
    n.prev_sibling = NIL_ENTITY_HANDLE
    return true
}

@(private="file")
_link_after :: proc "contextless" (
    manager: ^Entity_Manager,
    prev, new: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    p, p_ok := entity_get(manager, prev)
    n, n_ok := entity_get(manager, new)
    if !p_ok || !n_ok { return false }

    old_next_h := p.next_sibling
    n.next_sibling = old_next_h
    n.prev_sibling = prev
    if old_next_h != NIL_ENTITY_HANDLE {
        old_next, old_next_ok := entity_get(manager, old_next_h)
        if !old_next_ok { return false }
        old_next.prev_sibling = new
    }
    p.next_sibling = new
    return true
}

parent_add :: proc "contextless" (
    manager: ^Entity_Manager,
    self, parent: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    if parent == NIL_ENTITY_HANDLE { return false }
    if self == manager.root { return false }
    return child_add(manager, parent, self)
}

parent_remove :: proc "contextless" (
    manager: ^Entity_Manager,
    self: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    n, ok := entity_get(manager, self)
    if !ok || n.parent == NIL_ENTITY_HANDLE { return false }
    if n.parent == manager.root { return false }
    return _unlink_from_circle(manager, self)
}

child_add :: proc "contextless" (
    manager: ^Entity_Manager,
    parent, child: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    if parent == child { return false }
    if child == manager.root { return false }

    p, p_ok := entity_get(manager, parent)
    c, c_ok := entity_get(manager, child)
    if !p_ok || !c_ok { return false }

    if c.parent != NIL_ENTITY_HANDLE {
        _unlink_from_circle(manager, child)
    }

    if p.first_child == NIL_ENTITY_HANDLE {
        p.first_child  = child
        c.next_sibling = child
        c.prev_sibling = child
    } else {
        head_h := p.first_child
        head, head_ok := entity_get(manager, head_h)
        if !head_ok { return false }
        _link_after(manager, head.prev_sibling, child)
    }
    c.parent = parent
    return true
}

child_remove :: proc "contextless" (
    manager: ^Entity_Manager,
    self, child: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    if self == manager.root { return false }
    c, ok := entity_get(manager, child)
    if !ok || c.parent != self { return false }
    return _unlink_from_circle(manager, child)
}

entity_root :: proc(manager: ^Entity_Manager) -> ^Entity {
    assert_contextless(manager.is_init)

    return &manager.root_data
}

// ============================================================================
// Interpolation
// ============================================================================

entity_interpolation_snapshot :: proc(manager: ^Entity_Manager) {
    assert_contextless(manager.is_init)

    for variant_idx in 0..<len(manager.variants) {
        data := &manager.variants[variant_idx]
        if .Interpolate not_in data.flags { continue }

        for slot_idx in 1 ..< data.len {
            slot := entity_data_entity(data, slot_idx)
            if slot.handle.index == 0 { continue }

            slot.prev_position = slot.position
            slot.prev_rotation = slot.rotation
            slot.prev_scale    = slot.scale
        }
    }
}

transform :: proc(e: ^Entity, alpha: f32) -> (pos, rot, scl: [3]f32) {
    pos = e.prev_position + (e.position - e.prev_position) * alpha
    rot = e.prev_rotation + (e.rotation - e.prev_rotation) * alpha
    scl = e.prev_scale    + (e.scale    - e.prev_scale)    * alpha
    return
}
