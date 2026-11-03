class_name SockField
extends Node3D
## Owns every sock body and the SockRenderer that draws them.
## Bodies sleep almost all the time; only awake ones push their transform to
## the renderer. With freeze_settled (data/physics.json) a sleeping sock is also
## frozen, so a small disturbance cannot wake the whole pile at once; moving
## socks wake their neighbours instead. See NOTES.md, Interfaces and Measurement.

const SOCK_LAYER := 2
const SOCK_MASK := 1 | 2
const WORLD_LAYER := 1

enum State { IDLE, POURING, SETTLING, RESTORING, READY }

var renderer: SockRenderer
var socks: SockSet
var state := State.IDLE
## Seconds from pour() until the pile was ready, for the debug overlay.
var pour_seconds := 0.0
## Time the field's own frame work took, for the debug overlay.
var script_usec := 0
## Awake socks that actually move, as reported through Events.socks_moving.
var moving_count := 0

var _tuning: Dictionary
var _bodies: Array[Sock] = []
var _awake := {} # sock_id -> Sock
var _aside := {} # sock_id -> Transform3D at the moment it left the pile
var _flights := {} # sock_id -> [start: Vector3, seconds: float]
var _shapes: Array[Shape3D] = []
var _shape_xform := Transform3D.IDENTITY
var _material: PhysicsMaterial
var _rng := RandomNumberGenerator.new()
var _lumps := FastNoiseLite.new()
var _freeze_settled := true
var _to_freeze: Array[Sock] = []
var _chain := PackedVector3Array() # spots around fast socks to wake next step
var _still := PackedFloat32Array() # seconds each sock has barely moved

var _radius := 3.0
var _next := 0 # next sock to spawn
var _frame := 0
var _started_msec := 0
var _settle_seconds := 0.0
var _top := 0.0
var _reported_done := -1
var _reported_moving := 0
var _restore_data: Dictionary
var _ghosts := {} # sock_id -> held Sock that still passes through other socks
var _carried := {} # sock_id -> true, held in the player's bundle: always a ghost
var _skip := {} # sock_id -> true, left out of the current pour
var _raining := false # pour_rest() on a field that is already in play

var _summit := Vector3.ZERO
var _scan_best := Vector3(0.0, -INF, 0.0)
var _scan_index := 0


func _ready() -> void:
	add_to_group("sock_field")
	_tuning = Config.physics
	_freeze_settled = bool(_tuning.freeze_settled)
	_material = PhysicsMaterial.new()
	_material.friction = float(_tuning.sock_friction)
	_material.bounce = float(_tuning.sock_bounce)
	_material.rough = true
	renderer = SockRenderer.new()
	renderer.name = "SockRenderer"
	add_child(renderer)


func _exit_tree() -> void:
	# Set-aside bodies live outside the tree until remove_pair().
	for sock in _bodies:
		if sock != null and not sock.is_inside_tree():
			sock.free()


## Fresh pile: drops all socks in waves until everything sleeps.
func pour(sock_set: SockSet, mode: Dictionary) -> void:
	_begin(sock_set)
	_skip = {}
	_radius = float(mode.get("pile_radius", 3.0))
	_rng.seed = sock_set.seed_value
	_lumps.seed = sock_set.seed_value
	_lumps.frequency = float(_tuning.pour_lump_frequency)
	state = State.POURING
	Events.pile_progress.emit(0, socks.sock_count())


## Starts a run with only these socks (sock_id -> Transform3D) in the room;
## the rest comes later with pour_rest(). Emits pile_ready right away.
func prepare(sock_set: SockSet, placements: Dictionary) -> void:
	_begin(sock_set)
	_skip = {}
	for sock_id: int in placements:
		_spawn(sock_id, placements[sock_id], Vector3.ZERO, false)
	state = State.READY
	pour_seconds = 0.0
	Events.pile_ready.emit()


## Pours every sock that is not in play yet into a field that is already
## running (the rift). skip holds sock ids to leave out, such as found pairs.
## Emits Events.rain_finished instead of pile_ready when done.
func pour_rest(mode: Dictionary, skip: Dictionary) -> void:
	_skip = skip.duplicate()
	for sock_id in _bodies.size():
		if _bodies[sock_id] != null:
			_skip[sock_id] = true
	_radius = float(mode.get("pile_radius", 3.0))
	_rng.seed = socks.seed_value
	_next = 0
	_frame = 0
	_top = 0.0
	_settle_seconds = 0.0
	_reported_done = -1
	_started_msec = Time.get_ticks_msec()
	_raining = true
	state = State.POURING
	_skip_reserved()


