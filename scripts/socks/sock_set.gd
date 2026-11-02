class_name SockSet
extends RefCounted
## All socks of one game, generated from a seed.
## Sock indices are shuffled, so index order doubles as the pour order.
## A saved game only needs the seed and the sock transforms.

const MAX_TRIES := 64

var seed_value := 0
var pair_count := 0

# Per pair.
var base_colors := PackedInt32Array()
var accent_colors := PackedInt32Array()
var patterns := PackedInt32Array()
var stripe_counts := PackedInt32Array()
var lengths := PackedInt32Array()
var near_of := PackedInt32Array() # pair this one was derived from, or -1

# Per sock.
var sock_pairs := PackedInt32Array()

var _used := {}
var _rng := RandomNumberGenerator.new()
var _weight_total := 0.0


## Empty seed text means a random seed. Numbers are used as they are.
static func seed_from_text(text: String) -> int:
	var clean := text.strip_edges()
	if clean.is_empty():
		return randi()
	if clean.is_valid_int():
		return clean.to_int()
	return clean.hash()


## near_share comes from the mode data (0.2 = 20 % of all pairs). Returns null if the data cannot fit.
static func generate(p_seed: int, p_pair_count: int, near_share: float) -> SockSet:
	if p_pair_count > SockCatalog.capacity():
		push_error("%d pairs do not fit, the sock data allows %d" % [p_pair_count, SockCatalog.capacity()])
		return null
	var result := SockSet.new()
	result.seed_value = p_seed
	result.pair_count = p_pair_count
	result._build(near_share)
	return result


func sock_count() -> int:
	return sock_pairs.size()


func pair_of(sock: int) -> int:
	return sock_pairs[sock]


func is_match(sock_a: int, sock_b: int) -> bool:
	return sock_a != sock_b and sock_pairs[sock_a] == sock_pairs[sock_b]


## True when two different pairs differ in exactly one visible trait.
func is_near_miss(sock_a: int, sock_b: int) -> bool:
	return trait_distance(sock_pairs[sock_a], sock_pairs[sock_b]) == 1


## Number of visible traits in which two pairs differ.
func trait_distance(pair_a: int, pair_b: int) -> int:
	var distance := 0
	if base_colors[pair_a] != base_colors[pair_b]:
		distance += 1
	if lengths[pair_a] != lengths[pair_b]:
		distance += 1
	var pattern_a := SockCatalog.pattern(patterns[pair_a])
	var pattern_b := SockCatalog.pattern(patterns[pair_b])
	if patterns[pair_a] != patterns[pair_b]:
		distance += 1
	if pattern_a["uses_accent"] and pattern_b["uses_accent"] and accent_colors[pair_a] != accent_colors[pair_b]:
		distance += 1
	var count_a := stripe_counts[pair_a]
	var count_b := stripe_counts[pair_b]
	if count_a > 0 and count_b > 0 and count_a != count_b:
		distance += 1
	return distance


func sock_info(sock: int) -> Dictionary:
	var pair := sock_pairs[sock]
	return {
		"pair_id": pair,
		"base_color": base_colors[pair],
		"accent_color": accent_colors[pair],
		"pattern": patterns[pair],
		"stripes": stripe_counts[pair],
		"length": lengths[pair],
	}


## Value for MultiMesh.set_instance_custom_data, decoded in sock.gdshader.
func custom_data(sock: int) -> Color:
	var pair := sock_pairs[sock]
	return Color(
		base_colors[pair] / 255.0,
		accent_colors[pair] / 255.0,
		(patterns[pair] * 16 + stripe_counts[pair]) / 255.0,
		SockCatalog.length_scale(lengths[pair]) * 0.5
	)


## Empty when the set follows all rules.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var socks_per_pair := PackedInt32Array()
	socks_per_pair.resize(pair_count)
	var bases := {}
	var kinds := {}
	var plain_total := 0
	for pair in pair_count:
		if near_of[pair] < 0:
			plain_total += 1
		var key := _key(base_colors[pair], accent_colors[pair], patterns[pair], stripe_counts[pair], lengths[pair])
		if seen.has(key):
			errors.append("pairs %d and %d look the same" % [seen[key], pair])
		seen[key] = pair
		bases[base_colors[pair]] = true
		kinds[patterns[pair]] = true
		if near_of[pair] >= 0 and trait_distance(pair, near_of[pair]) != 1:
			errors.append("pair %d is not one trait away from pair %d" % [pair, near_of[pair]])
	for sock in sock_count():
		socks_per_pair[sock_pairs[sock]] += 1
	for pair in pair_count:
		if socks_per_pair[pair] != 2:
			errors.append("pair %d has %d socks" % [pair, socks_per_pair[pair]])
	if bases.size() < mini(plain_total, SockCatalog.palette_size()):
		errors.append("only %d base colors in use" % bases.size())
	if kinds.size() < mini(plain_total, SockCatalog.pattern_count()):
		errors.append("only %d patterns in use" % kinds.size())
	return errors


