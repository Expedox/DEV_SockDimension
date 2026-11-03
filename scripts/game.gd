extends Node3D
## Builds one run: cellar, sock field, player, pair logic and the UI scenes.
## UI scenes that do not exist yet are skipped.

const CELLAR_SCENE := "res://scenes/cellar.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const FIELD_SCRIPT := "res://scripts/physics/sock_field.gd"
const INTRO_SCENE := "res://scenes/ui/intro.tscn"
const TUTORIAL_SCENE := "res://scenes/ui/tutorial.tscn"
const TUNING_SCENE := "res://scenes/ui/washer_tuning.tscn"
const UI_SCENES := [
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/loading_screen.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/end_screen.tscn",
	"res://scenes/ui/debug_overlay.tscn",
]

var socks: SockSet
var cellar: Cellar
var field: SockField
var player: Player
var pairs: PairController
var blast: WasherBlast

## False until the washing machine burst and the rest of the socks settled.
var _rain_done := true
var _blast_started := false
## Pairs that start on the washer lid; finding all of them sets off the burst.
var _starter_pairs: Array[int] = []
var wall: SockWall


func _ready() -> void:
	var mode := Config.mode(GameState.mode_id)
	socks = SockSet.generate(GameState.seed_value, GameState.pairs_total, float(mode.near_pair_share))

	cellar = (load(CELLAR_SCENE) as PackedScene).instantiate()
	add_child(cellar)

	field = (load(FIELD_SCRIPT) as GDScript).new()
	field.name = "SockField"
	add_child(field)

	player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child(player)
	player.setup(field)
	player.place(cellar.player_spawn())
	var world: Dictionary = GameState.pending_world
	if world.has("player"):
		player.apply(world.player)

	pairs = PairController.new()
	pairs.name = "PairController"
	add_child(pairs)
	pairs.setup(player, field, cellar, socks)

	# Found pairs hang on the wall; rebuilt from the found list on load.
	wall = SockWall.new()
	wall.name = "SockWall"
	cellar.add_child(wall)
	wall.setup(socks, Config.world["pair_wall"], GameState.found_pair_ids, cellar.room_bounds())
	Events.pair_matched.connect(wall.on_pair_matched)

	for path: String in UI_SCENES:
		if ResourceLoader.exists(path):
			add_child((load(path) as PackedScene).instantiate())

	blast = WasherBlast.new()
	blast.name = "WasherBlast"
	add_child(blast)
	blast.global_transform = cellar.washer_top()
	load_burst_tuning()
	blast.setup(cellar.washer(), burst_tuning)
	blast.burst.connect(_on_washer_burst)

	# Story and first steps on a fresh pile, once, until switched on again in Settings.
	if not world.has("socks") and Settings.show_intro:
		Settings.set_value("show_intro", false)
		Settings.save()
		var intro: Node = (load(INTRO_SCENE) as PackedScene).instantiate()
		intro.finished.connect(_start_tutorial)
		add_child(intro)

	add_child((load(TUNING_SCENE) as PackedScene).instantiate())

	Events.pile_ready.connect(_on_pile_ready)
	Events.rain_finished.connect(_on_rain_finished)
	Events.pair_matched.connect(_on_pair_matched)
	Events.run_finished.connect(_on_run_finished)
	GameState.world_provider = self
	_pick_starter_pairs()
	_build_pile.call_deferred(world)


## Mid-burst the field has no stable snapshot: socks stays empty and the run
## starts over from the starter pairs on load.
func capture_world() -> Dictionary:
	return {"socks": field.capture(), "player": player.capture(), "rain_done": _rain_done}


func _build_pile(world: Dictionary) -> void:
	_rain_done = bool(world.get("rain_done", true))
	var saved: Dictionary = world.get("socks", {})
	if world.has("socks") and (_rain_done or saved.has("ids")):
		field.restore(socks, saved)
	else:
		# New run: only the starter pairs; the rest bursts out of the washer later.
		_rain_done = false
		field.prepare(socks, _starter_placements())


## The first few plain pairs of the set; the same for a seed every time.
func _pick_starter_pairs() -> void:
	var wanted := mini(int(Config.gameplay.get("starter_pairs", 3)), socks.pair_count)
	for pair in socks.pair_count:
		if _starter_pairs.size() >= wanted:
			break
		if socks.near_of[pair] == -1:
			_starter_pairs.append(pair)


func _start_tutorial() -> void:
	add_child((load(TUTORIAL_SCENE) as PackedScene).instantiate())


## Sets off the washer once every starter pair is found.
func _check_starters() -> void:
	if _blast_started or _rain_done:
		return
	for pair in _starter_pairs:
		if not pair in GameState.found_pair_ids:
			return
	_blast_started = true
	blast.start()


## Live washer settings: data/world.json -> washer_blast, overridden by
## the values saved from the F2 tuning panel.
var burst_tuning: Dictionary = {}
const TUNING_PATH := "user://washer_tuning.json"


