package entity_tests

import "core:testing"
import "base:intrinsics"
import nuppu "../../"

Node :: struct {
    using e: ^nuppu.Entity,
}

Test_Node_Union :: union {
    Node,
}

@(private="file")
make_node_manager :: proc() -> ^nuppu.Entity_Manager {
    manager, _ := new(nuppu.Entity_Manager)
    nuppu.entity_manager_init(manager)
    nuppu.entity_manager_add_variant(manager, Node, 6)
    return manager
}

@(private="file")
make_node :: proc(manager: ^nuppu.Entity_Manager) -> ^Node {
    handle, ok := nuppu._entity_add(manager, Node)
    if !ok { return nil }
    node, _ := nuppu.entity_get_typed(manager, handle, Node)
    return node
}

// ============================================================================
// Fresh node state
// ============================================================================

@(test)
test_fresh_node_has_no_relations :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    testing.expect(t, node != nil, "node is not nil")

    testing.expect(t, node.parent == nuppu.entity_root(manager).handle, "parent is NIL (root)")
    testing.expect(t, node.first_child == nuppu.NIL_ENTITY_HANDLE, "first_child is NIL")
    testing.expect(t, node.next_sibling == node.handle, "next_sibling is node")
    testing.expect(t, node.prev_sibling == node.handle, "prev_sibling is node")
}

// ============================================================================
// parent_add / unparent / child_add
// ============================================================================

@(test)
test_add_parent_nil_rejected :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    testing.expect(t, node != nil, "node is not nil")

    testing.expect_value(t, nuppu.parent_add(manager, node.handle, nuppu.NIL_ENTITY_HANDLE), false)

    n, _ := nuppu.entity_get(manager, node.handle)
    testing.expect(t, n.parent == nuppu.entity_root(manager).handle, "node.parent unchanged")
}

@(test)
test_add_parent_self_cycle_rejected :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    testing.expect(t, node != nil, "node is not nil")

    testing.expect_value(t, nuppu.parent_add(manager, node.handle, node.handle), false)
}

@(test)
test_add_child_self_cycle_rejected :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    testing.expect(t, node != nil, "node is not nil")

    testing.expect_value(t, nuppu.child_add(manager, node.handle, node.handle), false)
}

@(test)
test_single_child_forms_self_circle :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    child  := make_node(manager)
    testing.expect(t, parent != nil, "node is not nil")
    testing.expect(t, child != nil, "node is not nil")

    testing.expect_value(t, nuppu.parent_add(manager, child.handle, parent.handle), true)

    p, _ := nuppu.entity_get(manager, parent.handle)
    c, _ := nuppu.entity_get(manager, child.handle)

    testing.expect(t, p.first_child == child.handle, "parent.first_child == child")
    testing.expect(t, c.parent == parent.handle, "child.parent == parent")
    testing.expect(t, c.next_sibling == child.handle, "single child: next_sibling == self")
    testing.expect(t, c.prev_sibling == child.handle, "single child: prev_sibling == self")
}

@(test)
test_multiple_children_wrap_at_tail :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    testing.expect(t, parent != nil, "node is not nil")
    parent_h := parent.handle

    n :: 4
    children: [n]nuppu.Entity_Handle
    for i in 0..<n {
        c := make_node(manager)
        testing.expect(t, c != nil, "node is not nil")
        children[i] = c.handle
        nuppu.parent_add(manager, c.handle, parent_h)
    }
    // parent_add inserts at the tail, so the first-added child remains the head.
    head := children[0]
    tail := children[n-1]

    p, _ := nuppu.entity_get(manager, parent_h)
    testing.expect(t, p.first_child == head, "first-added is the head")

    // Walk next_sibling N times — should wrap back to head.
    cur := head
    for _ in 0..<n {
        c_node, _ := nuppu.entity_get(manager, cur)
        cur = c_node.next_sibling
    }
    testing.expect(t, cur == head, "next_sibling chain wraps back to head")

    // Walk prev_sibling N times — should also wrap back to head (via tail).
    cur = head
    for _ in 0..<n {
        c_node, _ := nuppu.entity_get(manager, cur)
        cur = c_node.prev_sibling
    }
    testing.expect(t, cur == head, "prev_sibling chain wraps back to head")

    // Spot-check the wrap edges: head.prev == tail, tail.next == head.
    head_node, _ := nuppu.entity_get(manager, head)
    tail_node, _ := nuppu.entity_get(manager, tail)
    testing.expect(t, head_node.prev_sibling == tail, "head.prev wraps to tail")
    testing.expect(t, tail_node.next_sibling == head, "tail.next wraps to head")
}

