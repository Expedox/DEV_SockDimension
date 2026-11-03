class_name SpeedrunScores
extends RefCounted
## Local best times per speedrun size, in user://speedrun.save (SafeFile).
## Each size keeps the fastest runs: {time, mistakes, at (unix), versus}.

const SAVE_PATH := "user://speedrun.save"
const SAVE_VERSION := 1

## Tests point this somewhere else.
static var save_path := SAVE_PATH


static func entries(pairs: int) -> Array:
	return _load().get(str(pairs), [])


## Best time for a size in seconds, or -1.0 when nothing is listed yet.
static func best(pairs: int) -> float:
	var list := entries(pairs)
	return float(list[0].time) if not list.is_empty() else -1.0


## Adds a finished run. Returns its place in the list (0 = new best) or -1
## when it was too slow to be kept.
static func record(pairs: int, time: float, mistakes: int, versus := false) -> int:
	var all := _load()
	var list: Array = all.get(str(pairs), [])
	var entry := {"time": time, "mistakes": mistakes, "at": int(Time.get_unix_time_from_system()), "versus": versus}
	var rank := list.size()
	for i in list.size():
		if time < float(list[i].time):
			rank = i
			break
	list.insert(rank, entry)
	var keep := int(Config.gameplay.get("speedrun", {}).get("highscore_entries", 10))
	while list.size() > keep:
		list.pop_back()
	if rank >= list.size():
		return -1
	all[str(pairs)] = list
	if not SafeFile.write(save_path, SAVE_VERSION, all):
		push_warning("Could not write speedrun times to %s" % save_path)
	return rank


static func clear() -> void:
	SafeFile.remove(save_path)


static func _load() -> Dictionary:
	var file := SafeFile.read(save_path)
	if file.is_empty() or file.version != SAVE_VERSION or not file.data is Dictionary:
		return {}
	return file.data
