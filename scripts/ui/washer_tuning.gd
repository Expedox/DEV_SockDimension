extends CanvasLayer
## F2 panel for tuning how the socks gush out of the washing machine, live.
## F3 (or the button) takes the socks back and lets the machine boil over
## again. Save keeps the values in user://washer_tuning.json for every run.
## Developer tool, so the labels are not translated.

## [key, label, min, max, step]
const ROWS := [
	["reach_share", "Reach (share of room diagonal)", 0.05, 1.0, 0.01],
	["gap", "Start distance (m)", 0.0, 5.0, 0.1],
	["spray_deg", "Spray width (degrees)", 10.0, 360.0, 5.0],
	["falloff", "Near / far (1 = even, higher = closer)", 0.3, 4.0, 0.05],
	["flight_min", "Flight time min (s, higher = higher arc)", 0.2, 2.5, 0.05],
	["flight_max", "Flight time max (s)", 0.3, 3.0, 0.05],
	["chaos", "Chaos (random kick)", 0.0, 1.5, 0.05],
	["spin", "Spin", 0.0, 30.0, 0.5],
	["wave_size", "Gush speed (socks per wave)", 5.0, 200.0, 5.0],
	["shake_seconds", "Shaking before it blows (s)", 0.0, 5.0, 0.1],
]

var _root: PanelContainer
var _sliders: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("washer_tuning"):
		get_viewport().set_input_as_handled()
		_toggle()
	elif event.is_action_pressed("washer_retrigger"):
		get_viewport().set_input_as_handled()
		_retrigger()


func _game() -> Node:
	return GameState.world_provider as Node


func _toggle() -> void:
	if _root.visible:
		_root.hide()
		if not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_refresh()
		_root.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _retrigger() -> void:
	if _game():
		_game().retrigger_burst()


func _refresh() -> void:
	if not _game():
		return
	var tuning: Dictionary = _game().burst_tuning
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(float(tuning.get(key, _sliders[key].value)))
		_show_value(key)


func _show_value(key: String) -> void:
	_values[key].text = str(snappedf(_sliders[key].value, _sliders[key].step))


func _build() -> void:
	_root = PanelContainer.new()
	_root.position = Vector2(16, 90)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.1, 0.85)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_root.add_child(column)
	var title := Label.new()
	title.text = "Washer burst  (F2 close, F3 trigger again)"
	column.add_child(title)

	for row: Array in ROWS:
		var key: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		column.add_child(line)
		var name_label := Label.new()
		name_label.text = row[1]
		name_label.custom_minimum_size.x = 330
		name_label.add_theme_font_size_override("font_size", 15)
		line.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.custom_minimum_size = Vector2(220, 24)
		slider.focus_mode = Control.FOCUS_NONE
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 50
		value.add_theme_font_size_override("font_size", 15)
		line.add_child(value)
		_sliders[key] = slider
		_values[key] = value
		slider.value_changed.connect(func(v: float) -> void:
			if _game():
				_game().burst_tuning[key] = v
			_show_value(key))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	for entry: Array in [["Trigger again", _retrigger], ["Save as default", _save], ["Reset", _reset]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		buttons.add_child(button)


func _save() -> void:
	if _game():
		_game().save_burst_tuning()


func _reset() -> void:
	if _game():
		_game().reset_burst_tuning()
		_refresh()
