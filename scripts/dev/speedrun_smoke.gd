extends Node
## Headless speedrun check. Matches every pair by hand once the clock runs.
##   godot --headless --path . res://scenes/dev/speedrun_smoke.tscn -- solo
## Versus on one machine: start "-- host" and "-- join" side by side; the host
## starts a versus run as soon as the other one is connected. The joiner waits
## a little before matching so the host wins.

var _role := "solo"


func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene != self:
		return
	var keeper := Node.new()
	keeper.set_script(get_script())
	keeper.set_meta("keeper", true)
	get_tree().root.add_child.call_deferred(keeper)
	var args := OS.get_cmdline_user_args()
	_role = args[0] if args.size() > 0 else "solo"
	match _role:
		"solo":
			GameState.start_speedrun.call_deferred("speedrun_50")
		"host":
			Net.host()
		"join":
			Net.join("127.0.0.1")


func _enter_tree() -> void:
	if not has_meta("keeper"):
		return
	var args := OS.get_cmdline_user_args()
	_role = args[0] if args.size() > 0 else "solo"
	Events.run_started.connect(_on_started)
	Events.run_finished.connect(_on_finished)
	Net.versus_rival_done.connect(func() -> void:
		print("SPEEDRUN %s rival done: time %.2f gave_up %s" % [_role, Net.versus_rival_time, Net.versus_rival_gave_up]))
	if _role == "host":
		Net.rival_joined.connect(func() -> void: Net.start_versus.call_deferred("speedrun_50"))
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("SPEEDRUN %s timeout" % _role)
		get_tree().quit(1))


func _on_started(mode_id: String) -> void:
	print("SPEEDRUN %s go: %s versus %s seed %d" % [_role, mode_id, GameState.versus, GameState.seed_value])
	if _role == "join":
		await get_tree().create_timer(2.0).timeout
	var game: Node = GameState.world_provider
	for pair in game.socks.pair_count:
		await get_tree().physics_frame
		GameState.register_match(pair, game.socks.base_color_of(pair * 2) if game.socks.has_method("base_color_of") else 0, 0)


func _on_finished(_mode_id: String) -> void:
	await get_tree().create_timer(1.0, true).timeout
	print("SPEEDRUN %s finished: %.2f s, rank %d, saved slot file %s, best %.2f" % [_role, GameState.play_time,
			GameState.speedrun_rank, SaveManager.has_save(0), SpeedrunScores.best(50)])
	if GameState.versus:
		print("SPEEDRUN %s won %s" % [_role, SpeedrunHud.won_versus()])
		await get_tree().create_timer(4.0, true).timeout
		print("SPEEDRUN %s after wait: rival time %.2f, won %s" % [_role, Net.versus_rival_time, SpeedrunHud.won_versus()])
	get_tree().quit()
