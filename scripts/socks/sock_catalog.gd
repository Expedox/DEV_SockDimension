class_name SockCatalog
extends RefCounted
## Read-only access to data/socks.json: palette, patterns, shapes, mesh and knit values.

const PATH := "res://data/socks.json"
const MAX_PALETTE := 32 # size of the palette array in sock.gdshader
const MAX_COUNT := 15 # pattern and count share one byte in the custom data
## sock.gdshader knows the patterns by position, so data/socks.json must keep this order.
const PATTERN_ORDER := [
	"plain", "stripes", "dots", "cuff_rings", "argyle",
	"hearts", "stars", "zigzag", "snowflakes", "rainbow", "paws", "lettering",
]
## Knitted words, one pair each per game. The count of a "lettering" pair picks
## the text; LEFT_RIGHT puts LEFT on one sock and RIGHT on its twin.
const LETTERING_TEXTS := [
	"LEFT / RIGHT", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY",
	"FRIDAY", "SATURDAY", "SUNDAY", "MOM <3", "DAD <3",
]

static var _data: Dictionary = {}
static var _colors: PackedColorArray = []
static var _accents: Array[PackedInt32Array] = []


static func data() -> Dictionary:
	if _data.is_empty():
		_load()
	return _data


static func mesh_values() -> Dictionary:
	return data()["mesh"]


static func knit_values() -> Dictionary:
	return data()["knit"]


static func palette_size() -> int:
	return data()["palette"].size()


static func pattern_count() -> int:
	return data()["patterns"].size()


## Rare easter-egg designs are marked "special" in the data. They are never
## rolled like the regular patterns; SockSet hands them out afterwards.
static func is_special(index: int) -> bool:
	return bool(pattern(index).get("special", false))


static func regular_pattern_count() -> int:
	var total := 0
	for i in pattern_count():
		if not is_special(i):
			total += 1
	return total


static func lettering_pattern() -> int:
	return pattern_index("lettering")


static func special_patterns() -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in pattern_count():
		if is_special(i):
			result.append(i)
	return result


static func shape_count() -> int:
	return data()["shapes"].size()


static func color_id(index: int) -> String:
	return data()["palette"][index]["id"]


static func pattern_id(index: int) -> String:
	return data()["patterns"][index]["id"]


static func shape_id(index: int) -> String:
	return data()["shapes"][index]["id"]


static func pattern_index(id: String) -> int:
	var patterns: Array = data()["patterns"]
	for i in patterns.size():
		if patterns[i]["id"] == id:
			return i
	return -1


static func pattern(index: int) -> Dictionary:
	return data()["patterns"][index]


static func shape(index: int) -> Dictionary:
	return data()["shapes"][index]


static func colors() -> PackedColorArray:
	data()
	return _colors


## Palette indices that read clearly as an accent on the given base color.
static func accents_for(base: int) -> PackedInt32Array:
	data()
	return _accents[base]


## How many visibly different regular pairs the current data allows.
## Plain socks without a contrast heel and toe show no accent at all.
static func capacity() -> int:
	var total := 0
	for base in palette_size():
		var accents := _accents[base].size()
		for p: Dictionary in data()["patterns"]:
			if p.get("special", false):
				continue
			var counts: int = p["counts"].size()
			if p["uses_accent"]:
				total += counts * accents * 2
			else:
				total += counts * (1 + accents)
	return total * shape_count()


static func _load() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Could not read %s" % PATH)
		return
	_data = parsed
	assert(palette_size() <= MAX_PALETTE, "Palette is larger than the shader array")
	assert(pattern_count() <= 16, "Pattern and count share one byte in the custom data")
	assert(pattern_count() == PATTERN_ORDER.size(), "Pattern list differs from sock.gdshader")
	for i in pattern_count():
		assert(pattern_id(i) == PATTERN_ORDER[i], "Pattern order differs from sock.gdshader")

	_colors = PackedColorArray()
	for entry: Dictionary in _data["palette"]:
		_colors.append(Color.html(entry["color"]))

	var min_distance: float = _data["min_accent_distance"]
	_accents.clear()
	for base in _colors.size():
		var allowed := PackedInt32Array()
		for accent in _colors.size():
			if accent != base and _color_distance(_colors[base], _colors[accent]) >= min_distance:
				allowed.append(accent)
		_accents.append(allowed)


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
