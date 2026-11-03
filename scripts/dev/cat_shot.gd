extends Node
## Starts a laundry day run, makes the cellar cat go for a sock right away and
## takes screenshots (on a small pile) of it napping, being petted, carrying and back home:
##   xvfb-run godot --rendering-driver opengl3 --fixed-fps 60 --path . res://scenes/dev/cat_shot.tscn -- <out_prefix>

var _prefix := "user://cat"


func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene != self:
		return
	var keeper := Node.new()
	keeper.set_script(get_script())
	keeper.set_meta("keeper", true)
	get_tree().root.add_child.call_deferred(keeper)
	Settings.show_intro = false
	GameState.start_new.call_deferred("laundry_day", "7")
	# A small pile is enough to watch the cat, and renders fast in software.
	(func() -> void: GameState.pairs_total = 80).call_deferred()


func _enter_tree() -> void:
	if not has_meta("keeper"):
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	Events.rain_finished.connect(_run, CONNECT_ONE_SHOT)
	Events.pile_ready.connect(func() -> void: GameState.world_provider.blast.start(), CONNECT_ONE_SHOT)


func _run() -> void:
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var cat: CellarCat = GameState.world_provider.cat
	var camera := Camera3D.new()
	camera.fov = 50.0
	get_tree().root.add_child(camera)
	camera.current = true
	await get_tree().create_timer(2.0).timeout
	await _shot(camera, cat, "nap", Vector3(0.9, 0.6, -0.9))
	cat.pet()
	await get_tree().create_timer(1.2).timeout
	await _shot(camera, cat, "pet", Vector3(0.9, 0.6, -0.9))
	print("CAT petted, achievement ", Achievements.is_unlocked("ACH_PET_CAT"))
	await get_tree().create_timer(2.0).timeout
	cat._steal_in = 0.0
	var waited := 0.0
	while not cat.is_carrying() and waited < 90.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	print("CAT carrying=%s after %.1f s at %s" % [cat.is_carrying(), waited, cat.global_position])
	await get_tree().create_timer(1.5).timeout
	await _shot(camera, cat, "carry", Vector3(1.0, 0.7, -0.8))
	waited = 0.0
	while cat.is_carrying() and waited < 90.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	print("CAT dropped after %.1f s at %s" % [waited, cat.global_position])
	await get_tree().create_timer(1.0).timeout
	await _shot(camera, cat, "drop", Vector3(1.2, 0.9, 1.2))
	get_tree().quit()


func _shot(camera: Camera3D, cat: Node3D, label: String, offset: Vector3) -> void:
	var focus := cat.global_position + Vector3.UP * 0.2
	camera.global_position = focus + offset
	camera.look_at(focus)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_prefix, label])
	print("CAT shot ", label)
