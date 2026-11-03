extends CanvasLayer
## Covers the game while the pile is poured or restored, then fades away.

var _root: Control
var _bar: ProgressBar
var _count: Label
var _done := 0
var _total := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_build()
	Events.pile_progress.connect(_on_progress)
	Events.pile_ready.connect(_on_ready, CONNECT_ONE_SHOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _build() -> void:
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	add_child(UiKit.full_rect(_root))
	_root.add_child(MenuBackdrop.new())
	var center := CenterContainer.new()
	_root.add_child(UiKit.full_rect(center))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 30)
	center.add_child(column)
	column.add_child(UiKit.label("GAME_TITLE", &"TitleLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var sheet := StitchedPanel.new()
	sheet.custom_minimum_size.x = 620
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(sheet)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	sheet.add_child(inner)
	var restoring := not GameState.pending_world.is_empty()
	inner.add_child(UiKit.label("LOADING_RESTORING" if restoring else "LOADING_POURING", &"", HORIZONTAL_ALIGNMENT_CENTER))
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 18
	inner.add_child(_bar)
	_count = UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	inner.add_child(_count)
	_total = GameState.pairs_total * 2
	_refresh()


func _on_progress(done: int, total: int) -> void:
	_done = done
	_total = total
	_refresh()


func _refresh() -> void:
	_bar.max_value = maxi(_total, 1)
	_bar.value = _done
	_count.text = tr("LOADING_PROGRESS").format({"done": _done, "total": _total})


func _on_ready() -> void:
	# Later progress comes from the washer burst, in plain sight.
	Events.pile_progress.disconnect(_on_progress)
	_done = _total
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_root.hide)
