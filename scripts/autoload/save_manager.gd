extends Node
## One save per mode under user://saves/, written through SafeFile. Saves on
## demand, on a timer, when the pile is ready, when a run ends and on quit.

const SAVE_DIR := "user://saves/"
const SAVE_EXTENSION := ".save"
const SAVE_VERSION := 1
const REQUIRED_KEYS := ["mode", "seed", "play_time", "mistakes", "throws", "completed", "found", "world"]

var _autosave_left := 0.0


func _ready() -> void:
	_autosave_left = _autosave_interval()
	Events.pile_ready.connect(_on_pile_ready)
	Events.run_finished.connect(_on_run_finished)


func _process(delta: float) -> void:
	if not GameState.running:
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		save_current()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_current()


func has_save(mode_id: String) -> bool:
	return SafeFile.exists(_path(mode_id))


## Mode id of the newest unfinished save, or "".
func latest_save() -> String:
	var latest := ""
	var latest_time := -1
	for mode: Dictionary in Config.modes:
		var info := save_info(mode.id)
		if info.is_empty() or info.completed:
			continue
		if info.saved_at > latest_time:
			latest = mode.id
			latest_time = info.saved_at
	return latest


## Summary for menus: mode, completed, pairs_found, play_time, saved_at, or {}.
func save_info(mode_id: String) -> Dictionary:
	var data := _load(mode_id)
	if data.is_empty():
		return {}
	return {
		"mode": data.mode,
		"completed": data.completed,
		"pairs_found": data.found.size(),
		"play_time": data.play_time,
		"saved_at": data.get("saved_at", 0),
	}


## Writes GameState.capture() for the current mode. Does nothing until the
## pile is ready, so a half-poured run never replaces a good save.
func save_current() -> bool:
	if not GameState.in_run() or not (GameState.running or GameState.completed):
		return false
	var data := GameState.capture()
	data.saved_at = int(Time.get_unix_time_from_system())
	var saved := SafeFile.write(_path(GameState.mode_id), SAVE_VERSION, data)
	if saved:
		_autosave_left = _autosave_interval()
		Events.game_saved.emit()
	else:
		push_error("Could not save %s" % GameState.mode_id)
	return saved


## Use this instead of get_tree().quit(), which skips the close notification.
func save_and_quit() -> void:
	save_current()
	get_tree().quit()


## Opens the saved run of a mode via GameState.start_loaded(). A finished run
## has nothing left to play, so it stays closed.
func continue_run(mode_id: String) -> bool:
	var data := _load(mode_id)
	if data.is_empty() or data.completed:
		return false
	_autosave_left = _autosave_interval()
	GameState.start_loaded(data)
	return true


func _load(mode_id: String) -> Dictionary:
	var file := SafeFile.read(_path(mode_id))
	if file.is_empty():
		return {}
	if file.version != SAVE_VERSION:
		push_warning("Save %s has version %d, expected %d" % [mode_id, file.version, SAVE_VERSION])
		return {}
	if not (file.data is Dictionary) or not file.data.has_all(REQUIRED_KEYS):
		push_warning("Save %s is incomplete" % mode_id)
		return {}
	return file.data


func _path(mode_id: String) -> String:
	return SAVE_DIR + mode_id + SAVE_EXTENSION


func _autosave_interval() -> float:
	return float(Config.gameplay.get("autosave_seconds", 300))


## A long pour should not be lost to a crash before the first autosave.
func _on_pile_ready() -> void:
	if GameState.pending_world.is_empty():
		save_current.call_deferred()


func _on_run_finished(_mode_id: String) -> void:
	save_current()
