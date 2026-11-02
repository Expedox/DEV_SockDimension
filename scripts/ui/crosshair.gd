class_name Crosshair
extends Control
## Small stitched ring in the screen centre that opens up over a sock.

const RADIUS := 7.0
const RADIUS_HOT := 13.0

var hot := false:
	set(value):
		if hot != value:
			hot = value
			var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "_radius", RADIUS_HOT if hot else RADIUS, 0.12)

var _radius := RADIUS:
	set(value):
		_radius = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _draw() -> void:
	var shade := Color(0, 0, 0, 0.35)
	var ink := UiTheme.color("paper")
	var t := inverse_lerp(RADIUS, RADIUS_HOT, _radius)
	draw_circle(Vector2.ZERO, 2.6, shade, true, -1.0, true)
	draw_circle(Vector2.ZERO, 1.8, ink, true, -1.0, true)
	if t > 0.02:
		# Dashed ring, like a stitch around the target.
		var dashes := 8
		var accent := UiTheme.color("mustard")
		accent.a = t
		for i in dashes:
			var a := TAU * i / dashes + 0.2
			draw_arc(Vector2.ZERO, _radius, a, a + TAU / dashes * 0.55, 4, accent, 2.5, true)