func _build(near_share: float) -> void:
	_rng.seed = seed_value
	_weight_total = 0.0
	for i in SockCatalog.pattern_count():
		_weight_total += SockCatalog.pattern(i)["weight"]

	for values: PackedInt32Array in [base_colors, accent_colors, patterns, stripe_counts, lengths, near_of]:
		values.resize(pair_count)
	near_of.fill(-1)

	var near_total := clampi(roundi(pair_count * near_share), 0, pair_count - 1)
	var plain_total := pair_count - near_total
	var forced_bases := _shuffled_range(SockCatalog.palette_size())

	for pair in plain_total:
		var forced_base := forced_bases[pair] if pair < forced_bases.size() else -1
		var forced_pattern := pair if pair < SockCatalog.pattern_count() else -1
		_fill_random(pair, forced_base, forced_pattern)

	for pair in range(plain_total, pair_count):
		if not _fill_near(pair):
			push_warning("No near pair left for pair %d" % pair)
			_fill_random(pair, -1, -1)

	sock_pairs.resize(pair_count * 2)
	for pair in pair_count:
		sock_pairs[pair * 2] = pair
		sock_pairs[pair * 2 + 1] = pair
	for i in range(sock_pairs.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := sock_pairs[i]
		sock_pairs[i] = sock_pairs[j]
		sock_pairs[j] = swap

	_used.clear()


func _fill_random(pair: int, forced_base: int, forced_pattern: int) -> void:
	for attempt in MAX_TRIES:
		var pattern := forced_pattern if forced_pattern >= 0 else _pick_pattern()
		var base := forced_base if forced_base >= 0 else _rng.randi_range(0, SockCatalog.palette_size() - 1)
		var info := SockCatalog.pattern(pattern)
		var accent := base
		if info["uses_accent"]:
			accent = _pick(SockCatalog.accents_for(base))
		var counts: Array = info["counts"]
		var count: int = counts[_rng.randi_range(0, counts.size() - 1)]
		var length := _rng.randi_range(0, SockCatalog.length_count() - 1)
		if _store_if_free(pair, base, accent, pattern, count, length):
			return
	_fill_first_free(pair)


## Fallback for a nearly full trait space: walks every combination once.
func _fill_first_free(pair: int) -> void:
	for pattern in SockCatalog.pattern_count():
		var info := SockCatalog.pattern(pattern)
		for base in SockCatalog.palette_size():
			var accents := SockCatalog.accents_for(base) if info["uses_accent"] else PackedInt32Array([base])
			for accent in accents:
				for count: int in info["counts"]:
					for length in SockCatalog.length_count():
						if _store_if_free(pair, base, accent, pattern, count, length):
							return
	push_error("Sock trait space is exhausted")


## Copies an earlier pair and changes exactly one trait.
func _fill_near(pair: int) -> bool:
	for attempt in MAX_TRIES:
		var source := _rng.randi_range(0, pair - 1)
		if _mutate(pair, source):
			near_of[pair] = source
			return true
	return false


func _mutate(pair: int, source: int) -> bool:
	var base := base_colors[source]
	var accent := accent_colors[source]
	var pattern := patterns[source]
	var count := stripe_counts[source]
	var length := lengths[source]
	var info := SockCatalog.pattern(pattern)
	var uses_accent: bool = info["uses_accent"]

	for trait_index in _shuffled_range(5):
		var options := PackedInt32Array()
		match trait_index:
			0: # base color
				for candidate in SockCatalog.palette_size():
					if candidate == base:
						continue
					if uses_accent and not SockCatalog.accents_for(candidate).has(accent):
						continue
					var new_accent := accent if uses_accent else candidate
					if not _used.has(_key(candidate, new_accent, pattern, count, length)):
						options.append(candidate)
				if not options.is_empty():
					var chosen := _pick(options)
					_store(pair, chosen, accent if uses_accent else chosen, pattern, count, length)
					return true
			1: # accent color
				if uses_accent:
					for candidate in SockCatalog.accents_for(base):
						if candidate != accent and not _used.has(_key(base, candidate, pattern, count, length)):
							options.append(candidate)
					if not options.is_empty():
						_store(pair, base, _pick(options), pattern, count, length)
						return true
			2: # stripe or ring count
				for candidate: int in info["counts"]:
					if candidate != count and not _used.has(_key(base, accent, pattern, candidate, length)):
						options.append(candidate)
				if not options.is_empty():
					_store(pair, base, accent, pattern, _pick(options), length)
					return true
			3: # length
				for candidate in SockCatalog.length_count():
					if candidate != length and not _used.has(_key(base, accent, pattern, count, candidate)):
						options.append(candidate)
				if not options.is_empty():
					_store(pair, base, accent, pattern, count, _pick(options))
					return true
			4: # pattern, only between patterns that share the count
				for candidate in SockCatalog.pattern_count():
					var other := SockCatalog.pattern(candidate)
					if candidate != pattern and other["uses_accent"] == uses_accent \
							and other["counts"].has(count) \
							and not _used.has(_key(base, accent, candidate, count, length)):
						options.append(candidate)
				if not options.is_empty():
					_store(pair, base, accent, _pick(options), count, length)
					return true
	return false


func _store_if_free(pair: int, base: int, accent: int, pattern: int, count: int, length: int) -> bool:
	if _used.has(_key(base, accent, pattern, count, length)):
		return false
	_store(pair, base, accent, pattern, count, length)
	return true


func _store(pair: int, base: int, accent: int, pattern: int, count: int, length: int) -> void:
	base_colors[pair] = base
	accent_colors[pair] = accent
	patterns[pair] = pattern
	stripe_counts[pair] = count
	lengths[pair] = length
	_used[_key(base, accent, pattern, count, length)] = true


func _key(base: int, accent: int, pattern: int, count: int, length: int) -> int:
	return base | accent << 8 | pattern << 16 | count << 24 | length << 32


func _pick(values: PackedInt32Array) -> int:
	return values[_rng.randi_range(0, values.size() - 1)]


func _pick_pattern() -> int:
	var roll := _rng.randf() * _weight_total
	for i in SockCatalog.pattern_count():
		roll -= SockCatalog.pattern(i)["weight"]
		if roll <= 0.0:
			return i
	return SockCatalog.pattern_count() - 1


func _shuffled_range(size: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	values.resize(size)
	for i in size:
		values[i] = i
	for i in range(size - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := values[i]
		values[i] = values[j]
		values[j] = swap
	return values