// ============================================================================
// unparent / child_remove
// ============================================================================

@(test)
test_unparent_at_root_fails :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    if node == nil { return }

    testing.expect_value(t, nuppu.unparent(manager, node.handle), false)
}

@(test)
test_unparent_moves_to_root :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    child  := make_node(manager)
    if parent == nil || child == nil { return }

    nuppu.parent_add(manager, child.handle, parent.handle)

    testing.expect_value(t, nuppu.unparent(manager, child.handle), true)

    p, _ := nuppu.entity_get(manager, parent.handle)
    c, _ := nuppu.entity_get(manager, child.handle)

    testing.expect(t, p.first_child == nuppu.NIL_ENTITY_HANDLE, "parent.first_child cleared")
    testing.expect(t, c.parent == nuppu.entity_root(manager).handle, "child re-parented to root")
}

@(test)
test_remove_only_child_clears_parent :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    child  := make_node(manager)
    if parent == nil || child == nil { return }

    nuppu.parent_add(manager, child.handle, parent.handle)
    testing.expect_value(t, nuppu.child_remove(manager, parent.handle, child.handle), true)

    p, _ := nuppu.entity_get(manager, parent.handle)
    testing.expect(t, p.first_child == nuppu.NIL_ENTITY_HANDLE, "parent has no children")
}

@(test)
test_remove_child_head_promotes_next :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    if parent == nil { return }
    parent_h := parent.handle

    n :: 3
    children: [n]nuppu.Entity_Handle
    for i in 0..<n {
        c := make_node(manager)
        if c == nil { return }
        children[i] = c.handle
        nuppu.parent_add(manager, c.handle, parent_h)
    }
    head := children[0]
    middle := children[1]
    tail := children[n-1]

    testing.expect_value(t, nuppu.child_remove(manager, parent_h, head), true)

    p, _ := nuppu.entity_get(manager, parent_h)
    testing.expect(t, p.first_child == middle, "head promoted to next")

    // New circle: middle -> tail -> middle (wrap).
    middle_node, _ := nuppu.entity_get(manager, middle)
    tail_node, _ := nuppu.entity_get(manager, tail)
    testing.expect(t, middle_node.next_sibling == tail, "middle.next == tail")
    testing.expect(t, middle_node.prev_sibling == tail, "middle.prev wraps to tail")
    testing.expect(t, tail_node.next_sibling == middle, "tail.next wraps to new head")
    testing.expect(t, tail_node.prev_sibling == middle, "tail.prev == middle")

    // Removed head is re-parented to the root.
    removed, ok := nuppu.entity_get(manager, head)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect(t, removed.parent == nuppu.entity_root(manager).handle, "removed.parent is root")
    }
}

@(test)
test_remove_child_tail_keeps_head :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    if parent == nil { return }
    parent_h := parent.handle

    n :: 3
    children: [n]nuppu.Entity_Handle
    for i in 0..<n {
        c := make_node(manager)
        if c == nil { return }
        children[i] = c.handle
        nuppu.parent_add(manager, c.handle, parent_h)
    }
    head := children[0]
    middle := children[1]
    tail := children[n-1]

    testing.expect_value(t, nuppu.child_remove(manager, parent_h, tail), true)

    p, _ := nuppu.entity_get(manager, parent_h)
    testing.expect(t, p.first_child == head, "head unchanged")

    // New circle: head <-> middle (mutual).
    head_node, _ := nuppu.entity_get(manager, head)
    middle_node, _ := nuppu.entity_get(manager, middle)
    testing.expect(t, head_node.next_sibling == middle, "head.next == middle")
    testing.expect(t, head_node.prev_sibling == middle, "head.prev wraps to middle")
    testing.expect(t, middle_node.next_sibling == head, "middle.next wraps to head")
    testing.expect(t, middle_node.prev_sibling == head, "middle.prev == head")
}

