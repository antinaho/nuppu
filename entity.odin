package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:log"
import "core:slice"

PTR_SIZE :: size_of(uintptr) * 8

ENTITY_INDEX      :: u16
ENTITY_GENERATION :: u8
ENTITY_VARIANT    :: u8

ENTITY_INDEX_BITS :: 8*size_of(ENTITY_INDEX)

MIN_SHIFT :: 1 // smallest first chunk (2 slots); Space for sentinel + 1 entity
MAX_SHIFT :: ENTITY_INDEX_BITS - 1

NO_PARTIAL :: max(int) // No chunk currently has a free slot.

Entity_Raw :: struct {
    index:   ENTITY_INDEX,
    gen:     ENTITY_GENERATION,
    variant: ENTITY_VARIANT,
}
Entity_Handle :: distinct Handle(Entity_Raw)

NIL_ENTITY_HANDLE :: Entity_Handle {}
ROOT_ENTITY_HANDLE :: Entity_Handle { handle = { index = max(ENTITY_INDEX) } }

CHUNK_CAP   :: #force_inline proc "contextless" (first_chunk_size: int, chunk_index: int) -> int { return first_chunk_size << uint(chunk_index) }
CHUNK_START :: #force_inline proc "contextless" (first_chunk_size: int, chunk_index: int) -> int { return CHUNK_CAP(first_chunk_size, chunk_index) - first_chunk_size }

Entity :: struct {
    handle:       Entity_Handle, // this

    parent:       Entity_Handle,
    first_child:  Entity_Handle,
    next_sibling: Entity_Handle,
    prev_sibling: Entity_Handle,

    mesh:         Mesh_Handle,
    materials:    [CONFIG.entity_max_materials]Material_Handle,

    position:     [3]f32,
    prev_position:[3]f32,
    rotation:     [3]f32, // TODO: currently euler, switch to quaternion
    prev_rotation:[3]f32,
    scale:        [3]f32,
    prev_scale:   [3]f32,
}

Entity_Flag  :: enum u32 {
    Interpolate,
    Has_Mesh,
}
Entity_Flags :: bit_set[Entity_Flag]

// Type for variants that register no GPU instance data.
NO_INSTANCE_DATA :: struct {}

Entity_Chunk :: struct {
    entities:  [^]Entity,                  // count * entities
    variants:  [^]byte,                    // count * size_t specialization bytes
    occupied:  Bit_Mask_Array,             // bit i set => slot i is live
}

// One container per registered entity type. Slot 0 is a reserved sentinel.
Entity_Data :: struct {
    chunks:           [dynamic]Entity_Chunk,
    first_chunk_size: int, // power of two
    top:              int, // high-water slot count (includes sentinel)
                           // not necessarily the same as the number of entities
    cap:              int, // total allocated slots
    partial:          int, // lowest chunk index with free slots; NO_PARTIAL = none
}

Entity_Manager :: struct
{
    types:         [dynamic]typeid,
    type_sizes:    [dynamic]int,
    flags:         [dynamic]Entity_Flags,
    variants:      [dynamic]Entity_Data,

    // Per-variant view of the optional shader instance-data field on drawn entities
    instance_data_offsets: [dynamic]int,
    instance_data_sizes:   [dynamic]int,

    root_data:     Entity,
    is_init:       bool,

    allocator:     runtime.Allocator,
}

Entity_Iterator :: struct {
    manager:     ^Entity_Manager,
    variant_idx: ENTITY_VARIANT,
    chunk_idx:   int,
    offset:      int,
}

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
    manager.variants   = make([dynamic]Entity_Data, len=0, cap=INITIAL_CAPACITY, allocator=allocator)
    manager.types      = make([dynamic]typeid, len=0, cap=INITIAL_CAPACITY, allocator=allocator)
    manager.type_sizes = make([dynamic]int, len=0, cap=INITIAL_CAPACITY, allocator=allocator)
    manager.flags      = make([dynamic]Entity_Flags, len=0, cap=INITIAL_CAPACITY, allocator=allocator)
    manager.instance_data_offsets = make([dynamic]int, len=0, cap=INITIAL_CAPACITY, allocator=allocator)
    manager.instance_data_sizes   = make([dynamic]int, len=0, cap=INITIAL_CAPACITY, allocator=allocator)

    // World root: a reserved transform-only node. Its parent is NIL and every
    // entity is parented either to it or to another entity.
    manager.root_data = Entity {
        handle       = ROOT_ENTITY_HANDLE,
        parent       = NIL_ENTITY_HANDLE,
        first_child  = NIL_ENTITY_HANDLE,
        next_sibling = NIL_ENTITY_HANDLE,
        prev_sibling = NIL_ENTITY_HANDLE,
        position     = {0, 0, 0},
        prev_position= {0, 0, 0},
        rotation     = {0, 0, 0},
        prev_rotation= {0, 0, 0},
        scale        = {1, 1, 1},
        prev_scale   = {1, 1, 1},
    }
}

