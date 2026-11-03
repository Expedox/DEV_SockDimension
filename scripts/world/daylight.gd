class_name Daylight
extends Node
## Time of day for one run: light through the cellar windows changes slowly.
## The start hour comes from the run seed, the clock from the play time, so
## nothing extra is saved. Values in data/world.json -> daylight.

var _cellar: Cellar
var _config: Dictionary
var _wait := 0.0


func setup(cellar: Cellar, config: Dictionary) -> void:
	_cellar = cellar
	_config = config
	add_to_group("daylight")
	_apply()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = float(_config.get("update_seconds", 0.5))
	_apply()


## Current clock hour of the run, 0 to below 24.
func hour() -> float:
	return clock_hour(_config, GameState.seed_value, GameState.play_time)


func _apply() -> void:
	if _cellar:
		_cellar.apply_daylight(sample(_config.get("keys", []), hour()))


## Same seed, same start hour; the clock then runs with play time.
static func clock_hour(config: Dictionary, seed_value: int, play_time: float) -> float:
	return fposmod(start_hour(config, seed_value)
		+ play_time / 3600.0 * float(config.get("game_minutes_per_real_minute", 4.0)), 24.0)


static func start_hour(config: Dictionary, seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value) ^ 0x5d1a7
	return rng.randf_range(float(config.get("start_hour_min", 0.0)), float(config.get("start_hour_max", 24.0)))


## Light at an hour, blended between the keys around it (wrapping at midnight).
## Keys are sorted by hour.
static func sample(keys: Array, at_hour: float) -> Dictionary:
	if keys.is_empty():
		return {}
	var count := keys.size()
	var after := 0
	while after < count and float(keys[after].hour) <= at_hour:
		after += 1
	var a: Dictionary = keys[(after - 1 + count) % count]
	var b: Dictionary = keys[after % count]
	var span := fposmod(float(b.hour) - float(a.hour), 24.0)
	var t := 0.0 if span <= 0.0 else fposmod(at_hour - float(a.hour), 24.0) / span
	t = smoothstep(0.0, 1.0, t)
	return {
		"sky": Color(a.sky).lerp(Color(b.sky), t),
		"light": Color(a.light).lerp(Color(b.light), t),
		"energy": lerpf(float(a.energy), float(b.energy), t),
		"glow": lerpf(float(a.glow), float(b.glow), t),
		"ambient": lerpf(float(a.get("ambient", 1.0)), float(b.get("ambient", 1.0)), t),
	}