## Saved pile: every sock comes back asleep where it was. state comes from capture().
func restore(sock_set: SockSet, saved: Dictionary) -> void:
	if not saved.has("ids"):
		push_warning("No sock positions saved, pouring a fresh pile")
		pour(sock_set, Config.mode(GameState.mode_id))
		return
	_begin(sock_set)
	_restore_data = saved
	state = State.RESTORING
	Events.pile_progress.emit(0, (saved.ids as PackedInt32Array).size())


## Binary friendly snapshot of every sock still in play. Socks in their flight
## to the basket count as in play. Empty while pouring.
func capture() -> Dictionary:
	if state != State.READY:
		return {}
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	var rotations := PackedFloat32Array()
	for sock in _bodies:
		if sock == null:
			continue
		var xform: Transform3D = _aside.get(sock.sock_id, sock.global_transform)
		var q := xform.basis.get_rotation_quaternion()
		ids.append(sock.sock_id)
		positions.append(xform.origin)
		rotations.append_array([q.x, q.y, q.z, q.w])
	return {"ids": ids, "positions": positions, "rotations": rotations}


func sock_at(collider: Object) -> Sock:
	var sock := collider as Sock
	if sock == null or sock.field != self or _aside.has(sock.sock_id):
		return null
	return sock


func sock_by_id(sock_id: int) -> Sock:
	if sock_id < 0 or sock_id >= _bodies.size() or _aside.has(sock_id):
		return null
	return _bodies[sock_id]


## The held sock floats; the player moves it through its velocity.
func begin_hold(sock: Sock) -> void:
	_flights.erase(sock.sock_id)
	sock.gravity_scale = 0.0
	sock.can_sleep = false
	# Off every layer: nothing (above all the player) bumps into it, while its
	# own mask still lets it push other socks around.
	sock.collision_layer = 0
	# Pass through other socks until it is out of the pile, or the pile
	# wedges it in place.
	sock.collision_mask = WORLD_LAYER
	_ghosts[sock.sock_id] = sock
	_carried.erase(sock.sock_id)
	_wake(sock)
	wake_around(sock.global_position, float(_tuning.wake_radius))


## A held sock tucked into the player's bundle. It stays a ghost, so an armful
## of socks never ploughs through the pile while walking over it.
func carry(sock: Sock) -> void:
	if not _ghosts.has(sock.sock_id):
		begin_hold(sock)
	sock.collision_mask = WORLD_LAYER
	_ghosts[sock.sock_id] = sock
	_carried[sock.sock_id] = true


func end_hold(sock: Sock) -> void:
	sock.gravity_scale = 1.0
	sock.collision_layer = SOCK_LAYER
	sock.collision_mask = SOCK_MASK
	_ghosts.erase(sock.sock_id)
	_carried.erase(sock.sock_id)
	sock.can_sleep = true


func throw_sock(sock: Sock, velocity: Vector3) -> void:
	end_hold(sock)
	sock.linear_velocity = velocity
	_flights[sock.sock_id] = [sock.global_position, 0.0]


func wake_around(position: Vector3, radius: float) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = SOCK_LAYER
	for hit in get_world_3d().direct_space_state.intersect_shape(query, int(_tuning.wake_max_socks)):
		var sock := sock_at(hit.collider)
		if sock != null:
			_wake(sock)


## Takes a matched sock out of the physics world. It stays in capture() until
## remove_pair(), and its drawing belongs to whoever animates it now.
func set_aside(sock: Sock) -> void:
	if _aside.has(sock.sock_id):
		return
	var xform := sock.global_transform
	_aside[sock.sock_id] = xform
	_awake.erase(sock.sock_id)
	_flights.erase(sock.sock_id)
	remove_child(sock)
	wake_around(xform.origin, float(_tuning.wake_radius))


## Removes both socks for good and lets the pile settle where they were.
func remove_pair(a: Sock, b: Sock) -> void:
	for sock in [a, b]:
		if sock == null or _bodies[sock.sock_id] != sock:
			continue
		# Aside socks are out of the tree, so do not touch their global transform.
		var at: Vector3 = _aside[sock.sock_id].origin if _aside.has(sock.sock_id) else sock.global_position
		_bodies[sock.sock_id] = null
		_aside.erase(sock.sock_id)
		_awake.erase(sock.sock_id)
		_flights.erase(sock.sock_id)
		renderer.hide_sock(sock.sock_id)
		if sock.is_inside_tree():
			sock.queue_free()
		else:
			sock.free()
		wake_around(at, float(_tuning.wake_radius))


## Highest resting sock of the pile, refreshed over a few frames.
func surface_height() -> Vector3:
	return _summit