entity_manager_destroy :: proc(
    manager: ^Entity_Manager,
) {
    if manager == nil { return }

    for &data, i in manager.variants {
        for &chunk, k in data.chunks {
            count := CHUNK_CAP(data.first_chunk_size, k)
            if chunk.entities != nil {
                mem.delete_slice(chunk.entities[:count], manager.allocator)
            }
            if chunk.variants != nil {
                size_t := manager.type_sizes[i]
                mem.delete_slice(([^]byte)(chunk.variants)[:count * size_t], manager.allocator)
            }
            bit_mask_array_destroy(&chunk.occupied)
        }
        delete(data.chunks)
    }

    delete(manager.variants)
    delete(manager.types)
    delete(manager.type_sizes)
    delete(manager.flags)
    delete(manager.instance_data_offsets)
    delete(manager.instance_data_sizes)

    alloc := manager.allocator
    manager^ = {}
    mem.free(rawptr(manager), alloc)
}

// Resets the manager to "nothing added" without reallocating. Keeps variant
// registrations and chunk allocations; zeroes entity + variant data and clears
// the occupancy bitmaps from index 1 on (slot 0 is the reserved sentinel).
entity_manager_clear :: proc(manager: ^Entity_Manager) {
    assert(manager.is_init, "entity_manager_clear: not initialized")

    for variant_idx in 0 ..< len(manager.variants) {
        data := &manager.variants[variant_idx]
        size_t := manager.type_sizes[variant_idx]

        for chunk_idx in 0 ..< len(data.chunks) {
            chunk := &data.chunks[chunk_idx]
            cap := CHUNK_CAP(data.first_chunk_size, chunk_idx)

            // Chunk 0 holds the nil sentinel at offset 0; keep it.
            start := chunk_idx == 0 ? 1 : 0

            if count := cap - start; count > 0 {
                intrinsics.mem_zero(rawptr(&chunk.entities[start]), count * size_of(Entity))
                intrinsics.mem_zero(rawptr(uintptr(chunk.variants) + uintptr(start * size_t)), count * size_t)
            }

            bit_mask_array_clear_all(&chunk.occupied)
            if chunk_idx == 0 {
                bit_mask_array_set(&chunk.occupied, 0) // re-mark the sentinel
            }
        }

        data.top     = 1 // only the sentinel remains
        data.partial = 0 // chunk 0 always has free slots
    }

    // Every entity was parented to root, so root now has no children.
    manager.root_data = Entity {
        handle        = ROOT_ENTITY_HANDLE,
        parent        = NIL_ENTITY_HANDLE,
        first_child   = NIL_ENTITY_HANDLE,
        next_sibling  = NIL_ENTITY_HANDLE,
        prev_sibling  = NIL_ENTITY_HANDLE,
        position      = {0, 0, 0},
        prev_position = {0, 0, 0},
        rotation      = {0, 0, 0},
        prev_rotation = {0, 0, 0},
        scale         = {1, 1, 1},
        prev_scale    = {1, 1, 1},
    }
}

entity_manager_add_variant :: proc(
    manager: ^Entity_Manager,
    $Entity_Type: typeid,
    $SHIFT: uint,
    flags: Entity_Flags = {},
)
    where intrinsics.type_is_struct(Entity_Type) && SHIFT >= MIN_SHIFT && SHIFT <= MAX_SHIFT
{
    _entity_manager_add_variant(manager, Entity_Type, NO_INSTANCE_DATA, SHIFT, flags)
}

