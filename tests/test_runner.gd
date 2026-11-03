extends Node
## Headless checks for saving, pairs and achievements. Run with
## godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 means everything passed. Writes only under user://tests/.

const Fakes := preload("res://tests/fakes.gd")
const TEST_DIR := "user://tests/"
const SCRIPT_DIRS := ["res://scripts/", "res://tests/"]

var _failures := 0
var _checks := 0


func _ready() -> void:
	_clean(TEST_DIR)
	SaveManager.save_dir = TEST_DIR + "saves/"
	Achievements.save_path = TEST_DIR + "achievements.save"
	SpeedrunScores.save_path = TEST_DIR + "speedrun.save"
	Achievements.load_state()

	_test_scripts_parse()
	_test_translations()
	_test_safe_file()
	_test_save_manager()
	_test_game_state_counters()
	_test_achievements()
	_test_socks()
	_test_speedrun()
	_test_sock_wall()
	_test_daylight()
	_test_drop_scatter()
	await _test_lost_found()
	await _test_firm_hand()
	await _test_hitboxes()
	await _test_unsnag()
	await _test_pair_controller()

	print("%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Every mode that can still be started, plus the retired big one for old saves.
func _room_modes() -> Array:
	var out := ["sock_dimension"]
	for mode: Dictionary in Config.story_modes() + Config.speedrun_modes():
		out.append(mode.id)
	return out


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)


func _test_scripts_parse() -> void:
	for dir_path: String in SCRIPT_DIRS:
		for path in _scripts_under(dir_path):
			var script := load(path) as GDScript
			check(script != null and script.can_instantiate(), "script parses: " + path)


## Every English text has a German one with the same placeholders.
func _test_translations() -> void:
	var en := _read_text_csv("res://i18n/game_text.csv")
	var de := _read_text_csv("res://i18n/game_text_de.csv")
	check(en.size() > 100, "english texts load")
	for key: String in en:
		check(de.has(key) and not String(de[key]).is_empty(), "german text for " + key)
		if de.has(key):
			check(_placeholders(en[key]) == _placeholders(de[key]), "same placeholders in " + key)
	for key: String in de:
		check(en.has(key), "german key also in english: " + key)
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	check(tr("MENU_NEW_GAME") == "Neues Spiel", "german locale translates")
	TranslationServer.set_locale("en")
	check(tr("MENU_NEW_GAME") == "New Game", "english locale translates")
	TranslationServer.set_locale(before)


func _read_text_csv(path: String) -> Dictionary:
	var out := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2 and not row[0].is_empty():
			out[row[0]] = row[1]
	return out


func _placeholders(text: String) -> Array:
	var regex := RegEx.create_from_string("\\{[a-z_]+\\}")
	var found := []
	for m in regex.search_all(text):
		found.append(m.get_string())
	found.sort()
	return found


func _test_safe_file() -> void:
	var path := TEST_DIR + "safe/one.save"
	check(SafeFile.read(path).is_empty(), "missing file reads as empty")
	check(SafeFile.write(path, 3, {"a": 1, "list": PackedInt32Array([4, 5])}), "first write")
	var first := SafeFile.read(path)
	check(first.get("version") == 3, "version comes back")
	check(first.get("data", {}).get("list") == PackedInt32Array([4, 5]), "packed array survives")
	check(first.get("from_backup") == false, "main file used")

	check(SafeFile.write(path, 3, {"a": 2}), "second write")
	check(FileAccess.file_exists(path + ".bak"), "old file kept as .bak")
	check(not FileAccess.file_exists(path + ".tmp"), "no .tmp left behind")

	# Cut the main file short: the end marker is gone, so the backup is used.
	var bytes := FileAccess.get_file_as_bytes(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes.slice(0, bytes.size() - 6))
	file.close()
	check(not SafeFile.read(path).is_empty(), "truncated file falls back")
	check(SafeFile.read(path).get("from_backup") == true, "fallback is flagged")
	check(SafeFile.read(path).get("data", {}).get("a") == 1, "fallback holds the previous data")

	SafeFile.remove(path)
	check(not SafeFile.exists(path), "remove deletes file and backup")


