package nuppu

import "base:intrinsics"
import "base:runtime"

ENTITY_INDEX      :: u32
ENTITY_VARIANT    :: u16
ENTITY_GENERATION :: u16

Entity :: struct {
    handle   : Entity_Handle, // this

    parent: Entity_Handle,
    first_child: Entity_Handle,
    next_sibling: Entity_Handle,
    prev_sibling: Entity_Handle,

    next_free: u32,
    position : [3]f32,
    rotation : [3]f32,
    scale    : [3]f32,
    flags    : u32,
}

NIL_ENTITY_HANDLE :: Entity_Handle {}

Entity_Handle :: struct {
    index:       ENTITY_INDEX,
    gen:         ENTITY_GENERATION,
    variant_idx: ENTITY_VARIANT,
}

UNION_LEN :: intrinsics.type_union_variant_count

Entity_Manager :: struct($Entity_Union: typeid)
    where
        intrinsics.type_is_union(Entity_Union),
        UNION_LEN(Entity_Union) < 256
{
    variants: [UNION_LEN(Entity_Union)]Entity_Data,
    sizes:    [UNION_LEN(Entity_Union)]i64,
}

Entity_Data :: struct {
    buffer: [^]byte,
    cap   : i32, // how many entities of a given variant can fit, NOT the cap of the buffer
    top   : i32, // highwater mark
    free  : i32,
}

entity_manager_init :: proc(
    manager: ^Entity_Manager($EU),
    capacities: []int,
    default_capacity: int = 1024,
    allocator := context.allocator,
) {
    val_ti := runtime.type_info_core(type_info_of(EU))
    val_ti_union := val_ti.variant.(runtime.Type_Info_Union)

    for val_var_ti, val_var_index in val_ti_union.variants {
        manager.sizes[val_var_index] = i64(val_var_ti.size)
    }

    for i in 0 ..< UNION_LEN(EU) {
        assert(capacities[i] >= 0, "Entity capacity must be >= 0")
        capacity := capacities[i] if capacities[i] > 0 else default_capacity
        assert(capacity >= 2, "Entity capacity must be >= 2 (slot 0 reserved)")

        data, _ := runtime.make_aligned([]byte, capacity * int(manager.sizes[i]), alignment = 4096, allocator = allocator)
        intrinsics.mem_zero(raw_data(data), capacity * int(manager.sizes[i]))

        manager.variants[i] = {
            buffer = raw_data(data),
            cap    = i32(capacity),
            top    = 0,
            free   = 0,
        }
    }

    for val_var_ti in val_ti_union.variants {
        sti := runtime.type_info_core(val_var_ti).variant.(runtime.Type_Info_Struct) or_continue

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

_resolve :: proc(
    manager: ^Entity_Manager($EU), 
    handle: Entity_Handle
) -> (^Entity, bool) {
    if handle.index == 0 || handle.gen == 0 { // 0 index for sentinal, used slot gen >= 1
        return nil, false
    }
    if handle.variant_idx >= len(manager.variants) {
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
    return slot, true
}

@(require_results)
add_entity :: proc(
    manager: ^Entity_Manager($EU),
    $T: typeid
) -> (^T, bool)
where intrinsics.type_is_variant_of(EU, T) #optional_ok
{
    variant_idx := intrinsics.type_variant_index_of(EU, T)
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

    return cast(^T)(slot), true
}

@(require_results)
get_entity :: proc(
    manager: ^Entity_Manager($EU),
    handle: Entity_Handle
) -> (^Entity, bool) #optional_ok {
    return _resolve(manager, handle)
}

remove_entity :: proc(
    manager: ^Entity_Manager($EU),
    handle: Entity_Handle
) -> bool {
    slot, ok := _resolve(manager, handle)
    if !ok { return false }

    data := &manager.variants[handle.variant_idx]
    slot.handle.gen += 1
    slot.next_free = u32(data.free)
    data.free = i32(handle.index)

    return true
}

// ============================================================================
// Scene node hierarchy
//
// Children of a parent form a circular doubly-linked intrusive list:
//   - empty:        parent.first_child == NIL_ENTITY_HANDLE
//   - one child B:  parent.first_child = B; B.next_sibling = B; B.prev_sibling = B
//   - N children:   parent.first_child = head; tail.next_sibling wraps to head;
//                   head.prev_sibling wraps to tail
//
// Sibling manipulation is internal. Only add/remove of parent and child is
// exposed. remove_entity does NOT auto-detach; caller must unlink first.
// ============================================================================

@(private="file")
_attach :: proc(
    manager: ^Entity_Manager($EU),
    parent, child: Entity_Handle,
) -> bool {
    if parent == child { return false }

    p, p_ok := _resolve(manager, parent)
    c, c_ok := _resolve(manager, child)
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
        head, head_ok := _resolve(manager, head_h)
        if !head_ok { return false }
        _link_after(manager, head.prev_sibling, child)
    }
    c.parent = parent
    return true
}

@(private="file")
_unlink_from_circle :: proc(
    manager: ^Entity_Manager($EU),
    node: Entity_Handle,
) -> bool {
    n, n_ok := _resolve(manager, node)
    if !n_ok || n.parent == NIL_ENTITY_HANDLE { return false }
    p, p_ok := _resolve(manager, n.parent)
    if !p_ok { return false }

    if n.next_sibling == node {
        p.first_child = NIL_ENTITY_HANDLE
    } else {
        prev_h, next_h := n.prev_sibling, n.next_sibling
        prev, prev_ok := _resolve(manager, prev_h)
        next, next_ok := _resolve(manager, next_h)
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
_link_after :: proc(
    manager: ^Entity_Manager($EU),
    prev, new: Entity_Handle,
) -> bool {
    p, p_ok := _resolve(manager, prev)
    n, n_ok := _resolve(manager, new)
    if !p_ok || !n_ok { return false }

    old_next_h := p.next_sibling
    n.next_sibling = old_next_h
    n.prev_sibling = prev
    if old_next_h != NIL_ENTITY_HANDLE {
        old_next, old_next_ok := _resolve(manager, old_next_h)
        if !old_next_ok { return false }
        old_next.prev_sibling = new
    }
    p.next_sibling = new
    return true
}

add_parent :: proc(
    manager: ^Entity_Manager($EU),
    self, parent: Entity_Handle,
) -> bool {
    if parent == NIL_ENTITY_HANDLE { return false }
    return _attach(manager, parent, self)
}

remove_parent :: proc(
    manager: ^Entity_Manager($EU),
    self: Entity_Handle,
) -> bool {
    n, ok := _resolve(manager, self)
    if !ok || n.parent == NIL_ENTITY_HANDLE { return false }
    return _unlink_from_circle(manager, self)
}

add_child :: proc(
    manager: ^Entity_Manager($EU),
    self, child: Entity_Handle,
) -> bool {
    return _attach(manager, self, child)
}

remove_child :: proc(
    manager: ^Entity_Manager($EU),
    self, child: Entity_Handle,
) -> bool {
    c, ok := _resolve(manager, child)
    if !ok || c.parent != self { return false }
    return _unlink_from_circle(manager, child)
}
