class_name Intro
extends CanvasLayer
## Story beats shown over the loading screen on a first new game. Click, Space
## or Enter goes on, Esc skips. The last beat waits for the pile, then fades to
## show the cellar. Holds the game paused while it covers a ready pile.

signal finished

## Text keys per beat: [line, body]. Body may be empty.
const BEATS := [
	["INTRO_1_LINE", "INTRO_1_BODY"],
	["INTRO_2_LINE", "INTRO_2_BODY"],
	["INTRO_3_LINE", "INTRO_3_BODY"],
	["INTRO_4_LINE", "INTRO_4_BODY"],
	["INTRO_5_LINE", "INTRO_5_BODY"],
]
const FADE := 0.45

var _root: Control
var _backdrop: Control
var _sheet: Control
var _line: Label
var _body: Label
var _hint: Label
var _dots: HBoxContainer
var _beat := -1
var _pile_ready := false
var _done := false
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_build()
	Events.pile_ready.connect(_on_pile_ready)
	_next()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var skip: bool = event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")
	var next: bool = event.is_action_pressed("ui_accept") or event.is_action_pressed("jump") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
	if event.is_echo():
		return
	if skip:
		_finish()
	elif next and not _busy:
		_next()


func _next() -> void:
	if _beat >= BEATS.size() - 1:
		if _pile_ready:
			_finish()
		return
	_beat += 1
	_busy = true
	var tween := create_tween()
	if _beat > 0:
		tween.tween_property(_sheet, "modulate:a", 0.0, FADE * 0.6)
	tween.tween_callback(_show_beat)
	tween.tween_property(_sheet, "modulate:a", 1.0, FADE)
	tween.tween_callback(func() -> void: _busy = false)


func _show_beat() -> void:
	_line.text = BEATS[_beat][0]
	_body.text = BEATS[_beat][1]
	for i in _dots.get_child_count():
		_dots.get_child(i).modulate.a = 1.0 if i == _beat else 0.35
	_refresh_hint()
	if _beat == BEATS.size() - 1 and _pile_ready:
		_reveal()


func _refresh_hint() -> void:
	var last := _beat == BEATS.size() - 1
	if last and not _pile_ready:
		_hint.text = "INTRO_WAIT"
	elif last:
		_hint.text = "INTRO_START"
	else:
		_hint.text = "INTRO_CONTINUE"


func _on_pile_ready() -> void:
	_pile_ready = true
	if _done:
		return
	# Freeze the clock and the player until the story is over.
	get_tree().paused = true
	_refresh_hint()
	if _beat == BEATS.size() - 1:
		_reveal()


## Lets the cellar shine through behind the last beat.
func _reveal() -> void:
	var tween := create_tween()
	tween.tween_property(_backdrop, "modulate:a", 0.0, 1.2)


func _finish() -> void:
	if _done:
		return
	_done = true
	if _pile_ready:
		get_tree().paused = false
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE)
	tween.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _build() -> void:
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.full_rect(_root))
	_backdrop = MenuBackdrop.new()
	_root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(UiKit.full_rect(center))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)

	_sheet = StitchedPanel.new()
	_sheet.custom_minimum_size.x = 760
	_sheet.modulate.a = 0.0
	column.add_child(_sheet)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 18)
	_sheet.add_child(inner)
	_line = UiKit.label("", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_line)
	_body = UiKit.label("", &"", HORIZONTAL_ALIGNMENT_CENTER)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_body)

	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 10)
	column.add_child(_dots)
	for i in BEATS.size():
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.draw.connect(func() -> void:
			dot.draw_circle(dot.size * 0.5, dot.size.x * 0.5, UiTheme.color("mustard"), true, -1.0, true))
		_dots.add_child(dot)

	_hint = UiKit.label("", &"OnDarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_hint.add_theme_font_size_override("font_size", UiTheme.size("font_small"))
	_hint.add_theme_color_override("font_color", UiTheme.color("on_dark"))
	_hint.add_theme_color_override("font_outline_color", UiTheme.color("backdrop_dark"))
	_hint.add_theme_constant_override("outline_size", 6)
	column.add_child(_hint)
