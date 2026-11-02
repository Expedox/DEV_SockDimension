class_name UiTheme
extends RefCounted
## Builds the shared cozy UI theme in code from data/ui_theme.json.
##
## Assign get_theme() to the root window so every Control in the game picks it
## up. Type variations: PrimaryButton, QuietButton, TitleLabel, HeadingLabel,
## MutedLabel, OnDarkLabel, HudLabel, HudChip, CardPanel.

const DATA_PATH := "res://data/ui_theme.json"

static var _data: Dictionary = {}
static var _theme: Theme
static var _body_font: Font
static var _title_font: Font


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Could not read %s" % DATA_PATH)
	return _data


static func color(key: String) -> Color:
	return Color.html(data().colors[key])


static func size(key: String) -> int:
	return int(data().sizes[key])


static func anim(key: String) -> float:
	return float(data().animation[key])


static func title_font() -> Font:
	if _title_font == null:
		_title_font = _make_font(data().fonts.title, 700)
	return _title_font


static func body_font() -> Font:
	if _body_font == null:
		_body_font = _make_font(data().fonts.body, 500)
	return _body_font


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _make_font(names: Array, weight: int) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return font


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = size("font_body")
	_build_labels(t)
	_build_panels(t)
	_build_buttons(t)
	_build_fields(t)
	_build_sliders(t)
	_build_toggles(t)
	_build_popups(t)
	_build_scroll(t)
	return t


static func _build_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", color("ink"))
	_label_variation(t, "MutedLabel", "ink_soft", size("font_small"))
	_label_variation(t, "OnDarkLabel", "on_dark", size("font_body"))
	_label_variation(t, "HeadingLabel", "ink", size("font_heading"))
	t.set_font("font", "HeadingLabel", title_font())

	_label_variation(t, "TitleLabel", "on_dark", size("font_title"))
	t.set_font("font", "TitleLabel", title_font())
	t.set_color("font_outline_color", "TitleLabel", color("tomato_dark"))
	t.set_constant("outline_size", "TitleLabel", 14)
	t.set_color("font_shadow_color", "TitleLabel", color("shadow"))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 7)

	_label_variation(t, "HudLabel", "on_dark", size("font_hud"))
	t.set_font("font", "HudLabel", title_font())


static func _label_variation(t: Theme, type: String, color_key: String, font_size: int) -> void:
	t.set_type_variation(type, "Label")
	t.set_color("font_color", type, color(color_key))
	t.set_font_size("font_size", type, font_size)


static func _flat(bg: String, corner: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color(bg)
	box.set_corner_radius_all(corner)
	box.corner_detail = 6
	box.anti_aliasing = true
	return box


static func _build_panels(t: Theme) -> void:
	var margin := size("panel_margin")
	var paper := _flat("paper", size("corner"))
	paper.set_content_margin_all(margin)
	paper.shadow_color = color("shadow")
	paper.shadow_size = 18
	paper.shadow_offset = Vector2(0, 8)
	paper.border_color = color("paper_edge")
	paper.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", paper)
	t.set_stylebox("panel", "Panel", paper)

	t.set_type_variation("CardPanel", "PanelContainer")
	var card := _flat("paper_shade", size("corner_small"))
	card.set_content_margin_all(18)
	t.set_stylebox("panel", "CardPanel", card)

	t.set_type_variation("HudChip", "PanelContainer")
	var chip := _flat("dim", size("corner_small"))
	chip.content_margin_left = 18
	chip.content_margin_right = 18
	chip.content_margin_top = 8
	chip.content_margin_bottom = 8
	t.set_stylebox("panel", "HudChip", chip)


## A fabric tag: flat fill with a thicker bottom edge that flattens when pressed.
static func _tag(bg: String, edge: String, depth: int) -> StyleBoxFlat:
	var box := _flat(bg, size("corner_small"))
	box.border_color = color(edge)
	box.border_width_bottom = depth
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 10 + (5 - depth)
	box.content_margin_bottom = 10
	return box


static func _button_styles(t: Theme, type: String, normal: Array, hover: Array, pressed: Array) -> void:
	t.set_stylebox("normal", type, _tag(normal[0], normal[1], 5))
	t.set_stylebox("hover", type, _tag(hover[0], hover[1], 5))
	t.set_stylebox("pressed", type, _tag(pressed[0], pressed[1], 1))
	t.set_stylebox("hover_pressed", type, _tag(pressed[0], pressed[1], 1))
	var disabled := _tag("paper_shade", "paper_shade", 2)
	t.set_stylebox("disabled", type, disabled)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = color("teal")
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(size("corner_small") + 3)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", type, focus)


static func _build_buttons(t: Theme) -> void:
	_button_styles(t, "Button", ["paper_shade", "paper_edge"], ["mustard", "mustard_dark"], ["mustard_dark", "mustard_dark"])
	t.set_color("font_color", "Button", color("ink"))
	t.set_color("font_hover_color", "Button", color("ink"))
	t.set_color("font_focus_color", "Button", color("ink"))
	t.set_color("font_pressed_color", "Button", color("ink"))
	t.set_color("font_hover_pressed_color", "Button", color("ink"))
	t.set_color("font_disabled_color", "Button", color("ink_faint"))

	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", ["tomato", "tomato_dark"], ["tomato_light", "tomato_dark"], ["tomato_dark", "tomato_dark"])
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "PrimaryButton", color("on_dark"))

	t.set_type_variation("QuietButton", "Button")
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 16
	empty.content_margin_right = 16
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	for state: String in ["normal", "pressed", "hover_pressed"]:
		t.set_stylebox(state, "QuietButton", empty)
	var quiet_hover := _flat("paper_shade", size("corner_small"))
	quiet_hover.content_margin_left = 16
	quiet_hover.content_margin_right = 16
	quiet_hover.content_margin_top = 8
	quiet_hover.content_margin_bottom = 8
	t.set_stylebox("hover", "QuietButton", quiet_hover)
	t.set_color("font_color", "QuietButton", color("ink_soft"))


