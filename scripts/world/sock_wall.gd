class_name SockWall
extends Node3D
## Found pairs hang here from peg rails, the twins side by side, like a sock
## shop. The rails run across several wall panels (data/world.json, key
## pair_wall) and read like a book: panel by panel, top to bottom, left to
## right. Order is shape (each starts a new row with a found/total label),
## then base colour (a small gap between colours), then pattern, count,
## accent and heel/toe. Every pair has a fixed slot from the start, so empty
## pegs show what is still missing. Built from GameState.found_pair_ids, so
## saves need nothing extra. This node sits at the world origin.

const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
const SHAPE_KEYS := {"sneaker": "WALL_SHAPE_SNEAKER", "sport": "WALL_SHAPE_SPORT", "knee": "WALL_SHAPE_KNEE"}

## Uniform scale the layout chose; 1.0 is the size of the socks in the pile.
var sock_scale := 0.0

var _config: Dictionary
var _socks: SockSet
var _layers: Array[MultiMesh] = [] # per shape
var _slot := PackedInt32Array() # per pair: first of its two instances in the shape layer
var _xform_a: Array[Transform3D] = [] # per pair, world transform of each sock
var _xform_b: Array[Transform3D] = []
var _shown := PackedByteArray() # per pair
var _labels: Array[Label3D] = [] # per shape
var _found_in_shape := PackedInt32Array()
var _total_in_shape := PackedInt32Array()


## Builds the boards and shows the pairs found so far.
func setup(sock_set: SockSet, config: Dictionary, found: PackedInt32Array, bounds: AABB) -> void:
	_socks = sock_set
	_config = config
	var panels := panel_frames(config)
	for i in panels.size():
		_build_board(panels[i], config["panels"][i])
	var plan := layout(sock_set, config)
	sock_scale = plan.scale
	_build_slots(plan, panels, bounds)
	for shape in SockCatalog.shape_count():
		_update_label(shape)
	for pair_id in found:
		show_pair(pair_id, false)


## Hook for Events.pair_matched.
func on_pair_matched(pair_id: int, _base_color: int, _pattern_type: int) -> void:
	show_pair(pair_id, true)


func is_shown(pair_id: int) -> bool:
	return pair_id >= 0 and pair_id < _shown.size() and _shown[pair_id] == 1


## World transform of the front sock of a pair.
func pair_transform(pair_id: int) -> Transform3D:
	return _xform_a[pair_id]


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


## Per panel: X along the wall (left to right seen from the room), Y up, Z
## into the room, origin at the board's front face centre.
static func panel_frames(config: Dictionary) -> Array[Transform3D]:
	var frames: Array[Transform3D] = []
	for panel: Dictionary in config["panels"]:
		var normal := Cellar.vec3(panel["normal"]).normalized()
		var right := Vector3.UP.cross(normal)
		frames.append(Transform3D(Basis(right, Vector3.UP, normal), Cellar.vec3(panel["center"])))
	return frames


## Pure layout, also used by tests. Finds the largest scale (up to
## max_scale) at which the whole set fits, and the slots at that scale.
static func layout(sock_set: SockSet, config: Dictionary) -> Dictionary:
	var shapes: Array[Dictionary] = []
	for shape in SockCatalog.shape_count():
		var groups := _groups(sock_set, shape)
		if groups.is_empty():
			continue
		shapes.append({"shape": shape, "groups": groups, "footprint": footprint(shape, config)})

	var high := float(config["max_scale"])
	var plan := _flow(shapes, high, config)
	if plan.is_empty():
		var low := 0.01
		for i in 30:
			var mid := (low + high) * 0.5
			if _flow(shapes, mid, config).is_empty():
				high = mid
			else:
				low = mid
		plan = _flow(shapes, low, config)
	return plan


## Rectangle a hanging pair covers at scale 1, relative to its peg point,
## plus each sock's transform at scale 1.
static func footprint(shape: int, config: Dictionary) -> Dictionary:
	var mesh_scale := float(SockCatalog.mesh_values().get("scale", 1.0))
	var cuff := SockMesh.cuff_point(shape)
	var thick := float(SockCatalog.mesh_values()["thickness"]) * mesh_scale
	var shift := float(SockCatalog.shape(shape)["width"]) * mesh_scale * float(config["pair_offset"])
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
		"a": socks[0], "b": socks[1], "thick": thick,
		"size": Vector2(box.size.x, box.size.y),
		"left": box.position.x, "top": box.end.y,
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


static func _half(panel: Dictionary, margin: float) -> Vector2:
	return Vector2(panel["size"][0], panel["size"][1]) * 0.5 - Vector2.ONE * margin


