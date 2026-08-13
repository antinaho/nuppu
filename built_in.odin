package nuppu

// ---------------------------------------------------------------------------
// Unit meshes

HALF :: f32(0.5)

UNIT_CUBE_VERTEX_COUNT :: 24
UNIT_CUBE_INDEX_COUNT :: 36

@(rodata)
UNIT_CUBE_VERTICES := [][3]f32 {
    {-HALF, -HALF, +HALF},
	{+HALF, -HALF, +HALF},
	{+HALF, +HALF, +HALF},
	{-HALF, +HALF, +HALF},
	{+HALF, -HALF, +HALF},
	{+HALF, -HALF, -HALF},
	{+HALF, +HALF, -HALF},
	{+HALF, +HALF, +HALF},
	{+HALF, -HALF, -HALF},
	{-HALF, -HALF, -HALF},
	{-HALF, +HALF, -HALF},
	{+HALF, +HALF, -HALF},
	{-HALF, -HALF, -HALF},
	{-HALF, -HALF, +HALF},
	{-HALF, +HALF, +HALF},
	{-HALF, +HALF, -HALF},
	{-HALF, +HALF, +HALF},
	{+HALF, +HALF, +HALF},
	{+HALF, +HALF, -HALF},
	{-HALF, +HALF, -HALF},
	{-HALF, -HALF, -HALF},
	{+HALF, -HALF, -HALF},
	{+HALF, -HALF, +HALF},
	{-HALF, -HALF, +HALF},
}

@(rodata)
UNIT_CUBE_NORMALS := [][3]f32 {
    { 0,  0,  1},
    { 0,  0,  1},
    { 0,  0,  1},
    { 0,  0,  1},
    { 1,  0,  0},
    { 1,  0,  0},
    { 1,  0,  0},
    { 1,  0,  0},
    { 0,  0, -1},
    { 0,  0, -1},
    { 0,  0, -1},
    { 0,  0, -1},
    {-1,  0,  0},
    {-1,  0,  0},
    {-1,  0,  0},
    {-1,  0,  0},
    { 0,  1,  0},
    { 0,  1,  0},
    { 0,  1,  0},
    { 0,  1,  0},
    { 0, -1,  0},
    { 0, -1,  0},
    { 0, -1,  0},
    { 0, -1,  0},
}

@(rodata)
UNIT_CUBE_TEXCOORDS := [][2]f32 {
    {0, 1},
    {1, 1},
    {1, 0},
    {0, 0},
    {0, 1},
    {1, 1},
    {1, 0},
    {0, 0},
    {0, 1},
    {1, 1},
    {1, 0},
    {0, 0},
    {0, 1},
    {1, 1},
    {1, 0},
    {0, 0},
    {0, 1},
    {1, 1},
    {1, 0},
    {0, 0},
    {0, 1},
    {1, 1},
    {1, 0},
    {0, 0},
}

@(rodata)
UNIT_CUBE_INDICES := []u32 {
    0,  1,  2,  2,  3,  0, // front
	4,  5,  6,  6,  7,  4, // right
	8,  9,  10, 10, 11,  8, // back
	12, 13, 14, 14, 15, 12, // left
	16, 17, 18, 18, 19, 16, // top
	20, 21, 22, 22, 23, 20, // bottom
}
 // --------
@(rodata)
UNIT_QUAD_VERTICES := [][3]f32 {
    { -HALF, -HALF, +0 },
    { +HALF, -HALF, +0 },
    { +HALF, +HALF, +0 },
    { -HALF, +HALF, +0 },
}

@(rodata)
UNIT_QUAD_INDICES := []u32 {
    0,
    1,
    2,
    2,
    3,
    0,
}

// ---------------------------------------------------------------------------
// Camera

import glm "core:math/linalg/glsl"

Camera :: struct {
    position: [3]f32,

    near: f32,
    far: f32,
    fovy: f32,
    aspect_ratio: f32,
}

Camera_Data :: struct #align(16) {
    to_clip:  glm.mat4,
    to_view:  glm.mat4,
}

camera_data :: proc(camera: Camera, centre: [3]f32) -> Camera_Data {
    return Camera_Data {
		to_clip = glm.mat4Perspective(glm.radians_f32(camera.fovy), camera.aspect_ratio, camera.near, camera.far),
        to_view = glm.mat4LookAt(camera.position, centre, {0, 1, 0}),
    }
}