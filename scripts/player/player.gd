class_name Player
extends CharacterBody3D
## First-person walker that can climb the pile, grab, throw and inspect socks.
## It carries a bundle of up to carry_max socks: one active sock in hand (the
## one that throws, pairs and inspects) and the rest tucked under the arm.
## Tuning lives in data/player.json.

const WORLD_LAYER := 1
const SOCK_LAYER := 2
const PLAYER_LAYER := 3
const SUMMIT_CHECK_SECONDS := 0.5
const WIGGLE_SECONDS := 0.35

var camera: Camera3D

var _cfg: Dictionary
var _field: SockField
var _held: Sock # the active sock in hand
var _carried: Array[Sock] = [] # the rest of the bundle, next active first
var _yaw := 0.0
var _pitch := 0.0
var _inspect_spin := Vector2.ZERO
var _wiggle_left := 0.0
var _summit_timer := 0.0
var _summit_done := false
var _pending_held := -1
var _pending_carried := PackedInt32Array()
var _typed := "" # last letters, for the debug cheat code
var _cheat_cache := Vector2i(-1, -1) # (sock, partner), avoids a scan every frame
var _stride_left := 0.0 # metres until the next footstep
## Per sock in hand: [seconds stuck behind something, position last frame].
var _snags := {}
var _fall_speed := 0.0
## Standing on socks. Socks never block the player sideways; a probe under the
## feet lifts the player onto them, so loose socks and slopes walk smoothly.
var _on_sock_ground := false
var _probe := PhysicsShapeQueryParameters3D.new()
## 0 normal view, 1 fully zoomed (silver socks unlock zoom).
var _zoom := 0.0


func _ready() -> void:
	_cfg = Config.player
	collision_layer = 1 << (PLAYER_LAYER - 1)
	collision_mask = 1 << (WORLD_LAYER - 1)
	var foot := SphereShape3D.new()
	foot.radius = float(_cfg.get("sock_foot_radius", 0.18))
	_probe.shape = foot
	_probe.collision_mask = 1 << (SOCK_LAYER - 1) # lone floor socks are not worth a bump
	floor_max_angle = deg_to_rad(float(_cfg.floor_max_angle_deg))
	floor_snap_length = float(_cfg.step_height)
	floor_stop_on_slope = true

	var shape := CapsuleShape3D.new()
	shape.radius = float(_cfg.capsule_radius)
	shape.height = float(_cfg.capsule_height)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)

	camera = Camera3D.new()
	camera.position.y = float(_cfg.eye_height)
	camera.near = 0.05
	camera.current = true
	add_child(camera)

	_yaw = rotation.y
	rotation = Vector3.ZERO
	Events.pile_ready.connect(_on_pile_ready)


func setup(field: SockField) -> void:
	_field = field


## Places the player at a spawn transform (feet position, facing).
func place(spawn: Transform3D) -> void:
	global_position = spawn.origin
	_yaw = spawn.basis.get_euler().y
	_pitch = 0.0
	_apply_look()


func held_sock() -> Sock:
	return _held


## The socks under the arm, not counting the active one in hand.
func carried_socks() -> Array[Sock]:
	return _carried


## Active sock plus bundle.
func carry_count() -> int:
	return _carried.size() + (1 if _held else 0)


## The sock under the crosshair within reach, never the held one.
func aimed_sock() -> Sock:
	if _field == null:
		return null
	# The physics box around a bent sock is much bigger than the sock, so each box hit
	# is checked against the real leg and foot; a miss looks further along the ray.
	var exclude: Array[RID] = []
	for i in int(_cfg.get("aim_max_checks", 6)):
		var hit := _ray(float(_cfg.grab_reach), SockField.ANY_SOCK, exclude)
		if hit.is_empty():
			return null
		var sock := _field.sock_at(hit.collider)
		if sock != null and sock != _held and not _carried.has(sock) and _on_sock(sock):
			return sock
		exclude.append(hit.rid)
	return null


## Whether the crosshair ray really touches the sock's leg or foot.
func _on_sock(sock: Sock) -> bool:
	var to_local := sock.global_transform.affine_inverse()
	var from := to_local * camera.global_position
	var dir := (to_local.basis * -camera.global_basis.z).normalized()
	var shape := _field.socks.shape_of(sock.sock_id)
	return SockMesh.ray_hit(shape, from, dir, float(_cfg.get("aim_tolerance", 0.015))) >= 0.0


