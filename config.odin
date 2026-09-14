package nuppu

import "core:mem"

CONFIG : struct {
    // Material
    max_materials: int,
    material_param_bytes: int,

    // Shader
    max_shaders: int,

    // Mesh
    max_meshes: int,

    // Entity
    entity_max_materials: int,

    // Instance data
    max_instance_data_bytes: int, // per entity, per frame

} : {

    // Material
    max_materials = 512,
    material_param_bytes = 1 * mem.Megabyte,

    // Shader
    max_shaders = 64,

    // Mesh
    max_meshes = 512,

    // Entity
    entity_max_materials = 6,

    // Instance data
    max_instance_data_bytes = 64,
}
