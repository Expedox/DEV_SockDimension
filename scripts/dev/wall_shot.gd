extends Node3D
## Hangs a share of a mode's pairs on the sock wall and takes screenshots:
##   xvfb-run godot --rendering-driver opengl3 --path . res://scenes/dev/wall_shot.tscn -- <mode> <share> <out_prefix>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Config.use_mode_room(args[0])
	var pairs := int(Config.mode(args[0]).pairs)
	var share := float(args[1])
	var prefix := args[2]
	var cellar: Cellar = load("res://scenes/cellar.tscn").instantiate()
	add_child(cellar)
	var sock_set := SockSet.generate(42, pairs, 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var found := PackedInt32Array()
	for pair in pairs:
		if rng.randf() < share:
			found.append(pair)
	var wall := SockWall.new()
	add_child(wall)
	wall.setup(sock_set, Config.world["pair_wall"], found, cellar.room_bounds())
	print("pairs %d, found %d, scale %.3f" % [pairs, found.size(), wall.sock_scale])

	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	var half := Cellar.vec3(Config.world.room_size) * 0.5
	var shots := [
		[Vector3(-half.x * 0.3, 2.0, -half.z * 0.4), Vector3(half.x, 3.0, half.z * 0.3), "room"],
		[Vector3(half.x - 2.5, 1.7, -2.0), Vector3(half.x, 1.4, -3.5), "close"],
	]
	for shot: Array in shots:
		camera.position = shot[0]
		camera.look_at(shot[1])
		for i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, shot[2]])
	get_tree().quit()
