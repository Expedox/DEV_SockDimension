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
	Achievements.load_state()

	_test_scripts_parse()
	_test_safe_file()
	_test_save_manager()
	_test_game_state_counters()
	_test_achievements()
	_test_socks()
	_test_sock_wall()
	await _test_pair_controller()

	print("%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


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
	GameState.register_match(0, 1, 1)
	check(GameState.pairs_found == 1 and GameState.streak == 1, "match counters")
	check(not finished[0], "not finished after one of two")
	GameState.register_match(1, 2, 2)
	check(finished[0] and GameState.completed and not GameState.running, "finishes on the last pair")

	Events.run_finished.disconnect(on_finish)
	_end_fake_run()


func _test_achievements() -> void:
	Achievements.save_path = TEST_DIR + "achievements2.save"
	Achievements.load_state()
	check(Achievements.get_unlocked_count() == 0, "fresh achievement state")
	check(Achievements.get_total_count() == 20, "twenty achievements defined")

	_start_fake_run("sock_dimension", 10)
	GameState.register_match(0, 0, 0)
	check(Achievements.is_unlocked("ACH_FIRST_PAIR"), "first pair unlocks")
	check(Achievements.get_progress("ACH_PAIRS_100") == 1, "pair counter progresses")
	check(not Achievements.is_unlocked("ACH_HALFWAY"), "not halfway after 1 of 10")
	for i in 4:
		GameState.register_match(i + 1, 0, 0)
	check(Achievements.is_unlocked("ACH_HALFWAY"), "halfway after 5 of 10")

	check(Achievements.is_night_owl_hour(0) and Achievements.is_night_owl_hour(3), "night owl hours")
	check(not Achievements.is_night_owl_hour(4) and not Achievements.is_night_owl_hour(23), "outside night owl")

	for i in 10:
		GameState.register_mismatch(true)
	check(Achievements.is_unlocked("ACH_NEAR_MISS"), "ten near misses")

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
		if definition.id != Achievements.COMPLETIONIST_ID:
			Achievements.unlock(definition.id)
	check(Achievements.is_unlocked(Achievements.COMPLETIONIST_ID), "completionist after all others")
	check(Achievements.get_percent() == 100, "percent reaches 100")
	_end_fake_run()

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
	var again := SockSet.generate(77, 5000, 0.2)
	check(again.sock_pairs == socks.sock_pairs and again.base_colors == socks.base_colors, "same seed, same socks")
	for shape in SockCatalog.shape_count():
		var near_mesh := SockMesh.get_mesh(shape, true)
		var far_mesh := SockMesh.get_mesh(shape)
		check(near_mesh != null and near_mesh.get_surface_count() == 1, "mesh for " + SockCatalog.shape_id(shape))
		check(far_mesh.surface_get_array_len(0) < near_mesh.surface_get_array_len(0), "far mesh is cheaper for " + SockCatalog.shape_id(shape))
		var size := SockMesh.collision_size(shape)
		check(size.x > 0.05 and size.y > 0.01 and size.z > 0.05, "box for " + SockCatalog.shape_id(shape))


func _test_sock_wall() -> void:
	var config: Dictionary = Config.world["pair_wall"]
	var room := AABB(Vector3(-9, 0, -7), Vector3(18, 6, 14))
	for pairs in [1500, 5000]:
		var socks := SockSet.generate(5, pairs, 0.2)
		var wall := SockWall.new()
		add_child(wall)
		var found := PackedInt32Array([0, 7, pairs - 1])
		wall.setup(socks, config, found, room)
		check(wall.sock_scale > 0.3, "wall socks readable for %d pairs (scale %.2f)" % [pairs, wall.sock_scale])
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