func load_burst_tuning() -> void:
	# Cleared in place: the washer keeps a reference to this dictionary.
	burst_tuning.clear()
	burst_tuning.merge(Config.world.get("washer_blast", {}))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH)) if FileAccess.file_exists(TUNING_PATH) else null
	if saved is Dictionary:
		burst_tuning.merge(saved, true)


func save_burst_tuning() -> void:
	var file := FileAccess.open(TUNING_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(burst_tuning, "  "))


func reset_burst_tuning() -> void:
	if FileAccess.file_exists(TUNING_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TUNING_PATH))
	load_burst_tuning()


## Tuning tool: takes the socks back into the washer and lets it boil over again.
func retrigger_burst() -> void:
	if not field.is_ready() or (_blast_started and not _rain_done):
		return
	field.recall()
	_rain_done = false
	_blast_started = true
	blast.start()


func _on_washer_burst() -> void:
	var cfg := burst_tuning
	var room := cellar.room_bounds()
	var margin := float(cfg.get("wall_margin", 0.8))
	var top := cellar.washer_top()
	var lid := cellar.washer_lid()
	var front := top.basis.z
	# Socks gush out of the door like foam boiling over and spread in a fan in
	# front of the machine. Reach is a share of the room's diagonal.
	var door := top.origin + Vector3.DOWN * float(cfg.get("door_depth", 0.65)) \
			+ front * (lid.y * 0.5 + float(cfg.get("door_out", 0.45)))
	var diagonal := Vector2(room.size.x, room.size.z).length()
	var burst := {
		"origin": door,
		"area": room.grow(-margin),
		"direction": Vector3(front.x, 0.0, front.z).normalized(),
		"reach": diagonal * float(cfg.get("reach_share", 0.4)),
		"gap": float(cfg.get("gap", 0.5)),
		"spray_deg": float(cfg.get("spray_deg", 100.0)),
		"falloff": float(cfg.get("falloff", 1.5)),
		"chaos": float(cfg.get("chaos", 0.0)),
		"spin": float(cfg.get("spin", 0.0)),
		"wave_size": int(cfg.get("wave_size", 30)),
		"flight_min": float(cfg.get("flight_min", 0.6)),
		"flight_max": float(cfg.get("flight_max", 1.4)),
		"spawn_spread": float(cfg.get("spawn_spread", 0.15)),
	}
	var skip := {}
	var found := {}
	for pair in GameState.found_pair_ids:
		found[pair] = true
	for sock_id in socks.sock_count():
		if found.has(socks.pair_of(sock_id)):
			skip[sock_id] = true
	field.pour_rest(Config.mode(GameState.mode_id), skip, burst)


func _on_rain_finished() -> void:
	_rain_done = true
	blast.stop_foam()
	SaveManager.save_current.call_deferred()


## A few whole pairs laid side by side on the washing machine, so the first
## match is right there. Count in data/gameplay.json.
func _starter_placements() -> Dictionary:
	var pair_ids: Array[int] = []
	for pair in _starter_pairs:
		if not pair in GameState.found_pair_ids:
			pair_ids.append(pair)
	var by_pair := {}
	for sock_id in socks.sock_count():
		if socks.pair_of(sock_id) in pair_ids:
			by_pair.get_or_add(socks.pair_of(sock_id), []).append(sock_id)
	var lid := cellar.washer_lid()
	var top := cellar.washer_top()
	var strips := pair_ids.size() * 2
	var placements := {}
	var index := 0
	for pair: int in pair_ids:
		for sock_id: int in by_pair[pair]:
			var size := SockMesh.collision_size(socks.shape_of(sock_id))
			# Long side along the lid width.
			var turn := Basis.IDENTITY if size.x >= size.z else Basis(Vector3.UP, PI * 0.5)
			var z := (float(index) + 0.5) / strips * lid.y - lid.y * 0.5
			var local := Transform3D(turn, Vector3(0.0, size.y * 0.5 + 0.01, z))
			placements[sock_id] = top * local
			index += 1
	return placements


func _on_pair_matched(_pair_id: int, _color: int, _pattern: int) -> void:
	_check_starters()


## Every pair found: the washer is fixed and the wall lights up.
func _on_run_finished(_mode_id: String) -> void:
	blast.repair()
	wall.light_up(true)


func _on_pile_ready() -> void:
	GameState.pending_world = {}
	GameState.running = not GameState.completed
	Events.run_started.emit(GameState.mode_id)
	_check_starters()
	# Broken washer smokes from the burst until the last pair; a finished run
	# shows the lit wall.
	blast.set_smoking(_rain_done and not GameState.completed)
	if GameState.completed:
		wall.light_up(false)


func _exit_tree() -> void:
	if GameState.world_provider == self:
		GameState.world_provider = null
		GameState.running = false