func awake_count() -> int:
	return _awake.size()


func body_count() -> int:
	return _bodies.size() - _bodies.count(null) - _aside.size()


func is_ready() -> bool:
	return state == State.READY


func _begin(sock_set: SockSet) -> void:
	socks = sock_set
	var count := socks.sock_count()
	var room := Cellar.vec3(Config.world.room_size)
	renderer.setup(socks, AABB(Vector3(-room.x * 0.5, -1.0, -room.z * 0.5), room + Vector3(0, 2, 0)))
	_bodies.resize(count)
	_bodies.fill(null)
	_still.resize(count)
	_still.fill(0.0)
	_shapes.clear()
	var capsule := String(_tuning.sock_shape) == "capsule"
	_shape_xform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO) if capsule else Transform3D.IDENTITY
	for shape in SockCatalog.shape_count():
		var size := SockMesh.collision_size(shape)
		if capsule:
			# Rounded socks slide off each other and settle into a cone; flat
			# boxes stack like bricks into a drum with straight walls.
			var round := CapsuleShape3D.new()
			round.radius = size.y * 0.5 * float(_tuning.capsule_thickness_scale)
			round.height = maxf(size.z, round.radius * 2.0)
			_shapes.append(round)
		else:
			var box := BoxShape3D.new()
			box.size = size
			_shapes.append(box)
	_next = 0
	_frame = 0
	_top = 0.0
	_settle_seconds = 0.0
	_reported_done = -1
	_started_msec = Time.get_ticks_msec()


func _physics_process(delta: float) -> void:
	_freeze_sleepers()
	_solidify_ghosts()
	# Also while pouring: landing socks must shake the top loose, or frozen
	# socks build straight walls instead of a slope.
	if state != State.RESTORING:
		_wake_chain()
	match state:
		State.POURING:
			_frame += 1
			# Waves wait while too much is still tumbling; that bounds the step cost.
			if _frame % int(_tuning.wave_interval_frames) == 0 \
					and _awake.size() < int(_tuning.pour_max_awake):
				_pour_wave()
			if _next >= socks.sock_count():
				state = State.SETTLING
		State.SETTLING:
			_settle_seconds += delta
			if _awake.size() <= _ghosts.size() or _settle_seconds >= float(_tuning.settle_timeout_seconds):
				_finish()
		State.RESTORING:
			_restore_batch()
		State.READY:
			_track_flights(delta)


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_push_awake(delta)
	_scan_summit()
	script_usec = Time.get_ticks_usec() - started
	match state:
		State.POURING, State.SETTLING:
			var done := _next - _awake.size()
			if done > _reported_done:
				_reported_done = done
				Events.pile_progress.emit(done, socks.sock_count())
		State.READY:
			var moving := moving_count
			if absi(moving - _reported_moving) >= int(_tuning.moving_report_step) \
					or (moving == 0 and _reported_moving != 0):
				_reported_moving = moving
				Events.socks_moving.emit(moving)


## Drops a wave just above the current top, more of it near the centre, so the
## socks heap up into a cone instead of spreading into a flat layer.
func _pour_wave() -> void:
	var count := mini(int(_tuning.wave_size), socks.sock_count() - _next)
	var spacing := float(_tuning.pour_spacing)
	var layer_height := float(_tuning.pour_layer_height)
	var layers := int(_tuning.pour_layers)
	var spout := _radius * float(_tuning.pour_spout_share)
	var height := minf(_top + float(_tuning.pour_gap), float(_tuning.pour_max_height))
	var tilt := deg_to_rad(float(_tuning.pour_tilt_deg))
	var cone_power := float(_tuning.pour_cone_power)
	var lumpiness := float(_tuning.pour_lumpiness)
	var taken := {}
	var placed := 0
	for attempt in count * 8:
		_skip_reserved()
		if placed >= count or _next >= socks.sock_count():
			break
		# Even spread over the disc, thinned out towards the rim: the column at
		# each spot grows in proportion to the cone height there.
		var angle := _rng.randf() * TAU
		var spot := Vector2(cos(angle), sin(angle)) * spout * sqrt(_rng.randf())
		# Fixed noise over the floor makes some spots grow faster: humps,
		# ridges and dips instead of a smooth cone.
		var lump := 1.0 + lumpiness * _lumps.get_noise_2dv(spot)
		if _rng.randf() > pow(maxf(1.0 - spot.length() / spout, 0.0), cone_power) * lump:
			continue
		var layer := _rng.randi_range(0, layers - 1)
		var cell := Vector3i(floori(spot.x / spacing), layer, floori(spot.y / spacing))
		if taken.has(cell):
			continue
		taken[cell] = true
		var basis := Basis(Vector3.UP, _rng.randf() * TAU)
		basis = basis * Basis(Vector3.RIGHT, _rng.randf_range(-tilt, tilt))
		basis = basis * Basis(Vector3.FORWARD, _rng.randf_range(-tilt, tilt))
		if _rng.randf() < 0.5:
			basis = basis * Basis(Vector3.FORWARD, PI)
		var origin := Vector3(spot.x, height + layer * layer_height, spot.y)
		_spawn(_next, Transform3D(basis, origin), Vector3.DOWN * float(_tuning.pour_speed), false)
		_next += 1
		placed += 1
	_skip_reserved()


