extends Node
## Player settings: loaded from user://settings.cfg on start, applied to the
## engine right away and saved whenever a menu closes.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"

var mouse_sensitivity := 0.0025
var invert_mouse := false
var fov := 75.0
var volume_master := 0.8
var volume_sfx := 1.0
var volume_ambience := 0.8
var graphics_quality := "high"
var fullscreen := true
var vsync := true
var language := "en"
var show_intro := true

var data: Dictionary = {}


func _ready() -> void:
	data = _read_data()
	_load()
	get_tree().root.theme = UiTheme.get_theme()
	apply()


## Value range for a slider: {min, max, step}.
func range_of(key: String) -> Dictionary:
	return data.get("ranges", {}).get(key, {"min": 0.0, "max": 1.0, "step": 0.01})


func languages() -> Array:
	return data.get("languages", [])


## Graphics presets as {id, key}; the values per preset live in data/world.json.
func quality_levels() -> Array:
	return data.get("quality_levels", [])


## Sets one field, applies it and tells listeners. Call save() when done.
func set_value(key: String, value: Variant) -> void:
	if get(key) == value:
		return
	set(key, value)
	apply()
	changed.emit()


func apply() -> void:
	_set_bus_volume(&"Master", volume_master)
	_set_bus_volume(_bus(String(data.get("sfx_bus", "SFX"))), volume_sfx)
	_set_bus_volume(_bus(String(data.get("ambience_bus", "Ambience"))), volume_ambience)
	TranslationServer.set_locale(language)
	if not Engine.is_embedded_in_editor() and DisplayServer.get_name() != "headless":
		var window_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != window_mode:
			DisplayServer.window_set_mode(window_mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _defaults():
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Could not save settings (%d)" % err)


func reset_to_defaults() -> void:
	for key: String in _defaults():
		set(key, _defaults()[key])
	apply()
	changed.emit()


func _load() -> void:
	var cfg := ConfigFile.new()
	var has_file := cfg.load(PATH) == OK
	for key: String in _defaults():
		var fallback: Variant = _defaults()[key]
		var value: Variant = cfg.get_value(SECTION, key, fallback) if has_file else fallback
		# Guard against hand-edited files with the wrong type.
		set(key, value if typeof(value) == typeof(fallback) else fallback)


func _defaults() -> Dictionary:
	return data.get("defaults", {})


func _read_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/settings.json"))
	if parsed is Dictionary:
		return parsed
	push_error("Could not read res://data/settings.json")
	return {}


func _bus(name: String) -> StringName:
	var bus := StringName(name)
	if AudioServer.get_bus_index(bus) == -1:
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
	return bus


func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)
