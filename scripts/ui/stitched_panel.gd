class_name StitchedPanel
extends PanelContainer
## Paper panel with a hand-sewn running stitch just inside its edge.

const INSET := 10.0
const DASH := 11.0
const GAP := 8.0
const WIDTH := 2.5


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var stitch := UiTheme.color("stitch")
	var corner := float(UiTheme.size("corner")) - INSET * 0.4
	var rect := Rect2(Vector2.ONE * INSET, size - Vector2.ONE * INSET * 2.0)
	var a := rect.position
	var b := rect.end
	_stitch_line(Vector2(a.x + corner, a.y), Vector2(b.x - corner, a.y), stitch)
	_stitch_line(Vector2(b.x, a.y + corner), Vector2(b.x, b.y - corner), stitch)
	_stitch_line(Vector2(b.x - corner, b.y), Vector2(a.x + corner, b.y), stitch)
	_stitch_line(Vector2(a.x, b.y - corner), Vector2(a.x, a.y + corner), stitch)
	draw_arc(Vector2(a.x + corner, a.y + corner), corner, PI, PI * 1.5, 6, stitch, WIDTH, true)
	draw_arc(Vector2(b.x - corner, a.y + corner), corner, PI * 1.5, TAU, 6, stitch, WIDTH, true)
	draw_arc(Vector2(b.x - corner, b.y - corner), corner, 0.0, PI * 0.5, 6, stitch, WIDTH, true)
	draw_arc(Vector2(a.x + corner, b.y - corner), corner, PI * 0.5, PI, 6, stitch, WIDTH, true)


func _stitch_line(from: Vector2, to: Vector2, stitch: Color) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / maxf(length, 0.001)
	var count := maxi(int((length + GAP) / (DASH + GAP)), 1)
	var spare := length - count * DASH - (count - 1) * GAP
	var pos := spare * 0.5
	for i in count:
		draw_line(from + dir * pos, from + dir * (pos + DASH), stitch, WIDTH, true)
		pos += DASH + GAP