func _test_save_manager() -> void:
	_start_fake_run("laundry_day", 3)
	GameState.slot = 2
	check(SaveManager.slot_count() == 3, "three save slots")
	check(not SaveManager.has_any_save(), "no save before saving")
	GameState.running = false
	check(not SaveManager.save_current(), "no save while the pile is pouring")
	GameState.running = true

	GameState.play_time = 42.5
	GameState.mistakes = 2
	GameState.found_pair_ids = PackedInt32Array([7])
	GameState.pairs_found = 1
	check(SaveManager.save_current(), "save_current writes")
	check(SaveManager.has_save(2) and not SaveManager.has_save(1), "save lands in the run's slot")
	check(SaveManager.latest_slot() == 2, "latest_slot finds the run")
	check(SaveManager.free_slot() == 1, "free_slot skips taken slots")

	var info := SaveManager.slot_info(2)
	check(info.get("mode") == "laundry_day", "slot_info mode")
	check(info.get("pairs_found") == 1, "slot_info pairs")
	check(is_equal_approx(float(info.get("play_time", 0.0)), 42.5), "slot_info time")
	check(info.get("completed") == false, "slot_info not completed")
	check(int(info.get("saved_at", 0)) > 0, "slot_info saved_at")

	var data := SaveManager._load(2)
	check(data.get("mistakes") == 2, "mistakes round trip")
	check(data.get("found") == PackedInt32Array([7]), "found ids round trip")
	check(data.get("world", {}).get("socks", {}).get("ids") == PackedInt32Array([1, 2]), "world round trip")

	GameState.completed = true
	GameState.running = false
	check(SaveManager.save_current(), "a finished run still saves")
	check(SaveManager.latest_slot() == 0, "finished runs are not continued")
	check(not SaveManager.continue_run(2), "continue refuses a finished run")
	SaveManager.delete_slot(2)
	check(not SaveManager.has_any_save(), "delete_slot empties the slot")
	_end_fake_run()

	# Saves of older builds were named after their mode; newest goes to slot 1.
	var old := {"mode": "laundry_day", "seed": 1, "play_time": 1.0, "mistakes": 0, "throws": 0,
		"completed": false, "found": PackedInt32Array(), "world": {}, "saved_at": 100}
	SafeFile.write(SaveManager.save_dir + "laundry_day.save", 1, old)
	var newer := old.duplicate()
	newer.mode = "sock_dimension"
	newer.saved_at = 200
	SafeFile.write(SaveManager.save_dir + "sock_dimension.save", 1, newer)
	check(SaveManager.migrate_legacy_saves() == 2, "both old saves migrate")
	check(SaveManager.slot_info(1).get("mode") == "sock_dimension", "newest old save is slot 1")
	check(SaveManager.slot_info(2).get("mode") == "laundry_day", "older old save is slot 2")
	check(not FileAccess.file_exists(SaveManager.save_dir + "laundry_day.save"), "old file is moved aside")
	check(SaveManager.migrate_legacy_saves() == 0, "migration runs once")
	SaveManager.delete_slot(1)
	SaveManager.delete_slot(2)


func _test_game_state_counters() -> void:
	_start_fake_run("laundry_day", 2)
	var finished := [false]
	var on_finish := func(_mode: String) -> void: finished[0] = true
	Events.run_finished.connect(on_finish)

	GameState.register_mismatch(true)
	check(GameState.mistakes == 1 and GameState.near_misses == 1 and GameState.streak == 0, "mismatch counters")
	GameState.register_throw(5)
	check(GameState.throws == 1, "throw counter")
	GameState.cat_steals = 3
	GameState.cat_catches = 1
	var cat_saved := GameState.capture()
	check(cat_saved.cat_steals == 3 and cat_saved.cat_catches == 1, "cat counters go into the save")
	GameState.register_match(0, 1, 1)
	check(GameState.pairs_found == 1 and GameState.streak == 1, "match counters")
	check(not finished[0], "not finished after one of two")
	var unlocked := []
	var on_unlock := func(ability: String) -> void: unlocked.append(ability)
	Events.ability_unlocked.connect(on_unlock)
	check(not GameState.has_ability("sprint") and not GameState.has_ability("zoom"), "no sprint or zoom at the start")
	GameState.register_match(1, 2, SockCatalog.pattern_index("gold"))
	check(GameState.has_ability("sprint") and unlocked == ["sprint"], "golden pair unlocks sprint")
	check(Array(GameState.capture().abilities) == ["sprint"], "unlocks go into the save")
	GameState.unlock_ability("sprint")
	check(unlocked.size() == 1, "sprint unlocks only once")
	Events.ability_unlocked.disconnect(on_unlock)
	check(finished[0] and GameState.completed and not GameState.running, "finishes on the last pair")
	Events.run_finished.disconnect(on_finish)
	_end_fake_run()

	_start_fake_run("laundry_day", 2)
	check(GameState.abilities.is_empty(), "a new run starts without unlocks")
	GameState.register_match(0, 1, SockCatalog.pattern_index("silver"))
	check(GameState.has_ability("zoom") and not GameState.has_ability("sprint"), "silver pair unlocks zoom")
	_end_fake_run()