## Forgets the held sock without touching its physics (it leaves for the basket).
## The next sock from the bundle moves into the hand.
func release_held() -> void:
	if _held:
		Events.sock_released.emit(_held.sock_id)
	_held = null
	_promote_next()


func wiggle_held() -> void:
	_wiggle_left = WIGGLE_SECONDS


func capture() -> Dictionary:
	return {
		"position": global_position,
		"yaw": _yaw,
		"pitch": _pitch,
		"held": _held.sock_id if _held else -1,
		"carried": PackedInt32Array(_carried.map(func(sock: Sock) -> int: return sock.sock_id)),
	}


func apply(state: Dictionary) -> void:
	global_position = state.get("position", global_position)
	_yaw = float(state.get("yaw", _yaw))
	_pitch = float(state.get("pitch", 0.0))
	_pending_held = int(state.get("held", -1))
	_pending_carried = PackedInt32Array(state.get("carried", PackedInt32Array()))
	_apply_look()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_track_cheat_code(event.keycode)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Zoomed in, the view turns slower so aiming stays steady.
		var motion: Vector2 = event.relative * Settings.mouse_sensitivity * (camera.fov / Settings.fov)
		if Settings.invert_mouse:
			motion.y = -motion.y
		if _held and Input.is_action_pressed("inspect"):
			_inspect_spin += motion
		else:
			_yaw -= motion.x
			_pitch = clampf(_pitch - motion.y, deg_to_rad(-89.0), deg_to_rad(89.0))
			_apply_look()
	elif event.is_action_pressed("grab"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif aimed_sock():
			_grab()
		elif _held:
			_drop()
	elif event.is_action_pressed("throw") and _held:
		_throw()
	elif event.is_action_pressed("drop_all") and _held:
		_drop_all()
	elif event.is_action_pressed("switch_next"):
		_cycle(1)
	elif event.is_action_pressed("switch_prev"):
		_cycle(-1)


func _physics_process(delta: float) -> void:
	_update_zoom(delta)
	_move(delta)
	if _held:
		_steer_held(delta)
	_steer_carried(delta)
	_check_summit(delta)
	_update_highlight()


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if get_tree().paused or not GameState.running:
		input = Vector2.ZERO
	var direction := (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := float(_cfg.speed)
	if GameState.has_ability("sprint") and Input.is_action_pressed("sprint"):
		speed *= float(_cfg.get("sprint_multiplier", 1.8))
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if _grounded():
		if Input.is_action_just_pressed("jump") and GameState.running:
			velocity.y = float(_cfg.jump_velocity)
			_on_sock_ground = false
	else:
		velocity += get_gravity() * delta

	var was_on_floor := _grounded()
	var start := global_transform
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	_fall_speed = maxf(-velocity.y, 0.0) if not was_on_floor else 0.0
	move_and_slide()
	if was_on_floor and horizontal.length() > 0.001:
		_try_step(start, horizontal)
	_stand_on_socks(start, was_on_floor, delta)
	_footsteps(was_on_floor, start.origin)


## Holding the zoom key narrows the view once silver socks unlocked it.
func _update_zoom(delta: float) -> void:
	var want := 1.0 if GameState.has_ability("zoom") and GameState.running \
			and Input.is_action_pressed("zoom") else 0.0
	_zoom = move_toward(_zoom, want, float(_cfg.get("zoom_speed", 6.0)) * delta)
	var eased := _zoom * _zoom * (3.0 - 2.0 * _zoom)
	camera.fov = lerpf(Settings.fov, minf(float(_cfg.get("zoom_fov", 22.0)), Settings.fov), eased)


func _grounded() -> bool:
	return is_on_floor() or _on_sock_ground


## Puts the feet on the sock surface below. Rises of up to sock_climb per step
## are walked up; a higher wall of socks blocks like a wall (jump over it).
func _stand_on_socks(start: Transform3D, was_grounded: bool, delta: float) -> void:
	_on_sock_ground = false
	if velocity.y > 0.0:
		return
	var climb := float(_cfg.get("sock_climb", 0.35))
	var snap := float(_cfg.step_height) if was_grounded else maxf(-velocity.y * delta, 0.0) + 0.02
	var radius := (_probe.shape as SphereShape3D).radius
	var space := get_world_3d().direct_space_state
	var top := global_position + Vector3.UP * (climb + radius)
	_probe.transform = Transform3D(Basis.IDENTITY, top)
	_probe.motion = Vector3.DOWN * (climb + snap)
	var cast := space.cast_motion(_probe)
	if cast[0] <= 0.0:
		# Even the highest probe is inside socks: too steep, stay where we were.
		if was_grounded:
			global_position = Vector3(start.origin.x, global_position.y, start.origin.z)
		return
	if cast[0] >= 1.0:
		return
	var surface := top.y + _probe.motion.y * cast[0] - radius
	if surface < global_position.y - snap:
		return
	global_position.y = maxf(surface, global_position.y) if not was_grounded else surface
	velocity.y = 0.0
	_on_sock_ground = true


## A step sound every stride, softer on socks than on the floor, and a thud
## when landing from a jump.
func _footsteps(was_on_floor: bool, from: Vector3) -> void:
	if not _grounded():
		return
	if not was_on_floor:
		if _fall_speed >= float(_cfg.get("land_sound_speed", 3.5)):
			Sfx.play("land_player")
		_stride_left = float(_cfg.get("step_stride", 1.8)) * 0.5
		return
	_stride_left -= ((global_position - from) * Vector3(1, 0, 1)).length()
	if _stride_left > 0.0:
		return
	_stride_left = float(_cfg.get("step_stride", 1.8))
	Sfx.play("step_socks" if _on_sock_ground or _on_socks() else "step_floor")


func _on_socks() -> bool:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().y > 0.5 and hit.get_collider() is Sock:
			return true
	return false


## Socks form a bumpy surface: lift over small edges instead of getting stuck.
func _try_step(start: Transform3D, horizontal: Vector3) -> void:
	var moved := (global_position - start.origin) * Vector3(1, 0, 1)
	if moved.length() >= horizontal.length() * 0.5:
		return
	var step := float(_cfg.step_height)
	var up := Vector3.UP * step
	if test_move(start, up):
		return
	var raised := start.translated(up)
	if test_move(raised, horizontal):
		return
	var collision := KinematicCollision3D.new()
	var ahead := raised.translated(horizontal)
	if test_move(ahead, -up, collision):
		global_position = ahead.origin - up + collision.get_travel()
	else:
		global_position = ahead.origin - up


func _apply_look() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	if camera:
		camera.rotation = Vector3(_pitch, 0.0, 0.0)


func _ray(length: float, mask: int, skip: Array[RID] = []) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(skip)
	if _held:
		exclude.append(_held.get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query)


func _grab() -> void:
	var sock := aimed_sock()
	if sock == null:
		return
	if carry_count() >= int(_cfg.get("carry_max", 1)):
		wiggle_held() # arms full
		return
	_take(sock)


## The new sock goes into the hand; the one held before joins the bundle.
func _take(sock: Sock) -> void:
	if _held:
		_carried.push_front(_held)
		_field.carry(_held)
	_held = sock
	_inspect_spin = Vector2.ZERO
	_field.begin_hold(sock)
	Events.sock_grabbed.emit(sock.sock_id)


func _drop() -> void:
	var sock := _held
	release_held()
	_field.end_hold(sock)


## Q: the whole armful falls apart and spreads out, so every sock stays visible.
func _drop_all() -> void:
	var socks: Array[Sock] = []
	while _held:
		socks.append(_held)
		_drop()
	var forward := -camera.global_basis.z
	for i in socks.size():
		var sock := socks[i]
		sock.linear_velocity = velocity + scatter_velocity(i, socks.size(), forward, _cfg, randf(), randf())
		sock.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) \
				* float(_cfg.get("drop_scatter_spin", 6.0))
	if not socks.is_empty():
		_field.wake_around(socks[0].global_position, float(_cfg.get("drop_scatter_wake", 1.2)))


## Kick for sock i of n when a bundle is dropped: spread round a circle with
## jitter, pushed a little forward and up.
static func scatter_velocity(i: int, n: int, forward: Vector3, cfg: Dictionary, r1: float, r2: float) -> Vector3:
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	var angle := TAU * float(i) / maxf(float(n), 1.0) + (r1 - 0.5) * TAU / maxf(float(n), 1.0)
	var side := flat.rotated(Vector3.UP, angle)
	var speed := float(cfg.get("drop_scatter_speed", 1.6)) * lerpf(0.6, 1.0, r2)
	return side * speed + flat * float(cfg.get("drop_scatter_forward", 0.6)) \
			+ Vector3.UP * float(cfg.get("drop_scatter_lift", 1.0))


func _throw() -> void:
	var sock := _held
	var throw_velocity := -camera.global_basis.z * float(_cfg.throw_speed) + velocity
	_held = null
	_field.throw_sock(sock, throw_velocity)
	GameState.register_throw(sock.sock_id)
	_promote_next()


func _promote_next() -> void:
	while not _carried.is_empty() and _held == null:
		var next: Sock = _carried.pop_front()
		if is_instance_valid(next) and next.is_inside_tree():
			_held = next
			_inspect_spin = Vector2.ZERO
			_field.begin_hold(next)


## Mouse wheel: the active sock goes to the bundle and the next one comes up.
func _cycle(step: int) -> void:
	if _held == null or _carried.is_empty():
		return
	var old := _held
	if step > 0:
		_carried.push_back(old)
		_held = _carried.pop_front()
	else:
		_carried.push_front(old)
		_held = _carried.pop_back()
	_field.carry(old)
	_field.begin_hold(_held)
	_inspect_spin = Vector2.ZERO
	Sfx.play("grab")


## Soft spring towards the hold point; never teleports.
func _steer_held(delta: float) -> void:
	if not is_instance_valid(_held):
		_held = null
		return
	var inspecting := Input.is_action_pressed("inspect")
	var distance := float(_cfg.hold_inspect_distance if inspecting else _cfg.hold_distance)
	var cam := camera.global_transform
	var target := cam.origin - cam.basis.z * distance - cam.basis.y * (0.0 if inspecting else 0.15)

	if _wiggle_left > 0.0:
		_wiggle_left -= delta
		var t := _wiggle_left / WIGGLE_SECONDS
		target += cam.basis.x * sin(_wiggle_left * 60.0) * 0.06 * t

	var max_speed := float(_cfg.hold_max_speed)
	_unsnag(_held, target, delta)
	_held.linear_velocity = ((target - _held.global_position) * float(_cfg.hold_spring)).limit_length(max_speed)

	# Hold the sock flat across the view; while inspecting, mouse and time spin it.
	if inspecting:
		_inspect_spin.x += float(_cfg.inspect_turn_speed) * delta * 0.25
	var wanted := cam.basis * Basis.from_euler(Vector3(_inspect_spin.y * 2.0, PI * 0.5 + _inspect_spin.x * 2.0, 0.0))
	var diff := (wanted.get_rotation_quaternion() * _held.global_basis.get_rotation_quaternion().inverse()).normalized()
	if diff.w < 0.0:
		diff = -diff
	var angle := diff.get_angle()
	var turn := Vector3.ZERO
	if angle > 0.0001:
		turn = diff.get_axis() * angle * float(_cfg.hold_turn_spring)
	_held.angular_velocity = turn.limit_length(max_speed * 2.0)


## The bundle hangs low on the left of the view, stacked like an armful.
func _steer_carried(delta: float) -> void:
	if _carried.is_empty():
		return
	var cam := camera.global_transform
	var spring := float(_cfg.hold_spring)
	var max_speed := float(_cfg.hold_max_speed)
	var gap := float(_cfg.get("carry_spacing", 0.045))
	var flat := cam.basis * Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0))
	for i in range(_carried.size() - 1, -1, -1):
		var sock: Sock = _carried[i]
		if not is_instance_valid(sock) or not sock.is_inside_tree():
			_carried.remove_at(i)
			continue
		var target := cam.origin - cam.basis.z * float(_cfg.get("carry_distance", 0.7)) \
				- cam.basis.x * 0.38 - cam.basis.y * (0.42 - gap * i)
		_unsnag(sock, target, delta)
		sock.linear_velocity = ((target - sock.global_position) * spring).limit_length(max_speed)
		var wanted := flat * Basis(Vector3.UP, 0.25 * sin(i * 1.7))
		var diff := (wanted.get_rotation_quaternion() * sock.global_basis.get_rotation_quaternion().inverse()).normalized()
		if diff.w < 0.0:
			diff = -diff
		var angle := diff.get_angle()
		sock.angular_velocity = diff.get_axis() * angle * float(_cfg.hold_turn_spring) if angle > 0.0001 else Vector3.ZERO


