extends Node3D
## Hangs a share of a mode's pairs on the sock wall and takes screenshots:
##   xvfb-run godot --rendering-driver opengl3 --path . res://scenes/dev/wall_shot.tscn -- <pairs> <share> <out_prefix>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var pairs := int(args[0])
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
	var shots := [
		[Vector3(-1.0, 2.2, -3.0), Vector3(9.0, 2.6, 2.0), "east"],
		[Vector3(-2.0, 2.2, -4.0), Vector3(4.0, 2.4, 7.0), "south"],
		[Vector3(7.0, 1.6, -3.0), Vector3(9.0, 1.3, -4.5), "close"],
	]
	for shot: Array in shots:
		camera.position = shot[0]
		camera.look_at(shot[1])
		for i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, shot[2]])
	get_tree().quit()