func _test_achievements() -> void:
	Achievements.save_path = TEST_DIR + "achievements2.save"
	Achievements.load_state()
	check(Achievements.get_unlocked_count() == 0, "fresh achievement state")
	check(Achievements.get_total_count() == 22, "twenty-two achievements defined")

	_start_fake_run("sock_dimension", 10)
	GameState.register_match(0, 0, 0)
	check(Achievements.is_unlocked("ACH_FIRST_PAIR"), "first pair unlocks")
	check(Achievements.get_progress("ACH_PAIRS_100") == 1, "pair counter progresses")
	check(not Achievements.is_unlocked("ACH_HALFWAY"), "not halfway after 1 of 10")
	for i in 4:
		GameState.register_match(i + 1, 0, 0)
	check(Achievements.is_unlocked("ACH_HALFWAY"), "halfway after 5 of 10")
	check(not Achievements.is_unlocked("ACH_LUCKY_SOCK"), "no lucky sock from regular pairs")
	GameState.register_match(6, 0, SockCatalog.special_patterns()[0])
	check(Achievements.is_unlocked("ACH_LUCKY_SOCK"), "a special pair unlocks lucky sock")

	check(Achievements.is_night_owl_hour(0) and Achievements.is_night_owl_hour(3), "night owl hours")
	check(not Achievements.is_night_owl_hour(4) and not Achievements.is_night_owl_hour(23), "outside night owl")

	for i in 10:
		GameState.register_mismatch(true)
	check(Achievements.is_unlocked("ACH_NEAR_MISS"), "ten near misses")

	check(not Achievements.is_unlocked("ACH_CAT_BURGLAR"), "cat burglar starts locked")
	Events.cat_caught.emit()
	check(Achievements.is_unlocked("ACH_CAT_BURGLAR"), "catching the cat unlocks cat burglar")
	Events.cat_petted.emit()
	check(Achievements.is_unlocked("ACH_PET_CAT"), "petting the cat unlocks its achievement")

	Events.sock_thrown.emit(12)
	Events.sock_in_basket.emit(12)
	check(Achievements.is_unlocked("ACH_TRICK_SHOT"), "trick shot")
	Events.sock_landed.emit(3, 25.0)
	check(Achievements.is_unlocked("ACH_YEET"), "yeet")
	Events.summit_reached.emit()
	check(Achievements.is_unlocked("ACH_KING_OF_THE_HILL"), "king of the hill")
	Events.socks_moving.emit(150)
	check(Achievements.is_unlocked("ACH_AVALANCHE"), "avalanche")

	Achievements.flush()
	var unlocked := Achievements.get_unlocked_count()
	var pairs := Achievements.get_stat("pairs_total")
	Achievements.load_state()
	check(Achievements.get_unlocked_count() == unlocked, "unlocks survive reload")
	check(Achievements.get_stat("pairs_total") == pairs, "stats survive reload")

	for definition: Dictionary in Achievements.get_definitions():
		if definition.id != Achievements.COMPLETIONIST_ID and not definition.speedrun:
			Achievements.unlock(definition.id)
	check(Achievements.is_unlocked(Achievements.COMPLETIONIST_ID), "completionist after all others but speedrun ones")
	# Speedrun achievements only unlock inside a speedrun.
	var story_mode := GameState.mode_id
	GameState.mode_id = "speedrun_50"
	for definition: Dictionary in Achievements.get_definitions():
		Achievements.unlock(definition.id)
	GameState.mode_id = story_mode
	check(Achievements.get_percent() == 100, "percent reaches 100")
	_end_fake_run()

	var keep: bool = Achievements.is_per_run()
	Achievements.params.per_run = false
	Achievements.on_new_game()
	check(Achievements.get_unlocked_count() > 0, "lifetime mode keeps unlocks on new game")
	check(Achievements.capture_run().is_empty(), "lifetime mode stores nothing in the run save")
	Achievements.params.per_run = true
	var snapshot := Achievements.capture_run()
	var had := Achievements.get_unlocked_count()
	Achievements.on_new_game()
	check(Achievements.get_unlocked_count() == 0 and Achievements.get_stat("pairs_total") == 0,
			"per run: new game starts with no achievements")
	Achievements.load_state()
	check(Achievements.get_unlocked_count() == 0, "per run: the wipe is saved")
	Achievements.restore_run(snapshot)
	check(Achievements.get_unlocked_count() == had, "per run: loading a save restores its achievements")
	Achievements.restore_run({})
	check(Achievements.get_unlocked_count() == 0, "per run: an old save without achievements starts empty")
	Achievements.params.per_run = keep

	Achievements.save_path = TEST_DIR + "achievements.save"
	Achievements.load_state()


func _test_socks() -> void:
	check(SockCatalog.capacity() >= 10000, "sock data has room for 5,000 pairs twice")
	var socks := SockSet.generate(77, 5000, 0.2)
	check(socks != null and socks.sock_count() == 10000, "5,000 pairs generate")
	if socks == null:
		return
	var errors := socks.validate()
	check(errors.is_empty(), "sock set follows the rules: " + ", ".join(errors.slice(0, 3)))
	var near := 0
	for pair in socks.pair_count:
		if socks.near_of[pair] >= 0:
			near += 1
	check(near == 1000, "a fifth are near pairs (%d)" % near)
	var special := 0
	var designs := {}
	for pair in socks.pair_count:
		if socks.is_special(pair):
			special += 1
			designs[socks.patterns[pair]] = true
	var share := float(SockCatalog.data()["special_share"])
	var words := SockCatalog.LETTERING_TEXTS.size()
	check(special == roundi(5000 * share) + words + SockCatalog.unlock_patterns().size() and special == socks.special_total, "rare designs on %d pairs" % special)
	check(designs.size() == SockCatalog.special_patterns().size(), "every rare design shows up")
	var texts := {}
	var left_right := -1
	for pair in socks.pair_count:
		if socks.patterns[pair] == SockCatalog.lettering_pattern():
			texts[socks.counts[pair]] = true
			if socks.counts[pair] == 0:
				left_right = pair
	check(texts.size() == words, "every knitted word once (%d)" % texts.size())
	if left_right >= 0:
		var feet := []
		for sock in socks.sock_count():
			if socks.pair_of(sock) == left_right:
				feet.append(socks.custom_data(sock).a)
		check(feet.size() == 2 and feet[0] != feet[1], "LEFT and RIGHT socks differ")
	for design in SockCatalog.unlock_patterns():
		var found := 0
		for pair in socks.pair_count:
			if socks.patterns[pair] == design:
				found += 1
				check(not socks.shows_accent(pair), "metal pair is all one yarn")
		check(found == 1, "one %s pair per game" % SockCatalog.pattern_id(design))
	var small := SockSet.generate(5, 1000, 0.2)
	check(small.validate().is_empty() and small.patterns.has(SockCatalog.pattern_index("gold")) and small.patterns.has(SockCatalog.pattern_index("silver")), "gold and silver in Laundry Day too")
	var again := SockSet.generate(77, 5000, 0.2)
	check(again.sock_pairs == socks.sock_pairs and again.base_colors == socks.base_colors and again.patterns == socks.patterns, "same seed, same socks")
	for shape in SockCatalog.shape_count():
		var near_mesh := SockMesh.get_mesh(shape, true)
		var far_mesh := SockMesh.get_mesh(shape)
		check(near_mesh != null and near_mesh.get_surface_count() == 1, "mesh for " + SockCatalog.shape_id(shape))
		check(far_mesh.surface_get_array_len(0) < near_mesh.surface_get_array_len(0), "far mesh is cheaper for " + SockCatalog.shape_id(shape))
		var size := SockMesh.collision_size(shape)
		check(size.x > 0.05 and size.y > 0.01 and size.z > 0.05, "box for " + SockCatalog.shape_id(shape))
		# Aiming follows the real leg and foot, not the box around them.
		var spine := SockMesh.spine(shape)
		var name := SockCatalog.shape_id(shape)
		var heel: Vector3 = spine["heel"]
		var toe: Vector3 = spine["toe"]
		var cuff: Vector3 = spine["cuff"]
		check(SockMesh.ray_hit(shape, heel.lerp(toe, 0.5) + Vector3.UP, Vector3.DOWN, 0.0) > 0.0, "aim hits the foot of " + name)
		check(SockMesh.ray_hit(shape, heel.lerp(cuff, 0.5) + Vector3.UP, Vector3.DOWN, 0.0) > 0.0, "aim hits the leg of " + name)
		var corner := cuff.lerp(toe, 0.5)
		var aabb := SockMesh.mesh_aabb(shape)
		if name != "sneaker":
			check(aabb.grow(0.001).has_point(Vector3(corner.x, 0.0, corner.z)) and SockMesh.ray_hit(shape, corner + Vector3.UP, Vector3.DOWN, 0.015) < 0.0, "aim misses the empty corner of " + name)
		check(SockMesh.ray_hit(shape, toe + Vector3(0.3, 1.0, 0.0), Vector3.DOWN, 0.015) < 0.0, "aim misses beside " + name)