## A sock in hand collides with walls and props like everything else. When it
## catches behind a shelf post while the player walks on, it would stay
## stuck there. So once it has made no headway for snag_seconds and the spot
## it wants to reach is free, it slips through until it is back in place.
func _unsnag(sock: Sock, target: Vector3, delta: float) -> void:
	var world := 1 << (WORLD_LAYER - 1)
	var gap := sock.global_position.distance_to(target)
	var entry: Array = _snags.get(sock.sock_id, [0.0, sock.global_position])
	if sock.collision_mask == 0:
		var back := gap < float(_cfg.get("snag_release_distance", 0.1)) or not _free_point(target)
		if back and not _overlaps_world(sock):
			sock.collision_mask = world
			_snags.erase(sock.sock_id)
		return
	var wanted := minf(gap * float(_cfg.hold_spring), float(_cfg.hold_max_speed)) * delta
	var moved: float = sock.global_position.distance_to(entry[1])
	var stuck := gap > float(_cfg.get("snag_distance", 0.2)) and moved < wanted * 0.25
	entry[0] = float(entry[0]) + delta if stuck else 0.0
	entry[1] = sock.global_position
	_snags[sock.sock_id] = entry
	if float(entry[0]) >= float(_cfg.get("snag_seconds", 0.25)) and _free_point(target):
		sock.collision_mask = 0
		entry[0] = 0.0


