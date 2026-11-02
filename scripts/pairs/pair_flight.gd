class_name PairFlight
extends Node3D
## Purely visual: two socks curl into a ball, which arcs into the basket.
## The bodies are already out of the game, so nothing here touches physics.

signal landed

var _renderer: SockRenderer
var _sock_ids := PackedInt32Array()
var _starts: Array[Transform3D] = []
var _tuning: Dictionary
var _center := Vector3.ZERO
var _control := Vector3.ZERO
var _rim := Vector3.ZERO
var _ball: Node3D


## starts holds the world transform of each sock at the moment of the match.
func launch(renderer: SockRenderer, sock_ids: PackedInt32Array, starts: Array[Transform3D],
		colors: PackedColorArray, rim: Vector3, pile_top: Vector3, tuning: Dictionary) -> void:
	_renderer = renderer
	_sock_ids = sock_ids
	_starts = starts
	_tuning = tuning
	_rim = rim
	_center = (starts[0].origin + starts[1].origin) * 0.5
	_build_ball(colors)

	var distance := _center.distance_to(rim)
	var fly_time := clampf(distance / float(tuning.fly_speed),
			float(tuning.fly_min_seconds), float(tuning.fly_max_seconds))
	var lift := maxf(distance * float(tuning.fly_arc_share), float(tuning.fly_arc_min))
	_control = (_center + rim) * 0.5
	_control.y = maxf(_center.y, rim.y) + lift

	var tween := create_tween()
	tween.tween_method(_roll, 0.0, 1.0, float(tuning.roll_seconds)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_hide_socks)
	tween.tween_method(_fly, 0.0, 1.0, fly_time)
	tween.tween_method(_drop.bind(pile_top), 0.0, 1.0, float(tuning.drop_seconds)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(landed.emit)
	tween.tween_callback(queue_free)


func _roll(t: float) -> void:
	var size := lerpf(1.0, float(_tuning.roll_end_scale), t)
	var turn := t * float(_tuning.roll_spin_turns) * TAU
	for i in _sock_ids.size():
		var start := _starts[i]
		var spun := start.basis.rotated(Vector3.UP, turn if i == 0 else -turn)
		var origin := start.origin.lerp(_center, t)
		_renderer.set_sock_transform(_sock_ids[i], Transform3D(spun.scaled(Vector3.ONE * size), origin))
	_ball.global_position = _center
	_ball.scale = Vector3.ONE * maxf(t, 0.01)


func _hide_socks() -> void:
	for sock_id in _sock_ids:
		_renderer.hide_sock(sock_id)


func _fly(t: float) -> void:
	var from := _center.lerp(_control, t)
	var to := _control.lerp(_rim, t)
	_ball.global_position = from.lerp(to, t)
	_ball.rotation.x = t * float(_tuning.fly_spin_turns) * TAU


func _drop(t: float, pile_top: Vector3) -> void:
	_ball.global_position = _rim.lerp(pile_top, t)


## Flattened sphere in the base color with a cuff band in the accent color.
func _build_ball(colors: PackedColorArray) -> void:
	var radius := float(_tuning.ball_radius)
	_ball = Node3D.new()
	add_child(_ball)
	_ball.scale = Vector3.ONE * 0.01

	var body_mesh := SphereMesh.new()
	body_mesh.radius = radius
	body_mesh.height = radius * 1.7
	body_mesh.radial_segments = 16
	body_mesh.rings = 8
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _plain(colors[0])
	_ball.add_child(body)

	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = radius * 0.92
	band_mesh.outer_radius = radius + float(_tuning.ball_band_width) * 0.5
	band_mesh.rings = 20
	band_mesh.ring_segments = 6
	var band := MeshInstance3D.new()
	band.mesh = band_mesh
	band.material_override = _plain(colors[1])
	band.rotation.z = PI * 0.5
	_ball.add_child(band)


func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
