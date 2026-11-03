extends Node3D
## Drops a few socks, some upside down, on the bare floor and takes a low
## screenshot, to see whether any cloth sinks into the floor:
##   xvfb-run godot --rendering-driver opengl3 --path . res://scenes/dev/floor_shot.tscn -- out.png

func _ready() -> void:
	add_child(load("res://scenes/cellar.tscn").instantiate())
	var field := SockField.new()
	add_child(field)
	var sock_set := SockSet.generate(3, 8, 0.0)
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	var rotations := PackedFloat32Array()
	for i in sock_set.sock_count():
		var basis := Basis(Vector3.UP, i * 0.8)
		if i % 2 == 1:
			basis = basis * Basis(Vector3.FORWARD, PI)
		var q := basis.get_rotation_quaternion()
		ids.append(i)
		positions.append(Vector3((i % 4) * 0.45 - 0.7, 0.3, (i / 4) * 0.5 - 0.25))
		rotations.append_array([q.x, q.y, q.z, q.w])
	field.restore(sock_set, {"ids": ids, "positions": positions, "rotations": rotations})
	await Events.pile_ready
	for i in sock_set.sock_count():
		field.wake_around(Vector3.ZERO, 3.0) # let them fall onto the floor
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 0.35, 1.3)
	camera.look_at(Vector3(0.0, 0.0, 0.0))
	camera.current = true
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
