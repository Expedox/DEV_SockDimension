extends CanvasLayer
## Shown when the last pair lands. SaveManager stores the completed run itself.

const DATA_PATH := "res://data/pairs.json"

var _root: Control
var _stats: VBoxContainer
var _button: Button
var _again: Button
var _versus_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	_root.hide()
	Events.run_finished.connect(_on_run_finished)


## Clock text such as 0:42:07.
static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, total / 60 % 60, total % 60]


func _on_run_finished(_mode_id: String) -> void:
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	await get_tree().create_timer(float(tuning.end_screen_delay_seconds)).timeout
	_show_results()


func _show_results() -> void:
	for child in _stats.get_children():
		child.queue_free()
	_versus_label = null
	_again.visible = GameState.is_speedrun()
	if GameState.is_speedrun():
		_show_speedrun()
	else:
		_show_story()
	_root.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_again if _again.visible else _button).grab_focus()


func _show_speedrun() -> void:
	_add_stat(tr("SPEEDRUN_RESULT").format({"pairs": GameState.pairs_total, "time": UiKit.format_race(GameState.play_time)}))
	if GameState.cheat_used:
		_add_stat(tr("SPEEDRUN_CHEAT_NOT_LISTED"))
	elif GameState.speedrun_rank == 0:
		_add_stat(tr("SPEEDRUN_NEW_BEST"))
	elif GameState.speedrun_rank > 0:
		_add_stat(tr("SPEEDRUN_RANK").format({"rank": GameState.speedrun_rank + 1}))
	else:
		_add_stat(tr("SPEEDRUN_BEST").format({"time": UiKit.format_race(SpeedrunScores.best(GameState.pairs_total))}))
	_add_stat(tr("END_FAILED").format({"count": GameState.mistakes}))
	if GameState.versus:
		_add_stat("")
		_versus_label = _stats.get_child(_stats.get_child_count() - 1)
		_versus_label.theme_type_variation = &"HeadingLabel"
		_refresh_versus()
		Net.versus_rival_done.connect(_refresh_versus)


func _refresh_versus() -> void:
	if not is_instance_valid(_versus_label):
		return
	var key := "SPEEDRUN_YOU_WIN" if SpeedrunHud.won_versus() else "SPEEDRUN_YOU_LOSE"
	var text := tr(key)
	if Net.versus_rival_gave_up:
		text += "  ·  " + tr("SPEEDRUN_RIVAL_GAVE_UP")
	elif Net.versus_rival_time >= 0.0:
		text += "  ·  " + tr("SPEEDRUN_RIVAL_FINISHED").format({"time": UiKit.format_race(Net.versus_rival_time)})
	else:
		text += "  ·  " + tr("SPEEDRUN_RIVAL_PROGRESS").format({"found": Net.rival_found, "total": GameState.pairs_total})
	_versus_label.text = text


func _process(_delta: float) -> void:
	# The rival's count moves on while they are still running.
	if _root.visible and is_instance_valid(_versus_label) and Net.versus_rival_time < 0.0:
		_refresh_versus()


## Same size again; in versus a rematch for both when the rival is still here.
func _on_again() -> void:
	# Only a rival who has finished too is back on an end screen and can take it.
	if GameState.versus and Net.versus_rival_time >= 0.0 and Net.start_versus(GameState.mode_id):
		return
	GameState.start_speedrun(GameState.mode_id)


func _show_story() -> void:
	_add_stat(tr("END_TIME").format({"time": format_time(GameState.play_time)}))
	_add_stat(tr("END_PAIRS").format({"found": GameState.pairs_found, "total": GameState.pairs_total}))
	_add_stat(tr("END_FAILED").format({"count": GameState.mistakes}))
	_add_stat(tr("END_THROWS").format({"count": GameState.throws}))
	_add_stat(tr("END_CAT").format({"stolen": GameState.cat_steals, "caught": GameState.cat_catches}))


func _add_stat(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_child(label)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	center.add_child(column)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = tr("END_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	column.add_child(card)

	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 12)
	card.add_child(_stats)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	column.add_child(buttons)
	_again = Button.new()
	_again.theme_type_variation = "PrimaryButton"
	_again.text = tr("SPEEDRUN_AGAIN")
	_again.pressed.connect(_on_again)
	_again.hide()
	buttons.add_child(_again)

	_button = Button.new()
	_button.theme_type_variation = "PrimaryButton"
	_button.text = tr("END_MAIN_MENU")
	_button.pressed.connect(GameState.to_main_menu)
	buttons.add_child(_button)
