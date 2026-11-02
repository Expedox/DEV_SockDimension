class_name ModeSelect
extends Control
## New game: pick a mode, optionally type a seed, confirm before replacing a save.

signal closed

const CARD_SIZE := Vector2(380, 190)

var _group := ButtonGroup.new()
var _cards: Array[Button] = []
var _seed_edit: LineEdit
var _start_button: Button


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(MenuBackdrop.new())
	_build()
	UiKit.fade_in(self)
	var preferred := 0
	var latest := SaveManager.latest_save()
	for i in Config.modes.size():
		if Config.modes[i].id == latest:
			preferred = i
	_cards[preferred].button_pressed = true
	_cards[preferred].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _build() -> void:
	var center := CenterContainer.new()
	add_child(UiKit.full_rect(center))
	var sheet := StitchedPanel.new()
	center.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	sheet.add_child(column)
	column.add_child(UiKit.label("MODE_SELECT_TITLE", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 22)
	column.add_child(cards)
	for mode: Dictionary in Config.modes:
		var card := _mode_card(mode)
		cards.add_child(card)
		_cards.append(card)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 16)
	column.add_child(seed_row)
	var seed_label := UiKit.label("MODE_SEED_LABEL")
	seed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "MODE_SEED_PLACEHOLDER"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.max_length = 32
	_seed_edit.clear_button_enabled = true
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _on_start())
	seed_row.add_child(_seed_edit)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	column.add_child(buttons)
	var back := UiKit.button("MENU_BACK")
	back.custom_minimum_size.x = 220
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)
	_start_button = UiKit.button("MENU_START", &"PrimaryButton")
	_start_button.custom_minimum_size.x = 220
	_start_button.pressed.connect(_on_start)
	buttons.add_child(_start_button)


## A toggle button laid out as a card: name, size and the state of its save.
func _mode_card(mode: Dictionary) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = _group
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("mode_id", mode.id)
	card.pressed.connect(func() -> void: _start_button.grab_focus())
	# Picked card glows mustard; the theme's pressed tag is too dark for a whole card.
	var picked := StyleBoxFlat.new()
	picked.bg_color = UiTheme.color("mustard")
	picked.border_color = UiTheme.color("mustard_dark")
	picked.border_width_bottom = 5
	picked.set_corner_radius_all(UiTheme.size("corner_small"))
	picked.anti_aliasing = true
	card.add_theme_stylebox_override("pressed", picked)
	card.add_theme_stylebox_override("hover_pressed", picked)

	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var name_label := UiKit.label(mode.name_key, &"HeadingLabel")
	column.add_child(name_label)
	column.add_child(UiKit.label(mode.desc_key))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var info := SaveManager.save_info(mode.id)
	if not info.is_empty():
		var save_label := UiKit.label("", &"MutedLabel")
		if info.completed:
			save_label.text = tr("MODE_SAVE_COMPLETED").format({"time": UiKit.format_time(info.play_time)})
		else:
			save_label.text = tr("MODE_SAVE_PROGRESS").format({
				"found": info.pairs_found, "total": int(mode.pairs), "time": UiKit.format_time(info.play_time)})
		column.add_child(save_label)
	for label: Control in column.get_children():
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _selected_mode() -> String:
	var pressed := _group.get_pressed_button()
	return pressed.get_meta("mode_id") if pressed else ""


func _on_start() -> void:
	var mode_id := _selected_mode()
	if mode_id.is_empty():
		return
	if not SaveManager.has_save(mode_id):
		_begin(mode_id)
		return
	var dialog := ConfirmDialog.ask(self, "MODE_OVERWRITE_TITLE", "MODE_OVERWRITE_BODY")
	dialog.answered.connect(func(yes: bool) -> void:
		if yes:
			_begin(mode_id)
		else:
			_start_button.grab_focus())


func _begin(mode_id: String) -> void:
	set_process_unhandled_input(false)
	GameState.start_new(mode_id, _seed_edit.text)
