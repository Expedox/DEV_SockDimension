extends Node
## Plays the synthesised effects and voices the shared game events.

const DATA_PATH := "res://data/sfx.json"

var _sounds: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var bus := _ensure_bus(String(data.get("bus", "SFX")))
	_build_pool(data, bus)
	_render_sounds(data)
	Events.sock_thrown.connect(func(_id: int) -> void: play("throw"))
	Events.sock_landed.connect(func(_id: int, _distance: float) -> void: play("plop"))


## Plays a sound in the world, or flat when no position is given.
func play(sound: String, position: Variant = null, volume_db: float = 0.0) -> void:
	var entry: Dictionary = _sounds.get(sound, {})
	if entry.is_empty():
		push_warning("Unknown sound: %s" % sound)
		return
	if not _allow(sound, entry):
		return

	var variants: Array = entry["variants"]
	var stream: AudioStream = variants.pick_random()
	var pitch: float = 1.0 + randf_range(-entry["pitch_jitter"], entry["pitch_jitter"])
	var level: float = entry["volume_db"] + volume_db

	if position is Vector3 and is_inside_tree():
		var player := _players_3d[_next_3d]
		_next_3d = (_next_3d + 1) % _players_3d.size()
		player.global_position = position
		player.stream = stream
		player.pitch_scale = pitch
		player.volume_db = level
		player.play()
	else:
		var player := _players_2d[_next_2d]
		_next_2d = (_next_2d + 1) % _players_2d.size()
		player.stream = stream
		player.pitch_scale = pitch
		player.volume_db = level
		player.play()


func has_sound(sound: String) -> bool:
	return _sounds.has(sound)


func _allow(sound: String, entry: Dictionary) -> bool:
	# A sliding pile can report hundreds of landings at once.
	var now := Time.get_ticks_msec()
	var gap_ms := 1000.0 / maxf(entry["max_per_second"], 0.1)
	if now - int(_last_played.get(sound, -100000)) < gap_ms:
		return false
	_last_played[sound] = now
	return true


func _ensure_bus(bus: String) -> StringName:
	if AudioServer.get_bus_index(bus) == -1:
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
	return StringName(bus)


func _build_pool(data: Dictionary, bus: StringName) -> void:
	for i in int(data.get("pool_3d", 12)):
		var player := AudioStreamPlayer3D.new()
		player.bus = bus
		player.unit_size = float(data.get("unit_size", 2.5))
		player.max_distance = float(data.get("max_distance", 45.0))
		add_child(player)
		_players_3d.append(player)
	for i in int(data.get("pool_2d", 4)):
		var player := AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		_players_2d.append(player)


func _render_sounds(data: Dictionary) -> void:
	var sample_rate := int(data.get("sample_rate", 32000))
	var sounds: Dictionary = data.get("sounds", {})
	for sound: String in sounds:
		var recipe: Dictionary = sounds[sound]
		var variants: Array[AudioStream] = []
		for v in int(recipe.get("variants", 1)):
			variants.append(SoundSynth.render(recipe, sample_rate, hash(sound) + v))
		_sounds[sound] = {
			"variants": variants,
			"volume_db": float(recipe.get("volume_db", 0.0)),
			"pitch_jitter": float(recipe.get("pitch_jitter", 0.0)),
			"max_per_second": float(recipe.get("max_per_second", 20.0)),
		}
