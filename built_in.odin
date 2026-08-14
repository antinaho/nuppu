package nuppu

import "core:math"
import glm "core:math/linalg/glsl"

// ---------------------------------------------------------------------------
// Unit meshes

HALF :: f32(0.5)

UNIT_CUBE_VERTEX_COUNT :: 24
UNIT_CUBE_UV_COUNT :: UNIT_CUBE_VERTEX_COUNT
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

camera_data :: proc(camera: Camera, centre: [3]f32, up: [3]f32 = {0, 1, 0}) -> Camera_Data {
    return Camera_Data {
		to_clip = glm.mat4Perspective(glm.radians_f32(camera.fovy), camera.aspect_ratio, camera.near, camera.far),
        to_view = glm.mat4LookAt(camera.position, centre, up),
    }
}

update_camera :: proc(prev_camera: Camera, curr_camera: Camera, alpha: f32) -> Camera {
    return Camera {
        position = math.lerp(prev_camera.position, curr_camera.position, alpha),
        near = math.lerp(prev_camera.near, curr_camera.near, alpha),
        far = math.lerp(prev_camera.far, curr_camera.far, alpha),
        fovy = math.lerp(prev_camera.fovy, curr_camera.fovy, alpha),
        aspect_ratio = math.lerp(prev_camera.aspect_ratio, curr_camera.aspect_ratio, alpha),
    }
}

// ---------------------------------------------------------------------------
// Math

shortest_arc_lerp :: proc(prev, curr, alpha: f32) -> f32 {
    PI  :: 3.141592653589793
    TAU :: 2.0 * PI

    // Normalize both to [-π, π]
    a := prev - TAU * math.floor((prev + PI) / TAU)
    b := curr - TAU * math.floor((curr + PI) / TAU)

    // Shortest-path difference, wrapped to (-π, π]
    diff := b - a
    diff -= TAU * math.floor((diff + PI) / TAU)

    return a + diff * alpha
}

// Lerps two euler-angle rotations by alpha. Composes the interpolated XYZ
// rotation into a mat4 you can drop directly into a TRS.
//
// Multi-axis rotations near gimbal lock (±90° pitch) are approximate —
// convert to quat + glm.quatSlerp later if you need exact 3D-aware interp.
lerp_rotation :: proc(prev, curr: [3]f32, alpha: f32) -> matrix[4, 4]f32 {
    rx := shortest_arc_lerp(prev.x, curr.x, alpha)
    ry := shortest_arc_lerp(prev.y, curr.y, alpha)
    rz := shortest_arc_lerp(prev.z, curr.z, alpha)

    return glm.mat4Rotate({0, 0, 1}, rz) *
           glm.mat4Rotate({0, 1, 0}, ry) *
           glm.mat4Rotate({1, 0, 0}, rx)
}

// ---------------------------------------------------------------------------
// OBJ loader

import "core:log"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:mem"

Vertex_3D :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

OBJ_Mesh :: struct {
	vertices: []Vertex_3D,
	indices:  []u32,
}

mesh_destroy :: proc(m: ^OBJ_Mesh, allocator: mem.Allocator) {
	delete(m.vertices, allocator)
	delete(m.indices, allocator)
	m^ = {}
}

@(private)
abs_int :: proc(x: int) -> int {
	return x < 0 ? -x : x
}

