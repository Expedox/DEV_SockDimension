class_name SockWall
extends Node3D
## Found pairs hang here from wooden peg rails, the twins side by side. One band per shape
## (sneaker, sport, knee-high), one block per base colour, then by pattern.
## Every pair of the set has a fixed slot, so the gaps show what is still
## missing. Built from GameState.found_pair_ids, so saves need nothing extra.
## Values in data/world.json, key pair_wall. The node's basis is the wall
## frame: X along the wall (left to right as seen from the room), Y up,
## Z out of the wall into the room.

const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
const SHAPE_KEYS := {"sneaker": "WALL_SHAPE_SNEAKER", "sport": "WALL_SHAPE_SPORT", "knee": "WALL_SHAPE_KNEE"}

## Uniform sock scale the layout chose, 1.0 is real size.
var sock_scale := 0.0

var _config: Dictionary
var _socks: SockSet
var _layers: Array[MultiMesh] = [] # per shape
var _slot := PackedInt32Array() # per pair: first of its two instances in the shape layer
var _xform_a: Array[Transform3D] = [] # per pair, final transform of each sock
var _xform_b: Array[Transform3D] = []
var _shown := PackedByteArray() # per pair
var _labels: Array[Label3D] = [] # per shape, may hold null for an empty band
var _found_in_shape := PackedInt32Array()
var _total_in_shape := PackedInt32Array()


## Places the wall and shows the pairs found so far.
func setup(sock_set: SockSet, config: Dictionary, found: PackedInt32Array) -> void:
	_socks = sock_set
	_config = config
	var normal := Cellar.vec3(config["normal"]).normalized()
	var right := Vector3.UP.cross(normal)
	transform = Transform3D(Basis(right, Vector3.UP, normal), Cellar.vec3(config["center"]))

	var size := Vector2(config["size"][0], config["size"][1])
	_build_board(size)
	var plan := layout(sock_set, config)
	sock_scale = plan.scale
	_build_slots(plan, size)
	for shape in SockCatalog.shape_count():
		_update_label(shape)
	for pair_id in found:
		show_pair(pair_id, false)


## Hook for Events.pair_matched.
func on_pair_matched(pair_id: int, _base_color: int, _pattern_type: int) -> void:
	show_pair(pair_id, true)


func is_shown(pair_id: int) -> bool:
	return pair_id >= 0 and pair_id < _shown.size() and _shown[pair_id] == 1


func show_pair(pair_id: int, animate: bool) -> void:
	if pair_id < 0 or pair_id >= _shown.size() or _shown[pair_id] == 1:
		return
	_shown[pair_id] = 1
	var shape := _socks.shapes[pair_id]
	_found_in_shape[shape] += 1
	_update_label(shape)
	if not animate:
		_set_pair(1.0, pair_id)
		return
	var tween := create_tween()
	tween.tween_method(_set_pair.bind(pair_id), 0.05, 1.0, float(_config["pop_seconds"])) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pair(grow: float, pair_id: int) -> void:
	var mm := _layers[_socks.shapes[pair_id]]
	var a := _xform_a[pair_id]
	var b := _xform_b[pair_id]
	mm.set_instance_transform(_slot[pair_id], Transform3D(a.basis * grow, a.origin))
	mm.set_instance_transform(_slot[pair_id] + 1, Transform3D(b.basis * grow, b.origin))


## Pure layout, also used by tests. Returns scale, and per shape: pair ids
## sorted into colour groups, rows, cell size and the hanging footprint.
static func layout(sock_set: SockSet, config: Dictionary) -> Dictionary:
	var width := float(config["size"][0]) - float(config["margin"]) * 2.0
	var height := float(config["size"][1]) - float(config["margin"]) * 2.0
	var pad := float(config["padding"])
	var bands: Array[Dictionary] = []
	for shape in SockCatalog.shape_count():
		var fp := footprint(shape, config)
		bands.append({
			"shape": shape,
			"groups": _groups(sock_set, shape),
			"footprint": fp,
			"cell": fp.size * (1.0 + pad),
			"rows": 0,
		})
	for i in range(bands.size() - 1, -1, -1):
		if bands[i].groups.is_empty():
			bands.remove_at(i)

	var low := 0.01
	var high := float(config["max_scale"])
	if not _fits(bands, high, width, height, config):
		for i in 40:
			var mid := (low + high) * 0.5
			if _fits(bands, mid, width, height, config):
				low = mid
			else:
				high = mid
		high = low
	_fits(bands, high, width, height, config) # leaves rows set for this scale
	return {"scale": high, "bands": bands, "width": width, "height": height}


