class_name CellarCat
extends Node3D
## Easter egg: a small tabby that lives in the cellar. It naps in its bed,
## strolls around now and then and, rarely, carries a loose sock somewhere
## else. Never touches socks in a hand, on the wall or in the basket.
## Numbers in data/world.json -> cat.

enum State { NAP, WALK, SIT, PICK, DROP }
enum Goal { STROLL, FETCH, CARRY, HOME }

const WORLD_LAYER := 1
const GROUND_MASK := 1 | 2 | 8 # world and both sock layers

const FUR_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_color : source_color;
uniform vec3 stripe_color : source_color;
uniform float stripes = 0.0;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float wobble = sin(local_pos.x * 31.0 + local_pos.z * 17.0) * 1.3;
	float band = smoothstep(0.25, 0.85, sin(local_pos.y * stripes + wobble));
	float fuzz = fract(sin(dot(floor(local_pos * 400.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	ALBEDO = mix(base_color, stripe_color, band * step(0.01, stripes) * 0.6) * (0.9 + fuzz * 0.12);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	RIM = 0.12;
	RIM_TINT = 0.8;
}
"""

var active := false # true once the pile is in play
var state := State.NAP
var goal := Goal.HOME

var _cfg: Dictionary
var _field: SockField
var _player: Node3D
var _basket_at := Vector3.ZERO
var _room: AABB
var _bed := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

var _target := Vector3.ZERO
var _sock: Sock # carried in the mouth
var _wanted: Sock # walking over to pick this one up
var _state_left := 0.0
var _strolls_left := 0
var _steal_in := 0.0
var _stroll_in := 0.0
var _caught := false
var _stuck := 0.0
var _walked := 0.0

# Rig
var _body: Node3D
var _head: Node3D
var _mouth: Node3D
var _legs: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _purr: AudioStreamPlayer3D
var _curl := 1.0 # 0 standing, 1 curled up asleep
var _gait := 0.0
var _speed := 0.0
var _time := 0.0
var _blink := 3.0


func setup(field: SockField, cellar: Cellar, player: Node3D, config: Dictionary) -> void:
	_cfg = config
	_field = field
	_player = player
	_room = cellar.room_bounds()
	_basket_at = cellar.basket_mouth()
	var share: Array = _cfg.get("bed_share", [0.86, 0.84])
	_bed = Vector3(_room.get_center().x + _room.size.x * 0.5 * float(share[0]), 0.0,
			_room.get_center().z + _room.size.z * 0.5 * float(share[1]))
	_rng.randomize()
	_build()
	_build_bed(cellar)
	position = _bed
	rotation.y = _rng.randf() * TAU
	var first: Array = _cfg.get("first_steal_seconds", [270.0, 330.0])
	_steal_in = _rng.randf_range(float(first[0]), float(first[1]))
	_reset_stroll()


## Pile ready (or not): the cat only roams while the run is on.
func set_active(on: bool) -> void:
	active = on
	if not on:
		release()


## Puts a carried sock down on the floor right away, e.g. before saving.
func release() -> void:
	if _sock == null:
		return
	if is_instance_valid(_sock) and _sock.is_inside_tree():
		var at := _mouth.global_position
		at.y = _ground(at, 0.4) + 0.08
		_sock.global_position = at
		_sock.linear_velocity = Vector3.ZERO
		_sock.angular_velocity = Vector3.ZERO
		_field.end_hold(_sock)
	_sock = null


func is_carrying() -> bool:
	return _sock != null


# --- Behaviour ---

func _physics_process(delta: float) -> void:
	if _cfg.is_empty():
		return
	_time += delta
	if active and not GameState.completed:
		_steal_in -= delta
		_stroll_in -= delta
	if _sock != null and not is_instance_valid(_sock):
		_sock = null
	match state:
		State.NAP:
			if active and not GameState.completed:
				if _steal_in <= 0.0:
					_start_fetch()
				elif _stroll_in <= 0.0:
					_strolls_left = _rng.randi_range(1, 3)
					_reset_stroll()
					_next_stroll()
		State.WALK:
			_walk(delta)
		State.SIT:
			_state_left -= delta
			if _state_left <= 0.0:
				_after_sit()
		State.PICK:
			_state_left -= delta
			if _state_left <= 0.0:
				_grab_wanted()
		State.DROP:
			_state_left -= delta
			if _state_left <= 0.0:
				release()
				_strolls_left = _rng.randi_range(0, 2)
				_sit(_rng.randf_range(1.5, 3.5))
	_hold_sock(delta)
	_check_caught()
	_animate(delta)
	_update_purr(delta)


func _start_fetch() -> void:
	var interval: Array = _cfg.get("steal_seconds", [270.0, 330.0])
	_steal_in = _rng.randf_range(float(interval[0]), float(interval[1]))
	var sock := _find_loose_sock()
	if sock == null:
		_go(_random_spot(), Goal.HOME)
		return
	_wanted = sock
	_caught = false
	_go(sock.global_position, Goal.FETCH)


func _reset_stroll() -> void:
	var interval: Array = _cfg.get("stroll_seconds", [70.0, 160.0])
	_stroll_in = _rng.randf_range(float(interval[0]), float(interval[1]))


func _next_stroll() -> void:
	if _strolls_left > 0:
		_strolls_left -= 1
		_go(_random_spot(), Goal.STROLL)
	else:
		_go(_bed, Goal.HOME)


func _go(where: Vector3, why: Goal) -> void:
	_target = where
	goal = why
	state = State.WALK
	_stuck = 0.0
	_walked = 0.0


func _sit(seconds: float) -> void:
	state = State.SIT
	_state_left = seconds


func _after_sit() -> void:
	_next_stroll()


func _walk(delta: float) -> void:
	if goal == Goal.FETCH:
		if not _can_take(_wanted):
			_wanted = null
			_next_stroll()
			return
		_target = _wanted.global_position
	var to := _target - global_position
	to.y = 0.0
	var reach := float(_cfg.get("pick_reach", 0.32)) if goal == Goal.FETCH else 0.15
	if to.length() <= reach:
		_arrive()
		return
	var fast := goal == Goal.CARRY or goal == Goal.FETCH
	var top := float(_cfg.get("trot_speed" if fast else "walk_speed", 0.6))
	_speed = move_toward(_speed, top, delta * 1.5)
	# Turn towards the goal, then pad along the floor or over the pile.
	var heading := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, heading, delta * float(_cfg.get("turn_speed", 4.0)))
	var facing := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var aligned := clampf(facing.dot(to.normalized()), 0.0, 1.0)
	var step := facing * _speed * (0.3 + 0.7 * aligned) * delta
	var next := global_position + step
	next.x = clampf(next.x, _room.position.x + 0.4, _room.end.x - 0.4)
	next.z = clampf(next.z, _room.position.z + 0.4, _room.end.z - 0.4)
	var ground := _ground(next, float(_cfg.get("step_up", 0.6)))
	next.y = lerpf(global_position.y, ground, 1.0 - exp(-10.0 * delta))
	if Vector2(next.x - _bed.x, next.z - _bed.z).length() < 0.32:
		next.y = maxf(next.y, 0.045) # on the cushion
	# Gives up on goals it cannot reach, e.g. wedged against a wall or the washer.
	_stuck = _stuck + delta if Vector2(next.x - global_position.x, next.z - global_position.z).length() < _speed * delta * 0.25 else 0.0
	global_position = next
	_walked += delta
	if _stuck > 3.0 or _walked > float(_cfg.get("give_up_seconds", 45.0)):
		_arrive()


func _arrive() -> void:
	_speed = 0.0
	match goal:
		Goal.FETCH:
			state = State.PICK
			_state_left = 0.6
		Goal.CARRY:
			state = State.DROP
			_state_left = 0.5
		Goal.HOME:
			if Vector2(global_position.x - _bed.x, global_position.z - _bed.z).length() < 0.6:
				state = State.NAP
			else:
				_go(_bed, Goal.HOME)
		_:
			_sit(_rng.randf_range(2.0, 6.0))


func _grab_wanted() -> void:
	if not _can_take(_wanted) or _wanted.global_position.distance_to(_mouth.global_position) > 0.9:
		_wanted = null
		_next_stroll()
		return
	_sock = _wanted
	_wanted = null
	_field.begin_hold(_sock)
	GameState.cat_steals += 1
	Sfx.play("meow", _mouth.global_position)
	# Half the time the loot goes to its bed, a little stash for the player to find.
	var dest := _bed + Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.2, 0.2))
	if _rng.randf() > float(_cfg.get("stash_share", 0.5)):
		dest = _random_spot(_sock.global_position, float(_cfg.get("min_carry_distance", 4.0)))
	_go(dest, Goal.CARRY)


## The carried sock dangles from the mouth, pulled along like the player's hold.
func _hold_sock(_delta: float) -> void:
	if _sock == null:
		return
	var target := _mouth.global_position + Vector3.DOWN * 0.07
	_sock.linear_velocity = ((target - _sock.global_position) * 18.0).limit_length(6.0)
	var wanted := global_basis * Basis(Vector3.RIGHT, PI * 0.5)
	var diff := (wanted.get_rotation_quaternion() * _sock.global_basis.get_rotation_quaternion().inverse()).normalized()
	if diff.w < 0.0:
		diff = -diff
	var angle := diff.get_angle()
	_sock.angular_velocity = diff.get_axis() * angle * 8.0 if angle > 0.0001 else Vector3.ZERO


## Caught red-pawed: the player walks up while the sock is in its mouth.
func _check_caught() -> void:
	if _sock == null or _caught or _player == null:
		return
	if _player.global_position.distance_to(global_position) <= float(_cfg.get("caught_distance", 2.5)):
		_caught = true
		GameState.cat_catches += 1
		Sfx.play("meow", _mouth.global_position)
		Events.cat_caught.emit()


func _can_take(sock: Sock) -> bool:
	if sock == null or not is_instance_valid(sock) or not sock.is_inside_tree():
		return false
	if _field.sock_by_id(sock.sock_id) != sock or _field.is_held(sock.sock_id):
		return false
	var at := sock.global_position
	if at.y > float(_cfg.get("max_pick_height", 1.2)):
		return false
	var basket := Vector2(at.x - _basket_at.x, at.z - _basket_at.z).length()
	return basket > float(_cfg.get("basket_keep_out", 1.3))


## A sock lying open at the top, low enough for a cat to reach.
func _find_loose_sock() -> Sock:
	var count := _field.socks.sock_count() if _field.socks else 0
	if count == 0:
		return null
	var space := get_world_3d().direct_space_state
	var best: Sock = null
	var best_score := INF
	for i in int(_cfg.get("search_tries", 60)):
		var sock := _field.sock_by_id(_rng.randi_range(0, count - 1))
		if not _can_take(sock):
			continue
		var from := sock.global_position + Vector3.UP * 2.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, sock.global_position, GROUND_MASK))
		if hit.is_empty() or hit.collider != sock:
			continue
		# Prefer socks near the cat, with a little randomness.
		var score := global_position.distance_to(sock.global_position) * _rng.randf_range(0.6, 1.4)
		if score < best_score:
			best_score = score
			best = sock
	return best


## A free spot on the floor, optionally far enough from `away`.
func _random_spot(away := Vector3.INF, min_distance := 0.0) -> Vector3:
	var inner := _room.grow(-float(_cfg.get("wall_margin", 1.2)))
	var spot := _bed
	for i in 30:
		spot = Vector3(_rng.randf_range(inner.position.x, inner.end.x), 0.0,
				_rng.randf_range(inner.position.z, inner.end.z))
		if Vector2(spot.x - _basket_at.x, spot.z - _basket_at.z).length() < float(_cfg.get("basket_keep_out", 1.3)):
			continue
		if away != Vector3.INF and spot.distance_to(Vector3(away.x, 0.0, away.z)) < min_distance:
			continue
		if _ground(spot, 0.8) > 0.35:
			continue # furniture or the pile itself
		return spot
	return spot


## Height to stand on at `at`, searching down from just above the cat.
func _ground(at: Vector3, step_up: float) -> float:
	if not is_inside_tree():
		return 0.0
	var from := Vector3(at.x, maxf(global_position.y, 0.0) + step_up, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, -1.0, at.z), GROUND_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return maxf(hit.position.y, 0.0) if not hit.is_empty() else 0.0


# --- Animation ---

func _animate(delta: float) -> void:
	var sleeping := state == State.NAP and Vector2(global_position.x - _bed.x, global_position.z - _bed.z).length() < 0.8
	_curl = move_toward(_curl, 1.0 if sleeping else 0.0, delta * (0.6 if sleeping else 2.5))
	var walking := state == State.WALK
	_gait += delta * _speed * 14.0
	var swing := sin(_gait) * 0.55 * clampf(_speed / 0.4, 0.0, 1.0)
	var crouch := 0.0
	if state == State.PICK or state == State.DROP:
		crouch = 1.0
	var breathe := sin(_time * 1.7) * (0.03 if sleeping else 0.012)

	# Body sinks and rounds off when curled up.
	_body.position = Vector3(0.0, lerpf(0.2 + absf(sin(_gait)) * 0.008, 0.1, _curl) - crouch * 0.03, 0.0)
	_body.rotation = Vector3(-crouch * 0.12, _curl * 0.35, _curl * 0.25)
	_body.scale = Vector3(1.0 + breathe + _curl * 0.15, 1.0 + breathe, 1.0 - _curl * 0.2)

	for i in _legs.size():
		var leg := _legs[i]
		var phase := swing if i == 0 or i == 3 else -swing
		leg.rotation.x = phase if walking else 0.0
		leg.scale = Vector3.ONE * (1.0 - _curl * 0.85)

	# Head: looks around while sitting, dips to pick up, tucks in to sleep.
	var look := sin(_time * 0.7) * 0.6 if state == State.SIT else 0.0
	var head_at := Vector3(0.0, 0.31 + sin(_gait * 2.0) * 0.006, -0.22)
	head_at = head_at.lerp(Vector3(0.12, 0.13, -0.15), _curl)
	head_at += Vector3(0.0, -0.13, -0.05) * crouch
	_head.position = head_at
	_head.rotation = Vector3(-crouch * 0.6 + _curl * 0.35, look + _curl * 0.9, _curl * 0.5)

	# Tail: up and swishing when awake, wrapped round the body when asleep.
	var tail_up := 1.0 - _curl
	for i in _tail.size():
		var seg := _tail[i]
		var sway := sin(_time * 2.2 - i * 0.6) * 0.18
		var awake_rot := Vector3(-0.55 if i == 0 else 0.12, sway, 0.0)
		var curl_rot := Vector3(0.05, 0.42 + sin(_time * 0.8 - i) * 0.03, 0.0)
		seg.rotation = curl_rot.lerp(awake_rot, tail_up)

	# Ears twitch now and then, eyes blink, and close for the nap.
	for i in _ears.size():
		_ears[i].rotation.z = (0.25 if i == 0 else -0.25) + (sin(_time * 9.0) * 0.15 if fmod(_time + i, 7.0) < 0.25 else 0.0)
	_blink -= delta
	var shut := _curl > 0.5 or _blink < 0.12
	if _blink < 0.0:
		_blink = _rng.randf_range(2.0, 6.0)
	for eye in _eyes:
		eye.scale.y = 0.12 if shut else 1.0


func _update_purr(delta: float) -> void:
	if _purr == null:
		return
	var near := _player != null and _player.global_position.distance_to(global_position) < float(_cfg.get("purr_distance", 3.0))
	var on := _curl > 0.7 and near
	var level := float(_cfg.get("purr_volume_db", -14.0))
	_purr.volume_db = move_toward(_purr.volume_db, level if on else -60.0, delta * 25.0)


# --- Model ---

func _fur(base: String, stripe: String = "", stripes: float = 0.0) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = FUR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", Color(base))
	material.set_shader_parameter("stripe_color", Color(stripe if stripe != "" else base))
	material.set_shader_parameter("stripes", stripes)
	return material


func _plain(color: String, roughness := 0.6, glow := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = glow
	return material


func _part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, rot := Vector3.ZERO, size := Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.rotation = rot
	part.scale = size
	parent.add_child(part)
	return part


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _build() -> void:
	var colors: Dictionary = _cfg.get("colors", {})
	var fur := _fur(colors.get("fur", "#d4873e"), colors.get("stripes", "#8e4c1f"), 70.0)
	var head_fur := _fur(colors.get("fur", "#d4873e"), colors.get("stripes", "#8e4c1f"), 90.0)
	var white := _fur(colors.get("white", "#efe7da"))
	var pink := _plain(colors.get("pink", "#e29a9a"), 0.5)
	var eye := _plain(colors.get("eyes", "#b9cf4a"), 0.15, 0.25)
	var dark := _plain("#141210", 0.2)

	_body = Node3D.new()
	add_child(_body)
	# Chest, slimmer waist and round haunches instead of one sausage.
	var along := Vector3(PI * 0.5, 0.0, 0.0)
	var waist := CapsuleMesh.new()
	waist.radius = 0.088
	waist.height = 0.38
	_part(_body, waist, fur, Vector3(0.0, 0.0, 0.01), along, Vector3(1.0, 1.0, 0.95))
	_part(_body, _sphere(0.098), fur, Vector3(0.0, 0.012, -0.12), along, Vector3(0.95, 1.15, 1.05))
	_part(_body, _sphere(0.104), fur, Vector3(0.0, 0.004, 0.12), along, Vector3(1.05, 1.1, 1.08))
	_part(_body, _sphere(0.072), white, Vector3(0.0, -0.035, -0.16), Vector3.ZERO, Vector3(0.95, 1.0, 1.0))
	_part(_body, _sphere(0.062), fur, Vector3(0.0, 0.085, -0.19), along, Vector3(1.0, 1.0, 1.1))

	# Legs pivot at the shoulder and hip; white paws.
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.022
	leg_mesh.height = 0.18
	for at in [Vector3(-0.055, 0.0, -0.14), Vector3(0.055, 0.0, -0.14), Vector3(-0.055, 0.0, 0.14), Vector3(0.055, 0.0, 0.14)]:
		var hip := Node3D.new()
		hip.position = at + Vector3(0.0, -0.03, 0.0)
		_body.add_child(hip)
		_part(hip, leg_mesh, fur, Vector3(0.0, -0.075, 0.0))
		_part(hip, _sphere(0.03), white, Vector3(0.0, -0.155, -0.012), Vector3.ZERO, Vector3(1.0, 0.6, 1.3))
		_legs.append(hip)

	# Tail: a chain of short segments, each bending a little.
	var seg_mesh := CapsuleMesh.new()
	seg_mesh.radius = 0.027
	seg_mesh.height = 0.095
	var parent: Node3D = _body
	var offset := Vector3(0.0, 0.04, 0.22)
	for i in 7:
		var seg := Node3D.new()
		seg.position = offset
		parent.add_child(seg)
		var tip := white if i == 6 else fur
		_part(seg, seg_mesh, tip, Vector3(0.0, 0.0, 0.035), Vector3(PI * 0.5, 0.0, 0.0), Vector3.ONE * (1.0 - i * 0.07))
		_tail.append(seg)
		parent = seg
		offset = Vector3(0.0, 0.0, 0.065)

	_head = Node3D.new()
	add_child(_head)
	_part(_head, _sphere(0.085), head_fur, Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0), Vector3(1.08, 1.0, 0.92))
	for side in [-1.0, 1.0]:
		_part(_head, _sphere(0.048), head_fur, Vector3(0.042 * side, -0.026, -0.02), along, Vector3(1.0, 0.9, 0.85))
	_part(_head, _sphere(0.042), white, Vector3(0.0, -0.032, -0.064), Vector3.ZERO, Vector3(1.25, 0.8, 0.9))
	_part(_head, _sphere(0.012), pink, Vector3(0.0, -0.012, -0.098), Vector3.ZERO, Vector3(1.3, 0.8, 0.8))
	_mouth = Node3D.new()
	_mouth.position = Vector3(0.0, -0.06, -0.09)
	_head.add_child(_mouth)
	for side in [-1.0, 1.0]:
		var socket := Node3D.new()
		socket.position = Vector3(0.035 * side, 0.016, -0.064)
		_head.add_child(socket)
		_part(socket, _sphere(0.021), eye, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.9, 0.7))
		_part(socket, _sphere(0.021), dark, Vector3(0.0, 0.0, -0.006), Vector3.ZERO, Vector3(0.3, 0.85, 0.7))
		_part(socket, _sphere(0.005), _plain("#ffffff", 0.1, 1.0), Vector3(0.006 * side, 0.008, -0.016))
		_eyes.append(socket)
		var ear := Node3D.new()
		ear.position = Vector3(0.05 * side, 0.06, -0.005)
		_head.add_child(ear)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.04
		cone.height = 0.075
		cone.radial_segments = 4
		_part(ear, cone, head_fur, Vector3(0.0, 0.025, 0.0), Vector3(0.0, PI * 0.25, 0.0), Vector3(1.0, 1.0, 0.45))
		_part(ear, cone, pink, Vector3(0.0, 0.022, -0.008), Vector3(0.0, PI * 0.25, 0.0), Vector3(0.65, 0.75, 0.25))
		_ears.append(ear)
		# Whiskers
		var whisker := CylinderMesh.new()
		whisker.top_radius = 0.0012
		whisker.bottom_radius = 0.0012
		whisker.height = 0.11
		whisker.radial_segments = 3
		for w in 3:
			_part(_head, whisker, _plain("#f4f0e8", 0.4), Vector3(0.06 * side, -0.03 + w * 0.008, -0.075),
					Vector3(0.0, 0.0, PI * 0.5 + side * (w - 1) * 0.12 * -1.0 + side * 0.1))

	var purr_at := Vector3(0.0, 0.2, 0.0)
	_purr = Sfx.start_loop("purr", self, purr_at) as AudioStreamPlayer3D
	if _purr:
		_purr.volume_db = -60.0


## A round, knitted-looking cushion in its corner.
func _build_bed(cellar: Cellar) -> void:
	var colors: Dictionary = _cfg.get("colors", {})
	# Solid like the other props: socks dropped in it rest on the cushion.
	var bed := Cellar.static_body("CatBed")
	cellar.add_child(bed)
	bed.position = _bed
	var rim := TorusMesh.new()
	rim.inner_radius = 0.26
	rim.outer_radius = 0.42
	rim.rings = 24
	rim.ring_segments = 10
	var rim_scale := Vector3(1.0, 1.4, 1.0)
	var rim_at := Vector3(0.0, 0.06, 0.0)
	_part(bed, rim, _fur(colors.get("bed", "#7b4f6e"), colors.get("bed_stripes", "#5c3a52"), 260.0),
			rim_at, Vector3.ZERO, rim_scale)
	# Collision shapes do not scale unevenly, so the squashed ring is baked in.
	var faces := rim.get_faces()
	for i in faces.size():
		faces[i] = faces[i] * rim_scale + rim_at
	var rim_shape := ConcavePolygonShape3D.new()
	rim_shape.set_faces(faces)
	var rim_collider := CollisionShape3D.new()
	rim_collider.shape = rim_shape
	bed.add_child(rim_collider)
	var cushion := CylinderMesh.new()
	cushion.top_radius = 0.3
	cushion.bottom_radius = 0.32
	cushion.height = 0.05
	_part(bed, cushion, _fur(colors.get("cushion", "#e2cfa8")), Vector3(0.0, 0.03, 0.0))
	Cellar.add_collider(bed, cushion, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0)))
