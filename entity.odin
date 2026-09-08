package nuppu

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:slice"

ENTITY_INDEX      :: u32
ENTITY_VARIANT    :: u16
ENTITY_GENERATION :: u16
ROOT_VARIANT_IDX  :: max(ENTITY_VARIANT)

Entity :: struct {
    handle:       Entity_Handle, // this

    parent:       Entity_Handle,
    first_child:  Entity_Handle,
    next_sibling: Entity_Handle,
    prev_sibling: Entity_Handle,

    next_free:    u32,
    position:     [3]f32,
    prev_position:[3]f32,
    rotation:     [3]f32, // TODO: currently euler
    prev_rotation:[3]f32,
    scale:        [3]f32,
    prev_scale:   [3]f32,
}

NIL_ENTITY_HANDLE :: Entity_Handle {}

Entity_Flag  :: enum {
    Interpolate,
}
Entity_Flags :: bit_set[Entity_Flag]

Entity_Handle :: struct {
    index:       ENTITY_INDEX,
    gen:         ENTITY_GENERATION,
    variant_idx: ENTITY_VARIANT,
}

Entity_Manager :: struct
{
    types:         [dynamic]typeid,
    variants:      [dynamic]Entity_Data,
    sizes:         [dynamic]i64,
    variant_flags: [dynamic]Entity_Flags,

    root_data:     Entity,
    root:          Entity_Handle,
    is_init:       bool,

    allocator:     runtime.Allocator,
}

Entity_Data :: struct {
    buffer: [^]byte,
    cap:    i32, // how many entities of a given variant buffer can fit, NOT the cap of the buffer
    top:    i32, // highwater mark
    free:   i32,
}

entity_manager_add_variant :: proc(manager: ^Entity_Manager, $T: typeid, capacity: int = 1024, flags: Entity_Flags = {})
    where intrinsics.type_is_struct(T)
{
    assert(manager.is_init)
    assert(capacity >= 2, "Entity capacity must be >= 2 (slot 0 reserved)")

    if slice.contains(manager.types[:], T) {
        return // already added
    }

    append(&manager.types, T)
    size_t := size_of(T)
    append(&manager.sizes, i64(size_t))
    append(&manager.variant_flags, flags)

    data, _ := runtime.make_aligned([]byte, capacity * size_t, alignment = 4096, allocator = manager.allocator)
    intrinsics.mem_zero(raw_data(data), capacity * size_t)

    append(&manager.variants, Entity_Data {
        buffer = raw_data(data),
        cap    = i32(capacity),
        top    = 0,
        free   = 0,
    })

    {
        ti  := runtime.type_info_core(type_info_of(T))^
        sti, ok := ti.variant.(runtime.Type_Info_Struct)
        if !ok {
            panic("All variants must be structs")
        }

        has_base := false
        for fi in 0..<sti.field_count {
            if sti.offsets[fi] == 0 {
                if sti.types[fi].id == typeid_of(Entity) {
                    has_base = true
                }
            }
        }

        if !has_base {
            panic("All variants must have a Entity member at offset 0")
        }
    }
}

entity_manager_init :: proc(
    manager: ^Entity_Manager,
    allocator := context.allocator
) {
    if manager.is_init { return }
    manager.is_init = true

    INITIAL_CAPACITY :: 16
    manager.allocator = allocator
    manager.variants = make([dynamic]Entity_Data, len=0, cap = INITIAL_CAPACITY, allocator = allocator)
    manager.sizes = make([dynamic]i64, len=0, cap = INITIAL_CAPACITY, allocator = allocator)
    manager.types = make([dynamic]typeid, len=0, cap = INITIAL_CAPACITY, allocator = allocator)
    manager.variant_flags = make([dynamic]Entity_Flags, len=0, cap = INITIAL_CAPACITY, allocator = allocator)

    manager.root_data = Entity {
        parent = NIL_ENTITY_HANDLE,
        first_child = NIL_ENTITY_HANDLE,
        next_sibling = NIL_ENTITY_HANDLE,
        prev_sibling = NIL_ENTITY_HANDLE,
        handle = Entity_Handle {
            index = 1,
            gen = 1,
            variant_idx = ROOT_VARIANT_IDX,
        },
        position = {0, 0, 0},
        scale    = {1, 1, 1},
        rotation = {0, 0, 0},
    }
    manager.root = manager.root_data.handle
}

entity_manager_destroy :: proc(
    manager: ^Entity_Manager,
    allocator := context.allocator,
) {
    if manager == nil { return }
    for i in 0 ..< len(manager.variants) {
        data := &manager.variants[i]
        if data.buffer == nil { continue }
        size_bytes := int(data.cap) * int(manager.sizes[i])
        slice := ([^]byte)(data.buffer)[:size_bytes]
        mem.delete_slice(slice, allocator)
    }

    delete(manager.variants)
    delete(manager.sizes)
    delete(manager.types)
    delete(manager.variant_flags)

    mem.free(rawptr(manager), allocator)
}