entity_manager_add_variant_data :: proc(
    manager: ^Entity_Manager,
    $Entity_Type: typeid,
    $SHIFT: uint,
    flags: Entity_Flags = {},
    $GPU_Instance: typeid,
)
    where intrinsics.type_is_struct(Entity_Type) && SHIFT >= MIN_SHIFT && SHIFT <= MAX_SHIFT
{
    _entity_manager_add_variant(manager, Entity_Type, GPU_Instance, SHIFT, flags)
}

@(require_results)
entity_add :: proc($T: typeid, name: string = "", loc := #caller_location) -> ^T {
    handle, ok := _entity_add(_state.entity_manager, T, name, loc)
    if !ok { return nil }
    entity, _ := entity_get_typed(_state.entity_manager, handle, T)
    return entity
}

// Public get. On failure in debug it reports where the handle was created so
// stale-handle bugs are easy to trace.
@(require_results)
entity_get :: proc(
    manager: ^Entity_Manager,
    handle: Entity_Handle,
    loc := #caller_location,
) -> (^Entity, bool) #optional_ok {
    entity, ok := _entity_get(manager, handle)
    when ODIN_DEBUG {
        if !ok && !_entity_eq(handle, NIL_ENTITY_HANDLE) {
            _warn_stale_entity(handle, loc)
        }
    }
    return entity, ok
}


@(require_results)
entity_get_typed :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle,
    $T: typeid,
) -> (^T, bool) #optional_ok #no_bounds_check {
    assert_contextless(manager.is_init)

    if _entity_eq(handle, ROOT_ENTITY_HANDLE) {
        return {}, false
    }

    if manager.types[handle.handle.variant] != T { return nil, false }
    
    data, ci, off, ok := _data_resolve(manager, handle)
    if !ok { return nil, false }

    c := &data.chunks[ci]
    size_t := manager.type_sizes[handle.handle.variant]
    return (^T)(rawptr(uintptr(c.variants) + uintptr(off * size_t))), true
}

entity_remove :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle,
) -> bool #no_bounds_check {
    assert_contextless(manager.is_init)

    if _entity_eq(handle, ROOT_ENTITY_HANDLE) { return false }

    data, ci, off, ok := _data_resolve(manager, handle)
    if !ok { return false }

    c := &data.chunks[ci]
    slot := &c.entities[off]

    if _entity_ne(slot.parent, NIL_ENTITY_HANDLE) {
        _unlink_from_circle(manager, handle)
    }

    was_full := c.occupied.live == c.occupied.bit_count
    _chunk_free_slot(c, off)

    slot.handle.handle.gen += 1
    slot.handle.handle.index = 0

    // Prefer reusing the earliest chunk that has holes.
    if was_full && (data.partial == NO_PARTIAL || ci < data.partial) {
        data.partial = ci
    }

    return true
}

entity_iterator_init :: proc(
    manager: ^Entity_Manager,
    $T: typeid,
) -> Entity_Iterator {
    assert_contextless(manager.is_init)
    variant_idx, found := slice.linear_search(manager.types[:], T)
    assert_contextless(found, "entity_iterator_init: type not registered")
    return Entity_Iterator {
        manager     = manager,
        variant_idx = ENTITY_VARIANT(variant_idx),
    }
}

entity_variant_iterator_next :: proc "contextless" (iter: ^Entity_Iterator, $T: typeid) -> (^T, Entity_Handle, bool) #no_bounds_check {
    for {
        entity, variant, ok := _iter_next_slot(iter)
        if !ok { return nil, NIL_ENTITY_HANDLE, false }
        if entity.handle.handle.index == 0 { continue }
        return (^T)(variant), entity.handle, true
    }
}

entity_iterator_next :: proc "contextless" (iter: ^Entity_Iterator) -> (^Entity, Entity_Handle, bool) #no_bounds_check {
    for {
        entity, _, ok := _iter_next_slot(iter)
        if !ok { return nil, NIL_ENTITY_HANDLE, false }
        if entity.handle.handle.index == 0 { continue }
        return entity, entity.handle, true
    }
}

// Global-manager convenience wrappers.
entities_of :: proc($T: typeid) -> Entity_Iterator {
    return entity_iterator_init(_state.entity_manager, T)
}

