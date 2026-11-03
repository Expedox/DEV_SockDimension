class_name SockMesh
extends RefCounted
## Builds one sock mesh per shape (sneaker, sport, knee-high) from data/socks.json.
## A sock lies flat in the XZ plane like a sock on a table: the foot points along +X,
## the leg leans back from the heel, Y is the thin side. Each bounding box is centered
## on the origin, so a physics body and its box shape can share the same origin.
##
## Vertex data read by sock.gdshader:
## UV.x  around the tube in meters, 0 on the back edge (back of the leg, heel, sole),
##       running to +-half the girth at the front edge (shin, instep), where the seam is
## UV.y  along the sock in meters, 0 at the cuff edge, negative inside the opening
## TANGENT points along UV.x, BINORMAL along UV.y.

const SHADER_PATH := "res://shaders/sock.gdshader"

static var _meshes: Array[ArrayMesh] = [] # detailed, for socks near the camera
static var _far_meshes: Array[ArrayMesh] = [] # fewer vertices, the knit is all in the shader
static var _offsets: Array[Vector3] = []
static var _materials: Array[ShaderMaterial] = []
static var _sizes: Array[Vector3] = []
static var _marks: Array[Dictionary] = [] # per shape: length, heel, toe, rib in meters along UV.y


## detailed: the near mesh (held, close by). Otherwise the cheap mesh for the pile.
static func get_mesh(shape: int, detailed := false) -> ArrayMesh:
	_ensure_built()
	return _meshes[shape] if detailed else _far_meshes[shape]


## Shared by every sock of that shape. Also set as the mesh surface material.
static func get_material(shape: int) -> ShaderMaterial:
	_ensure_built()
	if _materials.is_empty():
		_make_materials()
	return _materials[shape]


## Size of the box collision shape for a shape. Slightly smaller than the bounding
## box in the flat plane, because an L-shape leaves two box corners empty.
static func collision_size(shape: int) -> Vector3:
	_ensure_built()
	var fit: float = SockCatalog.mesh_values()["collision_fit"]
	var size := _sizes[shape]
	return Vector3(size.x * fit, size.y, size.z * fit)


static func _ensure_built() -> void:
	if _meshes.is_empty():
		for shape in SockCatalog.shape_count():
			_build(shape, true)
			_build(shape, false)


static func _make_materials() -> void:
	var linear := PackedVector3Array()
	for color in SockCatalog.colors():
		var c := color.srgb_to_linear()
		linear.append(Vector3(c.r, c.g, c.b))
	linear.resize(SockCatalog.MAX_PALETTE)
	var knit := SockCatalog.knit_values()
	var shader: Shader = load(SHADER_PATH)
	for shape in SockCatalog.shape_count():
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("palette", linear)
		for key: String in knit:
			material.set_shader_parameter(key, float(knit[key]))
		var marks := _marks[shape]
		material.set_shader_parameter("sock_length", marks["length"])
		material.set_shader_parameter("heel_at", marks["heel"])
		material.set_shader_parameter("toe_at", marks["toe"])
		material.set_shader_parameter("rib_length", marks["rib"])
		material.set_shader_parameter("pattern_end", marks["pattern_end"])
		_meshes[shape].surface_set_material(0, material)
		_far_meshes[shape].surface_set_material(0, material)
		_materials.append(material)


## One ring of the tube: center on the spine, direction toward the toe, side vector
## toward the back edge, half widths to the back and front, half thickness, UV.y.
class Ring:
	var center: Vector2
	var tangent: Vector2
	var back := 0.0
	var front := 0.0
	var thick := 0.0
	var along := 0.0


## Growing vertex arrays. A class, so helpers can append to them in place.
class Builder:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func add(pos: Vector3, normal: Vector3, tangent: Vector3, toward_toe: Vector3, uv: Vector2) -> void:
		vertices.append(pos)
		normals.append(normal)
		tangent = (tangent - normal * normal.dot(tangent)).normalized()
		var handed := 1.0 if normal.cross(tangent).dot(toward_toe) >= 0.0 else -1.0
		tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, handed]))
		uvs.append(uv)

	## Front faces are clockwise.
	func wind(a: int, b: int, c: int) -> void:
		var facing := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		var normal := normals[a] + normals[b] + normals[c]
		if facing.dot(normal) > 0.0:
			indices.append_array(PackedInt32Array([a, c, b]))
		else:
			indices.append_array(PackedInt32Array([a, b, c]))


static func _bell(x: float, width: float) -> float:
	return exp(-x * x / (2.0 * width * width))


