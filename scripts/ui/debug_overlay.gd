extends CanvasLayer
## F1 overlay with frame, physics and pile numbers. Developer tool, so the
## labels are not translated.

const REFRESH_SECONDS := 0.25

var _label: Label
var _wait := 0.0
var _frame_ms := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	panel.add_child(_label)
	add_child(panel)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug") and not event.is_echo():
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Smoothed, so a single spike stays readable.
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	_wait -= delta
	if not visible or _wait > 0.0:
		return
	_wait = REFRESH_SECONDS
	var lines := PackedStringArray([
		"FPS %d   frame %.1f ms" % [Engine.get_frames_per_second(), _frame_ms],
		"physics %.1f ms   process %.1f ms" % [
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0],
	])
	var field := get_tree().get_first_node_in_group("sock_field") as SockField
	if field != null:
		var bodies := field.body_count()
		var awake := field.awake_count()
		lines.append("socks %d   awake %d   asleep %d   moving %d" % [bodies, awake, bodies - awake, field.moving_count])
		lines.append("field script %.2f ms" % (field.script_usec / 1000.0))
		if field.is_ready():
			lines.append("pile built in %.1f s" % field.pour_seconds)
		else:
			lines.append("building pile ...")
	lines.append("memory %.0f MB   video %.0f MB   objects %d" % [
		OS.get_static_memory_usage() / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT)])
	lines.append("draw calls %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_label.text = "\n".join(lines)
