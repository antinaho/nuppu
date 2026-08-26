package nuppu

HALF :: f32(0.5)

UNIT_CUBE_VERTEX_COUNT :: 24
UNIT_CUBE_UV_COUNT :: UNIT_CUBE_VERTEX_COUNT
UNIT_CUBE_INDEX_COUNT :: 36

@(rodata)
UNIT_CUBE_VERTICES := [24][3]f32 {
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
UNIT_CUBE_NORMALS := [24][3]f32 {
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
UNIT_CUBE_TEXCOORDS := [24][2]f32 {
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
UNIT_CUBE_INDICES := [36]u32 {
    0,  1,  2,  2,  3,  0, // front
	4,  5,  6,  6,  7,  4, // right
	8,  9,  10, 10, 11,  8, // back
	12, 13, 14, 14, 15, 12, // left
	16, 17, 18, 18, 19, 16, // top
	20, 21, 22, 22, 23, 20, // bottom
}
 // --------
@(rodata)
UNIT_QUAD_VERTICES := [4][3]f32 {
    { -HALF, -HALF, +0 },
    { +HALF, -HALF, +0 },
    { +HALF, +HALF, +0 },
    { -HALF, +HALF, +0 },
}

@(rodata)
UNIT_QUAD_INDICES := [6]u32 {
    0,
    1,
    2,
    2,
    3,
    0,
}