@(test)
test_remove_child_middle_closes_gap :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    if parent == nil { return }
    parent_h := parent.handle

    n :: 3
    children: [n]nuppu.Entity_Handle
    for i in 0..<n {
        c := make_node(manager)
        if c == nil { return }
        children[i] = c.handle
        nuppu.parent_add(manager, c.handle, parent_h)
    }
    head := children[0]
    middle := children[1]
    tail := children[n-1]

    testing.expect_value(t, nuppu.child_remove(manager, parent_h, middle), true)

    p, _ := nuppu.entity_get(manager, parent_h)
    testing.expect(t, p.first_child == head, "head unchanged")

    head_node, _ := nuppu.entity_get(manager, head)
    tail_node, _ := nuppu.entity_get(manager, tail)
    testing.expect(t, head_node.next_sibling == tail, "head.next skips middle to tail")
    testing.expect(t, tail_node.prev_sibling == head, "tail.prev skips middle to head")
}

@(test)
test_remove_child_rejects_not_mine :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    a := make_node(manager)
    b := make_node(manager)
    c := make_node(manager)
    if a == nil || b == nil || c == nil { return }

    nuppu.parent_add(manager, b.handle, a.handle)
    nuppu.parent_add(manager, c.handle, a.handle)

    // b is a child of a, not of c.
    testing.expect_value(t, nuppu.child_remove(manager, c.handle, b.handle), false)

    // b is still attached to a.
    b_node, _ := nuppu.entity_get(manager, b.handle)
    testing.expect(t, b_node.parent == a.handle, "b still parented to a")
}

// ============================================================================
// Auto-unlink on re-attach
// ============================================================================

@(test)
test_add_parent_auto_unlinks_old :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    a := make_node(manager)
    b := make_node(manager)
    c := make_node(manager)
    if a == nil || b == nil || c == nil { return }

    nuppu.parent_add(manager, b.handle, a.handle)
    nuppu.parent_add(manager, c.handle, a.handle)

    // Re-parent b under c.
    testing.expect_value(t, nuppu.parent_add(manager, b.handle, c.handle), true)

    a_node, _ := nuppu.entity_get(manager, a.handle)
    c_node, _ := nuppu.entity_get(manager, c.handle)
    b_node, _ := nuppu.entity_get(manager, b.handle)

    testing.expect(t, a_node.first_child == c.handle, "a.first_child now c (b detached)")
    testing.expect(t, c_node.first_child == b.handle, "c.first_child == b")
    testing.expect(t, b_node.parent == c.handle, "b.parent == c")

    // b is the only child of c → self-circle.
    testing.expect(t, b_node.next_sibling == b.handle, "b.next_sibling wraps to self")
    testing.expect(t, b_node.prev_sibling == b.handle, "b.prev_sibling wraps to self")
}

@(test)
test_add_child_inside_circle_stays_attached :: proc(t: ^testing.T) {
    // A node already in the middle of a circle: adding it under a new parent
    // must detach it from its old position first.
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    a := make_node(manager)
    b := make_node(manager)
    x := make_node(manager)
    y := make_node(manager)
    if a == nil || b == nil || x == nil || y == nil { return }

    // a's children: x (head), b (tail), y — order is head -> ... -> tail.
    nuppu.parent_add(manager, x.handle, a.handle)
    nuppu.parent_add(manager, b.handle, a.handle)
    nuppu.parent_add(manager, y.handle, a.handle)

    // Re-parent x under b.
    nuppu.parent_add(manager, x.handle, b.handle)

    a_node, _ := nuppu.entity_get(manager, a.handle)
    b_node, _ := nuppu.entity_get(manager, b.handle)
    x_node, _ := nuppu.entity_get(manager, x.handle)

    // a's head pointer advances to x's next_sibling (b) — the natural choice
    // for preserving insertion order in the surviving 2-element circle.
    testing.expect(t, a_node.first_child == b.handle, "a.first_child == b (was x's next)")
    testing.expect(t, b_node.first_child == x.handle, "b.first_child == x")
    testing.expect(t, x_node.parent == b.handle, "x.parent == b")

    // a's remaining children b and y form a 2-element circle (b <-> y).
    b_node_2, _ := nuppu.entity_get(manager, b.handle)
    y_node, _ := nuppu.entity_get(manager, y.handle)
    testing.expect(t, b_node_2.next_sibling == y.handle, "b.next -> y")
    testing.expect(t, b_node_2.prev_sibling == y.handle, "b.prev wraps to y")
    testing.expect(t, y_node.next_sibling == b.handle, "y.next wraps to b")
    testing.expect(t, y_node.prev_sibling == b.handle, "y.prev -> b")
}

