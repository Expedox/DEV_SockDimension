class_name AchievementsMenu
extends Control
## Achievement list with total percentage. Add it as a full-screen child and
## listen for closed; it reads everything from the Achievements autoload.

signal closed

const CONTENT_WIDTH := 860.0
const LOCKED_ALPHA := 0.75

var _total_label: Label
var _total_bar: ProgressBar
var _rows: VBoxContainer
var _title_label: Label
var _back_button: Button
var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_built = true
	refresh()
	Events.achievement_unlocked.connect(_on_changed)
	Achievements.progress_changed.connect(_on_progress_changed)
	_back_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _built:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func refresh() -> void:
	_title_label.text = tr("ACHIEVEMENTS_TITLE")
	_back_button.text = tr("MENU_BACK")
	var total: int = Achievements.get_total_count()
	var done: int = Achievements.get_unlocked_count()
	var percent: int = Achievements.get_percent()
	_total_label.text = tr("ACHIEVEMENTS_TOTAL").format(
			{"unlocked": done, "total": total, "percent": percent})
	_total_bar.value = percent

	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for definition: Dictionary in Achievements.get_definitions():
		_rows.add_child(_make_row(definition))


func _on_changed(_id: String) -> void:
	refresh()


func _on_progress_changed(_id: String, _current: int, _target: int) -> void:
	refresh()


func _make_row(definition: Dictionary) -> Control:
	var id: String = definition.id
	var is_done: bool = Achievements.is_unlocked(id)
	var is_secret: bool = definition.hidden and not is_done

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.modulate.a = 1.0 if is_done else LOCKED_ALPHA
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	panel.add_child(columns)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(text_column)

	var name_label := Label.new()
	name_label.text = tr("ACHIEVEMENTS_HIDDEN") if is_secret else tr(definition.name)
	text_column.add_child(name_label)

	var description_label := Label.new()
	description_label.text = tr("ACHIEVEMENTS_HIDDEN") if is_secret else tr(definition.description)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.theme_type_variation = &"MutedLabel"
	text_column.add_child(description_label)

	var target: int = definition.target
	if target > 1 and not is_secret:
		var current: int = Achievements.get_progress(id)
		var bar := ProgressBar.new()
		bar.max_value = target
		bar.value = current
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		text_column.add_child(bar)
		var progress_label := Label.new()
		progress_label.text = tr("ACHIEVEMENTS_PROGRESS").format({"current": current, "target": target})
		progress_label.theme_type_variation = &"MutedLabel"
		text_column.add_child(progress_label)

	var status := Label.new()
	status.text = tr("ACHIEVEMENTS_UNLOCKED") if is_done else tr("ACHIEVEMENTS_LOCKED")
	status.add_theme_color_override("font_color",
			UiTheme.color("teal_dark") if is_done else UiTheme.color("ink_soft"))
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(status)
	return panel


func _build() -> void:
	var background := MenuBackdrop.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	column.add_theme_constant_override("separation", 12)
	var sheet := StitchedPanel.new()
	center.add_child(sheet)
	sheet.add_child(column)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeadingLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_total_label)

	_total_bar = ProgressBar.new()
	_total_bar.show_percentage = false
	_total_bar.custom_minimum_size.y = 10
	column.add_child(_total_bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 460
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(UiTheme.size("button_min_width"), UiTheme.size("button_min_height"))
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(_back_button)