static func _build_fields(t: Theme) -> void:
	var field := _flat("paper_shade", size("corner_small"))
	field.content_margin_left = 16
	field.content_margin_right = 16
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	field.border_color = color("paper_edge")
	field.set_border_width_all(2)
	var focused: StyleBoxFlat = field.duplicate()
	focused.border_color = color("teal")
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focused)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", color("ink"))
	t.set_color("font_placeholder_color", "LineEdit", color("ink_faint"))
	t.set_color("caret_color", "LineEdit", color("tomato"))
	t.set_color("selection_color", "LineEdit", color("mustard"))


static func _build_sliders(t: Theme) -> void:
	var track := _flat("paper_edge", 5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := _flat("tomato", 5)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _disc(26, color("tomato"), color("paper")))
	t.set_icon("grabber_highlight", "HSlider", _disc(26, color("tomato_light"), color("paper")))
	t.set_icon("grabber_disabled", "HSlider", _disc(26, color("paper_edge"), color("paper")))


static func _build_toggles(t: Theme) -> void:
	var on := _pill(56, 30, color("teal"), color("paper"), true)
	var off := _pill(56, 30, color("paper_edge"), color("paper"), false)
	t.set_icon("checked", "CheckButton", on)
	t.set_icon("unchecked", "CheckButton", off)
	t.set_icon("checked_disabled", "CheckButton", on)
	t.set_icon("unchecked_disabled", "CheckButton", off)
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", empty)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "CheckButton", color("ink"))


static func _build_popups(t: Theme) -> void:
	var popup := _flat("paper", size("corner_small"))
	popup.set_content_margin_all(10)
	popup.border_color = color("paper_edge")
	popup.set_border_width_all(2)
	t.set_stylebox("panel", "PopupMenu", popup)
	var hover := _flat("mustard", 8)
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_color("font_color", "PopupMenu", color("ink"))
	t.set_color("font_hover_color", "PopupMenu", color("ink"))
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_icon("arrow", "OptionButton", _chevron(16, color("ink_soft")))


static func _build_scroll(t: Theme) -> void:
	var track := _flat("paper_shade", 6)
	track.content_margin_left = 6
	track.content_margin_right = 6
	var grab := _flat("paper_edge", 6)
	grab.content_margin_left = 6
	grab.content_margin_right = 6
	var grab_hot := _flat("tomato", 6)
	grab_hot.content_margin_left = 6
	grab_hot.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hot)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hot)


## Antialiased filled disc with a contrasting rim.
static func _disc(diameter: int, fill: Color, rim: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var c := fill if d < r - 4.0 else rim
			c.a = clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Toggle pill with its knob on the left or right.
static func _pill(w: int, h: int, fill: Color, knob: Color, knob_right: bool) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	var knob_x := w - r if knob_right else r
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var nearest := Vector2(clampf(p.x, r, w - r), r)
			var edge := r - p.distance_to(nearest)
			var c := fill
			var knob_edge := (r - 4.0) - p.distance_to(Vector2(knob_x, r))
			c = c.lerp(knob, clampf(knob_edge, 0.0, 1.0))
			c.a = clampf(edge, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Small downward chevron for dropdowns.
static func _chevron(side: int, ink: Color) -> ImageTexture:
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var half := side * 0.5
	for y in side:
		for x in side:
			var line := half * 0.4 + absf(x + 0.5 - half) * -0.75 + half * 0.5
			var c := ink
			c.a = clampf(1.8 - absf(y + 0.5 - line), 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
