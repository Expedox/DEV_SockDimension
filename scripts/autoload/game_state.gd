extends Node
## State of the current run: counters, scene changes, save payload.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var mode_id := ""
## Save slot this run writes to, from 1.
var slot := 1
var seed_value := 0
var pairs_total := 0
var pairs_found := 0
var play_time := 0.0
var session_time := 0.0
var mistakes := 0
var throws := 0
var completed := false
var streak := 0
var near_misses := 0
var cat_steals := 0
var cat_catches := 0
var found_pair_ids := PackedInt32Array()
## Abilities unlocked this run by golden and silver socks ("sprint", "zoom"). Saved, reset by New Game.
var abilities := PackedStringArray()

## Sock and player state to restore; empty for a fresh pile.
var pending_world: Dictionary = {}
## Node providing capture_world() -> Dictionary while a run is live.
var world_provider: Object = null
## True while the clock runs (pile ready, run not finished).
var running := false
## Debug cheat (typed code from data/gameplay.json): the partner of the held or aimed sock glows. Never saved.
var cheat_mode := false


func _process(delta: float) -> void:
	if running and not get_tree().paused:
		play_time += delta
		session_time += delta


## Starts a fresh pile in a save slot. An empty seed text picks a random seed.
func start_new(new_mode: String, seed_text := "", new_slot := 1) -> void:
	_reset(new_mode)
	Achievements.on_new_game()
	slot = new_slot
	seed_value = _seed_from_text(seed_text)
	pending_world = {}
	get_tree().change_scene_to_file(GAME_SCENE)


## Restores a run from a dictionary built by capture() and opens the game.
func start_loaded(data: Dictionary, from_slot := 1) -> void:
	_reset(data.mode)
	slot = from_slot
	seed_value = data.seed
	play_time = data.play_time
	mistakes = data.mistakes
	throws = data.throws
	completed = data.completed
	streak = data.get("streak", 0)
	near_misses = data.get("near_misses", 0)
	cat_steals = data.get("cat_steals", 0)
	cat_catches = data.get("cat_catches", 0)
	found_pair_ids = data.found
	abilities = PackedStringArray(data.get("abilities", PackedStringArray()))
	pairs_found = found_pair_ids.size()
	pending_world = data.world
	Achievements.restore_run(data.get("achievements", {}))
	get_tree().change_scene_to_file(GAME_SCENE)


## Everything a save file holds. See NOTES.md, section Interfaces.
func capture() -> Dictionary:
	return {
		"mode": mode_id,
		"seed": seed_value,
		"play_time": play_time,
		"mistakes": mistakes,
		"throws": throws,
		"completed": completed,
		"streak": streak,
		"near_misses": near_misses,
		"cat_steals": cat_steals,
		"cat_catches": cat_catches,
		"found": found_pair_ids,
		"abilities": abilities,
		"world": world_provider.capture_world() if world_provider else {},
		"achievements": Achievements.capture_run(),
	}


func in_run() -> bool:
	return world_provider != null


func register_match(pair_id: int, base_color: int, pattern_type: int) -> void:
	found_pair_ids.append(pair_id)
	pairs_found += 1
	streak += 1
	Events.pair_matched.emit(pair_id, base_color, pattern_type)
	unlock_ability(SockCatalog.unlock_of(pattern_type))
	if pairs_found >= pairs_total:
		finish()


func has_ability(ability: String) -> bool:
	return abilities.has(ability)


func unlock_ability(ability: String) -> void:
	if ability.is_empty() or abilities.has(ability):
		return
	abilities.append(ability)
	Events.ability_unlocked.emit(ability)


func register_mismatch(near_miss: bool) -> void:
	mistakes += 1
	streak = 0
	if near_miss:
		near_misses += 1
	Events.pair_mismatched.emit(near_miss)


func register_throw(sock_id: int) -> void:
	throws += 1
	Events.sock_thrown.emit(sock_id)


func finish() -> void:
	completed = true
	running = false
	Events.run_finished.emit(mode_id)


func to_main_menu() -> void:
	running = false
	get_tree().paused = false
	world_provider = null
	get_tree().change_scene_to_file(MENU_SCENE)


func _reset(new_mode: String) -> void:
	mode_id = new_mode
	Config.use_mode_room(new_mode)
	pairs_total = int(Config.mode(new_mode).pairs)
	pairs_found = 0
	play_time = 0.0
	session_time = 0.0
	mistakes = 0
	throws = 0
	completed = false
	streak = 0
	near_misses = 0
	cat_steals = 0
	cat_catches = 0
	found_pair_ids = PackedInt32Array()
	abilities = PackedStringArray()
	running = false
	cheat_mode = false


func _seed_from_text(text: String) -> int:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return randi()
	return cleaned.to_int() if cleaned.is_valid_int() else cleaned.hash()