static func _build(shape_index: int, detailed: bool) -> void:
	var mesh_values := SockCatalog.mesh_values()
	var shape := SockCatalog.shape(shape_index)
	var sides: int = int(mesh_values["sides" if detailed else "far_sides"]) / 2 * 2
	var step: float = mesh_values["step" if detailed else "far_step"]
	var flatness: float = mesh_values["flatness"]
	var half_t: float = mesh_values["thickness"] * 0.5
	var radius: float = mesh_values["bend_radius"]
	var toe_len: float = mesh_values["toe_length"]
	var lip: float = mesh_values["lip_depth"]
	var angle := deg_to_rad(float(mesh_values["heel_angle_deg"]))
	var half_w: float = shape["width"] * 0.5
	var leg_len: float = shape["leg_length"]
	var foot_len: float = shape["foot_length"]
	var calf: float = shape["calf"]
	var bulge: float = shape["heel_bulge"]

	# Spine: straight leg down to the heel, an arc around the heel, straight foot, round toe.
	# The leg and foot center lines meet at the origin.
	var leg_dir := Vector2(cos(angle), sin(angle))
	var turn := PI - angle
	var reach := radius * tan(turn * 0.5)
	var arc_center := Vector2(reach, radius)
	var arc_from := (leg_dir * reach - arc_center).angle()
	var arc_to := -PI * 0.5

	var points: Array[Vector2] = []
	var leg_steps := maxi(1, ceili((leg_len - reach) / step))
	for i in leg_steps:
		points.append(leg_dir * lerpf(leg_len, reach, float(i) / leg_steps))
	var arc_steps := 6 if detailed else 4
	for i in arc_steps + 1:
		var a := lerp_angle(arc_from, arc_to, float(i) / arc_steps)
		points.append(arc_center + Vector2(cos(a), sin(a)) * radius)
	var toe_start := foot_len - toe_len
	var foot_steps := maxi(1, ceili((toe_start - reach) / step))
	for i in range(1, foot_steps + 1):
		points.append(Vector2(lerpf(reach, toe_start, float(i) / foot_steps), 0.0))
	var toe_marks := [0.3, 0.55, 0.75, 0.88, 0.96] if detailed else [0.45, 0.8, 0.96]
	for u: float in toe_marks:
		points.append(Vector2(toe_start + toe_len * u, 0.0))

	var heel_index := leg_steps + arc_steps / 2
	var first_toe := points.size() - toe_marks.size()

	# Distance along the spine.
	var along := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		along.append(along[i - 1] + points[i].distance_to(points[i - 1]))
	var heel_at := along[heel_index]
	var toe_at := along[first_toe - 1]
	var total: float = along[-1] + toe_len * (1.0 - float(toe_marks[-1]))
	var leg_part := along[leg_steps] # where the arc begins

	var rings: Array[Ring] = []
	for i in points.size():
		var ring := Ring.new()
		ring.center = points[i]
		var ahead := points[mini(i + 1, points.size() - 1)]
		var behind := points[maxi(i - 1, 0)]
		ring.tangent = (ahead - behind).normalized()
		ring.along = along[i]
		var d := along[i] - heel_at
		var w := half_w
		if i < leg_steps:
			# Height above the heel corner, 0 at the ankle.
			var h := leg_len - along[i]
			w *= 0.93 + calf * _bell(h - leg_len * 0.62, leg_len * 0.2) - 0.05 * _bell(h - 0.07, 0.035)
			if along[i] < shape["rib_length"]:
				w *= 0.97
		elif i >= first_toe:
			var u: float = toe_marks[i - first_toe]
			w *= pow(1.0 - pow(u, 2.5), 0.4) * 0.92 + 0.04
		else:
			var x := points[i].x / toe_start
			w *= 1.0 - 0.05 * _bell(x - 0.4, 0.15) + 0.04 * _bell(x - 0.85, 0.12)
		ring.back = w * (1.0 + bulge * _bell(d, 0.038))
		ring.front = w * (1.0 - 0.42 * _bell(d, 0.045))
		ring.thick = half_t * (1.0 + 0.25 * _bell(d, 0.04))
		if i >= first_toe:
			var u: float = toe_marks[i - first_toe]
			ring.thick *= sqrt(sqrt(1.0 - u * u)) * 0.85 + 0.1
		rings.append(ring)

	# Opening: the rim rolls inward into a shallow, narrower lip.
	var inner := Ring.new()
	inner.center = points[0] - leg_dir * lip
	inner.tangent = rings[0].tangent
	inner.back = rings[0].back * 0.84
	inner.front = rings[0].front * 0.84
	inner.thick = rings[0].thick * 0.3
	inner.along = -lip
	rings.push_front(inner)

	# Grid of ring vertices: sides + 1 per ring, seam on the front edge.
	var grid: Array[PackedVector3Array] = []
	for ring in rings:
		var side := Vector3(ring.tangent.y, 0.0, -ring.tangent.x)
		var center := Vector3(ring.center.x, 0.0, ring.center.y)
		var row := PackedVector3Array()
		for k in sides + 1:
			var a := -PI + TAU * k / sides
			var cx := cos(a)
			var cy := sin(a)
			var x := signf(cx) * pow(absf(cx), 2.0 / flatness)
			var y := signf(cy) * pow(absf(cy), 2.0 / flatness)
			row.append(center + side * x * (ring.back if x > 0.0 else ring.front) + Vector3.UP * y * ring.thick)
		row[sides] = row[0]
		grid.append(row)

	var m := Builder.new()

	var outward_check := 0.0
	var ring_count := grid.size()
	var half := sides / 2
	var foot_ring := ring_count - toe_marks.size() - 1
	for r in ring_count:
		var row := grid[r]
		# Girth in meters, measured from the back edge (index half) both ways.
		var around := PackedFloat32Array()
		around.resize(sides + 1)
		around[half] = 0.0
		for k in range(half + 1, sides + 1):
			around[k] = around[k - 1] + row[k].distance_to(row[k - 1])
		for k in range(half - 1, -1, -1):
			around[k] = around[k + 1] - row[k].distance_to(row[k + 1])
		var next := grid[mini(r + 1, ring_count - 1)]
		var prev := grid[maxi(r - 1, 0)]
		for k in sides + 1:
			var toward_toe := (next[k] - prev[k]).normalized()
			var right := row[(k + 1) % sides] - row[(k - 1 + sides) % sides]
			var normal := right.cross(toward_toe).normalized()
			if r == foot_ring:
				var center := Vector3(rings[r].center.x, 0.0, rings[r].center.y)
				outward_check += normal.dot(row[k] - center)
			m.add(row[k], normal, right, toward_toe, Vector2(around[k], rings[r].along))

	# Outward was computed with one fixed orientation; flip everything if it points in.
	if outward_check < 0.0:
		for i in m.normals.size():
			m.normals[i] = -m.normals[i]
			m.tangents[i * 4 + 3] = -m.tangents[i * 4 + 3]

	# The rim faces out of the opening.
	var leg_out := Vector3(leg_dir.x, 0.0, leg_dir.y)
	for k in sides + 1:
		var i := (sides + 1) + k
		var n := (m.normals[(sides + 1) * 2 + k] * 0.6 + leg_out).normalized()
		m.normals[i] = n

	for r in ring_count - 1:
		for k in sides:
			var a := r * (sides + 1) + k
			var b := a + sides + 1
			m.wind(a, a + 1, b)
			m.wind(b, a + 1, b + 1)

	# Bottom of the lip, so the opening reads as a dark pocket.
	var cap := m.vertices.size()
	var cap_pos := Vector3(inner.center.x, 0.0, inner.center.y) - leg_out * 0.004
	m.add(cap_pos, leg_out, Vector3.UP, -leg_out, Vector2(0.0, -lip - 0.004))
	for k in sides:
		m.wind(cap, k, k + 1)

	# Toe tip.
	var last := (ring_count - 1) * (sides + 1)
	var tip := m.vertices.size()
	m.add(Vector3(foot_len, 0.0, 0.0), Vector3.RIGHT, Vector3.UP, Vector3.RIGHT, Vector2(0.0, total))
	for k in sides:
		m.wind(last + k, last + k + 1, tip)

	# Center the bounding box. The far mesh reuses the near offset, so swapping is seamless.
	var aabb := AABB(m.vertices[0], Vector3.ZERO)
	for pos in m.vertices:
		aabb = aabb.expand(pos)
	var offset := -aabb.get_center() if detailed else _offsets[shape_index]
	# Game scale: bigger than life socks make a pile you look up at.
	var scale := float(mesh_values.get("scale", 1.0))
	for i in m.vertices.size():
		m.vertices[i] = (m.vertices[i] + offset) * scale

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m.vertices
	arrays[Mesh.ARRAY_NORMAL] = m.normals
	arrays[Mesh.ARRAY_TANGENT] = m.tangents
	arrays[Mesh.ARRAY_TEX_UV] = m.uvs
	arrays[Mesh.ARRAY_INDEX] = m.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if not detailed:
		_far_meshes.append(mesh)
		return
	_meshes.append(mesh)
	_offsets.append(offset)
	_sizes.append(aabb.size * scale)
	_marks.append({
		"length": total,
		"heel": heel_at,
		"toe": toe_at,
		"rib": minf(float(shape["rib_length"]), leg_part),
		# Patterns run from below the rib (or the cuff on short socks) to the toe cap.
		"pattern_end": toe_at,
	})
