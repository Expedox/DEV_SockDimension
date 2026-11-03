class_name Tutorial
extends CanvasLayer
## First-steps card at the top of the screen. Each step waits for the player to
## do the thing it names, then moves on. Steps and timings are in data/gameplay.json.

## The player made a pair: time for the rest of the socks.
signal lesson_done

const STEPS := ["move", "grab", "inspect", "throw", "pair", "done"]

var _card: PanelContainer
var _title: Label
var _text: Label
var _step := -1
var _step_time := 0.0
var _tip_time := 0.0
var _cfg: Dictionary


func _ready() -> void:
	layer = 6
	_cfg = Config.gameplay.get("tutorial", {})
	_build()
	Events.sock_grabbed.connect(func(_id: int) -> void: _done_if("grab"))
	Events.sock_thrown.connect(func(_id: int) -> void: _done_if("throw"))
	Events.pair_matched.connect(_on_matched)
	Events.pair_mismatched.connect(_on_mismatched)
	_advance()


func _process(delta: float) -> void:
	_card.visible = GameState.running and not get_tree().paused
	if not _card.visible:
		return
	_step_time += delta
	if _tip_time > 0.0:
		_tip_time -= delta
		if _tip_time <= 0.0:
			_show_step()
	match STEPS[_step]:
		"move":
			if _step_time > float(_cfg.get("move_seconds", 7.0)):
				_advance()
		"inspect":
			if Input.is_action_pressed("inspect") and _step_time > 1.0 \
					or _step_time > float(_cfg.get("inspect_seconds", 12.0)):
				_advance()
		"done":
			if _step_time > float(_cfg.get("done_seconds", 6.0)):
				var tween := create_tween()
				tween.tween_property(_card, "modulate:a", 0.0, 0.6)
				tween.tween_callback(queue_free)
				set_process(false)


func _done_if(step: String) -> void:
	# Grabbing early also covers the walk step.
	if STEPS[_step] == step or (step == "grab" and STEPS[_step] == "move"):
		_advance()


func _on_matched(_pair_id: int, _color: int, _pattern: int) -> void:
	# A pair found early skips the rest of the lesson.
	if STEPS[_step] != "done":
		_step = STEPS.find("pair")
		_advance()


func _on_mismatched(_near_miss: bool) -> void:
	if STEPS[_step] == "done":
		return
	_set_text("TUT_MISS_TITLE", "TUT_MISS_TEXT")
	_tip_time = float(_cfg.get("tip_seconds", 4.0))


func _advance() -> void:
	_step = mini(_step + 1, STEPS.size() - 1)
	_step_time = 0.0
	_tip_time = 0.0
	_show_step()
	if STEPS[_step] == "done":
		lesson_done.emit()
	if _step > 0:
		var tween := _card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_card.scale = Vector2.ONE * 0.92
		tween.tween_property(_card, "scale", Vector2.ONE, 0.25)


func _show_step() -> void:
	var key: String = STEPS[_step].to_upper()
	_set_text("TUT_%s_TITLE" % key, "TUT_%s_TEXT" % key)


func _set_text(title: String, text: String) -> void:
	_title.text = title
	_text.text = text


func _build() -> void:
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.full_rect(root))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", 96)
	root.add_child(UiKit.full_rect(margin))

	_card = StitchedPanel.new()
	_card.custom_minimum_size.x = 560
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.resized.connect(func() -> void: _card.pivot_offset = _card.size * 0.5)
	margin.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_card.add_child(column)
	_title = UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_color_override("font_color", UiTheme.color("tomato_dark"))
	_title.uppercase = true
	column.add_child(_title)
	_text = UiKit.label("", &"", HORIZONTAL_ALIGNMENT_CENTER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_text)
