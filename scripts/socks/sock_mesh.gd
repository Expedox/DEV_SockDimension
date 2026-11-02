class_name SockMesh
extends RefCounted
## Builds the shared low-poly sock: a flattened tube swept along an L-shaped spine.
## The sock lies flat in the XZ plane with its bounding box centered on the origin,
## so a physics body and its box shape can share the same origin.

const SHADER_PATH := "res://shaders/sock.gdshader"

static var _mesh: ArrayMesh
static var _material: ShaderMaterial
static var _leg_vector := Vector3.ZERO
static var _heel_v := 0.0
static var _base_size := Vector3.ZERO


## UV.x runs around the tube, UV.y from cuff (0) to toe (1), UV2.y is the leg stretch weight.
static func get_mesh() -> ArrayMesh:
	if _mesh == null:
		_build()
	return _mesh


static func get_material() -> ShaderMaterial:
	if _material == null:
		get_mesh()
		var values := SockCatalog.mesh_values()
		var linear := PackedVector3Array()
		for color in SockCatalog.colors():
			var c := color.srgb_to_linear()
			linear.append(Vector3(c.r, c.g, c.b))
		linear.resize(SockCatalog.MAX_PALETTE)
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
		_material.set_shader_parameter("palette", linear)
		_material.set_shader_parameter("leg_vector", _leg_vector)
		_material.set_shader_parameter("heel_v", _heel_v)
		_material.set_shader_parameter("cuff_band", values["cuff_band"])
		_material.set_shader_parameter("toe_start", values["toe_start"])
		_mesh.surface_set_material(0, _material)
	return _material


## Size of the box collision shape for a length index. Slightly smaller than the
## bounding box, because an L-shape leaves two of the box corners empty.
static func collision_size(length_index: int) -> Vector3:
	get_mesh()
	var stretch := _leg_vector.abs() * (SockCatalog.length_scale(length_index) - 1.0)
	var fit: float = SockCatalog.mesh_values()["collision_fit"]
	var size := _base_size + stretch
	return Vector3(size.x * fit, size.y, size.z * fit)


static func _build() -> void:
	var values := SockCatalog.mesh_values()
	var sides: int = values["sides"]
	var half_thickness: float = values["thickness"] * 0.5
	var half_width: float = values["width"] * 0.5
	var foot: float = values["foot_length"]
	var leg: float = values["leg_length"]
	var angle := deg_to_rad(float(values["heel_angle_deg"]))
	var leg_dir := Vector2(cos(angle), sin(angle))

	# Spine as (position, width factor, leg weight).
	var spine: Array[Vector2] = []
	var widths := PackedFloat32Array()
	var leg_weights := PackedFloat32Array()
	var bend := half_width * 1.2
	for t: float in [1.0, 0.8, 0.55, 0.3]:
		spine.append(leg_dir * lerpf(bend, leg, t))
		widths.append(0.9)
		leg_weights.append(t)
	var bend_start := leg_dir * bend
	var bend_end := Vector2(bend, 0.0)
	for t: float in [0.0, 0.33, 0.66, 1.0]:
		var a := bend_start.lerp(Vector2.ZERO, t)
		var b := Vector2.ZERO.lerp(bend_end, t)
		spine.append(a.lerp(b, t))
		widths.append(0.95 + 0.3 * sin(t * PI))
		leg_weights.append(0.0)
	for t: float in [0.35, 0.7, 0.86, 0.95]:
		spine.append(Vector2(lerpf(bend, foot, t), 0.0))
		widths.append(1.0 if t < 0.8 else sqrt(1.0 - pow((t - 0.8) / 0.2, 2.0)) * 0.95 + 0.05)
		leg_weights.append(0.0)

	# V coordinate follows arc length.
	var v_values := PackedFloat32Array([0.0])
	for i in range(1, spine.size()):
		v_values.append(v_values[i - 1] + spine[i].distance_to(spine[i - 1]))
	var total := v_values[-1] + spine[-1].distance_to(Vector2(foot, 0.0))
	for i in v_values.size():
		v_values[i] /= total
	_heel_v = v_values[5] * 0.5 + v_values[6] * 0.5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	var indices := PackedInt32Array()

	var add := func(pos: Vector3, normal: Vector3, uv: Vector2, weight: float) -> void:
		vertices.append(pos)
		normals.append(normal)
		uvs.append(uv)
		uvs2.append(Vector2(0.0, weight))

	for i in spine.size():
		var ahead := spine[mini(i + 1, spine.size() - 1)]
		var behind := spine[maxi(i - 1, 0)]
		var tangent := (ahead - behind).normalized()
		# Side vector points to the outside of the bend (the heel).
		var side := Vector3(tangent.y, 0.0, -tangent.x)
		var center := Vector3(spine[i].x, 0.0, spine[i].y)
		var w := half_width * widths[i]
		var t := half_thickness * clampf(widths[i] * 1.1, 0.4, 1.0)
		for s in sides + 1:
			var a := TAU * s / sides
			var pos := center + side * cos(a) * w + Vector3.UP * sin(a) * t
			var normal := (side * cos(a) / w + Vector3.UP * sin(a) / t).normalized()
			add.call(pos, normal, Vector2(float(s) / sides, v_values[i]), leg_weights[i])

	for i in spine.size() - 1:
		var row := i * (sides + 1)
		for s in sides:
			var a := row + s
			var b := a + sides + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))

	# Cuff opening: dark inset disc, flagged by V < 0.
	var cuff_dir := Vector3(leg_dir.x, 0.0, leg_dir.y)
	var cuff_center := Vector3(spine[0].x, 0.0, spine[0].y) - cuff_dir * 0.015
	var cuff_first := vertices.size()
	add.call(cuff_center, cuff_dir, Vector2(0.5, -0.05), 1.0)
	for s in sides + 1:
		add.call(vertices[s], cuff_dir, Vector2(float(s) / sides, -0.05), 1.0)
	for s in sides:
		indices.append_array(PackedInt32Array([cuff_first, cuff_first + 2 + s, cuff_first + 1 + s]))

	# Toe tip.
	var toe_row := (spine.size() - 1) * (sides + 1)
	var toe_tip := vertices.size()
	add.call(Vector3(foot, 0.0, 0.0), Vector3.RIGHT, Vector2(0.5, 1.0), 0.0)
	for s in sides:
		indices.append_array(PackedInt32Array([toe_row + s, toe_row + s + 1, toe_tip]))

	# Center the bounding box.
	var aabb := AABB(vertices[0], Vector3.ZERO)
	for pos in vertices:
		aabb = aabb.expand(pos)
	var offset := -aabb.get_center()
	for i in vertices.size():
		vertices[i] += offset
	_base_size = aabb.size
	_leg_vector = cuff_dir * leg

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
