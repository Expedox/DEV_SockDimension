class_name SpeedrunHud
extends CanvasLayer
## Speedrun start and race info: waits for the rival's pile in versus, counts
## 3-2-1-Go, then starts the clock. Shows when the rival finished or gave up.

var _big: Label
var _rival: Label
var _waiting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 6
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.full_rect(root))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(UiKit.full_rect(center))
	_big = UiKit.label("", &"TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_big.add_theme_font_size_override("font_size", 190)
	center.add_child(_big)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 150)
	root.add_child(UiKit.full_rect(margin))
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"HudChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_rival = UiKit.label("", &"HudLabel")
	chip.add_child(_rival)
	chip.hide()
	margin.add_child(chip)

	Events.pile_ready.connect(_on_pile_ready, CONNECT_ONE_SHOT)
	Net.versus_go.connect(_on_go)
	Net.versus_rival_done.connect(_on_rival_done)
	Net.versus_declined.connect(_on_declined)
	Events.run_finished.connect(func(_m: String) -> void:
		if GameState.versus:
			Net.versus_finished(GameState.play_time))


func _on_pile_ready() -> void:
	if GameState.versus and Net.has_rival() and not Net.versus_rival_gave_up:
		_waiting = true
		_big.text = tr("SPEEDRUN_WAITING")
		Net.versus_ready()
	else:
		_countdown()


func _on_go() -> void:
	if _waiting:
		_waiting = false
		_countdown()


func _countdown() -> void:
	var steps := int(Config.gameplay.get("speedrun", {}).get("countdown_seconds", 3))
	var tween := create_tween()
	for n in range(steps, 0, -1):
		tween.tween_callback(_show_step.bind(str(n)))
		tween.tween_interval(1.0)
	tween.tween_callback(_start)
	tween.tween_interval(0.8)
	tween.tween_callback(func() -> void: _big.text = "")


func _show_step(text: String) -> void:
	_big.text = text
	if Sfx.has_sound("grab"):
		Sfx.play("grab")


func _start() -> void:
	_big.text = tr("SPEEDRUN_GO")
	if Sfx.has_sound("match"):
		Sfx.play("match")
	GameState.running = true
	Events.run_started.emit(GameState.mode_id)


## Versus result once we finished: true = we won, false = lost.
static func won_versus() -> bool:
	return Net.versus_rival_time < 0.0 or GameState.play_time <= Net.versus_rival_time


## The rival was busy in their own run: this one goes on alone.
func _on_declined() -> void:
	if not GameState.versus or GameState.running:
		return
	GameState.versus = false
	_rival.text = tr("SPEEDRUN_RIVAL_BUSY")
	(_rival.get_parent() as Control).show()
	if _waiting:
		_waiting = false
		_countdown()


func _on_rival_done() -> void:
	if not GameState.versus:
		return
	var chip := _rival.get_parent() as Control
	chip.show()
	if Net.versus_rival_gave_up:
		_rival.text = tr("SPEEDRUN_RIVAL_GAVE_UP")
	else:
		_rival.text = tr("SPEEDRUN_RIVAL_FINISHED").format({"time": UiKit.format_race(Net.versus_rival_time)})
	if _waiting:
		_waiting = false
		_countdown()
