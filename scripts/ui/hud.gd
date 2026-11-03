extends CanvasLayer
## In-run overlay: found pairs and play time at the top, crosshair, control
## hints, and a short "Saved" note whenever the game is written to disk.

var _top: HBoxContainer
var _pairs_label: Label
var _pairs_chip: PanelContainer
var _time_label: Label
var _cheat_chip: PanelContainer
var _crosshair: Crosshair
var _hint: Label
var _saved: PanelContainer
var _saved_tween: Tween
var _player: Node
var _shown_pairs := -1
var _shown_seconds := -1
var _hint_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_build()
	Events.game_saved.connect(_on_saved)
	Events.pair_matched.connect(func(_a: int, _b: int, _c: int) -> void: _pulse(_pairs_chip))


func _process(_delta: float) -> void:
	var live := GameState.running and not get_tree().paused
	_top.visible = GameState.running or GameState.completed
	_cheat_chip.visible = GameState.cheat_mode
	_crosshair.visible = live
	_hint.visible = live
	if _shown_pairs != GameState.pairs_found:
		_shown_pairs = GameState.pairs_found
		_refresh_pairs()
	if _shown_seconds != int(GameState.play_time):
		_shown_seconds = int(GameState.play_time)
		_time_label.text = tr("HUD_TIME").format({"time": UiKit.format_time(GameState.play_time)})
	if live:
		_update_aim()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_shown_pairs = -1
		_shown_seconds = -1
		_hint_key = ""


func _refresh_pairs() -> void:
	_pairs_label.text = tr("HUD_PAIRS").format({"found": GameState.pairs_found, "total": GameState.pairs_total})


## Reads the player from the game scene (GameState.world_provider.player).
func _update_aim() -> void:
	if not is_instance_valid(_player) and GameState.world_provider:
		_player = GameState.world_provider.get("player")
	var holding := false
	var aiming := false
	if _player:
		holding = _player.has_method("held_sock") and _player.held_sock() != null
		aiming = _player.has_method("aimed_sock") and _player.aimed_sock() != null
	_crosshair.hot = aiming
	var count: int = _player.call("carry_count") if holding and _player.has_method("carry_count") else 0
	var key := ("HINT_HELD%d" % count) if holding else "HINT_GRAB"
	key += ":" + ",".join(GameState.abilities)
	if key != _hint_key:
		_hint_key = key
		if holding:
			_hint.text = "%s     %s     %s     %s     %s" % [tr("HINT_GRAB"), tr("HINT_DROP"), tr("HINT_THROW"), tr("HINT_PAIR"), tr("HINT_INSPECT")]
			if count > 1:
				_hint.text += "\n" + tr("HINT_CARRY").format({"count": count, "max": int(Config.player.get("carry_max", 1))})
		else:
			_hint.text = tr("HINT_GRAB")
		for ability in GameState.abilities:
			_hint.text += "     " + tr("HINT_%s" % ability.to_upper())


func _build() -> void:
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.full_rect(root))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	root.add_child(UiKit.full_rect(margin))

	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 12)
	_top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_top)
	_pairs_label = UiKit.label("", &"HudLabel")
	_pairs_chip = _chip(_pairs_label, _sock_icon())
	_top.add_child(_pairs_chip)
	_time_label = UiKit.label("", &"HudLabel")
	_top.add_child(_chip(_time_label))
	_cheat_chip = _chip(UiKit.label("HUD_CHEAT", &"HudLabel"))
	_cheat_chip.visible = false
	_top.add_child(_cheat_chip)

	_crosshair = Crosshair.new()
	root.add_child(_crosshair)

	_hint = UiKit.label("", &"OnDarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_hint.add_theme_font_size_override("font_size", UiTheme.size("font_small"))
	_hint.add_theme_color_override("font_color", UiTheme.color("on_dark_soft"))
	_hint.add_theme_color_override("font_shadow_color", UiTheme.color("shadow"))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_END
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_hint)

	var saved_label := UiKit.label("HUD_SAVED", &"HudLabel")
	_saved = _chip(saved_label, _check_icon())
	_saved.size_flags_horizontal = Control.SIZE_SHRINK_END
	_saved.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_saved.modulate.a = 0.0
	margin.add_child(_saved)


func _chip(label: Label, icon: Control = null) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"HudChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.resized.connect(func() -> void: chip.pivot_offset = chip.size * 0.5)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	if icon:
		icon.custom_minimum_size = Vector2(26, 26)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	row.add_child(label)
	return chip


## Tiny sock silhouette, same outline as the menu backdrop.
func _sock_icon() -> Control:
	var icon := Control.new()
	icon.draw.connect(func() -> void:
		var s := icon.size.y * 0.5
		var points := PackedVector2Array()
		for p: Vector2 in MenuBackdrop.SOCK_OUTLINE:
			points.append(p * s * 0.95 + Vector2(s * 0.85, s))
		icon.draw_colored_polygon(points, UiTheme.color("tomato"))
		icon.draw_rect(Rect2(Vector2(-0.34, -1.0) * s * 0.95 + Vector2(s * 0.85, s), Vector2(0.54, 0.22) * s * 0.95), UiTheme.color("mustard")))
	return icon


func _check_icon() -> Control:
	var icon := Control.new()
	icon.draw.connect(func() -> void:
		var s := icon.size
		var c := UiTheme.color("teal")
		icon.draw_circle(s * 0.5, s.x * 0.5, c, true, -1.0, true)
		icon.draw_polyline(PackedVector2Array([s * Vector2(0.27, 0.52), s * Vector2(0.44, 0.68), s * Vector2(0.74, 0.34)]),
				UiTheme.color("paper"), 3.0, true))
	return icon


func _pulse(chip: Control) -> void:
	var tween := chip.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(chip, "scale", Vector2.ONE * 1.12, 0.1)
	tween.tween_property(chip, "scale", Vector2.ONE, 0.22)


func _on_saved() -> void:
	if _saved_tween:
		_saved_tween.kill()
	_saved_tween = create_tween()
	_saved_tween.tween_property(_saved, "modulate:a", 1.0, 0.15)
	_saved_tween.tween_interval(UiTheme.anim("saved_visible"))
	_saved_tween.tween_property(_saved, "modulate:a", 0.0, UiTheme.anim("saved_fade"))
