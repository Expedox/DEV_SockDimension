class_name SettingsPanel
extends Control
## Settings screen for the main menu and the pause menu. Changes apply live and
## are written to disk when the panel closes.

signal closed

const CONTENT_WIDTH := 760.0

## Draws the knitted menu backdrop; off in the pause menu, which dims the game instead.
var with_backdrop := true

var _value_labels: Dictionary = {}
var _back_button: Button


func _ready() -> void:
	UiKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if with_backdrop:
		add_child(MenuBackdrop.new())
	else:
		var dim := ColorRect.new()
		dim.color = UiTheme.color("dim")
		add_child(UiKit.full_rect(dim))
	_build()
	UiKit.fade_in(self)
	_back_button.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_values()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	set_process_unhandled_input(false)
	Settings.save()
	closed.emit()


func _build() -> void:
	var center := CenterContainer.new()
	add_child(UiKit.full_rect(center))
	var sheet := StitchedPanel.new()
	center.add_child(sheet)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = CONTENT_WIDTH
	column.add_theme_constant_override("separation", 10)
	sheet.add_child(column)
	column.add_child(UiKit.label("SETTINGS_TITLE", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 520
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)

	_section(rows, "SETTINGS_SECTION_CONTROLS")
	_slider(rows, "SETTINGS_MOUSE_SENSITIVITY", "mouse_sensitivity", "mouse_sensitivity")
	_toggle(rows, "SETTINGS_INVERT_MOUSE", "invert_mouse")
	_slider(rows, "SETTINGS_FOV", "fov", "fov")
	_toggle(rows, "SETTINGS_SHOW_INTRO", "show_intro")
	_section(rows, "SETTINGS_SECTION_SOUND")
	_slider(rows, "SETTINGS_VOLUME_MASTER", "volume_master", "volume")
	_slider(rows, "SETTINGS_VOLUME_SFX", "volume_sfx", "volume")
	_section(rows, "SETTINGS_SECTION_DISPLAY")
	_display_mode(rows)
	_toggle(rows, "SETTINGS_VSYNC", "vsync")
	_language(rows)

	_back_button = UiKit.button("MENU_BACK", &"PrimaryButton")
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_close)
	column.add_child(_back_button)
	_refresh_values()


func _section(parent: Control, key: String) -> void:
	var heading := UiKit.label(key, &"MutedLabel")
	heading.add_theme_color_override("font_color", UiTheme.color("tomato_dark"))
	heading.uppercase = true
	heading.custom_minimum_size.y = 40
	heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(heading)


## Card row with the name on the left and the control on the right.
func _row(parent: Control, key: String, control: Control) -> HBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var name_label := UiKit.label(key)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


func _slider(parent: Control, key: String, field: String, range_key: String) -> void:
	var limits := Settings.range_of(range_key)
	var slider := HSlider.new()
	slider.min_value = float(limits.min)
	slider.max_value = float(limits.max)
	slider.step = float(limits.step)
	slider.value = Settings.get(field)
	slider.custom_minimum_size = Vector2(260, 32)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_value(field, v)
		_refresh_values())
	var row := _row(parent, key, slider)
	var value_label := UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.custom_minimum_size.x = 70
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)
	_value_labels[field] = value_label


func _toggle(parent: Control, key: String, field: String) -> void:
	var toggle := CheckButton.new()
	toggle.button_pressed = Settings.get(field)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.toggled.connect(func(on: bool) -> void: Settings.set_value(field, on))
	_row(parent, key, toggle)


func _display_mode(parent: Control) -> void:
	var options := _option_button()
	options.add_item("SETTINGS_WINDOWED")
	options.add_item("SETTINGS_FULLSCREEN")
	options.selected = 1 if Settings.fullscreen else 0
	options.item_selected.connect(func(index: int) -> void: Settings.set_value("fullscreen", index == 1))
	_row(parent, "SETTINGS_DISPLAY_MODE", options)


func _language(parent: Control) -> void:
	var options := _option_button()
	var languages := Settings.languages()
	for i in languages.size():
		options.add_item(languages[i].key)
		if languages[i].locale == Settings.language:
			options.selected = i
	options.item_selected.connect(func(index: int) -> void:
		Settings.set_value("language", String(languages[index].locale)))
	_row(parent, "SETTINGS_LANGUAGE", options)


func _option_button() -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(260, 48)
	options.focus_mode = Control.FOCUS_ALL
	return options


func _refresh_values() -> void:
	for field: String in _value_labels:
		var value: float = Settings.get(field)
		var text := ""
		match field:
			"mouse_sensitivity":
				var limits := Settings.range_of("mouse_sensitivity")
				text = "%d%%" % roundi(inverse_lerp(float(limits.min), float(limits.max), value) * 100.0)
			"fov":
				text = "%d°" % roundi(value)
			_:
				text = "%d%%" % roundi(value * 100.0)
		_value_labels[field].text = text
