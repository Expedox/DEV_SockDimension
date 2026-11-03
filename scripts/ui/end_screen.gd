extends CanvasLayer
## Shown when the last pair lands. SaveManager stores the completed run itself.

const DATA_PATH := "res://data/pairs.json"

var _root: Control
var _stats: VBoxContainer
var _button: Button


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
	_add_stat(tr("END_TIME").format({"time": format_time(GameState.play_time)}))
	_add_stat(tr("END_PAIRS").format({"found": GameState.pairs_found, "total": GameState.pairs_total}))
	_add_stat(tr("END_FAILED").format({"count": GameState.mistakes}))
	_add_stat(tr("END_THROWS").format({"count": GameState.throws}))
	_add_stat(tr("END_CAT").format({"stolen": GameState.cat_steals, "caught": GameState.cat_catches}))
	_root.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_button.grab_focus()


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

	_button = Button.new()
	_button.theme_type_variation = "PrimaryButton"
	_button.text = tr("END_MAIN_MENU")
	_button.pressed.connect(GameState.to_main_menu)
	column.add_child(_button)
