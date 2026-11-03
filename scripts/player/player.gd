class_name Player
extends CharacterBody3D
## First-person walker that can climb the pile, grab, throw and inspect socks.
## Tuning lives in data/player.json.

const WORLD_LAYER := 1
const SOCK_LAYER := 2
const PLAYER_LAYER := 3
const SUMMIT_CHECK_SECONDS := 0.5
const WIGGLE_SECONDS := 0.35

var camera: Camera3D

var _cfg: Dictionary
var _field: SockField
var _held: Sock
var _yaw := 0.0
var _pitch := 0.0
var _inspect_spin := Vector2.ZERO
var _wiggle_left := 0.0
var _summit_timer := 0.0
var _summit_done := false
var _pending_held := -1
var _typed := "" # last letters, for the debug cheat code


func _ready() -> void:
	_cfg = Config.player
	collision_layer = 1 << (PLAYER_LAYER - 1)
	collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (SOCK_LAYER - 1))
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


## The sock under the crosshair within reach, never the held one.
func aimed_sock() -> Sock:
	if _field == null:
		return null
	var hit := _ray(float(_cfg.grab_reach), 1 << (SOCK_LAYER - 1))
	if hit.is_empty():
		return null
	var sock := _field.sock_at(hit.collider)
	return null if sock == _held else sock


## Forgets the held sock without touching its physics (it leaves for the basket).
func release_held() -> void:
	if _held:
		Events.sock_released.emit(_held.sock_id)
	_held = null


func wiggle_held() -> void:
	_wiggle_left = WIGGLE_SECONDS


func capture() -> Dictionary:
	return {
		"position": global_position,
		"yaw": _yaw,
		"pitch": _pitch,
		"held": _held.sock_id if _held else -1,
	}


func apply(state: Dictionary) -> void:
	global_position = state.get("position", global_position)
	_yaw = float(state.get("yaw", _yaw))
	_pitch = float(state.get("pitch", 0.0))
	_pending_held = int(state.get("held", -1))
	_apply_look()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_track_cheat_code(event.keycode)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative * Settings.mouse_sensitivity
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
		elif _held:
			_drop()
		else:
			_grab()
	elif event.is_action_pressed("throw") and _held:
		_throw()
	elif event.is_action_pressed("throw") and GameState.cheat_mode:
		_show_partner()


func _physics_process(delta: float) -> void:
	camera.fov = Settings.fov
	_move(delta)
	if _held:
		_steer_held(delta)
	_check_summit(delta)
	_update_highlight()


func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if get_tree().paused or not GameState.running:
		input = Vector2.ZERO
	var direction := (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := float(_cfg.speed)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and GameState.running:
			velocity.y = float(_cfg.jump_velocity)
	else:
		velocity += get_gravity() * delta

	var was_on_floor := is_on_floor()
	var start := global_transform
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	move_and_slide()
	if was_on_floor and horizontal.length() > 0.001:
		_try_step(start, horizontal)


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


func _ray(length: float, mask: int) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [get_rid()] if _held == null else [get_rid(), _held.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _grab() -> void:
	var sock := aimed_sock()
	if sock:
		_take(sock)


func _take(sock: Sock) -> void:
	_held = sock
	_inspect_spin = Vector2.ZERO
	_field.begin_hold(sock)
	Events.sock_grabbed.emit(sock.sock_id)


func _drop() -> void:
	var sock := _held
	release_held()
	_field.end_hold(sock)


func _throw() -> void:
	var sock := _held
	var throw_velocity := -camera.global_basis.z * float(_cfg.throw_speed) + velocity
	_held = null
	_field.throw_sock(sock, throw_velocity)
	GameState.register_throw(sock.sock_id)


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


## Only the sock under the crosshair glows, so it is clear which one a click takes.
func _update_highlight() -> void:
	if _field == null or _field.renderer == null:
		return
	var sock := aimed_sock()
	_field.renderer.set_highlight(sock.sock_id if sock else -1)


## Debug cheat: typing the code from data/gameplay.json toggles cheat mode.
func _track_cheat_code(keycode: Key) -> void:
	var code := String(Config.gameplay.get("cheat_code", "")).to_upper()
	if code.is_empty():
		return
	_typed = (_typed + OS.get_keycode_string(keycode).to_upper()).right(code.length())
	if _typed == code:
		_typed = ""
		GameState.cheat_mode = not GameState.cheat_mode
		if not GameState.cheat_mode and _field and _field.renderer:
			_field.renderer.set_partner_highlight(-1)


## Cheat only: right-click on a sock lights up its partner; on nothing clears it.
func _show_partner() -> void:
	if _field == null or _field.renderer == null or _field.socks == null:
		return
	var sock := aimed_sock()
	_field.renderer.set_partner_highlight(_field.socks.partner_of(sock.sock_id) if sock else -1)


func _check_summit(delta: float) -> void:
	if _summit_done or _field == null or not GameState.running or not is_on_floor():
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
	if _pending_held >= 0 and _field and _field.has_method("sock_by_id"):
		var sock: Sock = _field.call("sock_by_id", _pending_held)
		if sock:
			sock.global_position = camera.global_position - camera.global_basis.z * float(_cfg.hold_distance)
			_take(sock)
	_pending_held = -1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