func _skip_reserved() -> void:
	while _next < socks.sock_count() and _skip.has(_next):
		_next += 1


func _restore_batch() -> void:
	var ids: PackedInt32Array = _restore_data.ids
	var positions: PackedVector3Array = _restore_data.positions
	var rotations: PackedFloat32Array = _restore_data.rotations
	var end := mini(_next + int(_tuning.restore_batch), ids.size())
	for i in range(_next, end):
		var q := Quaternion(rotations[i * 4], rotations[i * 4 + 1], rotations[i * 4 + 2], rotations[i * 4 + 3])
		_spawn(ids[i], Transform3D(Basis(q.normalized()), positions[i]), Vector3.ZERO, true)
	_next = end
	Events.pile_progress.emit(_next, ids.size())
	if _next >= ids.size():
		_restore_data = {}
		_finish()


func _spawn(sock_id: int, xform: Transform3D, velocity: Vector3, asleep: bool) -> void:
	var sock := Sock.new()
	sock.sock_id = sock_id
	sock.field = self
	sock.name = "Sock%d" % sock_id
	sock.mass = float(_tuning.sock_mass)
	sock.physics_material_override = _material
	sock.linear_damp = float(_tuning.sock_linear_damp)
	sock.angular_damp = float(_tuning.sock_angular_damp)
	sock.can_sleep = true
	sock.collision_layer = SOCK_LAYER
	sock.collision_mask = SOCK_MASK
	sock.transform = xform
	sock.linear_velocity = velocity
	sock.sleeping = asleep
	sock.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	sock.freeze = asleep and _freeze_settled
	var owner_id := sock.create_shape_owner(sock)
	sock.shape_owner_add_shape(owner_id, _shapes[socks.shape_of(sock_id)])
	sock.shape_owner_set_transform(owner_id, _shape_xform)
	_bodies[sock_id] = sock
	add_child(sock)
	renderer.set_sock_transform(sock_id, xform)
	if not asleep:
		_awake[sock_id] = sock


func _finish() -> void:
	# A sock in the player's hand (possible while the rift pours) stays awake.
	var held := {}
	for sock: Sock in _awake.values():
		if _ghosts.has(sock.sock_id):
			held[sock.sock_id] = sock
			continue
		sock.sleeping = true
		sock.freeze = _freeze_settled
		_lift_out_of_floor(sock)
		renderer.set_sock_transform(sock.sock_id, sock.global_transform)
	_awake = held
	_to_freeze.clear()
	state = State.READY
	_skip = {}
	pour_seconds = (Time.get_ticks_msec() - _started_msec) / 1000.0
	_reported_moving = 0
	if _raining:
		_raining = false
		Events.rain_finished.emit()
	else:
		Events.pile_ready.emit()


func _wake(sock: Sock) -> void:
	sock.freeze = false
	sock.sleeping = false
	_awake[sock.sock_id] = sock


func _on_sock_sleep_changed(sock: Sock) -> void:
	if _aside.has(sock.sock_id):
		return
	if sock.sleeping:
		renderer.set_sock_transform(sock.sock_id, sock.global_transform)
		_awake.erase(sock.sock_id)
		if _freeze_settled:
			_to_freeze.append(sock)
	else:
		_awake[sock.sock_id] = sock


