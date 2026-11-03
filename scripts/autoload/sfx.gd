extends Node
## Plays the synthesised effects and voices the shared game events.

const DATA_PATH := "res://data/sfx.json"

var _sounds: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _last_played: Dictionary = {}
var _loops: Dictionary = {}
var _room_bus: StringName
var _ambience_bus: StringName
var _players_ambient: Array[AudioStreamPlayer3D] = []
var _next_ambient := 0
var _loop_settings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var bus := _ensure_bus(String(data.get("bus", "SFX")))
	_room_bus = _ensure_room_bus(data.get("room", {}), bus)
	# Background sounds get their own bus so they have their own volume slider.
	var ambience: Dictionary = data.get("room", {}).duplicate()
	ambience.merge(data.get("ambience", {}), true)
	ambience["bus"] = String(data.get("ambience", {}).get("bus", "Ambience"))
	_ambience_bus = _ensure_room_bus(ambience, &"Master")
	_build_pool(data, bus)
	_render_sounds(data)
	_render_loops(data)
	Events.sock_thrown.connect(func(_id: int) -> void: play("throw"))
	Events.sock_grabbed.connect(func(_id: int) -> void: play("grab"))
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
		var player: AudioStreamPlayer3D
		if entry["ambient"]:
			player = _players_ambient[_next_ambient]
			_next_ambient = (_next_ambient + 1) % _players_ambient.size()
		else:
			player = _players_3d[_next_3d]
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


## Starts a looping background sound as a child of `parent`, so it ends with
## the level. With a position it plays in the world, otherwise flat.
func start_loop(loop: String, parent: Node, position: Variant = null) -> Node:
	var stream: AudioStream = _loops.get(loop)
	if stream == null:
		push_warning("Unknown loop: %s" % loop)
		return null
	var settings: Dictionary = _loop_settings[loop]
	var player: Node
	if position is Vector3:
		var player_3d := AudioStreamPlayer3D.new()
		player_3d.bus = _ambience_bus
		player_3d.attenuation_filter_cutoff_hz = float(settings.get("far_cutoff_hz", 5000.0))
		player_3d.pitch_scale = float(settings.get("pitch", 1.0))
		player_3d.unit_size = float(settings.get("unit_size", 3.0))
		player_3d.max_distance = float(settings.get("max_distance", 30.0))
		player_3d.volume_db = float(settings.get("volume_db", -20.0))
		player_3d.stream = stream
		player_3d.autoplay = true
		player_3d.position = position
		player = player_3d
	else:
		var player_2d := AudioStreamPlayer.new()
		player_2d.bus = _ambience_bus
		player_2d.volume_db = float(settings.get("volume_db", -20.0))
		player_2d.stream = stream
		player_2d.autoplay = true
		player = player_2d
	player.name = loop.to_pascal_case() + "Loop"
	parent.add_child(player)
	return player


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


## Bus for sounds in the cellar: a short, soft room echo, then on to `send_to`.
func _ensure_room_bus(config: Dictionary, send_to: StringName) -> StringName:
	var bus := String(config.get("bus", "Room"))
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, send_to)
	# The settings may have made the bus already, just for its volume.
	if AudioServer.get_bus_effect_count(index) > 0:
		return StringName(bus)
	var reverb := AudioEffectReverb.new()
	reverb.room_size = float(config.get("room_size", 0.45))
	reverb.damping = float(config.get("damping", 0.7))
	reverb.spread = float(config.get("spread", 0.8))
	reverb.hipass = float(config.get("hipass", 0.15))
	reverb.predelay_msec = float(config.get("predelay_msec", 25.0))
	reverb.wet = float(config.get("wet", 0.18))
	reverb.dry = float(config.get("dry", 1.0))
	AudioServer.add_bus_effect(index, reverb)
	return StringName(bus)


func _build_pool(data: Dictionary, bus: StringName) -> void:
	for i in int(data.get("pool_3d", 12)):
		var player := AudioStreamPlayer3D.new()
		player.bus = _room_bus
		player.attenuation_filter_cutoff_hz = float(data.get("far_cutoff_hz", 6000.0))
		player.unit_size = float(data.get("unit_size", 2.5))
		player.max_distance = float(data.get("max_distance", 45.0))
		add_child(player)
		_players_3d.append(player)
	for i in int(data.get("pool_ambient", 4)):
		var player := AudioStreamPlayer3D.new()
		player.bus = _ambience_bus
		player.attenuation_filter_cutoff_hz = float(data.get("far_cutoff_hz", 6000.0))
		player.unit_size = float(data.get("unit_size", 2.5))
		player.max_distance = float(data.get("max_distance", 45.0))
		add_child(player)
		_players_ambient.append(player)
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
			"ambient": bool(recipe.get("ambient", false)),
		}


func _render_loops(data: Dictionary) -> void:
	var sample_rate := int(data.get("sample_rate", 32000))
	var loops: Dictionary = data.get("loops", {})
	for loop: String in loops:
		var recipe: Dictionary = loops[loop]
		_loops[loop] = SoundSynth.render_loop(recipe, int(recipe.get("sample_rate", sample_rate)), hash(loop))
		_loop_settings[loop] = recipe
