class_name SockRenderer
extends Node3D
## Draws every sock. Per sock shape there are two MultiMeshes: a cheap one for the whole
## pile and a detailed one with a few slots for socks close to the camera. The renderer
## moves socks between them by itself, so callers only ever use sock ids (SockSet indices).
## Physics bodies have no mesh of their own; they push their transform here, and only
## while they are awake.

const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
const FAR_AWAY := Vector3(1e9, 1e9, 1e9)
const SCAN_PER_FRAME := 1500 # socks checked for near/far per frame

var _far: Array[MultiMesh] = []
var _near: Array[MultiMesh] = []
var _shape_of := PackedInt32Array() # per sock
var _slot_of := PackedInt32Array() # per sock: instance index in its shape's far MultiMesh
var _near_slot := PackedInt32Array() # per sock: slot in the near MultiMesh, or -1
var _positions := PackedVector3Array() # per sock, last pushed origin
var _hidden := PackedByteArray() # per sock
var _free_near: Array[PackedInt32Array] = [] # per shape: unused near slots
var _near_socks := PackedInt32Array() # socks currently drawn detailed
var _scan := 0
var _highlighted := -1
var _partner := -1 # cheat glow, independent of the crosshair one
var _sock_set: SockSet
var _radius := 2.0


## Call once per game. All socks start hidden. bounds must enclose the room, it
## replaces the bounding box that would otherwise be recomputed on every change.
func setup(sock_set: SockSet, bounds: AABB, shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON) -> void:
	for child in get_children():
		child.queue_free()
	_far.clear()
	_sock_set = sock_set
	_highlighted = -1
	_partner = -1
	_near.clear()
	_free_near.clear()
	_near_socks.clear()
	var values := SockCatalog.mesh_values()
	_radius = float(values["detail_radius"])
	var capacity := int(values["detail_capacity"])

	var count := sock_set.sock_count()
	_shape_of.resize(count)
	_slot_of.resize(count)
	_near_slot.resize(count)
	_near_slot.fill(-1)
	_positions.resize(count)
	_positions.fill(FAR_AWAY)
	_hidden.resize(count)
	_hidden.fill(1)
	var per_shape := PackedInt32Array()
	per_shape.resize(SockCatalog.shape_count())
	for sock in count:
		var shape := sock_set.shape_of(sock)
		_shape_of[sock] = shape
		_slot_of[sock] = per_shape[shape]
		per_shape[shape] += 1

	for shape in per_shape.size():
		_far.append(_add_layer(shape, false, per_shape[shape], bounds, shadows))
		var near_count := mini(capacity, per_shape[shape])
		_near.append(_add_layer(shape, true, near_count, bounds, shadows))
		var slots := PackedInt32Array()
		for i in range(near_count - 1, -1, -1):
			slots.append(i)
		_free_near.append(slots)

	for sock in count:
		var data := sock_set.custom_data(sock)
		_far[_shape_of[sock]].set_instance_custom_data(_slot_of[sock], data)


func _add_layer(shape: int, detailed: bool, count: int, bounds: AABB,
		shadows: GeometryInstance3D.ShadowCastingSetting) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = SockMesh.get_mesh(shape, detailed)
	mm.custom_aabb = bounds
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, HIDDEN)
	SockMesh.get_material(shape)
	var instance := MultiMeshInstance3D.new()
	instance.name = SockCatalog.shape_id(shape).capitalize() + (" Near" if detailed else "")
	instance.multimesh = mm
	instance.cast_shadow = shadows
	add_child(instance)
	return mm


func set_sock_transform(sock: int, xform: Transform3D) -> void:
	_positions[sock] = xform.origin
	_hidden[sock] = 0
	var near := _near_slot[sock]
	if near >= 0:
		_near[_shape_of[sock]].set_instance_transform(near, xform)
	else:
		_far[_shape_of[sock]].set_instance_transform(_slot_of[sock], xform)


