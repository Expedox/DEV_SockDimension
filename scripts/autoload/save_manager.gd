extends Node
## Numbered save slots under user://saves/, written through SafeFile. Saves on
## demand, on a timer, when the pile is ready, when a run ends and on quit.
## The slot of the live run is GameState.slot.

const SAVE_DIR := "user://saves/"
const SAVE_EXTENSION := ".save"
const SLOT_PREFIX := "slot_"
const SAVE_VERSION := 1
const REQUIRED_KEYS := ["mode", "seed", "play_time", "mistakes", "throws", "completed", "found", "world"]
## Old builds kept one save per mode, named after the mode.
const LEGACY_SUFFIX := ".migrated"

## Tests point this somewhere else.
var save_dir := SAVE_DIR
var _autosave_left := 0.0


func _ready() -> void:
	_autosave_left = _autosave_interval()
	Events.pile_ready.connect(_on_pile_ready)
	Events.run_finished.connect(_on_run_finished)
	migrate_legacy_saves()


func _process(delta: float) -> void:
	if not GameState.running:
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		save_current()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_current()


func slot_count() -> int:
	return maxi(1, int(Config.gameplay.get("save_slots", 3)))


func has_save(slot: int) -> bool:
	return SafeFile.exists(_path(slot))


func has_any_save() -> bool:
	for slot in range(1, slot_count() + 1):
		if has_save(slot):
			return true
	return false


## First slot without a save, or 0 when all are taken.
func free_slot() -> int:
	for slot in range(1, slot_count() + 1):
		if not has_save(slot):
			return slot
	return 0


## Slot of the newest unfinished save, or 0.
func latest_slot() -> int:
	var latest := 0
	var latest_time := -1
	for slot in range(1, slot_count() + 1):
		var info := slot_info(slot)
		if info.is_empty() or info.completed:
			continue
		if info.saved_at > latest_time:
			latest = slot
			latest_time = info.saved_at
	return latest


## Summary for menus: mode, completed, pairs_found, play_time, saved_at, or {}.
func slot_info(slot: int) -> Dictionary:
	var data := _load(slot)
	if data.is_empty():
		return {}
	return {
		"mode": data.mode,
		"completed": data.completed,
		"pairs_found": data.found.size(),
		"play_time": data.play_time,
		"saved_at": data.get("saved_at", 0),
	}


## Deletes a slot with its backup copy.
func delete_slot(slot: int) -> void:
	SafeFile.remove(_path(slot))


## Moves per-mode saves of older builds into free slots, newest first. The
## old file is renamed, not deleted, so nothing is lost if this goes wrong.
func migrate_legacy_saves() -> int:
	var found: Array[Dictionary] = []
	for mode: Dictionary in Config.modes:
		var path: String = save_dir + mode.id + SAVE_EXTENSION
		var data := _read(path)
		if not data.is_empty():
			found.append({"path": path, "data": data})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.data.get("saved_at", 0)) > int(b.data.get("saved_at", 0)))
	var moved := 0
	for entry: Dictionary in found:
		var slot := free_slot()
		if slot == 0:
			break
		if not SafeFile.write(_path(slot), SAVE_VERSION, entry.data):
			push_error("Could not move %s into slot %d" % [entry.path, slot])
			continue
		for suffix: String in ["", SafeFile.BAK_SUFFIX]:
			if FileAccess.file_exists(entry.path + suffix):
				DirAccess.rename_absolute(entry.path + suffix, entry.path + suffix + LEGACY_SUFFIX)
		moved += 1
	return moved


## Writes GameState.capture() for the current mode. Does nothing until the
## pile is ready, so a half-poured run never replaces a good save.
func save_current() -> bool:
	if not GameState.in_run() or not (GameState.running or GameState.completed):
		return false
	var data := GameState.capture()
	data.saved_at = int(Time.get_unix_time_from_system())
	var saved := SafeFile.write(_path(GameState.slot), SAVE_VERSION, data)
	if saved:
		_autosave_left = _autosave_interval()
		Events.game_saved.emit()
	else:
		push_error("Could not save slot %d" % GameState.slot)
	return saved


## Use this instead of get_tree().quit(), which skips the close notification.
func save_and_quit() -> void:
	save_current()
	get_tree().quit()


## Opens the run saved in a slot via GameState.start_loaded(). A finished run
## has nothing left to play, so it stays closed.
func continue_run(slot: int) -> bool:
	var data := _load(slot)
	if data.is_empty() or data.completed or Config.mode(data.mode).is_empty():
		return false
	_autosave_left = _autosave_interval()
	GameState.start_loaded(data, slot)
	return true


func _load(slot: int) -> Dictionary:
	return _read(_path(slot))


func _read(path: String) -> Dictionary:
	var file := SafeFile.read(path)
	if file.is_empty():
		return {}
	if file.version != SAVE_VERSION:
		push_warning("Save %s has version %d, expected %d" % [path, file.version, SAVE_VERSION])
		return {}
	if not (file.data is Dictionary) or not file.data.has_all(REQUIRED_KEYS):
		push_warning("Save %s is incomplete" % path)
		return {}
	return file.data


func _path(slot: int) -> String:
	return save_dir + SLOT_PREFIX + str(slot) + SAVE_EXTENSION


func _autosave_interval() -> float:
	return float(Config.gameplay.get("autosave_seconds", 300))


## A long pour should not be lost to a crash before the first autosave.
func _on_pile_ready() -> void:
	if GameState.pending_world.is_empty():
		save_current.call_deferred()


func _on_run_finished(_mode_id: String) -> void:
	save_current()