## Lays every pair out at one scale. Returns {} when it does not fit.
## Slots are in panel space: {pair: [panel, peg point, column]}.
static func _flow(shapes: Array[Dictionary], scale: float, config: Dictionary) -> Dictionary:
	var panels: Array = config["panels"]
	var margin := float(config["margin"])
	var label_h := float(config["label_height"])
	var overlap := float(config["overlap"])
	var pad := float(config["padding"])
	var slots := {}
	var rails: Array = [] # [panel, peg y, x from, x to]
	var labels: Array = [] # [shape, panel, position]
	var p := 0
	var half := _half(panels[0], margin)
	var y := half.y # top of the next free row in panel p

	for entry in shapes:
		var fp: Dictionary = entry.footprint
		var size: Vector2 = fp.size * scale
		var pitch := size.x * (1.0 - overlap)
		var row_h := size.y * (1.0 + pad)
		var gap := pitch * float(config["group_gap"])
		# Each shape starts a fresh row with its label above.
		while y - label_h - row_h < -half.y:
			p += 1
			if p >= panels.size():
				return {}
			half = _half(panels[p], margin)
			y = half.y
		labels.append([entry.shape, p, Vector2(-half.x, y - label_h * 0.5)])
		y -= label_h

		var x := 0.0 # from the left edge of the panel
		var col := 0
		var peg_y := 0.0
		var in_row := false
		for group: Array in entry.groups:
			if in_row and col > 0:
				x += gap
			for pair: int in group:
				# Wrap when the foot of this pair would leave the panel.
				if in_row and x + size.x > half.x * 2.0:
					rails.append([p, peg_y, -half.x, -half.x + x - pitch + size.x * 0.5])
					y -= row_h
					in_row = false
				if not in_row:
					if y - row_h < -half.y:
						p += 1
						if p >= panels.size():
							return {}
						half = _half(panels[p], margin)
						y = half.y
					x = 0.0
					col = 0
					peg_y = y - row_h * pad * 0.5 - fp.top * scale
					in_row = true
				slots[pair] = [p, Vector2(-half.x + x - fp.left * scale, peg_y), col]
				x += pitch
				col += 1
		if in_row:
			rails.append([p, peg_y, -half.x, -half.x + x - pitch + size.x * 0.5])
			y -= row_h
		y -= float(config["band_gap"])
	return {"scale": scale, "slots": slots, "rails": rails, "labels": labels, "shapes": shapes}


func _build_slots(plan: Dictionary, panels: Array[Transform3D], bounds: AABB) -> void:
	var count := _socks.pair_count
	_slot.resize(count)
	_shown.resize(count)
	_shown.fill(0)
	_xform_a.resize(count)
	_xform_b.resize(count)
	var shape_count := SockCatalog.shape_count()
	_found_in_shape.resize(shape_count)
	_found_in_shape.fill(0)
	_total_in_shape.resize(shape_count)
	_total_in_shape.fill(0)
	_labels.resize(shape_count)
	_layers.resize(shape_count)

	var first_sock := PackedInt32Array()
	first_sock.resize(count)
	for sock in range(_socks.sock_count() - 1, -1, -1):
		first_sock[_socks.pair_of(sock)] = sock

	var s: float = plan.scale
	for entry: Dictionary in plan.shapes:
		var shape: int = entry.shape
		var fp: Dictionary = entry.footprint
		var total := 0
		for g: Array in entry.groups:
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

		var next := 0
		# Neighbours overlap a little, so every other column hangs a bit further out.
		var step := Vector3(0, 0, float(fp.thick) * 2.4 * s)
		for g: Array in entry.groups:
			for pair: int in g:
				var slot: Array = plan.slots[pair]
				var frame := panels[slot[0]]
				var peg: Vector2 = slot[1]
				var at := Vector3(peg.x, peg.y, 0.0) + step * float(int(slot[2]) % 2)
				var a: Transform3D = fp.a
				var b: Transform3D = fp.b
				_xform_a[pair] = frame * Transform3D(a.basis * s, at + a.origin * s)
				_xform_b[pair] = frame * Transform3D(b.basis * s, at + b.origin * s)
				_slot[pair] = next
				var data := _socks.custom_data(first_sock[pair])
				mm.set_instance_custom_data(next, data)
				mm.set_instance_custom_data(next + 1, data)
				mm.set_instance_transform(next, HIDDEN)
				mm.set_instance_transform(next + 1, HIDDEN)
				next += 2

	for entry: Array in plan.labels:
		var frame := panels[entry[1]]
		var at: Vector2 = entry[2]
		var label := _add_label(entry[0])
		label.transform = frame * Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.01))
		_labels[entry[0]] = label
	_build_rails(plan.rails, panels, bounds)


func _build_board(frame: Transform3D, panel: Dictionary) -> void:
	var size := Vector2(panel["size"][0], panel["size"][1])
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
	body.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, -depth * 0.5))
	add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, depth + 0.08)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.z = 0.04
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, depth)
	var board := MeshInstance3D.new()
	board.mesh = mesh
	board.material_override = wood
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(board)


func _build_rails(rails: Array, panels: Array[Transform3D], bounds: AABB) -> void:
	var radius := float(_config["peg_radius"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
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
	mm.instance_count = rails.size()
	for i in rails.size():
		var rail: Array = rails[i]
		var from: float = rail[2]
		var to: float = rail[3]
		var along := Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(1.0, to - from, 1.0))
		var local := Transform3D(along, Vector3((from + to) * 0.5, float(rail[1]) + radius, radius))
		mm.set_instance_transform(i, panels[rail[0]] * local)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Rails"
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _add_label(shape: int) -> Label3D:
	var label := Label3D.new()
	label.name = "Label" + SockCatalog.shape_id(shape).capitalize()
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