advance_entities_of :: proc(iter: ^Entity_Iterator) -> (^Entity, Entity_Handle, bool) {
    return entity_iterator_next(iter)
}


parent_add :: proc "contextless" (
    manager: ^Entity_Manager,
    self, parent: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    if _entity_eq(parent, NIL_ENTITY_HANDLE) { return false }
    if _entity_eq(self, ROOT_ENTITY_HANDLE) { return false }
    return child_add(manager, parent, self)
}

// Detaches `self` from its current parent and attaches it to `new_parent`,
// which may be another entity or the root. Defaults to the root, since every
// entity must always have a parent.
unparent :: proc "contextless" (
    manager: ^Entity_Manager,
    self: Entity_Handle,
    new_parent: Entity_Handle = ROOT_ENTITY_HANDLE,
) -> bool {
    assert_contextless(manager.is_init)

    if _entity_eq(self, ROOT_ENTITY_HANDLE) { return false }
    parent := new_parent
    if _entity_eq(parent, NIL_ENTITY_HANDLE) { parent = ROOT_ENTITY_HANDLE }
    if _entity_eq(parent, self) { return false }

    n, ok := _entity_get(manager, self)
    if !ok || _entity_eq(n.parent, parent) { return false }
    return child_add(manager, parent, self)
}

child_add :: proc "contextless" (
    manager: ^Entity_Manager,
    parent, child: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    if _entity_eq(parent, child) { return false }
    if _entity_eq(child, ROOT_ENTITY_HANDLE) { return false }

    p, p_ok := _entity_get(manager, parent)
    c, c_ok := _entity_get(manager, child)
    if !p_ok || !c_ok { return false }

    if _entity_ne(c.parent, NIL_ENTITY_HANDLE) {
        _unlink_from_circle(manager, child)
    }

    if _entity_eq(p.first_child, NIL_ENTITY_HANDLE) {
        p.first_child  = child
        c.next_sibling = child
        c.prev_sibling = child
    } else {
        head_h := p.first_child
        head, head_ok := _entity_get(manager, head_h)
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

    if _entity_eq(self, ROOT_ENTITY_HANDLE) { return false }
    c, ok := _entity_get(manager, child)
    if !ok || _entity_ne(c.parent, self) { return false }
    if !_unlink_from_circle(manager, child) { return false }
    // Entities always keep a parent; an unparented child falls back to root.
    return child_add(manager, ROOT_ENTITY_HANDLE, child)
}

entity_root :: proc(manager: ^Entity_Manager) -> ^Entity {
    assert_contextless(manager.is_init)

    return &manager.root_data
}

entity_interpolation_snapshot :: proc(manager: ^Entity_Manager) {
    assert_contextless(manager.is_init)

    for variant_idx in 0..<len(manager.variants) {
        data := &manager.variants[variant_idx]
        flags := manager.flags[variant_idx]
        if .Interpolate not_in flags { continue }

        for slot_idx in 1 ..< data.top {
            ci, off := _data_chunk_for(data, slot_idx)
            slot_ptr := &data.chunks[ci].entities[off]
            if slot_ptr.handle.handle.index == 0 { continue }

            slot_ptr.prev_position = slot_ptr.position
            slot_ptr.prev_rotation = slot_ptr.rotation
            slot_ptr.prev_scale    = slot_ptr.scale
        }
    }
}

transform :: proc(e: ^Entity, alpha: f32) -> (pos, rot, scl: [3]f32) {
    pos = e.prev_position + (e.position - e.prev_position) * alpha
    rot = e.prev_rotation + (e.rotation - e.prev_rotation) * alpha
    scl = e.prev_scale    + (e.scale    - e.prev_scale)    * alpha
    return
}



_entity_eq :: #force_inline proc "contextless" (a, b: Entity_Handle) -> bool {
    return a.handle == b.handle
}

_entity_ne :: #force_inline proc "contextless" (a, b: Entity_Handle) -> bool {
    return a.handle != b.handle
}

