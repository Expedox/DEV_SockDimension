class_name AchievementService
extends Node
## Local achievements and lifetime stats, shared by all saves. Listens to Events
## and GameState; the conditions live here and the numbers in
## data/achievements.json. Storefronts hook in via AchievementPlatform.

signal progress_changed(id: String, current: int, target: int)

const DATA_PATH := "res://data/achievements.json"
const SAVE_PATH := "user://achievements.save"
const SAVE_VERSION := 1
const COMPLETIONIST_ID := "ACH_COMPLETIONIST"

var params: Dictionary = {}
## Tests point this somewhere else before calling load_state().
var save_path := SAVE_PATH

var _definitions: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _unlocked: Dictionary = {} # id -> unix time
var _stats: Dictionary = {}
var _run: Dictionary = {"colors": {}, "patterns": {}} # what the current game has found
var _platform := AchievementPlatform.new()
var _toast: AchievementToast
var _dirty := false
var _dirty_seconds := 0.0
var _thrown_sock := -1 # last thrown sock that nobody has touched since


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_definitions()
	load_state()
	_merge_platform_unlocks()
	_evaluate_stats()
	_toast = AchievementToast.new()
	add_child(_toast)
	Events.pair_matched.connect(_on_pair_matched)
	Events.pair_mismatched.connect(_on_pair_mismatched)
	Events.run_finished.connect(_on_run_finished)
	Events.sock_grabbed.connect(_on_sock_grabbed)
	Events.sock_thrown.connect(_on_sock_thrown)
	Events.sock_landed.connect(_on_sock_landed)
	Events.sock_in_basket.connect(_on_sock_in_basket)
	Events.socks_moving.connect(_on_socks_moving)
	Events.summit_reached.connect(_on_summit_reached)
	Events.game_saved.connect(flush)


func _process(delta: float) -> void:
	_platform.poll()
	if GameState.session_time >= float(params.get("marathon_seconds", 7200)):
		unlock("ACH_MARATHON")
	if _dirty:
		_dirty_seconds += delta
		if _dirty_seconds >= float(params.get("save_interval_seconds", 30)):
			flush()


func _exit_tree() -> void:
	flush()


# --- Queries ---

## All definitions in display order. Keys: id, name, description, hidden, target.
func get_definitions() -> Array[Dictionary]:
	return _definitions


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func get_progress(id: String) -> int:
	var definition: Dictionary = _by_id.get(id, {})
	if definition.is_empty():
		return 0
	var target := int(definition.target)
	if _unlocked.has(id):
		return target
	if definition.stat == "":
		return 0
	return mini(int(_stats.get(definition.stat, 0)), target)


func get_unlocked_count() -> int:
	return _unlocked.size()


func get_total_count() -> int:
	return _definitions.size()


## Whole percent, rounded down so 100 means everything is done.
func get_percent() -> int:
	if _definitions.is_empty():
		return 0
	return _unlocked.size() * 100 / _definitions.size()


func get_stat(key: String) -> int:
	return int(_stats.get(key, 0))


# --- Game events ---

func _on_pair_matched(_pair_id: int, base_color: int, pattern_type: int) -> void:
	_thrown_sock = -1
	_stats.pairs_total = get_stat("pairs_total") + 1
	_stats.best_streak = maxi(get_stat("best_streak"), GameState.streak)
	_mark_dirty()
	_evaluate_stats()

	var total: int = GameState.pairs_total
	var halfway := float(params.get("halfway_fraction", 0.5))
	if total > 0 and float(GameState.pairs_found) / total >= halfway:
		unlock("ACH_HALFWAY")
	if is_night_owl_hour(int(Time.get_time_dict_from_system().hour)):
		unlock("ACH_NIGHT_OWL")

	# Colors and patterns count per game; another game (or a fresh one) starts over.
	var run_key := "%s:%d" % [GameState.mode_id, GameState.seed_value]
	if GameState.pairs_found <= 1 or _run.get("key", "") != run_key:
		_run = {"key": run_key, "colors": {}, "patterns": {}}
	_run.colors[base_color] = true
	# Pattern Master counts the regular patterns; rare designs have their own.
	if pattern_type >= 0 and pattern_type < SockCatalog.pattern_count() and SockCatalog.is_special(pattern_type):
		unlock("ACH_LUCKY_SOCK")
	else:
		_run.patterns[pattern_type] = true
	if _run.colors.size() >= SockCatalog.palette_size():
		unlock("ACH_RAINBOW")
	if _run.patterns.size() >= SockCatalog.regular_pattern_count():
		unlock("ACH_PATTERNS")