func _test_speedrun() -> void:
	SpeedrunScores.save_path = TEST_DIR + "speedrun.save"
	SpeedrunScores.clear()
	var sizes := []
	for mode: Dictionary in Config.speedrun_modes():
		sizes.append(int(mode.pairs))
	check(sizes == [50, 100, 250, 500], "speedrun sizes 50/100/250/500")
	var story := Config.story_modes()
	check(story.size() == 1 and story[0].id == "laundry_day", "New Game offers only Laundry Day")
	check(int(Config.mode("laundry_day").pairs) == 1500, "Laundry Day keeps 1500 pairs")
	check(Config.is_speedrun("speedrun_50") and not Config.is_speedrun("laundry_day"), "speedrun flag")
	check(SpeedrunScores.best(50) < 0.0, "no best time yet")
	check(SpeedrunScores.record(50, 90.0, 2) == 0, "first time is the best")
	check(SpeedrunScores.record(50, 120.0, 0) == 1, "slower time ranks second")
	check(SpeedrunScores.record(50, 60.5, 1, true) == 0, "faster time becomes the best")
	check(is_equal_approx(SpeedrunScores.best(50), 60.5), "best time read back")
	check(SpeedrunScores.entries(100).is_empty(), "sizes keep separate lists")
	var keep := int(Config.gameplay.speedrun.highscore_entries)
	for n in keep:
		SpeedrunScores.record(50, 10.0 + n, 0)
	check(SpeedrunScores.entries(50).size() == keep, "list keeps %d entries" % keep)
	check(SpeedrunScores.record(50, 9999.0, 0) == -1, "too slow is not listed")
	check(UiKit.format_race(83.45) == "1:23.4", "race clock " + UiKit.format_race(83.45))
	# A speedrun never touches the save slots and unlocks nothing.
	Achievements.reset_all()
	_start_fake_run("speedrun_50", 0)
	check(not SaveManager.save_current(), "speedrun is not saved")
	Achievements.unlock("ACH_YEET")
	check(not Achievements.is_unlocked("ACH_YEET"), "no story achievements in a speedrun")
	GameState.pairs_total = 50
	GameState.play_time = 301.0
	GameState.finish()
	check(not Achievements.is_unlocked("ACH_SPEEDRUN_50"), "50 pairs in over 5 minutes: no achievement")
	GameState.completed = false
	GameState.play_time = 299.0
	GameState.finish()
	check(Achievements.is_unlocked("ACH_SPEEDRUN_50"), "50 pairs in under 5 minutes unlocks Quick Feet")
	Achievements.reset_all()
	check(Achievements.is_unlocked("ACH_SPEEDRUN_50"), "speedrun achievement survives a new game")
	_end_fake_run()
	GameState._reset("laundry_day")
	SpeedrunScores.clear()
	Achievements.reset_all()
	check(not Achievements.get_definitions().any(func(d: Dictionary) -> bool:
		return d.id in ["ACH_SOCK_DIMENSION", "ACH_PAIRS_5000"]), "5000 pair achievements are gone")
	SpeedrunScores.clear()


