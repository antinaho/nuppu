#+build !js
#+build !freestanding

package nuppu

import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import glm "core:math/linalg/glsl"

// Camera

Camera :: struct {
    position: [3]f32,

    near: f32,
    far: f32,
    fovy: f32,
    aspect_ratio: f32,
}

update_camera :: proc(prev_camera: Camera, curr_camera: Camera, alpha: f32) -> Camera {
    return Camera {
        position = math.lerp(prev_camera.position, curr_camera.position, alpha),
        near = math.lerp(prev_camera.near, curr_camera.near, alpha),
        far = math.lerp(prev_camera.far, curr_camera.far, alpha),
        fovy = math.lerp(prev_camera.fovy, curr_camera.fovy, alpha),
        aspect_ratio = curr_camera.aspect_ratio,
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

OBJ_Mesh :: struct {
	positions: [][3]f32,
	normals:   [][3]f32,
	uvs:       [][2]f32,
	indices:   []u32,
}

mesh_destroy :: proc(m: ^OBJ_Mesh, allocator: mem.Allocator) {
	delete(m.positions, allocator)
	delete(m.normals, allocator)
	delete(m.uvs, allocator)
	delete(m.indices, allocator)
	m^ = {}
}

// A single face-vertex reference in the OBJ file. All indices are 1-based as
// they appear in the OBJ; negative values are pre-resolved to absolute. t and n
// are 0 when the OBJ reference omitted them (e.g. "1//3" -> {1, 0, 3}).
Face_Ref :: struct {
	p, t, n: int,
}

// Barycentric point-in-triangle test on raw 3D positions. Assumes the three
// triangle vertices are coplanar (the polygon's vertices generally are, by
// construction of the ear clipper below).
@(private)
point_in_triangle :: proc(p, a, b, c: [3]f32) -> bool {
	v0  := c - a
	v1  := b - a
	v2  := p - a

	dot00 := glm.dot(v0, v0)
	dot01 := glm.dot(v0, v1)
	dot02 := glm.dot(v0, v2)
	dot11 := glm.dot(v1, v1)
	dot12 := glm.dot(v1, v2)

	inv_denom := 1.0 / (dot00 * dot11 - dot01 * dot01)
	u := (dot11 * dot02 - dot01 * dot12) * inv_denom
	v := (dot00 * dot12 - dot01 * dot02) * inv_denom

	return (u >= 0) && (v >= 0) && (u + v <= 1)
}

// Triangulates a simple polygon via ear clipping. Correct for non-convex
// polygons (unlike fan triangulation). The polygon is given by `poly_positions`
// (in vertex order); `poly_indices` maps each polygon-vertex to its
// already-deduplicated global vertex index, which is what gets emitted into
// `into`. Falls back to a single triangle + warning on degenerate input
// (collinear vertices, self-intersection) so the loader can never loop forever.
@(private)
ear_clip_polygon :: proc(poly_positions: [][3]f32, poly_indices: []u32, into: ^[dynamic]u32) {
	n := len(poly_positions)
	if n < 3 { return }

	// Plane normal via Newell's method (robust against non-coplanar input).
	normal: [3]f32
	for i in 0 ..< n {
		curr := poly_positions[i]
		next := poly_positions[(i + 1) % n]
		normal.x += (curr.y - next.y) * (curr.z + next.z)
		normal.y += (curr.z - next.z) * (curr.x + next.x)
		normal.z += (curr.x - next.x) * (curr.y + next.y)
	}
	n_len := glm.length(normal)
	if n_len > 0 { normal /= n_len }

	alive := make([dynamic]int, context.temp_allocator)
	defer delete(alive)
	for i in 0 ..< n { append(&alive, i) }

	// Safety cap: O(n^2) iterations is the worst case for ear clipping.
	safety := n * n + 4
	for len(alive) > 3 && safety > 0 {
		safety -= 1
		found_ear := false

		for ai in 0 ..< len(alive) {
			prev_i := alive[(ai + len(alive) - 1) % len(alive)]
			curr_i := alive[ai]
			next_i := alive[(ai + 1) % len(alive)]

			a := poly_positions[prev_i]
			b := poly_positions[curr_i]
			c := poly_positions[next_i]

			// Convex w.r.t. polygon normal?
			edge1 := b - a
			edge2 := c - a
			cross_x := edge1.y * edge2.z - edge1.z * edge2.y
			cross_y := edge1.z * edge2.x - edge1.x * edge2.z
			cross_z := edge1.x * edge2.y - edge1.y * edge2.x
			if cross_x * normal.x + cross_y * normal.y + cross_z * normal.z <= 0 {
				continue
			}

			// No other vertex inside triangle (a, b, c)?
			inside := false
			for ti in 0 ..< len(alive) {
				t := alive[ti]
				if t == prev_i || t == curr_i || t == next_i { continue }
				if point_in_triangle(poly_positions[t], a, b, c) {
					inside = true
					break
				}
			}
			if inside { continue }

			append(into, poly_indices[prev_i], poly_indices[curr_i], poly_indices[next_i])
			unordered_remove(&alive, ai)
			found_ear = true
			break
		}

		if !found_ear {
			log.warnf("ear clipping failed (degenerate polygon), emitting first triangle only")
			append(into, poly_indices[alive[0]], poly_indices[alive[1]], poly_indices[alive[2]])
			return
		}
	}

	if len(alive) == 3 {
		append(into, poly_indices[alive[0]], poly_indices[alive[1]], poly_indices[alive[2]])
	}
}

when ODIN_OS != .JS {

mesh_load_from_obj :: proc(path: string, allocator: mem.Allocator) -> (mesh: OBJ_Mesh, err: os.Error) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		return {}, read_err
	}
	defer delete(data, allocator)

	positions := make([dynamic][3]f32, allocator)
	uvs       := make([dynamic][2]f32, allocator)
	normals   := make([dynamic][3]f32, allocator)
	findices  := make([dynamic]u32, allocator)
	dedup     := make(map[Face_Ref]u32, allocator)
	defer {
		delete(positions)
		delete(uvs)
		delete(normals)
		delete(dedup)
	}

	// Parallel vertex arrays: positions[i], normals[i], uvs[i] describe vertex i.
	// All three stay in lockstep so a single u32 index references all attributes.
	vert_positions := make([dynamic][3]f32, allocator)
	vert_normals   := make([dynamic][3]f32, allocator)
	vert_uvs       := make([dynamic][2]f32, allocator)
	defer {
		delete(vert_positions)
		delete(vert_normals)
		delete(vert_uvs)
	}

	// Face_Ref builder from a single "v/vt/vn" token. Returns false if the
	// position index is invalid (face gets dropped).
	resolve_ref :: proc(
		token: string,
		positions: [dynamic][3]f32,
		uvs:       [dynamic][2]f32,
		normals:   [dynamic][3]f32,
	) -> (ref: Face_Ref, ok: bool) {
		parts := strings.split(token, "/", context.temp_allocator)
		if len(parts) == 0 { return {}, false }

		p_raw, p_ok := strconv.parse_int(parts[0])
		if !p_ok || p_raw == 0 || math.abs(p_raw) > len(positions) {
			return {}, false
		}
		ref.p = p_raw > 0 ? p_raw : len(positions) + p_raw + 1

		if len(parts) >= 2 && len(parts[1]) > 0 {
			if t_raw, t_ok := strconv.parse_int(parts[1]); t_ok {
				if t_raw != 0 {
					if math.abs(t_raw) > len(uvs) {
						log.warnf("malformed vt index in face vertex %q", token)
					} else {
						ref.t = t_raw > 0 ? t_raw : len(uvs) + t_raw + 1
					}
				}
			}
		}

		if len(parts) >= 3 && len(parts[2]) > 0 {
			if n_raw, n_ok := strconv.parse_int(parts[2]); n_ok {
				if n_raw != 0 {
					if math.abs(n_raw) > len(normals) {
						log.warnf("malformed vn index in face vertex %q", token)
					} else {
						ref.n = n_raw > 0 ? n_raw : len(normals) + n_raw + 1
					}
				}
			}
		}
		return ref, true
	}

	line_it := strings.split_lines(string(data), context.temp_allocator)
	for line in line_it {
		trim := strings.trim_space(line)
		if len(trim) == 0 || trim[0] == '#' { continue }

		fields := strings.split(trim, " ", context.temp_allocator)
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

			// Resolve all face-vertex references, deduplicating as we go.
			poly_indices   := make([dynamic]u32, context.temp_allocator)
			poly_positions := make([dynamic][3]f32, context.temp_allocator)
			all_ok := true

			for i in 1 ..< len(fields) {
				ref, ok := resolve_ref(fields[i], positions, uvs, normals)
				if !ok {
					log.warnf("dropping malformed face vertex %q in %s", fields[i], path)
					all_ok = false
					break
				}

				// Position is always valid (resolve_ref checked ref.p).
				append(&poly_positions, positions[ref.p - 1])

				if existing, found := dedup[ref]; found {
					append(&poly_indices, existing)
				} else {
					new_idx := u32(len(vert_positions))
					append(&vert_positions, positions[ref.p - 1])
					if ref.n >= 1 && ref.n <= len(normals) {
						append(&vert_normals, normals[ref.n - 1])
					} else {
						append(&vert_normals, [3]f32{})
					}
					if ref.t >= 1 && ref.t <= len(uvs) {
						append(&vert_uvs, uvs[ref.t - 1])
					} else {
						append(&vert_uvs, [2]f32{})
					}
					dedup[ref] = new_idx
					append(&poly_indices, new_idx)
				}
			}

			if !all_ok || len(poly_indices) < 3 {
				log.warnf("dropping degenerate face in %s", path)
				continue
			}

			// 3-vertex face: trivial triangle.
			if len(poly_indices) == 3 {
				append(&findices, poly_indices[0], poly_indices[1], poly_indices[2])
			} else {
				ear_clip_polygon(poly_positions[:], poly_indices[:], &findices)
			}
		}
	}

	mesh.positions = vert_positions[:]
	mesh.normals   = vert_normals[:]
	mesh.uvs       = vert_uvs[:]
	mesh.indices   = findices[:]

	// If the OBJ had no `vn` lines, vert_normals is all zeros. Compute smooth
	// vertex normals from the indexed triangles: each vertex accumulates the
	// unnormalized face normal of every triangle it belongs to, then we
	// normalize at the end. Produces correct smooth shading for meshes like
	// the Stanford bunny that ship positions+faces only.
	if len(normals) == 0 && len(findices) >= 3 {
		for i := 0; i + 2 < len(findices); i += 3 {
			i0, i1, i2 := findices[i], findices[i+1], findices[i+2]
			p0 := vert_positions[i0]
			p1 := vert_positions[i1]
			p2 := vert_positions[i2]

			// Face normal (unnormalized, magnitude = 2 * triangle area).
			e1 := p1 - p0
			e2 := p2 - p0
			n  := [3]f32{
				e1.y * e2.z - e1.z * e2.y,
				e1.z * e2.x - e1.x * e2.z,
				e1.x * e2.y - e1.y * e2.x,
			}

			vert_normals[i0] += n
			vert_normals[i1] += n
			vert_normals[i2] += n
		}
		for i in 0 ..< len(vert_normals) {
			v := vert_normals[i]
			l := math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
			if l > 0 {
				inv := 1.0 / l
				vert_normals[i] = [3]f32{v.x * inv, v.y * inv, v.z * inv}
			}
		}
		mesh.normals = vert_normals[:]
	}

	return mesh, nil
}
}