// Global index => chunk index + offset into chunk.
_data_chunk_for :: proc "contextless" (
    data: ^Entity_Data,
    index: int
) -> (ci: int, off: int) #no_bounds_check {
    j := index + data.first_chunk_size
    e := PTR_SIZE - 1 - intrinsics.count_leading_zeros(j)
    p := 1 << uint(e)
    ci  = e - intrinsics.count_trailing_zeros(data.first_chunk_size)
    off = j - p
    return
}

// Validates a handle against its container and returns the container plus the
// chunk + offset it maps to.
_data_resolve :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle
) -> (data: ^Entity_Data, ci: int, off: int, ok: bool) #no_bounds_check {
    if handle.handle.index == 0 || handle.handle.gen == 0 { return nil, 0, 0, false }
    if handle.handle.variant >= ENTITY_VARIANT(len(manager.variants)) { return nil, 0, 0, false }

    data = &manager.variants[handle.handle.variant]
    if u64(handle.handle.index) >= u64(data.top) { return nil, 0, 0, false }

    ci, off = _data_chunk_for(data, int(handle.handle.index))
    slot := &data.chunks[ci].entities[off]
    if slot.handle.handle.gen != handle.handle.gen { return nil, 0, 0, false }
    if slot.handle.handle.index == 0 { return nil, 0, 0, false }
    return data, ci, off, true
}

_chunk_free_slot :: proc "contextless" (c: ^Entity_Chunk, off: int) #no_bounds_check {
    bit_mask_array_clear(&c.occupied, off)
}

// Finds a field of type `target` inside a variant struct, recursing through
// `using` fields. Panics if more than one field matches
_struct_find_type :: proc(sti: ^runtime.Type_Info_Struct, target: typeid, base: uintptr) -> (offset: uintptr, size: int, found: bool) {
    for i in 0 ..< int(sti.field_count) {
        t := sti.types[i]
        if t.id == target {
            if found {
                panic("entity_manager_add_variant: multiple fields match the target type")
            }
            offset = base + sti.offsets[i]
            size   = t.size
            found  = true
        } else if sti.usings[i] {
            sub_ti := runtime.type_info_core(t)
            if sub, sub_ok := sub_ti.variant.(runtime.Type_Info_Struct); sub_ok {
                off, sz, sub_found := _struct_find_type(&sub, target, base + sti.offsets[i])
                if sub_found {
                    if found {
                        panic("entity_manager_add_variant: multiple fields match the target type")
                    }
                    offset = off
                    size   = sz
                    found  = true
                }
            }
        }
    }
    return
}

_entity_manager_add_variant :: proc(
    manager: ^Entity_Manager,
    $Entity_Type: typeid,
    $Instance_Type: typeid,
    shift: uint,
    flags: Entity_Flags,
)
    where intrinsics.type_is_struct(Entity_Type),
          Instance_Type == NO_INSTANCE_DATA || intrinsics.type_has_field(Entity_Type, "gpu_instance"),
          size_of(Instance_Type) <= CONFIG.max_instance_data_bytes
{

    assert(manager.is_init)

    for type in manager.types {
        if type == Entity_Type {
            log.warnf("entity_manager_add_variant: type already registered")
            return
        }
    }

    // Must carry ^Entity back-pointer at offset 0. Searches recursively.
    sti := runtime.type_info_core(type_info_of(Entity_Type)).variant.(runtime.Type_Info_Struct)
    entity_offset, _, entity_found := _struct_find_type(&sti, typeid_of(^Entity), 0)
    if !entity_found || entity_offset != 0 {
        panic("All variants must have a ^Entity member at offset 0")
    }

    // The where clause guarantees `gpu_instance` exists when instance data is
    // requested; assert the rest of the contract and resolve the offset here.
    data_offset: int
    data_size:   int
    when Instance_Type != NO_INSTANCE_DATA {
        #assert(intrinsics.type_field_type(Entity_Type, "gpu_instance") == Instance_Type,
                "entity_manager_add_variant: gpu_instance must have the registered instance-data type")
        data_offset = int(offset_of_by_string(Entity_Type, "gpu_instance"))
        data_size   = size_of(Instance_Type)
    }

    append(&manager.types, Entity_Type)
    append(&manager.flags, flags)
    append(&manager.type_sizes, size_of(Entity_Type))
    append(&manager.instance_data_offsets, data_offset)
    append(&manager.instance_data_sizes, data_size)
    append(&manager.variants, Entity_Data {
        first_chunk_size = 1 << shift,
        partial          = NO_PARTIAL,
    })

    // Reserve slot 0 as the nil sentinel.
    nil_entity_handle := _entity_add(manager, Entity_Type)
    assert(nil_entity_handle.handle.index == 0)
    assert(nil_entity_handle.handle.gen == 1)
}