func _test_sock_wall() -> void:
	for mode_id in _room_modes():
		Config.use_mode_room(mode_id)
		var config: Dictionary = Config.world["pair_wall"]
		var size := Cellar.vec3(Config.world.room_size)
		var room := AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		var pairs := int(Config.mode(mode_id).pairs)
		var socks := SockSet.generate(5, pairs, 0.2)
		var wall := SockWall.new()
		add_child(wall)
		var found := PackedInt32Array([0, 7, pairs - 1])
		wall.setup(socks, config, found, room)
		check(wall.sock_scale > 0.99, "%s wall hangs pairs at pile size (scale %.2f)" % [mode_id, wall.sock_scale])
		check(wall.is_shown(7) and not wall.is_shown(8), "wall shows exactly the found pairs")
		wall.on_pair_matched(8, 0, 0)
		check(wall.is_shown(8), "a new match goes on the wall")
		# Every pair has its own slot inside the room.
		var seen := {}
		var inside := true
		for pair in pairs:
			var at := wall.pair_transform(pair).origin
			seen[Vector3i(at * 1000.0)] = true
			if not room.grow(0.01).has_point(at):
				inside = false
		check(inside, "all %d slots in the room" % pairs)
		check(seen.size() == pairs, "one slot per pair (%d of %d)" % [seen.size(), pairs])
		wall.free()
	Config.use_mode_room("laundry_day")


func _test_lost_found() -> void:
	var margin := float(Config.physics.lost_margin)
	var floor_limit := float(Config.physics.fall_limit_y)
	for mode_id in _room_modes():
		Config.use_mode_room(mode_id)
		var size := Cellar.vec3(Config.world.room_size)
		var room := AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		var config: Dictionary = Config.world.lost_found
		var crate := AABB(Cellar.vec3(config.position) - Cellar.vec3(config.size) * Vector3(0.5, 0, 0.5), Cellar.vec3(config.size))
		check(room.encloses(crate), "%s: lost and found crate inside the room" % mode_id)
		var all_above := true
		for n in 40:
			var drop := SockField.lost_found_drop(config, n)
			if SockField.is_lost(room, drop, margin, floor_limit) or drop.y <= crate.end.y \
					or not Rect2(crate.position.x, crate.position.z, crate.size.x, crate.size.z).has_point(Vector2(drop.x, drop.z)):
				all_above = false
		check(all_above, "%s: escaped socks drop into the crate" % mode_id)
		check(not SockField.is_lost(room, Vector3(size.x * 0.5 - 0.1, 0.1, 0.0), margin, floor_limit), "%s: sock at the wall is not lost" % mode_id)
		check(SockField.is_lost(room, Vector3(size.x * 0.5 + 1.0, 0.1, 0.0), margin, floor_limit), "%s: sock behind a wall is lost" % mode_id)
		check(SockField.is_lost(room, Vector3(0.0, size.y + 1.0, 0.0), margin, floor_limit), "%s: sock above the ceiling is lost" % mode_id)
		check(SockField.is_lost(room, Vector3(0.0, floor_limit - 1.0, 0.0), margin, floor_limit), "%s: sock under the floor is lost" % mode_id)
	Config.use_mode_room("laundry_day")

	# Real field: one sock flies out through a wall, one rests outside frozen
	# (as in an older save), one stays in the room.
	var cellar := Cellar.new()
	add_child(cellar)
	var field := SockField.new()
	add_child(field)
	var socks := SockSet.generate(9, 3, 0.0)
	var half := Cellar.vec3(Config.world.room_size) * 0.5
	field.prepare(socks, {
		0: Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)),
		1: Transform3D(Basis.IDENTITY, Vector3(half.x + 1.5, 0.2, 0.0)),
		2: Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, -half.z - 1.5)),
	})
	field.sock_by_id(2).freeze = true
	field.sock_by_id(2).sleeping = true
	var lost := []
	var on_lost := func(sock_id: int) -> void: lost.append(sock_id)
	Events.sock_lost.connect(on_lost)
	var config: Dictionary = Config.world.lost_found
	var crate := AABB(Cellar.vec3(config.position) - Cellar.vec3(config.size) * Vector3(0.5, 0, 0.5), Cellar.vec3(config.size))
	var waited := 0.0
	var landed := false
	while waited < 6.0 and not landed:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		landed = lost.size() == 2
		for sock_id in [1, 2]:
			var sock := field.sock_by_id(sock_id)
			if sock == null or not crate.grow(0.05).has_point(sock.global_position) or sock.linear_velocity.length() > 0.1:
				landed = false
	Events.sock_lost.disconnect(on_lost)
	check(lost.has(1) and lost.has(2) and not lost.has(0), "escaped socks reported, the one in the room not (%s)" % str(lost))
	check(landed, "escaped socks come to rest in the lost and found crate")
	check(field.sock_by_id(0).global_position.distance_to(Vector3(0.0, 0.2, 0.0)) < 0.5, "a sock in the room stays where it is")
	field.queue_free()
	cellar.queue_free()
	await get_tree().process_frame


## Letting go of one sock never knocks another out of the hand: a held sock
## stays held and blind to other socks, even with a dropped one right on it.
func _test_firm_hand() -> void:
	var cellar := Cellar.new()
	add_child(cellar)
	var field := SockField.new()
	add_child(field)
	var hand := Vector3(0.0, 1.2, 0.0)
	field.prepare(SockSet.generate(9, 3, 0.0), {
		0: Transform3D(Basis.IDENTITY, hand),
		1: Transform3D(Basis.IDENTITY, hand + Vector3(0.02, 0.03, 0.0)),
		2: Transform3D(Basis.IDENTITY, hand + Vector3(0.0, 0.25, 0.0)),
	})
	var held := field.sock_by_id(0)
	var dropped := field.sock_by_id(1)
	var falling := field.sock_by_id(2)
	field.begin_hold(held)
	field.begin_hold(dropped)
	await get_tree().physics_frame
	field.end_hold(dropped) # let go right next to the held sock
	falling.freeze = false
	falling.linear_velocity = Vector3.DOWN * 4.0 # and one lands on top of it
	var always_held := true
	var worst := 0.0
	var waited := 0.0
	while waited < 2.0:
		held.linear_velocity = (hand - held.global_position) * 14.0
		held.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		always_held = always_held and field.is_held(0)
		worst = maxf(worst, held.global_position.distance_to(hand))
	check(always_held, "a held sock stays held after another one is let go")
	check(held.collision_mask == SockField.WORLD_LAYER and held.collision_layer == 0,
			"a held sock never collides with other socks")
	check(worst < 0.05, "a held sock is not pushed out of the hand (%.3f m)" % worst)
	check(dropped.global_position.y < hand.y - 0.5, "the sock let go falls away")
	field.queue_free()
	cellar.queue_free()
	await get_tree().process_frame


