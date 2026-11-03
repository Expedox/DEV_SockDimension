class_name SpeedrunSelect
extends Control
## Speedrun: pick a size, see its best times, start alone or against the LAN rival.

signal closed

const CARD_SIZE := Vector2(210, 130)

var _group := ButtonGroup.new()
var _cards: Array[Button] = []
var _scores: VBoxContainer
var _scores_title: Label
var _start_button: Button
var _versus_button: Button
var _versus_note: Label


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(MenuBackdrop.new())
	_build()
	UiKit.fade_in(self)
	_cards[0].button_pressed = true
	_refresh_scores()
	_refresh_versus()
	Net.lobby_changed.connect(_refresh_versus)
	Net.rival_run_changed.connect(_refresh_versus)
	Net.rival_joined.connect(_refresh_versus)
	Net.rival_left.connect(_refresh_versus)
	Net.versus_declined.connect(func() -> void: _versus_note.text = tr("SPEEDRUN_RIVAL_BUSY"))
	_start_button.grab_focus.call_deferred()


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
	column.add_theme_constant_override("separation", 20)
	sheet.add_child(column)
	column.add_child(UiKit.label("SPEEDRUN_TITLE", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var intro := UiKit.label("SPEEDRUN_INTRO", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 900
	column.add_child(intro)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 18)
	column.add_child(cards)
	for mode: Dictionary in Config.speedrun_modes():
		var card := _size_card(mode)
		cards.add_child(card)
		_cards.append(card)

	var board := PanelContainer.new()
	board.theme_type_variation = &"CardPanel"
	column.add_child(board)
	var board_column := VBoxContainer.new()
	board_column.add_theme_constant_override("separation", 6)
	board.add_child(board_column)
	_scores_title = UiKit.label("", &"", HORIZONTAL_ALIGNMENT_CENTER)
	board_column.add_child(_scores_title)
	_scores = VBoxContainer.new()
	_scores.custom_minimum_size.y = 250
	_scores.add_theme_constant_override("separation", 2)
	board_column.add_child(_scores)

	_versus_note = UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_versus_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	column.add_child(buttons)
	var back := UiKit.button("MENU_BACK")
	back.custom_minimum_size.x = 200
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)
	_versus_button = UiKit.button("SPEEDRUN_VERSUS")
	_versus_button.custom_minimum_size.x = 200
	_versus_button.pressed.connect(_on_versus)
	buttons.add_child(_versus_button)
	_start_button = UiKit.button("SPEEDRUN_SOLO", &"PrimaryButton")
	_start_button.custom_minimum_size.x = 200
	_start_button.pressed.connect(_on_start)
	buttons.add_child(_start_button)


func _size_card(mode: Dictionary) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = _group
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("mode_id", mode.id)
	card.set_meta("pairs", int(mode.pairs))
	card.toggled.connect(func(on: bool) -> void:
		if on:
			_refresh_scores())
	var picked := StyleBoxFlat.new()
	picked.bg_color = UiTheme.color("mustard")
	picked.border_color = UiTheme.color("mustard_dark")
	picked.border_width_bottom = 5
	picked.set_corner_radius_all(UiTheme.size("corner_small"))
	picked.anti_aliasing = true
	card.add_theme_stylebox_override("pressed", picked)
	card.add_theme_stylebox_override("hover_pressed", picked)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	card.add_child(UiKit.full_rect(column))
	column.add_child(UiKit.label(tr("SPEEDRUN_PAIRS").format({"pairs": int(mode.pairs)}), &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var best := SpeedrunScores.best(int(mode.pairs))
	var best_text := tr("SPEEDRUN_BEST").format({"time": UiKit.format_race(best)}) if best >= 0.0 else tr("SPEEDRUN_NO_TIME")
	column.add_child(UiKit.label(best_text, &"", HORIZONTAL_ALIGNMENT_CENTER))
	for label: Control in column.get_children():
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _selected() -> Button:
	return _group.get_pressed_button() as Button


func _refresh_scores() -> void:
	var card := _selected()
	if card == null or _scores == null:
		return
	var pairs: int = card.get_meta("pairs")
	_scores_title.text = tr("SPEEDRUN_SCORES_TITLE").format({"pairs": pairs})
	for child in _scores.get_children():
		child.queue_free()
	var list := SpeedrunScores.entries(pairs)
	if list.is_empty():
		_scores.add_child(UiKit.label("SPEEDRUN_NO_TIME", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER))
		return
	for i in list.size():
		var e: Dictionary = list[i]
		var date := Time.get_date_string_from_unix_time(int(e.at) + _utc_offset())
		var line := tr("SPEEDRUN_SCORE_LINE").format({"rank": i + 1, "time": UiKit.format_race(float(e.time)),
			"mistakes": int(e.mistakes), "date": date})
		if e.get("versus", false):
			line += "  ·  " + tr("SPEEDRUN_VS_TAG")
		_scores.add_child(UiKit.label(line, &"", HORIZONTAL_ALIGNMENT_CENTER))


func _refresh_versus() -> void:
	_versus_button.visible = Net.has_rival()
	_versus_button.disabled = Net.rival_in_run()
	if not Net.has_rival():
		_versus_note.text = tr("SPEEDRUN_VERSUS_HINT")
	elif Net.rival_in_run():
		_versus_note.text = tr("SPEEDRUN_RIVAL_BUSY")
	else:
		_versus_note.text = tr("SPEEDRUN_VERSUS_READY")


func _on_start() -> void:
	var card := _selected()
	if card:
		set_process_unhandled_input(false)
		GameState.start_speedrun(card.get_meta("mode_id"))


func _on_versus() -> void:
	var card := _selected()
	if card and Net.start_versus(card.get_meta("mode_id")):
		set_process_unhandled_input(false)


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