## Makes one sock glow (the one under the crosshair); -1 clears it. Only one at a time.
## The flag lives in the custom data alpha (+2); far and near copies both get it.
func set_highlight(sock: int) -> void:
	if sock == _highlighted:
		return
	var old := _highlighted
	_highlighted = sock
	_refresh_glow(old)
	_refresh_glow(sock)


func highlighted() -> int:
	return _highlighted


## Cheat only: a second glow on the partner sock; -1 clears it.
func set_partner_highlight(sock: int) -> void:
	if sock == _partner:
		return
	var old := _partner
	_partner = sock
	_refresh_glow(old)
	_refresh_glow(sock)


func partner_highlighted() -> int:
	return _partner


func _refresh_glow(sock: int) -> void:
	if sock < 0:
		return
	var data := _sock_set.custom_data(sock)
	if sock == _highlighted or sock == _partner:
		data.a += 2.0
	_far[_shape_of[sock]].set_instance_custom_data(_slot_of[sock], data)
	var near := _near_slot[sock]
	if near >= 0:
		_near[_shape_of[sock]].set_instance_custom_data(near, data)


## For socks that left the pile (matched, in the basket).
func hide_sock(sock: int) -> void:
	if sock == _highlighted:
		set_highlight(-1)
	if sock == _partner:
		set_partner_highlight(-1)
	_set_far(sock)
	_far[_shape_of[sock]].set_instance_transform(_slot_of[sock], HIDDEN)
	_hidden[sock] = 1
	_positions[sock] = FAR_AWAY


## World-space read back, used by saving and by anything that needs a sock without a body.
func get_sock_transform(sock: int) -> Transform3D:
	var near := _near_slot[sock]
	if near >= 0:
		return _near[_shape_of[sock]].get_instance_transform(near)
	return _far[_shape_of[sock]].get_instance_transform(_slot_of[sock])


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or _positions.is_empty():
		return
	var eye := camera.global_position
	var near_sq := _radius * _radius
	var far_sq := near_sq * 1.3 # a little slack, so socks at the edge do not flicker

	# Drop socks that moved out of range.
	for i in range(_near_socks.size() - 1, -1, -1):
		var sock := _near_socks[i]
		if _positions[sock].distance_squared_to(eye) > far_sq:
			_set_far(sock)

	# Look at a slice of the pile each frame and promote what is close.
	var count := _positions.size()
	for n in mini(SCAN_PER_FRAME, count):
		var sock := _scan
		_scan = (_scan + 1) % count
		if _near_slot[sock] < 0 and _hidden[sock] == 0 \
				and _positions[sock].distance_squared_to(eye) < near_sq:
			_set_near(sock)


func _set_near(sock: int) -> void:
	var shape := _shape_of[sock]
	var slots := _free_near[shape]
	if slots.is_empty():
		return
	var slot := slots[slots.size() - 1]
	slots.remove_at(slots.size() - 1)
	_free_near[shape] = slots
	var far := _far[shape]
	var near := _near[shape]
	near.set_instance_custom_data(slot, far.get_instance_custom_data(_slot_of[sock]))
	near.set_instance_transform(slot, far.get_instance_transform(_slot_of[sock]))
	far.set_instance_transform(_slot_of[sock], HIDDEN)
	_near_slot[sock] = slot
	_near_socks.append(sock)


func _set_far(sock: int) -> void:
	var slot := _near_slot[sock]
	if slot < 0:
		return
	var shape := _shape_of[sock]
	var near := _near[shape]
	_far[shape].set_instance_transform(_slot_of[sock], near.get_instance_transform(slot))
	near.set_instance_transform(slot, HIDDEN)
	var slots := _free_near[shape]
	slots.append(slot)
	_free_near[shape] = slots
	_near_slot[sock] = -1
	var index := _near_socks.find(sock)
	if index >= 0:
		_near_socks.remove_at(index)
