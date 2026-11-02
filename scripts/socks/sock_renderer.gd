class_name SockRenderer
extends Node3D
## Draws every sock. One MultiMesh per sock shape, so three draw calls for the whole pile.
## Physics bodies have no mesh of their own; they push their transform here, and only
## while they are awake. Callers only ever use sock ids (SockSet indices).

const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _layers: Array[MultiMesh] = []
var _layer_of := PackedInt32Array() # per sock: shape
var _slot_of := PackedInt32Array() # per sock: instance index inside its shape's MultiMesh


## Call once per game. All socks start hidden. bounds must enclose the room, it
## replaces the bounding box that would otherwise be recomputed on every change.
func setup(sock_set: SockSet, bounds: AABB, shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON) -> void:
	for child in get_children():
		child.queue_free()
	_layers.clear()
	var count := sock_set.sock_count()
	_layer_of.resize(count)
	_slot_of.resize(count)
	var per_shape := PackedInt32Array()
	per_shape.resize(SockCatalog.shape_count())
	for sock in count:
		var shape := sock_set.shape_of(sock)
		_layer_of[sock] = shape
		_slot_of[sock] = per_shape[shape]
		per_shape[shape] += 1

	for shape in per_shape.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = SockMesh.get_mesh(shape)
		mm.custom_aabb = bounds
		mm.instance_count = per_shape[shape]
		SockMesh.get_material(shape)
		var instance := MultiMeshInstance3D.new()
		instance.name = SockCatalog.shape_id(shape).capitalize()
		instance.multimesh = mm
		instance.cast_shadow = shadows
		add_child(instance)
		_layers.append(mm)

	for sock in count:
		var mm := _layers[_layer_of[sock]]
		mm.set_instance_transform(_slot_of[sock], HIDDEN)
		mm.set_instance_custom_data(_slot_of[sock], sock_set.custom_data(sock))


func set_sock_transform(sock: int, xform: Transform3D) -> void:
	_layers[_layer_of[sock]].set_instance_transform(_slot_of[sock], xform)


## For socks that left the pile (matched, in the basket).
func hide_sock(sock: int) -> void:
	set_sock_transform(sock, HIDDEN)


## World-space read back, used by saving and by anything that needs a sock without a body.
func get_sock_transform(sock: int) -> Transform3D:
	return _layers[_layer_of[sock]].get_instance_transform(_slot_of[sock])