mesh_load_from_obj :: proc(path: string, allocator: mem.Allocator) -> (mesh: OBJ_Mesh, err: os.Error) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		return {}, read_err
	}
	defer delete(data, allocator)

	positions: [dynamic][3]f32
	uvs:       [dynamic][2]f32
	normals:   [dynamic][3]f32
	vertices:  [dynamic]Vertex_3D
	findices:  [dynamic]u32
	defer {
		delete(positions)
		delete(uvs)
		delete(normals)
	}

	parse_face_vertex :: proc(
		token: string,
		positions: [dynamic][3]f32,
		uvs:       [dynamic][2]f32,
		normals:   [dynamic][3]f32,
		out: ^Vertex_3D,
	) -> bool {
		parts, _ := strings.split(token, "/", context.temp_allocator)
		defer delete(parts, context.temp_allocator)

		v_idx, v_ok := strconv.parse_int(parts[0])
		if !v_ok || v_idx == 0 || abs_int(v_idx) > len(positions) { return false }
		out.position = positions[v_idx > 0 ? v_idx - 1 : len(positions) + v_idx]

		if len(parts) >= 2 && len(parts[1]) > 0 {
			vt_idx, vt_ok := strconv.parse_int(parts[1])
			if vt_ok && vt_idx != 0 && abs_int(vt_idx) <= len(uvs) {
				out.uv = uvs[vt_idx > 0 ? vt_idx - 1 : len(uvs) + vt_idx]
			}
		}

		if len(parts) >= 3 && len(parts[2]) > 0 {
			vn_idx, vn_ok := strconv.parse_int(parts[2])
			if vn_ok && vn_idx != 0 && abs_int(vn_idx) <= len(normals) {
				out.normal = normals[vn_idx > 0 ? vn_idx - 1 : len(normals) + vn_idx]
			}
		}
		return true
	}

	line_it := strings.split_lines(string(data), context.temp_allocator)
	for line in line_it {
		trim := strings.trim_space(line)
		if len(trim) == 0 || trim[0] == '#' { continue }

		fields, _ := strings.split(trim, " ", context.temp_allocator)
		if len(fields) == 0 { continue }

		switch fields[0] {
		case "v":
			if len(fields) < 4 {
				log.warnf("ignoring short v line: %q in %s", trim, path)
				break
			}
			if x, xok := strconv.parse_f32(fields[1]); xok {
				if y, yok := strconv.parse_f32(fields[2]); yok {
					if z, zok := strconv.parse_f32(fields[3]); zok {
						append(&positions, [3]f32{x, y, z})
					} else {
						log.warnf("malformed v z: %q in %s", trim, path)
					}
				} else {
					log.warnf("malformed v y: %q in %s", trim, path)
				}
			} else {
				log.warnf("malformed v x: %q in %s", trim, path)
			}
		case "vt":
			if len(fields) < 3 {
				log.warnf("ignoring short vt line: %q in %s", trim, path)
				break
			}
			if u, uok := strconv.parse_f32(fields[1]); uok {
				if v, vok := strconv.parse_f32(fields[2]); vok {
					append(&uvs, [2]f32{u, v})
				} else {
					log.warnf("malformed vt v: %q in %s", trim, path)
				}
			} else {
				log.warnf("malformed vt u: %q in %s", trim, path)
			}
		case "vn":
			if len(fields) < 4 {
				log.warnf("ignoring short vn line: %q in %s", trim, path)
				break
			}
			if x, xok := strconv.parse_f32(fields[1]); xok {
				if y, yok := strconv.parse_f32(fields[2]); yok {
					if z, zok := strconv.parse_f32(fields[3]); zok {
						append(&normals, [3]f32{x, y, z})
					} else {
						log.warnf("malformed vn z: %q in %s", trim, path)
					}
				} else {
					log.warnf("malformed vn y: %q in %s", trim, path)
				}
			} else {
				log.warnf("malformed vn x: %q in %s", trim, path)
			}
		case "f":
			if len(fields) < 4 {
				log.warnf("ignoring short f line: %q in %s", trim, path)
				break
			}

			parsed: [dynamic]Vertex_3D
			all_ok := true
			for i in 1 ..< len(fields) {
				vtx: Vertex_3D
				if parse_face_vertex(fields[i], positions, uvs, normals, &vtx) {
					append(&parsed, vtx)
				} else {
					all_ok = false
					break
				}
			}
			if !all_ok || len(parsed) < 3 {
				log.warnf("dropping degenerate face in %s", path)
				delete(parsed)
				continue
			}

			// Fan-triangulate the polygon.
			base_idx := u32(len(vertices))
			append(&vertices, ..parsed[:])
			for i in 1 ..< len(parsed) - 1 {
				append(&findices, base_idx)
				append(&findices, base_idx + u32(i))
				append(&findices, base_idx + u32(i + 1))
			}
			delete(parsed)
		}
		delete(fields, context.temp_allocator)
	}

	mesh.vertices = vertices[:]
	mesh.indices  = findices[:]
	return mesh, nil
}
