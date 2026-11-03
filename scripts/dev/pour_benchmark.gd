extends Node3D
## Headless timing run: pours a mode, idles, wakes the summit, saves and
## restores. Run with a fixed frame rate so every frame is one physics step:
##   godot --headless --fixed-fps 60 res://scenes/dev/pour_benchmark.tscn -- sock_dimension [nofreeze]

const IDLE_FRAMES := 300
const WAKE_FRAMES := 300

var _mode_id := "sock_dimension"
var _field: SockField
var _set: SockSet
var _phase := "pour"
var _frames := 0
var _last_usec := 0
var _samples := PackedFloat32Array()
var _log_at := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_mode_id = args[0]
	if args.has("nofreeze"):
		Config.physics.freeze_settled = false
		print("freeze_settled off: plain Jolt sleeping")
	var mode := Config.mode(_mode_id)
	add_child(load("res://scenes/cellar.tscn").instantiate())
	var overlay: CanvasLayer = load("res://scenes/ui/debug_overlay.tscn").instantiate()
	add_child(overlay)
	overlay.visible = true # runs its text building too, like on screen
	var t := Time.get_ticks_msec()
	_set = SockSet.generate(12345, int(mode.pairs), float(mode.near_pair_share))
	print("CPU: %s, %d threads" % [OS.get_processor_name(), OS.get_processor_count()])
	print("Generated %d socks in %d ms" % [_set.sock_count(), Time.get_ticks_msec() - t])
	_field = _new_field()
	Events.pile_ready.connect(_on_pile_ready)
	_field.pour(_set, mode)
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_samples.append((now - _last_usec) / 1000.0)
	_last_usec = now
	_frames += 1
	match _phase:
		"pour":
			_log_at += _delta
			if _log_at >= 2.0:
				_log_at = 0.0
				print("  pouring: %d bodies, %d awake, frame %.1f ms" % [_field.body_count(), _field.awake_count(), _samples[-1]])
		"idle":
			if _frames >= IDLE_FRAMES:
				_report("Idle pile")
				var top := _field.surface_height()
				print("Summit at %s" % top)
				_field.wake_around(top, float(Config.physics.wake_radius))
				print("Woke %d socks around the summit" % _field.awake_count())
				_next("wake")
		"wake":
			if _frames >= WAKE_FRAMES:
				_report("After waking the summit")
				_save_and_restore()


func _on_pile_ready() -> void:
	if _phase == "pour":
		_report("Pour")
		print("Pile ready after %.1f s, %d socks, summit %.2f m" % [_field.pour_seconds, _field.body_count(), _field.surface_height().y])
		_next("idle")
	elif _phase == "restore":
		print("Restored %d socks in %.2f s, %d awake" % [_field.body_count(), _field.pour_seconds, _field.awake_count()])
		_next("restored")
		await get_tree().create_timer(1.0).timeout
		_report("One second after restore")
		_next("restored")
		await get_tree().create_timer(4.0).timeout
		_report("Five seconds after restore")
		get_tree().quit()


func _save_and_restore() -> void:
	var t := Time.get_ticks_usec()
	var data := _field.capture()
	var bytes := var_to_bytes(data)
	print("capture() %.1f ms, %d socks, %d KB" % [(Time.get_ticks_usec() - t) / 1000.0, data.ids.size(), bytes.size() / 1024])
	_field.queue_free()
	_field = _new_field()
	_next("restore")
	_field.restore(_set, bytes_to_var(bytes))


func _new_field() -> SockField:
	var field := SockField.new()
	add_child(field)
	return field


func _next(phase: String) -> void:
	_phase = phase
	_frames = 0
	_samples.clear()


func _report(label: String) -> void:
	if _samples.is_empty():
		return
	var sorted := _samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in sorted:
		total += s
	var not_sleeping := 0
	for child in _field.get_children():
		if child is Sock and not PhysicsServer3D.body_get_state(child.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
			not_sleeping += 1
	print("  bodies not sleeping: %d, field script %.2f ms" % [not_sleeping, _field.script_usec / 1000.0])
	print("%s: %d frames, avg %.2f ms, median %.2f ms, p95 %.2f ms, max %.2f ms" % [label, sorted.size(),
			total / sorted.size(), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], sorted[-1]])
