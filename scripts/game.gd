extends Node3D
## Builds one run: cellar, sock field, player, pair logic and the UI scenes.
## UI scenes that do not exist yet are skipped.

const CELLAR_SCENE := "res://scenes/cellar.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const FIELD_SCRIPT := "res://scripts/physics/sock_field.gd"
const INTRO_SCENE := "res://scenes/ui/intro.tscn"
const TUTORIAL_SCENE := "res://scenes/ui/tutorial.tscn"
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
var rift: Rift

## False until the rest of the pile came through the rift.
var _rain_done := true
## Rift waits for the tutorial instead of a short timer.
var _wait_for_lesson := false
var _rift_started := false
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

	rift = Rift.new()
	rift.name = "Rift"
	add_child(rift)
	rift.position = Cellar.vec3(Config.world.get("rift", {}).get("position", [0.0, 5.6, 0.0]))
	rift.opened.connect(_on_rift_opened)

	# Story and first steps on a fresh pile, once, until switched on again in Settings.
	# The rift opens when the tutorial is through.
	if not world.has("socks") and Settings.show_intro:
		Settings.set_value("show_intro", false)
		Settings.save()
		_wait_for_lesson = true
		var intro: Node = (load(INTRO_SCENE) as PackedScene).instantiate()
		intro.finished.connect(_start_tutorial)
		add_child(intro)

	Events.pile_ready.connect(_on_pile_ready)
	Events.rain_finished.connect(_on_rain_finished)
	GameState.world_provider = self
	_build_pile.call_deferred(world)


## Mid-rain the field has no stable snapshot: socks stays empty and the rain
## starts over from the starter pairs on load.
func capture_world() -> Dictionary:
	return {"socks": field.capture(), "player": player.capture(), "rain_done": _rain_done}


func _build_pile(world: Dictionary) -> void:
	_rain_done = bool(world.get("rain_done", true))
	var saved: Dictionary = world.get("socks", {})
	if world.has("socks") and (_rain_done or saved.has("ids")):
		field.restore(socks, saved)
	else:
		# New run: only the starter pairs; the rest rains in through the rift.
		_rain_done = false
		field.prepare(socks, _starter_placements())


func _start_tutorial() -> void:
	var tutorial: Node = (load(TUTORIAL_SCENE) as PackedScene).instantiate()
	tutorial.lesson_done.connect(_open_rift)
	add_child(tutorial)


func _open_rift() -> void:
	if _rift_started or _rain_done:
		return
	_rift_started = true
	rift.open()


func _on_rift_opened() -> void:
	var skip := {}
	var found := {}
	for pair in GameState.found_pair_ids:
		found[pair] = true
	for sock_id in socks.sock_count():
		if found.has(socks.pair_of(sock_id)):
			skip[sock_id] = true
	field.pour_rest(Config.mode(GameState.mode_id), skip)


func _on_rain_finished() -> void:
	_rain_done = true
	rift.close()
	SaveManager.save_current.call_deferred()


## A few whole pairs laid side by side on the washing machine, so the first
## match is right there. Count in data/gameplay.json.
func _starter_placements() -> Dictionary:
	var wanted := mini(int(Config.gameplay.get("starter_pairs", 3)), socks.pair_count)
	var pair_ids: Array[int] = []
	for pair in socks.pair_count:
		if pair_ids.size() >= wanted:
			break
		if socks.near_of[pair] == -1 and not pair in GameState.found_pair_ids:
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


func _on_pile_ready() -> void:
	GameState.pending_world = {}
	GameState.running = not GameState.completed
	Events.run_started.emit(GameState.mode_id)
	if _rain_done:
		rift.show_scar()
	elif not _wait_for_lesson:
		get_tree().create_timer(float(Config.world.get("rift", {}).get("delay_seconds", 3.0))).timeout.connect(_open_rift)


func _exit_tree() -> void:
	if GameState.world_provider == self:
		GameState.world_provider = null
		GameState.running = false