func _push_awake(delta: float) -> void:
	var fall_limit := float(_tuning.fall_limit_y)
	var rest_speed := float(_tuning.rest_speed)
	var rest_seconds := float(_tuning.rest_seconds)
	var resting: Array[Sock] = []
	var moving_speed := float(_tuning.moving_speed)
	var chain_speed := float(_tuning.chain_wake_speed)
	var chain_max := int(_tuning.chain_wake_per_frame)
	var moving := 0
	for sock: Sock in _awake.values():
		var xform := sock.global_transform
		if xform.origin.y < fall_limit:
			_rescue(sock)
			continue
		renderer.set_sock_transform(sock.sock_id, xform)
		var speed := sock.linear_velocity.length()
		if speed > moving_speed:
			moving += 1
			if _freeze_settled and speed > chain_speed and _chain.size() < chain_max:
				_chain.append(xform.origin)
		elif xform.origin.y > _top:
			_top = xform.origin.y
		# Our own sleep check: Jolt only sleeps whole touching groups, which in a
		# pile means everything at once or nothing.
		if _freeze_settled and speed < rest_speed and sock.can_sleep \
				and sock.angular_velocity.length() < rest_speed * 4.0:
			_still[sock.sock_id] += delta
			if _still[sock.sock_id] >= rest_seconds:
				resting.append(sock)
		else:
			_still[sock.sock_id] = 0.0
	moving_count = moving
	for sock in resting:
		_still[sock.sock_id] = 0.0
		_awake.erase(sock.sock_id)
		sock.sleeping = true
		sock.freeze = true
		_lift_out_of_floor(sock)


## Frozen socks do not feel a push, so fast socks wake what lies around them.
func _wake_chain() -> void:
	var radius := float(_tuning.chain_wake_radius)
	for spot in _chain:
		wake_around(spot, radius)
	_chain.clear()


## Under the weight of the pile the solver lets bottom socks sink a little into
## the floor. Once a sock rests, put it back on top of the floor.
func _lift_out_of_floor(sock: Sock) -> void:
	var shape := _shapes[socks.shape_of(sock.sock_id)]
	var half := (shape as BoxShape3D).size * 0.5 if shape is BoxShape3D else Vector3.ONE * (shape as CapsuleShape3D).radius
	var basis := (sock.global_transform * _shape_xform).basis
	var reach := absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
	var bottom := sock.global_position.y - reach
	if bottom < 0.0:
		sock.global_position.y -= bottom
		renderer.set_sock_transform(sock.sock_id, sock.global_transform)


## A held sock gets its sock collisions back once nothing overlaps it.
func _solidify_ghosts() -> void:
	if _ghosts.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = SOCK_LAYER
	query.margin = float(_tuning.ghost_margin)
	for sock_id: int in _ghosts.keys():
		var sock: Sock = _ghosts[sock_id]
		if not is_instance_valid(sock) or not sock.is_inside_tree():
			_ghosts.erase(sock_id)
			_carried.erase(sock_id)
			continue
		if _carried.has(sock_id):
			continue
		query.shape = _shapes[socks.shape_of(sock_id)]
		query.transform = sock.global_transform * _shape_xform
		query.exclude = [sock.get_rid()]
		if space.intersect_shape(query, 1).is_empty():
			sock.collision_mask = SOCK_MASK
			_ghosts.erase(sock_id)


func _freeze_sleepers() -> void:
	for sock in _to_freeze:
		if is_instance_valid(sock) and sock.is_inside_tree() and sock.sleeping and sock.can_sleep:
			sock.freeze = true
			_lift_out_of_floor(sock)
	_to_freeze.clear()


## A sock that slipped through the floor drops back onto the pile.
func _rescue(sock: Sock) -> void:
	sock.global_position = Vector3(0.0, _summit.y + float(_tuning.pour_gap), 0.0)
	sock.linear_velocity = Vector3.ZERO
	sock.angular_velocity = Vector3.ZERO


func _track_flights(delta: float) -> void:
	for sock_id: int in _flights.keys():
		var sock := _bodies[sock_id]
		if sock == null or not sock.is_inside_tree():
			_flights.erase(sock_id)
			continue
		var flight: Array = _flights[sock_id]
		flight[1] += delta
		if flight[1] < float(_tuning.land_min_seconds):
			continue
		if sock.sleeping or sock.linear_velocity.length() < float(_tuning.land_speed):
			var start: Vector3 = flight[0]
			var end := sock.global_position
			_flights.erase(sock_id)
			Events.sock_landed.emit(sock_id, Vector2(end.x - start.x, end.z - start.z).length())


func _scan_summit() -> void:
	var end := mini(_scan_index + int(_tuning.summit_scan_per_frame), _bodies.size())
	for i in range(_scan_index, end):
		var sock := _bodies[i]
		# Only resting socks: a held or flying sock is not part of the hill.
		if sock != null and sock.sleeping and not _aside.has(i):
			var at := sock.global_position
			if at.y > _scan_best.y:
				_scan_best = at
	_scan_index = end
	if _scan_index >= _bodies.size():
		if _scan_best.y > -INF:
			_summit = _scan_best
		_scan_best = Vector3(0.0, -INF, 0.0)
		_scan_index = 0