// ============================================================================
// Cleanup flow with entity_remove (tree-aware)
// ============================================================================

@(test)
test_remove_entity_unlinks_from_parent :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    child  := make_node(manager)
    if parent == nil || child == nil { return }

    nuppu.parent_add(manager, child.handle, parent.handle)

    child_h := child.handle
    testing.expect_value(t, nuppu.entity_remove(manager, child_h), true)

    p, _ := nuppu.entity_get(manager, parent.handle)
    testing.expect(t, p.first_child == nuppu.NIL_ENTITY_HANDLE, "parent.first_child cleared (auto-unlink)")

    _, found := nuppu.entity_get(manager, child_h)
    testing.expect_value(t, found, false)
}

@(test)
test_remove_root_child_unlinks_from_root :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    if node == nil { return }

    node_h := node.handle
    testing.expect_value(t, nuppu.entity_remove(manager, node_h), true)

    root := nuppu.entity_root(manager)
    testing.expect(t, root.first_child == nuppu.NIL_ENTITY_HANDLE, "root.first_child cleared")

    _, found := nuppu.entity_get(manager, node_h)
    testing.expect_value(t, found, false)
}

@(test)
test_remove_root_rejected :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    root := nuppu.entity_root(manager)
    testing.expect_value(t, nuppu.entity_remove(manager, root.handle), false)
}

@(test)
test_child_remove_root_rejected :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    node := make_node(manager)
    if node == nil { return }
    root_h := nuppu.entity_root(manager).handle

    testing.expect_value(t, nuppu.child_remove(manager, root_h, node.handle), false)

    n, _ := nuppu.entity_get(manager, node.handle)
    testing.expect(t, n.parent == root_h, "node still under root")
}

@(test)
test_reparent_from_root_via_parent_add :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    a := make_node(manager)
    b := make_node(manager)
    if a == nil || b == nil { return }

    testing.expect_value(t, nuppu.parent_add(manager, a.handle, b.handle), true)

    a_node, _ := nuppu.entity_get(manager, a.handle)
    b_node, _ := nuppu.entity_get(manager, b.handle)
    root := nuppu.entity_root(manager)

    testing.expect(t, a_node.parent == b.handle, "a reparented under b")
    testing.expect(t, b_node.first_child == a.handle, "b.first_child == a")
    testing.expect(t, root.first_child == b.handle, "root.first_child now b")
    testing.expect(t, b_node.next_sibling == b.handle, "b wraps to self (only child of root)")
    testing.expect(t, b_node.prev_sibling == b.handle, "b wraps to self")
}

@(test)
test_explicit_unlink_then_remove :: proc(t: ^testing.T) {
    manager := make_node_manager()
    defer nuppu.entity_manager_destroy(manager)
    parent := make_node(manager)
    child  := make_node(manager)
    if parent == nil || child == nil { return }

    nuppu.parent_add(manager, child.handle, parent.handle)

    child_h := child.handle
    // Pre-unlink is no longer required, but still permitted and harmless.
    testing.expect_value(t, nuppu.unparent(manager, child_h), true)
    testing.expect_value(t, nuppu.entity_remove(manager, child_h), true)

    p, _ := nuppu.entity_get(manager, parent.handle)
    testing.expect(t, p.first_child == nuppu.NIL_ENTITY_HANDLE, "parent has no children")

    _, found := nuppu.entity_get(manager, child_h)
    testing.expect_value(t, found, false)
}