func _on_pair_mismatched(near_miss: bool) -> void:
	if near_miss:
		_stats.near_misses = get_stat("near_misses") + 1
		_mark_dirty()
		_evaluate_stats()


func _on_run_finished(mode_id: String) -> void:
	unlock("ACH_%s" % mode_id.to_upper())
	if GameState.mistakes == 0:
		unlock("ACH_FLAWLESS")
	var fast_limit := float(params.get("fast_laundry_seconds", 10800))
	if mode_id == "laundry_day" and GameState.play_time < fast_limit:
		unlock("ACH_FAST_LAUNDRY")
	_mark_dirty()
	flush()


func _on_sock_grabbed(sock_id: int) -> void:
	if sock_id == _thrown_sock:
		_thrown_sock = -1


func _on_sock_thrown(sock_id: int) -> void:
	_thrown_sock = sock_id


## distance runs from where the sock left the hand to where it came to rest.
func _on_sock_landed(_sock_id: int, distance: float) -> void:
	if distance >= float(params.get("yeet_distance_m", 20.0)):
		unlock("ACH_YEET")


func _on_sock_in_basket(sock_id: int) -> void:
	if sock_id == _thrown_sock:
		unlock("ACH_TRICK_SHOT")


func _on_socks_moving(count: int) -> void:
	if GameState.running and count >= int(params.get("avalanche_socks", 100)):
		unlock("ACH_AVALANCHE")


func _on_summit_reached() -> void:
	unlock("ACH_KING_OF_THE_HILL")


func is_night_owl_hour(hour: int) -> bool:
	return hour >= int(params.get("night_owl_start_hour", 0)) \
			and hour < int(params.get("night_owl_end_hour", 4))


func unlock(id: String) -> void:
	if _unlocked.has(id) or not _by_id.has(id):
		return
	_unlocked[id] = int(Time.get_unix_time_from_system())
	var target := int(_by_id[id].target)
	_platform.set_progress(id, target, target)
	_platform.unlock(id)
	_platform.store()
	progress_changed.emit(id, target, target)
	Events.achievement_unlocked.emit(id)
	if _toast != null:
		_toast.enqueue(_by_id[id].name, _by_id[id].description)
	_mark_dirty()
	flush()
	_check_completionist()


# --- Data and persistence ---

func load_definitions() -> void:
	_definitions.clear()
	_by_id.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("Could not read %s" % DATA_PATH)
		return
	params = parsed.get("params", {})
	for entry: Dictionary in parsed.get("achievements", []):
		var id := String(entry.get("id", ""))
		if id == "" or _by_id.has(id):
			push_error("Bad or duplicate achievement id '%s'" % id)
			continue
		var definition := {
			"id": id,
			"name": String(entry.get("name", id)),
			"description": String(entry.get("description", "")),
			"hidden": bool(entry.get("hidden", false)),
			"target": maxi(int(entry.get("target", 1)), 1),
			"stat": String(entry.get("stat", "")),
		}
		_definitions.append(definition)
		_by_id[id] = definition


func load_state() -> void:
	_unlocked = {}
	_stats = {}
	_run = {"colors": {}, "patterns": {}}
	var result := SafeFile.read(save_path)
	if result.is_empty() or result.version != SAVE_VERSION or not result.data is Dictionary:
		return
	_unlocked = result.data.get("unlocked", {})
	_stats = result.data.get("stats", {})
	_run = result.data.get("run", _run)


## Writes pending changes now. Pair counts wait for the next interval.
func flush() -> void:
	if not _dirty:
		return
	var data := {"unlocked": _unlocked, "stats": _stats, "run": _run}
	if not SafeFile.write(save_path, SAVE_VERSION, data):
		push_warning("Could not write achievements to %s" % save_path)
		return
	_dirty = false
	_dirty_seconds = 0.0


func _mark_dirty() -> void:
	_dirty = true


func _merge_platform_unlocks() -> void:
	for id: String in _platform.get_unlocked_ids():
		if _by_id.has(id) and not _unlocked.has(id):
			_unlocked[id] = int(Time.get_unix_time_from_system())
			_mark_dirty()


func _evaluate_stats() -> void:
	for definition: Dictionary in _definitions:
		if definition.stat == "" or _unlocked.has(definition.id):
			continue
		var id: String = definition.id
		var current := get_progress(id)
		var target: int = definition.target
		if current >= target:
			unlock(id)
		elif current > 0:
			_platform.set_progress(id, current, target)
			progress_changed.emit(id, current, target)


func _check_completionist() -> void:
	for definition: Dictionary in _definitions:
		if definition.id != COMPLETIONIST_ID and not _unlocked.has(definition.id):
			return
	unlock(COMPLETIONIST_ID)