## Every solid prop collides exactly where it is drawn: the colliders of each
## static body cover the same box as its meshes, nothing sticks out into the
## room. The shelf once had its box turned 90 degrees, 1.3 m into the room.
func _test_hitboxes() -> void:
	for mode_id in _room_modes():
		Config.use_mode_room(mode_id)
		var cellar := Cellar.new()
		add_child(cellar)
		var cat := CellarCat.new()
		add_child(cat)
		var socks := SockSet.generate(3, 200, 0.2)
		var field := SockField.new()
		add_child(field)
		field.prepare(socks, {0: Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0))})
		var size := Cellar.vec3(Config.world.room_size)
		var room := AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		var stand_in := Node3D.new()
		add_child(stand_in)
		cat.setup(field, cellar, stand_in, Config.world.cat)
		var wall := SockWall.new()
		add_child(wall)
		var found := PackedInt32Array()
		for pair in 60:
			found.append(pair * 3)
		wall.setup(socks, Config.world.pair_wall, found, room)
		await get_tree().physics_frame

		var bodies := 0
		var bad: Array[String] = []
		for body: StaticBody3D in _static_bodies(cellar):
			if body.name == "BasketBody":
				continue
			var meshes := _mesh_box(body)
			var shapes := _shape_box(body)
			if not meshes.has_volume():
				continue
			bodies += 1
			if not _same_box(meshes, shapes, 0.01):
				bad.append("%s mesh %s vs shape %s" % [body.name, meshes, shapes])
		check(bodies >= 14, "%s: all solid props found (%d)" % [mode_id, bodies])
		check(bad.is_empty(), "%s: every prop collides where it is drawn %s" % [mode_id, str(bad)])

		var space := get_viewport().world_3d.direct_space_state
		var shelf := cellar.get_node("Shelf") as StaticBody3D
		var shelf_box := _mesh_box(shelf)
		var front := shelf_box.end.x
		var free_front := true
		for i in 40:
			var z := shelf_box.position.z + shelf_box.size.z * i / 39.0
			for y in [0.1, 0.5, 1.0, 1.5, 1.9]:
				if _solid_at(space, Vector3(front + 0.02, y, z)):
					free_front = false
		check(free_front, "%s: nothing solid right in front of the shelf" % mode_id)
		check(_solid_at(space, Vector3(front - 0.05, shelf_box.position.y + 0.135, shelf_box.get_center().z)),
				"%s: the shelf boards are solid" % mode_id)

		var basket := cellar.basket.get_node("BasketBody") as StaticBody3D
		var basket_shapes := _shape_box(basket)
		var basket_meshes := _mesh_box(cellar.basket)
		# (The slanted wall boxes may dip a centimetre into the floor slab.)
		basket_meshes = basket_meshes.grow(0.01).merge(AABB(basket_meshes.position - Vector3(0, 0.05, 0), Vector3(0.01, 0.01, 0.01)))
		check(basket_meshes.encloses(basket_shapes), "%s: basket walls stay inside its outline (%s vs %s)" % [mode_id, basket_meshes, basket_shapes])
		var r := float(Config.world.basket_radius)
		var at := cellar.basket.global_position
		check(not _solid_at(space, at + Vector3(r + 0.05, float(Config.world.basket_height) * 0.95, 0.0)),
				"%s: nothing solid just outside the basket rim" % mode_id)

		# Hanging pairs are solid; an empty board is only as thick as it looks.
		check(wall.hung_collider_count() == found.size() * 2, "%s: two solid socks per hanging pair" % mode_id)
		check(_solid_at(space, wall.pair_transform(found[5]).origin), "%s: a hanging sock is solid" % mode_id)
		var empty := wall.pair_transform(1).origin # pair 1 is not found yet
		check(not _solid_at(space, empty), "%s: an empty peg is not solid" % mode_id)

		# A sock thrown along the front of the shelf flies as far as one thrown
		# through open space: nothing invisible holds it back.
		var sock := field.sock_by_id(0)
		var reach := []
		for gap in [0.3, 1.5]:
			var start := Vector3(front + gap, 1.0, shelf_box.position.z - 0.3)
			sock.freeze = false
			sock.global_transform = Transform3D(Basis.IDENTITY, start)
			sock.linear_velocity = Vector3(0.0, 0.0, 6.0)
			sock.angular_velocity = Vector3.ZERO
			sock.sleeping = false
			for frame in 20:
				await get_tree().physics_frame
			reach.append(sock.global_position.z - start.z)
		check(reach[0] > reach[1] * 0.95, "%s: a sock flies past the shelf unhindered (%.2f of %.2f m)" % [mode_id, reach[0], reach[1]])

		# A sock that lands on the ceiling pipes is nudged down, never stuck out of reach.
		var pipe := cellar.get_node("Pipes/Pipe1") as MeshInstance3D
		sock.freeze = false
		sock.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), pipe.global_position + Vector3.UP * 0.2)
		sock.linear_velocity = Vector3.ZERO
		sock.sleeping = false
		var landed_high := false
		for frame in 360:
			await get_tree().physics_frame
			landed_high = landed_high or (sock.global_position.y > 5.0 and sock.linear_velocity.length() < 0.05)
		check(sock.global_position.y < 1.0 and landed_high, "%s: no sock stays on the pipes (y %.2f, rested up there: %s)" % [mode_id, sock.global_position.y, landed_high])

		wall.queue_free()
		stand_in.queue_free()
		cat.queue_free()
		field.queue_free()
		cellar.queue_free()
		await get_tree().process_frame
	Config.use_mode_room("laundry_day")