## Rectangle a hanging pair covers at real size, relative to its peg point,
## plus each sock's transform at real size.
static func footprint(shape: int, config: Dictionary) -> Dictionary:
	var cuff := SockMesh.cuff_point(shape)
	var thick := float(SockCatalog.mesh_values()["thickness"])
	var shift := float(SockCatalog.shape(shape)["width"]) * float(config["pair_offset"])
	# Foot to the right, thin side facing the room, leg straight up from the peg.
	var basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var leg := basis * SockMesh.leg_direction()
	basis = Basis(Quaternion(leg.normalized(), Vector3.UP)) * basis
	# The twin hangs just behind, shifted along the peg so both show.
	var socks: Array[Transform3D] = [
		Transform3D(basis, Vector3(-shift * 0.5, 0.0, thick * 1.6) - basis * cuff),
		Transform3D(basis, Vector3(shift * 0.5, -thick * 0.3, thick * 0.6) - basis * cuff),
	]
	var box := AABB()
	var first := true
	var mesh_box := SockMesh.mesh_aabb(shape)
	for xform in socks:
		var b := xform * mesh_box
		box = b if first else box.merge(b)
		first = false
	return {
		"a": socks[0], "b": socks[1],
		"size": Vector2(box.size.x, box.size.y),
		"center": Vector2(box.get_center().x, box.get_center().y),
	}


## Pair ids of one shape, one array per base colour in palette order, sorted
## by pattern, count, accent and heel/toe inside.
static func _groups(sock_set: SockSet, shape: int) -> Array:
	var by_color := []
	by_color.resize(SockCatalog.palette_size())
	for i in by_color.size():
		by_color[i] = []
	for pair in sock_set.pair_count:
		if sock_set.shapes[pair] == shape:
			by_color[sock_set.base_colors[pair]].append(pair)
	var groups := []
	for list: Array in by_color:
		if list.is_empty():
			continue
		list.sort_custom(func(x: int, y: int) -> bool:
			return _sort_key(sock_set, x) < _sort_key(sock_set, y))
		groups.append(list)
	return groups


static func _sort_key(s: SockSet, pair: int) -> int:
	return ((s.patterns[pair] * 16 + s.counts[pair]) * 64 + s.accent_colors[pair]) * 2 + s.heel_toes[pair]


## Whether all bands fit at this scale; sets each band's row count.
static func _fits(bands: Array[Dictionary], scale: float, width: float, height: float, config: Dictionary) -> bool:
	var used := float(config["band_gap"]) * maxf(bands.size() - 1, 0)
	for band in bands:
		var cell: Vector2 = band.cell * scale
		var gap := cell.x * float(config["group_gap"])
		var largest := 0
		for g: Array in band.groups:
			largest = maxi(largest, g.size())
		var rows := -1
		for r in range(1, largest + 1):
			var w: float = gap * (band.groups.size() - 1)
			for g: Array in band.groups:
				w += ceili(float(g.size()) / r) * cell.x
			if w <= width:
				rows = r
				break
		if rows < 0:
			return false
		band.rows = rows
		used += float(config["label_height"]) + rows * cell.y
	return used <= height


