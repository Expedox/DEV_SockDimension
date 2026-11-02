class_name SockRenderer
extends MultiMeshInstance3D
## Draws every sock through one MultiMesh. Physics bodies have no mesh of their own;
## they push their transform here, and only while they are awake.

const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)


## Call once per game. All socks start hidden. bounds must enclose the room, it
## replaces the bounding box that would otherwise be recomputed on every change.
func setup(sock_set: SockSet, bounds: AABB) -> void:
	var count := sock_set.sock_count()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = SockMesh.get_mesh()
	mm.custom_aabb = bounds
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, HIDDEN)
		mm.set_instance_custom_data(i, sock_set.custom_data(i))
	SockMesh.get_material()
	multimesh = mm


func set_sock_transform(sock: int, xform: Transform3D) -> void:
	multimesh.set_instance_transform(sock, xform)


## For socks that left the pile (matched, in the basket).
func hide_sock(sock: int) -> void:
	multimesh.set_instance_transform(sock, HIDDEN)


## World-space read back, used by saving and by anything that needs a sock without a body.
func get_sock_transform(sock: int) -> Transform3D:
	return multimesh.get_instance_transform(sock)
