class_name UiKit
extends RefCounted
## Small builders shared by the menus: buttons with a soft hover bounce,
## fades and the clock format.


## Button with min size from the theme and a gentle grow on hover and focus.
static func button(text_key: String, variation := &"") -> Button:
	var b := Button.new()
	b.text = text_key
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(UiTheme.size("button_min_width"), UiTheme.size("button_min_height"))
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(_bounce.bind(b, true))
	b.mouse_exited.connect(_bounce.bind(b, false))
	b.focus_entered.connect(_bounce.bind(b, true))
	b.focus_exited.connect(_bounce.bind(b, false))
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	return b


static func _bounce(b: Button, grow: bool) -> void:
	if not b.is_inside_tree():
		return
	var target := UiTheme.anim("button_hover_scale") if grow and not b.disabled else 1.0
	var tween := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(b, "scale", Vector2.ONE * target, UiTheme.anim("button_hover_time"))


static func label(text: String, variation := &"", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.horizontal_alignment = align
	return l


## Full-rect Control that ignores the mouse, for layout roots.
static func full_rect(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


## Fades a node in from transparent, rising slightly.
static func fade_in(node: CanvasItem) -> void:
	node.modulate.a = 0.0
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "modulate:a", 1.0, UiTheme.anim("screen_fade"))


## Fades a node out, then frees it.
static func fade_out_and_free(node: CanvasItem) -> void:
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "modulate:a", 0.0, UiTheme.anim("screen_fade"))
	tween.tween_callback(node.queue_free)


## Clock text such as 0:42:07.
## Race clock with tenths: 1:23.4, or 1:02:03.4 past an hour.
static func format_race(seconds: float) -> String:
	var tenths := int(floor(maxf(seconds, 0.0) * 10.0))
	var total := tenths / 10
	if total >= 3600:
		return "%d:%02d:%02d.%d" % [total / 3600, total / 60 % 60, total % 60, tenths % 10]
	return "%d:%02d.%d" % [total / 60, total % 60, tenths % 10]


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, total / 60 % 60, total % 60]
