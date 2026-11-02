extends Node3D
## Builds one run: cellar, sock field, player, pair logic and the UI scenes.
## UI scenes that do not exist yet are skipped.

const CELLAR_SCENE := "res://scenes/cellar.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const FIELD_SCRIPT := "res://scripts/physics/sock_field.gd"
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

	for path: String in UI_SCENES:
		if ResourceLoader.exists(path):
			add_child((load(path) as PackedScene).instantiate())

	Events.pile_ready.connect(_on_pile_ready)
	GameState.world_provider = self
	_build_pile.call_deferred(world)


func capture_world() -> Dictionary:
	return {"socks": field.capture(), "player": player.capture()}


func _build_pile(world: Dictionary) -> void:
	if world.has("socks"):
		field.restore(socks, world.socks)
	else:
		field.pour(socks, Config.mode(GameState.mode_id))


func _on_pile_ready() -> void:
	GameState.pending_world = {}
	GameState.running = not GameState.completed
	Events.run_started.emit(GameState.mode_id)


func _exit_tree() -> void:
	if GameState.world_provider == self:
		GameState.world_provider = null
		GameState.running = false