@(require_results)
entity_add :: proc "contextless" (
    manager: ^Entity_Manager,
    $T: typeid
) -> (^T, bool) #optional_ok #no_bounds_check
{
    assert_contextless(manager.is_init)
    
    variant_idx, found := slice.linear_search(manager.types[:], T)
    assert_contextless(found, "entity_add: type not registered")
    data := &manager.variants[variant_idx]
    size := manager.sizes[variant_idx]
    base := uintptr(data.buffer)

    index := data.free
    slot := cast(^Entity)uintptr(base + uintptr(index) * uintptr(size))

    if index > 0 {
        data.free = i32(slot.next_free)
    } else if data.top < data.cap - 1 {
        data.top += 1
        index = data.top
        slot = cast(^Entity)uintptr(base + uintptr(index) * uintptr(size))
    } else {
        return nil, false
    }

    prev_gen := slot.handle.gen

    intrinsics.mem_zero(rawptr(slot), int(size))

    slot.handle = {
        index       = ENTITY_INDEX(index),
        gen         = prev_gen == 0 ? 1 : prev_gen,
        variant_idx = ENTITY_VARIANT(variant_idx),
    }
    slot.next_free = 0

    if  slot.handle != manager.root {
        child_add(manager, manager.root, slot.handle)
    }

    return cast(^T)(slot), true
}

@(require_results)
entity_get :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle
) -> (^Entity, bool) #optional_ok #no_bounds_check {
    assert_contextless(manager.is_init)

    if handle.variant_idx == ROOT_VARIANT_IDX {
        return &manager.root_data, true
    }

    if handle.index == 0 || handle.gen == 0 { // 0 index for sentinal, used slot gen >= 1
        return nil, false
    }
    if handle.variant_idx >= ENTITY_VARIANT(len(manager.variants)) {
        return nil, false
    }

    data := &manager.variants[handle.variant_idx]
    if handle.index > u32(data.top) {
        return nil, false
    }
    ptr := uintptr(data.buffer) + uintptr(handle.index) * uintptr(manager.sizes[int(handle.variant_idx)])
    slot := cast(^Entity)(ptr)
    if slot.handle.gen != handle.gen {
        return nil, false
    }
    if slot.handle.index == 0 {
        return nil, false
    }
    return slot, true
}

entity_remove :: proc "contextless" (
    manager: ^Entity_Manager,
    handle: Entity_Handle,
) -> bool #no_bounds_check {
    assert_contextless(manager.is_init)

    if handle == manager.root { return false }

    slot, ok := entity_get(manager, handle)
    if !ok { return false }

    if slot.parent != NIL_ENTITY_HANDLE {
        _unlink_from_circle(manager, handle)
    }

    data := &manager.variants[handle.variant_idx]
    slot.handle.gen += 1
    slot.handle.index = 0
    slot.next_free = u32(data.free)
    data.free = i32(handle.index)

    return true
}

// ============================================================================
// Iterators
// ============================================================================

/*
iterator := make_entity_iterator(manager, Entity_Type)
for ent_ptr, handle := entity_iterator_next(&iterator) {
    ...
}
*/

Entity_Iterator :: struct {
    manager: ^Entity_Manager,
    variant_idx: ENTITY_VARIANT,
    cursor: ENTITY_INDEX,
}

entity_iterator_init :: proc(
    manager: ^Entity_Manager,
    $T: typeid,
) -> Entity_Iterator {
    assert_contextless(manager.is_init)
    variant_idx, found := slice.linear_search(manager.types[:], T)
    assert_contextless(found, "entity_iterator_init: type not registered")
    return Entity_Iterator {
        manager = manager,
        cursor = 1, // skip sentinel at slot 0
        variant_idx = ENTITY_VARIANT(variant_idx),
    }
}

entity_iterator_next :: proc "contextless" (iter: ^Entity_Iterator) -> (^Entity, Entity_Handle, bool) #no_bounds_check {
    data := &iter.manager.variants[iter.variant_idx]
    size := iter.manager.sizes[iter.variant_idx]

    for iter.cursor < u32(data.cap) {
        base := uintptr(data.buffer) + uintptr(iter.cursor) * uintptr(size)
        slot := cast(^Entity)(base)
        defer iter.cursor += 1

        if slot.handle.index == 0 { continue }

        return slot, slot.handle, true
    }
    return nil, NIL_ENTITY_HANDLE, false
}

// ============================================================================
// Scene node hierarchy
//
// Children of a parent form a circular doubly-linked intrusive list:
//   - empty:        parent.first_child == NIL_ENTITY_HANDLE
//   - one child B:  parent.first_child = B; B.next_sibling = B; B.prev_sibling = B
//   - N children:   parent.first_child = head; tail.next_sibling wraps to head;
//                   head.prev_sibling wraps to tail
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
//
// Each registered variant can be tagged with entity_manager_add_variant(..., flags).
// Variants with the .Interpolate flag have their prev_position / prev_rotation /
// prev_scale snapshotted on every call to entity_interpolation_snapshot.
//
// Call entity_interpolation_snapshot at the start of every fixed sim tick — before
// mutating positions. Render-side call transform(e, alpha) to read the lerped
// value; alpha is the inter-tick interpolation factor (0..1) you already pass
// to your render proc.
//
// Why: the variant buffer is opaque (typed slots, polymorphic walk), so we
// re-read raw bytes from offset 0 — guaranteed to be the Entity base because
// entity_manager_add_variant validates it has an Entity member at offset 0.
// ============================================================================

entity_interpolation_snapshot :: proc(manager: ^Entity_Manager) {
    assert_contextless(manager.is_init)

    for variant_idx in 0..<len(manager.variant_flags) {
        if .Interpolate not_in manager.variant_flags[variant_idx] { continue }

        data := &manager.variants[variant_idx]
        size := manager.sizes[variant_idx]

        for slot_idx in 1..=u32(data.top) {
            base := uintptr(data.buffer) + uintptr(slot_idx) * uintptr(size)
            slot := cast(^Entity)(base)
            if slot.handle.index == 0 { continue } // free slot

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
