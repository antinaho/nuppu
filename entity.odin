package nuppu

import "base:intrinsics"
import "base:runtime"

Entity :: struct {
    using handle : Entity_Handle, // this entity
    // parent: Entity_Handle,
    // first_child: Entity_Handle,
    // next_sib:    Entity_Handle,
    // prev_sib:    Entity_Handle,

    position:   [3]f32,
    rotation:   [3]f32, // TODO quaternion
    scale:      [3]f32,
    flags:      u32,

    variant: any,
}

Entity_Handle :: struct {
    variant_idx: u8,
}

Entity_Data :: struct {
    buffer:     [^]byte,
    cap:        i32, // How many entities of a given variant can fit, NOT the cap of the buffer
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

entity_manager_init :: proc(
    manager: ^Entity_Manager($EU),
    elements_per_type: [255]int,
    allocator := context.allocator,
)
{
    val_ti := runtime.type_info_core(type_info_of(EU))
    val_ti_union := val_ti.variant.(runtime.Type_Info_Union)

    for val_var_ti, val_var_index in val_ti_union.variants {
        manager.sizes[val_var_index] = i64(val_var_ti.size)
    }

    for i in 0 ..< UNION_LEN(EU) {
        element_count := elements_per_type[i]
        data := runtime.make_aligned([]byte, element_count * int(manager.sizes[i]), alignment = 4096, allocator = allocator)
        manager.variants[i] = {
            buffer = raw_data(data),
            cap = i32(element_count),
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

// Only use this to initialize an entity. DON'T store the pointer
// Store the T.handle instead
@(require_results)
entity_new :: proc(
    manager: ^Entity_Manager($EU), 
    $T: typeid) -> ^T
    where intrinsics.type_is_variant_of(EU, T)       
{
    variant_idx := intrinsics.type_variant_index_of(EU, T)

    data := &manager.variants[variant_idx]

    index := -1
    gen := 0

    result := cast(^T)(uintptr(data.buffer) + uintptr(index) * uintptr(manager.sizes[variant_idx]))

    result.handle = {
        variant_idx = u8(variant_idx),
    }
    
    return result
}

//

_Door :: struct {
    using e: Entity,
    is_open: bool,
}

_Frog :: struct {
    using e: Entity,
    jump_height: f32,
}

Entity_Union :: union {
    _Frog,
    _Door,
}

F :: proc() {
    manager := new(Entity_Manager(Entity_Union))
    entity_manager_init(manager, 1024, context.allocator)

    handle := entity_new(manager, _Door)
}
