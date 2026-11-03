extends Node
## Loads everything under data/ once at startup and registers input actions.

var modes: Array = []
var physics: Dictionary = {}
var player: Dictionary = {}
var gameplay: Dictionary = {}
## The cellar for the current mode; see use_mode_room().
var world: Dictionary = {}
## data/world.json as written, laid out for its own room_size.
var base_world: Dictionary = {}
var achievements: Array = []
var net: Dictionary = {}


func _init() -> void:
	modes = _load("res://data/modes.json").get("modes", [])
	physics = _load("res://data/physics.json")
	player = _load("res://data/player.json")
	gameplay = _load("res://data/gameplay.json")
	net = _load("res://data/net.json")
	base_world = _load("res://data/world.json")
	world = base_world.duplicate(true)
	achievements = _load("res://data/achievements.json").get("achievements", [])
	_register_input(_load("res://data/input.json"))


func mode(id: String) -> Dictionary:
	for entry: Dictionary in modes:
		if entry.id == id:
			return entry
	push_error("Unknown mode: %s" % id)
	return {}


## Sets world for a mode. A mode with its own room_size gets the cellar of
## data/world.json stretched to it: things near a wall move with that wall,
## things near the middle stay, things in the upper half move with the
## ceiling. Spawn and basket stay where they are, close to the pile.
func use_mode_room(id: String) -> void:
	world = base_world.duplicate(true)
	var size: Array = mode(id).get("room_size", [])
	if size.size() == 3:
		world = stretched_world(base_world, Vector3(size[0], size[1], size[2]))


static func stretched_world(base: Dictionary, size: Vector3) -> Dictionary:
	var w := base.duplicate(true)
	var old := Vector3(base.room_size[0], base.room_size[1], base.room_size[2])
	var r := _Room.new(old, size)
	w.room_size = [size.x, size.y, size.z]
	w.washer_position = r.point(w.washer_position)
	w.lost_found.position = r.point(w.lost_found.position)
	# Lamps hang lower and reach further under a higher ceiling, and a bigger
	# floor gets more of the plain side lamps on a grid.
	var tall := size.y / old.y
	for lamp: Dictionary in w.lamps:
		lamp.position = [r.x(lamp.position[0]), r.z(lamp.position[1])]
		lamp.drop = float(lamp.drop) + (size.y - old.y) * 0.5
		lamp.range = float(lamp.range) * tall
		lamp.fill_range = float(lamp.get("fill_range", lamp.range)) * tall
	var template: Dictionary = {}
	for lamp: Dictionary in w.lamps:
		if not lamp.get("shadow", false):
			template = lamp
			break
	var spacing := float(base.get("lamp_spacing", 9.0))
	var nx := maxi(1, roundi(size.x / spacing))
	var nz := maxi(1, roundi(size.z / spacing))
	for i in nx:
		for k in nz:
			var at := Vector2((i + 0.5) * size.x / nx - size.x * 0.5, (k + 0.5) * size.z / nz - size.z * 0.5)
			var free := not template.is_empty()
			for lamp: Dictionary in w.lamps:
				if at.distance_to(Vector2(lamp.position[0], lamp.position[1])) < spacing * 0.45:
					free = false
			if free:
				var extra: Dictionary = template.duplicate(true)
				extra.position = [at.x, at.y]
				w.lamps.append(extra)
	for window: Dictionary in w.windows:
		window.x = r.x(window.x)
		window.y = r.y(window.y)
	var lights: Dictionary = w.fairy_lights
	var length := float(lights.to_x) - float(lights.from_x)
	lights.from_x = r.x(lights.from_x)
	lights.to_x = r.x(lights.to_x)
	lights.height = r.y(lights.height)
	lights.count = int(float(lights.count) * (float(lights.to_x) - float(lights.from_x)) / length)
	w.shelf.z = r.z(w.shelf.z)
	w.clothesline.from = r.point(w.clothesline.from)
	w.clothesline.to = r.point(w.clothesline.to)
	w.ambience.hum_position = r.point(w.ambience.get("hum_position", [0, 0, 0]))
	for sound: Dictionary in w.ambience.get("random_sounds", []):
		var moved := []
		for at: Array in sound.positions:
			moved.append(r.point(at))
		sound.positions = moved
	for loop: Dictionary in w.ambience.get("loops", []):
		if loop.has("position"):
			loop.position = r.point(loop.position)
	if w.has("rift"):
		w.rift.position = r.point(w.rift.position)
	for panel: Dictionary in w.pair_wall.panels:
		var c: Array = panel.center
		var half_w := float(panel.size[0]) * 0.5
		var half_h := float(panel.size[1]) * 0.5
		var along_x := absf(float(panel.normal[2])) > 0.5
		var mid := float(c[0]) if along_x else float(c[2])
		var a := r.x(mid - half_w) if along_x else r.z(mid - half_w)
		var b := r.x(mid + half_w) if along_x else r.z(mid + half_w)
		var lo := float(c[1]) - half_h
		var hi := r.y(float(c[1]) + half_h)
		var wall := r.point(c)
		panel.center = [(a + b) * 0.5 if along_x else wall[0], (lo + hi) * 0.5, wall[2] if along_x else (a + b) * 0.5]
		panel.size = [b - a, hi - lo]
	return w


class _Room:
	var old: Vector3
	var delta: Vector3

	func _init(old_size: Vector3, new_size: Vector3) -> void:
		old = old_size
		delta = new_size - old_size

	func x(v: float) -> float:
		return v + signf(v) * delta.x * 0.5 if absf(v) > old.x * 0.25 else v

	func z(v: float) -> float:
		return v + signf(v) * delta.z * 0.5 if absf(v) > old.z * 0.25 else v

	func y(v: float) -> float:
		return v + delta.y if v > old.y * 0.5 else v

	func point(p: Array) -> Array:
		return [x(float(p[0])), y(float(p[1])), z(float(p[2]))]


func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Could not read %s" % path)
	return {}


func _register_input(table: Dictionary) -> void:
	for action: String in table.get("keys", {}):
		InputMap.add_action(action)
		for key: String in table.keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = OS.find_keycode_from_string(key)
			InputMap.action_add_event(action, event)
	for action: String in table.get("mouse", {}):
		InputMap.add_action(action)
		var event := InputEventMouseButton.new()
		event.button_index = int(table.mouse[action]) as MouseButton
		InputMap.action_add_event(action, event)