## A sock in hand caught behind a wall slips through to the hand and becomes
## solid again there.
func _test_unsnag() -> void:
	var cellar := Cellar.new()
	add_child(cellar)
	var field := SockField.new()
	add_child(field)
	var config: Dictionary = Config.world.lost_found
	var crate := Cellar.vec3(config.position)
	var inside := crate + Vector3(0.0, 0.25, 0.0)
	var hand := crate + Vector3(Cellar.vec3(config.size).x * 0.5 + 0.6, 0.25, 0.0)
	field.prepare(SockSet.generate(9, 2, 0.0), {0: Transform3D(Basis.IDENTITY, inside)})
	var player := Player.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	add_child(player)
	player.global_position = Vector3(0, 0, 3)
	var sock := field.sock_by_id(0)
	field.begin_hold(sock)
	var cfg := Config.player
	var slipped := false
	var waited := 0.0
	while waited < 2.0 and sock.global_position.distance_to(hand) > 0.05:
		var dt := get_physics_process_delta_time()
		player._unsnag(sock, hand, dt)
		slipped = slipped or sock.collision_mask == 0
		sock.linear_velocity = ((hand - sock.global_position) * float(cfg.hold_spring)).limit_length(float(cfg.hold_max_speed))
		sock.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
		waited += dt
	for frame in 5:
		player._unsnag(sock, hand, get_physics_process_delta_time())
		await get_tree().physics_frame
	check(slipped, "a sock stuck behind the crate wall slips through")
	check(sock.global_position.distance_to(hand) < 0.1, "it reaches the hand (%.2f m off)" % sock.global_position.distance_to(hand))
	check(sock.collision_mask == SockField.WORLD_LAYER, "and is solid again in the hand")
	player.queue_free()
	field.queue_free()
	cellar.queue_free()
	await get_tree().process_frame


func _static_bodies(root: Node) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for child in root.get_children():
		if child is StaticBody3D:
			out.append(child)
		out.append_array(_static_bodies(child))
	return out


