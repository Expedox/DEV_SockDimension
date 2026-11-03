extends Node
## Starts a real laundry day run headless, sets off the washer right away and
## quits once the scattered socks have settled:
##   godot --headless --path . res://scenes/dev/smoke_run.tscn
## With a window and "-- <mode> <png path>" it also saves a screenshot from the spawn point.

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene != self:
		return
	# Survive the scene change by moving under the root as a plain node.
	var keeper := Node.new()
	keeper.set_script(get_script())
	keeper.set_meta("keeper", true)
	get_tree().root.add_child.call_deferred(keeper)
	var args := OS.get_cmdline_user_args()
	Settings.show_intro = false
	GameState.start_new.call_deferred(args[0] if args.size() > 0 else "laundry_day", "7")


func _enter_tree() -> void:
	if not has_meta("keeper"):
		return
	Events.rain_finished.connect(_on_ready_pile)
	Events.pile_ready.connect(func() -> void: GameState.world_provider.blast.start(), CONNECT_ONE_SHOT)


func _on_ready_pile() -> void:
	await get_tree().create_timer(1.0).timeout
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and DisplayServer.get_name() != "headless":
		for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[1])
		print("SMOKE screenshot ", args[1])
	var field := get_tree().get_first_node_in_group("sock_field") as SockField
	print("SMOKE ready: %d socks, pour %.1f s, summit %s, saved %d" % [field.body_count(),
			field.pour_seconds, field.surface_height(), field.capture().ids.size()])
	get_tree().quit()