@(require_results)
_entity_add :: proc (
    manager: ^Entity_Manager,
    T: typeid,
    name: string = "",
    loc := #caller_location,
) -> (Entity_Handle, bool) #optional_ok #no_bounds_check
{
    assert_contextless(manager.is_init)

    variant_idx, found := slice.linear_search(manager.types[:], T)
    assert_contextless(found, "entity_add: type not registered")

    data := &manager.variants[variant_idx]

    if data.partial == NO_PARTIAL {
        // Index space is bounded by ENTITY_INDEX, so the highest usable chunk
        // index is ENTITY_INDEX_BITS - 1 - log2(first_chunk_size).
        max_chunks := ENTITY_INDEX_BITS - intrinsics.count_trailing_zeros(data.first_chunk_size)
        if len(data.chunks) >= max_chunks {
            panic("entity_add: max chunk count reached; entity index space exhausted")
        }

        idx    := len(data.chunks)
        cap    := CHUNK_CAP(data.first_chunk_size, idx)
        size_t := manager.type_sizes[variant_idx]

        e_buf, _ := runtime.make_aligned([]Entity, cap, alignment=4096, allocator=manager.allocator)
        v_buf, _ := runtime.make_aligned([]byte, cap * size_t, alignment=4096, allocator=manager.allocator)
        occupied_arr, err := bit_mask_array_init(cap, alignment=4096, allocator=manager.allocator)
        assert(e_buf != nil && v_buf != nil && err == nil, "_data_append_chunk: allocation failed")

        intrinsics.mem_zero(raw_data(e_buf), cap * size_of(Entity))
        intrinsics.mem_zero(raw_data(v_buf), cap * size_t)

        append(&data.chunks, Entity_Chunk {
            entities = raw_data(e_buf),
            variants = raw_data(v_buf),
            occupied = occupied_arr,
        })
        data.cap += cap
        
        data.partial = len(data.chunks) - 1
    }

    ci := data.partial
    c  := &data.chunks[ci]
    
    index_within_chunk, found_slot := bit_mask_array_flip_first_zero(&c.occupied)
    assert(found_slot, "entity_add: partial chunk had no free slot")
    index := CHUNK_START(data.first_chunk_size, ci) + index_within_chunk

    if c.occupied.live == c.occupied.bit_count {
        // Chunk is full; advance to the next chunk that still has holes.
        // reset partial incase all currently allocated chunks are full
        data.partial = NO_PARTIAL
        for j := ci + 1; j < len(data.chunks); j += 1 {
            if data.chunks[j].occupied.live < data.chunks[j].occupied.bit_count {
                data.partial = j
                break
            }
        }
    }

    if index == data.top {
        data.top += 1
    }

    entity_ptr  := &c.entities[index_within_chunk]
    size_t := manager.type_sizes[variant_idx]
    variant_ptr := rawptr(uintptr(c.variants) + uintptr(index_within_chunk * size_t))

    prev_gen := entity_ptr.handle.handle.gen

    intrinsics.mem_zero(rawptr(entity_ptr), size_of(Entity))
    intrinsics.mem_zero(variant_ptr, size_t)

    entity_ptr.handle = Entity_Handle {
        handle = Entity_Raw {
            index   = ENTITY_INDEX(index),
            gen     = prev_gen == 0 ? 1 : prev_gen,
            variant = ENTITY_VARIANT(variant_idx),
        },
    }
    when ODIN_DEBUG {
        entity_ptr.handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state != nil ? _state.frame_n : 0,
            name             = name,
        }
    }

    (^rawptr)(variant_ptr)^ = rawptr(entity_ptr)

    // Every real entity is parented to the root
    if entity_ptr.handle.handle.index != 0 {
        child_add(manager, ROOT_ENTITY_HANDLE, entity_ptr.handle)
    }

    return entity_ptr.handle, true
}