## World box of the meshes drawn by a node, not counting nested bodies.
func _mesh_box(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child in node.get_children():
		if child is CollisionObject3D and child != node:
			continue
		var b := AABB()
		if child is MeshInstance3D:
			b = (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
		elif child is Node3D:
			b = _mesh_box(child)
			if not b.has_volume():
				continue
		else:
			continue
		box = b if first else box.merge(b)
		first = false
	return box


func _shape_box(body: CollisionObject3D) -> AABB:
	var box := AABB()
	var first := true
	for child in body.get_children():
		if child is CollisionShape3D:
			var collider := child as CollisionShape3D
			var b := collider.global_transform * collider.shape.get_debug_mesh().get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


func _same_box(a: AABB, b: AABB, tolerance: float) -> bool:
	return a.position.distance_to(b.position) <= tolerance * 1.8 and a.end.distance_to(b.end) <= tolerance * 1.8


func _solid_at(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.01
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = Cellar.WORLD_LAYER
	return not space.intersect_shape(query, 1).is_empty()


func _test_drop_scatter() -> void:
	var cfg := {"drop_scatter_speed": 1.6, "drop_scatter_forward": 0.6, "drop_scatter_lift": 1.0}
	var n := 10
	var spread := Vector3.ZERO
	var min_gap := INF
	var kicks: Array[Vector3] = []
	for i in n:
		var v := Player.scatter_velocity(i, n, Vector3(0, -0.3, -1), cfg, 0.5, 0.5)
		kicks.append(Vector3(v.x, 0, v.z))
		spread += Vector3(v.x, 0, v.z)
	for i in n:
		min_gap = minf(min_gap, kicks[i].distance_to(kicks[(i + 1) % n]))
	check(min_gap > 0.3, "dropped socks fly apart in different directions")
	check((spread / n).dot(Vector3.FORWARD) > 0.3, "a dropped bundle spreads a little forward")
	check(Player.scatter_velocity(0, 1, Vector3.FORWARD, cfg, 0.5, 0.5).y > 0.5, "dropped socks pop up before they fall")


func _test_daylight() -> void:
	var config: Dictionary = Config.world["daylight"]
	var keys: Array = config["keys"]
	var start := Daylight.start_hour(config, 1234)
	check(start == Daylight.start_hour(config, 1234), "daylight: same seed, same start hour")
	check(start >= float(config.start_hour_min) and start <= float(config.start_hour_max), "daylight: start hour in range")
	var rate := float(config.game_minutes_per_real_minute)
	var later := Daylight.clock_hour(config, 1234, 3600.0)
	check(is_equal_approx(fposmod(later - start, 24.0), rate), "daylight: one real hour moves the clock by the rate")
	check(Daylight.clock_hour(config, 1234, 3600.0 * 24.0 * 60.0 / rate) < 24.0, "daylight: clock wraps at midnight")
	var prev := -1.0
	for key: Dictionary in keys:
		check(float(key.hour) > prev and float(key.hour) < 24.0, "daylight: keys sorted by hour")
		prev = float(key.hour)
	var noon: Dictionary = keys[keys.size() / 2]
	var at_key := Daylight.sample(keys, float(noon.hour))
	check(is_equal_approx(at_key.energy, float(noon.energy)), "daylight: sample at a key gives that key")
	var late := Daylight.sample(keys, 23.5)
	var first: Dictionary = keys[0]
	var last: Dictionary = keys[keys.size() - 1]
	check(late.energy >= minf(first.energy, last.energy) - 0.001 and late.energy <= maxf(first.energy, last.energy) + 0.001,
		"daylight: blends across midnight")
	check(Daylight.sample(keys, 13.0).energy > Daylight.sample(keys, 2.0).energy, "daylight: brighter at noon than at night")


func _test_pair_controller() -> void:
	var socks := SockSet.generate(11, 6, 0.0)
	check(socks != null, "sock set generated")
	if socks == null:
		return
	_start_fake_run("laundry_day", 6)

	var cellar: Cellar = load("res://scenes/cellar.tscn").instantiate()
	add_child(cellar)
	var field := Fakes.FakeField.new()
	field.renderer = SockRenderer.new()
	field.renderer.setup(socks, cellar.room_bounds())
	add_child(field.renderer)
	add_child(field)
	var player := Fakes.FakePlayer.new()
	add_child(player)
	var controller := PairController.new()
	add_child(controller)
	controller.setup(player, field, cellar, socks)

	var r := SockRenderer.new()
	r.setup(socks, cellar.room_bounds())
	add_child(r)
	r.set_highlight(0)
	r.set_highlight(1)
	check(r.highlighted() == 1, "only the latest aimed sock glows")
	r.set_highlight(0)
	r.hide_sock(0)
	check(r.highlighted() == -1, "a sock leaving the pile drops its glow")
	var partner := socks.partner_of(2)
	check(partner != 2 and socks.is_match(2, partner), "partner_of finds the other sock of the pair")
	r.set_highlight(2)
	r.set_partner_highlight(partner)
	check(r.highlighted() == 2 and r.partner_highlighted() == partner, "cheat glow sits next to the aimed glow")
	r.hide_sock(partner)
	check(r.partner_highlighted() == -1, "a partner leaving the pile drops the cheat glow")
	r.queue_free()

	var first := -1
	var second := -1
	var other := -1
	for i in socks.sock_count():
		for j in socks.sock_count():
			if first == -1 and socks.is_match(i, j):
				first = i
				second = j
	for i in socks.sock_count():
		if socks.pair_of(i) != socks.pair_of(first):
			other = i
			break

	player.held = _sock(first)
	player.aimed = _sock(other)
	controller._try_pair()
	check(player.wiggles == 1 and GameState.mistakes == 1, "wrong pair wiggles and counts")
	check(player.held != null, "wrong pair keeps the sock in hand")

	var matched := [false]
	var on_match := func(pair_id: int, _c: int, _p: int) -> void: matched[0] = pair_id == socks.pair_of(first)
	Events.pair_matched.connect(on_match)
	player.aimed = _sock(second)
	controller._try_pair()
	check(player.held == null, "match releases the hand")
	check(field.set_aside_ids.size() == 2, "both socks set aside")
	check(GameState.pairs_found == 0, "a match only counts on landing")
	var waited := 0.0
	while not matched[0] and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(matched[0], "pair lands and is registered")
	check(field.removed_ids.size() == 2, "pair removed from the field")
	check(cellar.basket.pairs_in_basket == 1, "basket pile grows")
	Events.pair_matched.disconnect(on_match)

	var in_basket := [-1]
	var on_basket := func(sock_id: int) -> void: in_basket[0] = sock_id
	Events.sock_in_basket.connect(on_basket)
	var loose := _sock(other)
	controller._on_sock_entered_basket(loose)
	check(in_basket[0] == -1, "a sock that was not thrown is no trick shot")
	Events.sock_thrown.emit(other)
	controller._on_sock_entered_basket(loose)
	check(in_basket[0] == other, "a thrown sock in the basket is reported with its id")
	Events.sock_in_basket.disconnect(on_basket)

	for node: Node in [controller, player, field, field.renderer, cellar]:
		node.queue_free()
	_end_fake_run()
	# Let the audio server drop the cellar's looping sounds before quitting.
	await get_tree().process_frame
	await get_tree().process_frame


func _sock(sock_id: int) -> Fakes.FakeSock:
	var sock := Fakes.FakeSock.new()
	sock.sock_id = sock_id
	sock.freeze = true
	add_child(sock)
	return sock


func _start_fake_run(mode: String, pairs: int) -> void:
	GameState._reset(mode)
	GameState.pairs_total = pairs
	GameState.world_provider = Fakes.FakeWorld.new()
	GameState.running = true


func _end_fake_run() -> void:
	GameState.running = false
	GameState.completed = false
	GameState.world_provider = null


func _scripts_under(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			found.append(dir_path + file)
	for sub in DirAccess.get_directories_at(dir_path):
		found.append_array(_scripts_under(dir_path + sub + "/"))
	return found


func _clean(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path + file)
	for sub in DirAccess.get_directories_at(dir_path):
		_clean(dir_path + sub + "/")
		DirAccess.remove_absolute(dir_path + sub)
