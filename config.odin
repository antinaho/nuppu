package nuppu

import "core:mem"

// Compile-time engine tunables. Each subsystem owns the handle masks and
// validity asserts derived from these numbers (see material/shader/texture/mesh).

// MATERIALS
MAX_MATERIALS :: 1 << 8

// TEXTURES
MAX_TEXTURES :: 512

// SAMPLERS
MAX_SAMPLERS :: 64

// SHADERS
MAX_SHADERS :: 1 << 6

// MESHES
MAX_MESHES          :: 512
INDEX_STORAGE_BYTES :: 8 * mem.Megabyte
VERTEX_STORAGE_BYTES :: 8 * mem.Megabyte

MAX_INSTANCES_PER_TYPE :: max(u16)

FRAMES_IN_FLIGHT  :: 2
FRAME_ARENA_BYTES :: 16 * mem.Megabyte