func _free_point(at: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = at
	query.collision_mask = 1 << (WORLD_LAYER - 1)
	return get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


func _overlaps_world(sock: Sock) -> bool:
	var owners := sock.get_shape_owners()
	if owners.is_empty():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sock.shape_owner_get_shape(owners[0], 0)
	query.transform = sock.global_transform * sock.shape_owner_get_transform(owners[0])
	query.collision_mask = 1 << (WORLD_LAYER - 1)
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Only the sock under the crosshair glows, so it is clear which one a click takes.
func _update_highlight() -> void:
	if _field == null or _field.renderer == null:
		return
	var sock := aimed_sock()
	_field.renderer.set_highlight(sock.sock_id if sock else -1)
	# Debug cheat: the partner of the held sock (else the aimed one) glows too.
	var partner := -1
	var source: Sock = _held if _held else sock
	if GameState.cheat_mode and source and _field.socks:
		if _cheat_cache.x != source.sock_id:
			_cheat_cache = Vector2i(source.sock_id, _field.socks.partner_of(source.sock_id))
		partner = _cheat_cache.y
	_field.renderer.set_partner_highlight(partner)


## Debug cheat: typing the code from data/gameplay.json toggles cheat mode.
func _track_cheat_code(keycode: Key) -> void:
	var code := String(Config.gameplay.get("cheat_code", "")).to_upper()
	if code.is_empty():
		return
	_typed = (_typed + OS.get_keycode_string(keycode).to_upper()).right(code.length())
	if _typed == code:
		_typed = ""
		GameState.cheat_mode = not GameState.cheat_mode
		GameState.cheat_used = GameState.cheat_used or GameState.cheat_mode


func _check_summit(delta: float) -> void:
	if _summit_done or _field == null or not GameState.running or not _grounded():
		return
	_summit_timer -= delta
	if _summit_timer > 0.0:
		return
	_summit_timer = SUMMIT_CHECK_SECONDS
	var top := _field.surface_height()
	var flat := Vector2(global_position.x - top.x, global_position.z - top.z)
	if flat.length() <= float(Config.gameplay.summit_radius) and global_position.y >= top.y - 0.35:
		_summit_done = true
		Events.summit_reached.emit()


func _on_pile_ready() -> void:
	if _field and _field.has_method("sock_by_id"):
		# Bundle first (last to first, each pushed under the arm), then the hand.
		var ids := Array(_pending_carried)
		ids.reverse()
		ids.append(_pending_held)
		for sock_id: int in ids:
			var sock: Sock = _field.call("sock_by_id", sock_id) if sock_id >= 0 else null
			if sock:
				sock.global_position = camera.global_position - camera.global_basis.z * float(_cfg.hold_distance)
				_take(sock)
	_pending_held = -1
	_pending_carried = PackedInt32Array()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