@(require_results)
_entity_get :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle
) -> (^Entity, bool) #optional_ok #no_bounds_check {
    assert_contextless(manager.is_init)

    if _entity_eq(handle, ROOT_ENTITY_HANDLE) {
        return &manager.root_data, true
    }

    data, ci, off, ok := _data_resolve(manager, handle)
    if !ok { return nil, false }
    return &data.chunks[ci].entities[off], true
}

when ODIN_DEBUG {
    _warn_stale_entity :: proc(handle: Entity_Handle, loc: runtime.Source_Code_Location) {
        // The dedup map only exists once `run` has set up debug state (tests
        // build with ODIN_DEBUG but never call `run`).
        if _debug_warned_call_sites != nil {
            h := debug_warn_hash(loc)
            if h in _debug_warned_call_sites { return }
            _debug_warned_call_sites[h] = true
        }

        log.warnf(
            "[nuppu] stale entity handle idx=%v gen=%v variant=%v — created at %v:%v on frame %v (lookup at %v:%v)",
            handle.handle.index,
            handle.handle.gen,
            handle.handle.variant,
            handle.metadata.created_at.file_path,
            handle.metadata.created_at.line,
            handle.metadata.created_on_frame,
            loc.file_path,
            loc.line,
        )
    }
}

// Walks chunks linearly and returns both slot views for the current position.
_iter_next_slot :: proc "contextless" (iter: ^Entity_Iterator) -> (entity: ^Entity, variant: rawptr, ok: bool) #no_bounds_check {
    data := &iter.manager.variants[iter.variant_idx]

    for iter.chunk_idx < len(data.chunks) {
        count := CHUNK_CAP(data.first_chunk_size, int(iter.chunk_idx))
        start := CHUNK_START(data.first_chunk_size, int(iter.chunk_idx))
        for iter.offset < count {
            index := start + iter.offset
            defer iter.offset += 1

            if index >= data.top {
                return nil, nil, false
            }
            
            c := &data.chunks[iter.chunk_idx]
            ent := &c.entities[iter.offset]
            if ent.handle.handle.index == 0 { continue }
            
            size_t := iter.manager.type_sizes[iter.variant_idx]
            return ent, rawptr(uintptr(c.variants) + uintptr(iter.offset * size_t)), true
        }
        iter.chunk_idx += 1
        iter.offset = 0
    }
    return nil, nil, false
}


_unlink_from_circle :: proc "contextless" (
    manager: ^Entity_Manager,
    node: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)
    n, n_ok := _entity_get(manager, node)
    if !n_ok || _entity_eq(n.parent, NIL_ENTITY_HANDLE) { return false }
    p, p_ok := _entity_get(manager, n.parent)
    if !p_ok { return false }

    if _entity_eq(n.next_sibling, node) {
        p.first_child = NIL_ENTITY_HANDLE
    } else {
        prev_h, next_h := n.prev_sibling, n.next_sibling
        prev, prev_ok := _entity_get(manager, prev_h)
        next, next_ok := _entity_get(manager, next_h)
        if !prev_ok || !next_ok { return false }
        prev.next_sibling = next_h
        next.prev_sibling = prev_h
        if _entity_eq(p.first_child, node) {
            p.first_child = next_h
        }
    }

    n.parent       = NIL_ENTITY_HANDLE
    n.next_sibling = NIL_ENTITY_HANDLE
    n.prev_sibling = NIL_ENTITY_HANDLE
    return true
}

_link_after :: proc "contextless" (
    manager: ^Entity_Manager,
    prev, new: Entity_Handle,
) -> bool {
    assert_contextless(manager.is_init)

    p, p_ok := _entity_get(manager, prev)
    n, n_ok := _entity_get(manager, new)
    if !p_ok || !n_ok { return false }

    old_next_h := p.next_sibling
    n.next_sibling = old_next_h
    n.prev_sibling = prev
    if _entity_ne(old_next_h, NIL_ENTITY_HANDLE) {
        old_next, old_next_ok := _entity_get(manager, old_next_h)
        if !old_next_ok { return false }
        old_next.prev_sibling = new
    }
    p.next_sibling = new
    return true
}
