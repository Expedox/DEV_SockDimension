extends Node
## Loads everything under data/ once at startup and registers input actions.

var modes: Array = []
var physics: Dictionary = {}
var player: Dictionary = {}
var gameplay: Dictionary = {}
var world: Dictionary = {}
var achievements: Array = []


func _init() -> void:
	modes = _load("res://data/modes.json").get("modes", [])
	physics = _load("res://data/physics.json")
	player = _load("res://data/player.json")
	gameplay = _load("res://data/gameplay.json")
	world = _load("res://data/world.json")
	achievements = _load("res://data/achievements.json").get("achievements", [])
	_register_input(_load("res://data/input.json"))


func mode(id: String) -> Dictionary:
	for entry: Dictionary in modes:
		if entry.id == id:
			return entry
	push_error("Unknown mode: %s" % id)
	return {}


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