func _build_slots(plan: Dictionary, size: Vector2) -> void:
	var count := _socks.pair_count
	_slot.resize(count)
	_shown.resize(count)
	_shown.fill(0)
	_xform_a.resize(count)
	_xform_b.resize(count)
	_found_in_shape.resize(SockCatalog.shape_count())
	_found_in_shape.fill(0)
	_total_in_shape.resize(SockCatalog.shape_count())
	_total_in_shape.fill(0)
	_labels.resize(SockCatalog.shape_count())

	var first_sock := PackedInt32Array()
	first_sock.resize(count)
	for sock in range(_socks.sock_count() - 1, -1, -1):
		first_sock[_socks.pair_of(sock)] = sock

	var s: float = plan.scale
	var bounds := AABB(Vector3(-size.x, -size.y, -1.0) * 0.5, Vector3(size.x, size.y, 1.0))
	var pegs: Array[Transform3D] = []
	var top: float = plan.height * 0.5
	var peg_radius := float(_config["peg_radius"])

	for shape in SockCatalog.shape_count():
		_layers.append(null)
	for band: Dictionary in plan.bands:
		var shape: int = band.shape
		var fp: Dictionary = band.footprint
		var cell: Vector2 = band.cell * s
		var gap := cell.x * float(_config["group_gap"])
		var total := 0
		for g: Array in band.groups:
			total += g.size()
		_total_in_shape[shape] = total

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = SockMesh.get_mesh(shape, false)
		SockMesh.get_material(shape)
		mm.custom_aabb = bounds
		mm.instance_count = total * 2
		var instance := MultiMeshInstance3D.new()
		instance.name = "Wall" + SockCatalog.shape_id(shape).capitalize()
		instance.multimesh = mm
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_layers[shape] = mm

		_labels[shape] = _add_label(shape, Vector3(-plan.width * 0.5, top - float(_config["label_height"]) * 0.5, 0.01))
		top -= float(_config["label_height"])

		var band_width: float = gap * (band.groups.size() - 1)
		for g: Array in band.groups:
			band_width += ceili(float(g.size()) / band.rows) * cell.x
		var x: float = -band_width * 0.5
		var next := 0
		var center: Vector2 = fp.center * s
		for g: Array in band.groups:
			var cols := ceili(float(g.size()) / band.rows)
			for i in g.size():
				var pair: int = g[i]
				var slot_center := Vector2(x + (i % cols + 0.5) * cell.x, top - (int(float(i) / cols) + 0.5) * cell.y)
				var peg := Vector3(slot_center.x - center.x, slot_center.y - center.y, 0.0)
				_xform_a[pair] = _scaled(fp.a, s, peg)
				_xform_b[pair] = _scaled(fp.b, s, peg)
				_slot[pair] = next
				var data := _socks.custom_data(first_sock[pair])
				mm.set_instance_custom_data(next, data)
				mm.set_instance_custom_data(next + 1, data)
				mm.set_instance_transform(next, HIDDEN)
				mm.set_instance_transform(next + 1, HIDDEN)
				next += 2
			# One peg rail per row of the block, just above the cuffs.
			var rows := ceili(float(g.size()) / cols)
			for r in rows:
				var y := top - (r + 0.5) * cell.y - center.y + peg_radius
				var rail := Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(1.0, cols * cell.x, 1.0))
				pegs.append(Transform3D(rail, Vector3(x + cols * cell.x * 0.5, y, peg_radius)))
			x += cols * cell.x + gap
		top -= band.rows * cell.y + float(_config["band_gap"])
	_build_pegs(pegs, bounds)


func _scaled(xform: Transform3D, s: float, at: Vector3) -> Transform3D:
	return Transform3D(xform.basis * s, at + xform.origin * s)


func _build_board(size: Vector2) -> void:
	var depth := float(_config["board_depth"])
	var wood := ShaderMaterial.new()
	wood.shader = Cellar.WOOD_SHADER
	wood.set_shader_parameter("wood_color", Color(_config["board_color"]))
	wood.set_shader_parameter("wood_dark", Color(_config["board_dark"]))
	wood.set_shader_parameter("plank_width", 0.2)
	wood.set_shader_parameter("grain_axis", 0)
	wood.set_shader_parameter("seams", true)

	var body := StaticBody3D.new()
	body.name = "Board"
	body.collision_layer = Cellar.WORLD_LAYER
	body.collision_mask = 0
	body.position = Vector3(0, 0, -depth * 0.5)
	add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, depth + 0.06)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.z = 0.03
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, depth)
	var board := MeshInstance3D.new()
	board.mesh = mesh
	board.material_override = wood
	body.add_child(board)


func _build_pegs(pegs: Array[Transform3D], bounds: AABB) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = float(_config["peg_radius"])
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(_config["peg_color"])
	material.roughness = 0.7
	mesh.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.custom_aabb = bounds
	mm.instance_count = pegs.size()
	for i in pegs.size():
		mm.set_instance_transform(i, pegs[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Pegs"
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _add_label(shape: int, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = "Label" + SockCatalog.shape_id(shape).capitalize()
	label.position = at
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.pixel_size = float(_config["label_pixel_size"])
	label.font_size = 64
	label.outline_size = 0
	label.modulate = Color(_config["label_color"])
	label.shaded = true
	add_child(label)
	return label


func _update_label(shape: int) -> void:
	var label := _labels[shape]
	if label == null:
		return
	var key: String = SHAPE_KEYS.get(SockCatalog.shape_id(shape), SockCatalog.shape_id(shape))
	label.text = "%s   %d / %d" % [tr(key), _found_in_shape[shape], _total_in_shape[shape]]
