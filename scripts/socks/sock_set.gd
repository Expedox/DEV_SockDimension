class_name SockSet
extends RefCounted
## All socks of one game, generated from a seed.
## Sock indices are shuffled, so index order doubles as the pour order.
## A saved game only needs the seed and the sock transforms.

const MAX_TRIES := 64

var seed_value := 0
var pair_count := 0

# Per pair. Visible traits: shape, base color, design (pattern and count),
# accent color (only where the design or heel and toe show it), contrast heel and toe.
var base_colors := PackedInt32Array()
var accent_colors := PackedInt32Array()
var patterns := PackedInt32Array()
var counts := PackedInt32Array()
var shapes := PackedInt32Array()
var heel_toes := PackedByteArray()
var near_of := PackedInt32Array() # pair this one was derived from, or -1
var special_total := 0 # pairs with a rare easter-egg design
var _first_sock := PackedInt32Array() # per pair, built on demand

# Per sock.
var sock_pairs := PackedInt32Array()

var _used := {}
var _rng := RandomNumberGenerator.new()
var _pattern_weights := PackedFloat32Array()
var _shape_weights := PackedFloat32Array()
var _heel_toe_share := 0.0


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
	if shapes[pair_a] != shapes[pair_b]:
		distance += 1
	if base_colors[pair_a] != base_colors[pair_b]:
		distance += 1
	if patterns[pair_a] != patterns[pair_b] or counts[pair_a] != counts[pair_b]:
		distance += 1
	if heel_toes[pair_a] != heel_toes[pair_b]:
		distance += 1
	if shows_accent(pair_a) and shows_accent(pair_b) and accent_colors[pair_a] != accent_colors[pair_b]:
		distance += 1
	return distance


## Rare easter-egg design. Both socks share it, like any other trait.
func is_special(pair: int) -> bool:
	return SockCatalog.is_special(patterns[pair])


func shows_accent(pair: int) -> bool:
	return heel_toes[pair] == 1 or SockCatalog.pattern(patterns[pair])["uses_accent"]


## The other sock of the same pair, or -1.
func partner_of(sock: int) -> int:
	var pair := sock_pairs[sock]
	for other in sock_pairs.size():
		if other != sock and sock_pairs[other] == pair:
			return other
	return -1


func shape_of(sock: int) -> int:
	return shapes[sock_pairs[sock]]


## count is the number of stripes or rings, or the dot and diamond size.
func sock_info(sock: int) -> Dictionary:
	var pair := sock_pairs[sock]
	return {
		"pair_id": pair,
		"base_color": base_colors[pair],
		"accent_color": accent_colors[pair],
		"pattern": patterns[pair],
		"count": counts[pair],
		"shape": shapes[pair],
		"heel_toe": heel_toes[pair] == 1,
	}


## Value for MultiMesh.set_instance_custom_data, decoded in sock.gdshader.
func custom_data(sock: int) -> Color:
	var pair := sock_pairs[sock]
	return pair_custom_data(pair, sock != first_sock(pair))


## second marks the twin, which only matters for socks that differ per foot (LEFT / RIGHT).
## Alpha: +1 contrast heel and toe, +4 second sock; the renderer adds 2 while aimed at.
func pair_custom_data(pair: int, second: bool) -> Color:
	return Color(
		base_colors[pair] / 255.0,
		accent_colors[pair] / 255.0,
		(patterns[pair] * 16 + counts[pair]) / 255.0,
		float(heel_toes[pair]) + (4.0 if second else 0.0)
	)


## Lower of the two sock indices of a pair.
func first_sock(pair: int) -> int:
	if _first_sock.size() != pair_count:
		_first_sock.resize(pair_count)
		_first_sock.fill(-1)
		for sock in sock_count():
			var p := sock_pairs[sock]
			if _first_sock[p] < 0:
				_first_sock[p] = sock
	return _first_sock[pair]


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
		if is_special(pair):
			if near_of[pair] >= 0:
				errors.append("pair %d is special and a near pair" % pair)
		else:
			kinds[patterns[pair]] = true
		var key := _key(base_colors[pair], accent_colors[pair], patterns[pair], counts[pair], shapes[pair], heel_toes[pair])
		if seen.has(key):
			errors.append("pairs %d and %d look the same" % [seen[key], pair])
		seen[key] = pair
		if not shows_accent(pair) and accent_colors[pair] != base_colors[pair]:
			errors.append("pair %d has a hidden accent" % pair)
		bases[base_colors[pair]] = true
		if near_of[pair] >= 0 and trait_distance(pair, near_of[pair]) != 1:
			errors.append("pair %d is not one trait away from pair %d" % [pair, near_of[pair]])
	for sock in sock_count():
		socks_per_pair[sock_pairs[sock]] += 1
	for pair in pair_count:
		if socks_per_pair[pair] != 2:
			errors.append("pair %d has %d socks" % [pair, socks_per_pair[pair]])
	if bases.size() < mini(plain_total, SockCatalog.palette_size()):
		errors.append("only %d base colors in use" % bases.size())
	if kinds.size() < mini(plain_total, SockCatalog.regular_pattern_count()):
		errors.append("only %d patterns in use" % kinds.size())
	return errors


func _build(near_share: float) -> void:
	_rng.seed = seed_value
	_pattern_weights.clear()
	for i in SockCatalog.pattern_count():
		_pattern_weights.append(0.0 if SockCatalog.is_special(i) else float(SockCatalog.pattern(i)["weight"]))
	_shape_weights.clear()
	for i in SockCatalog.shape_count():
		_shape_weights.append(SockCatalog.shape(i)["weight"])
	_heel_toe_share = SockCatalog.data()["heel_toe_share"]

	base_colors.resize(pair_count)
	accent_colors.resize(pair_count)
	patterns.resize(pair_count)
	counts.resize(pair_count)
	shapes.resize(pair_count)
	heel_toes.resize(pair_count)
	near_of.resize(pair_count)
	near_of.fill(-1)

	var near_total := clampi(roundi(pair_count * near_share), 0, pair_count - 1)
	var plain_total := pair_count - near_total
	var forced_bases := _shuffled_range(SockCatalog.palette_size())

	for pair in plain_total:
		var forced_base := forced_bases[pair] if pair < forced_bases.size() else -1
		var forced_pattern := pair if pair < SockCatalog.regular_pattern_count() else -1
		_fill_random(pair, forced_base, forced_pattern)

	for pair in range(plain_total, pair_count):
		if not _fill_near(pair):
			push_warning("No near pair left for pair %d" % pair)
			_fill_random(pair, -1, -1)

	_add_specials(float(SockCatalog.data().get("special_share", 0.0)))

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
		var pattern := forced_pattern if forced_pattern >= 0 else _pick_weighted(_pattern_weights)
		var base := forced_base if forced_base >= 0 else _rng.randi_range(0, SockCatalog.palette_size() - 1)
		var info := SockCatalog.pattern(pattern)
		var heel_toe := 1 if _rng.randf() < _heel_toe_share else 0
		var accent := base
		if info["uses_accent"] or heel_toe == 1:
			accent = _pick(SockCatalog.accents_for(base))
		var count := _pick_count(pattern)
		var shape := _pick_weighted(_shape_weights)
		if _store_if_free(pair, base, accent, pattern, count, shape, heel_toe):
			return
	_fill_first_free(pair)


## Turns a share of the free-standing pairs into rare easter-egg designs.
## Runs on its own random stream, so pair ids and the pour order stay exactly
## as without specials (older saves keep their socks). Near pairs and their
## sources are left alone, so every near pair stays one trait away.
func _add_specials(share: float) -> void:
	special_total = 0
	var designs := PackedInt32Array()
	for d in SockCatalog.special_patterns():
		if float(SockCatalog.pattern(d)["weight"]) > 0.0:
			designs.append(d)
	if designs.is_empty() or share <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "special"])
	var weights := PackedFloat32Array()
	for d in designs:
		weights.append(float(SockCatalog.pattern(d)["weight"]))

	var is_source := PackedByteArray()
	is_source.resize(pair_count)
	for pair in pair_count:
		if near_of[pair] >= 0:
			is_source[near_of[pair]] = 1
	# The first pairs carry the forced colors and patterns for the achievements.
	var first := maxi(SockCatalog.palette_size(), SockCatalog.regular_pattern_count())
	var candidates := PackedInt32Array()
	for pair in range(first, pair_count):
		if near_of[pair] < 0 and is_source[pair] == 0:
			candidates.append(pair)
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap

	var target := mini(roundi(pair_count * share), candidates.size())
	var next := 0
	while next < candidates.size() and special_total < target:
		var pair := candidates[next]
		next += 1
		for attempt in 8:
			var design := designs[_pick_weighted_with(rng, weights)]
			var info := SockCatalog.pattern(design)
			var options: Array = info["counts"]
			var count := int(options[rng.randi_range(0, options.size() - 1)])
			var heel_toe := int(heel_toes[pair])
			var base := base_colors[pair]
			var accent := accent_colors[pair]
			if info["uses_accent"] or heel_toe == 1:
				if accent == base:
					var allowed := SockCatalog.accents_for(base)
					accent = allowed[rng.randi_range(0, allowed.size() - 1)]
			else:
				accent = base
			var key := _key(base, accent, design, count, shapes[pair], heel_toe)
			if _used.has(key):
				continue
			_used.erase(_key(base, accent_colors[pair], patterns[pair], counts[pair], shapes[pair], heel_toe))
			_store(pair, base, accent, design, count, shapes[pair], heel_toe)
			special_total += 1
			break

	# The knitted words come on top, once each, after the rolled designs so
	# those stay as they were. Always the long sock, so the word fits the leg.
	var lettering := SockCatalog.lettering_pattern()
	if lettering >= 0:
		var shape := maxi(0, _shape_index(str(SockCatalog.data().get("lettering_shape", ""))))
		for value: Variant in SockCatalog.pattern(lettering)["counts"]:
			if next >= candidates.size():
				break
			var pair := candidates[next]
			next += 1
			var base := base_colors[pair]
			var accent := accent_colors[pair]
			if accent == base:
				var allowed := SockCatalog.accents_for(base)
				accent = allowed[rng.randi_range(0, allowed.size() - 1)]
			_used.erase(_key(base, accent_colors[pair], patterns[pair], counts[pair], shapes[pair], heel_toes[pair]))
			_store(pair, base, accent, lettering, int(value), shape, heel_toes[pair])
			special_total += 1

	# Golden and silver socks come last, one pair each. The whole sock is
	# metallic yarn, so it has no accent and no contrast heel and toe.
	for design in SockCatalog.unlock_patterns():
		if next >= candidates.size():
			break
		var pair := candidates[next]
		next += 1
		var base := base_colors[pair]
		_used.erase(_key(base, accent_colors[pair], patterns[pair], counts[pair], shapes[pair], heel_toes[pair]))
		_store(pair, base, base, design, 0, shapes[pair], 0)
		special_total += 1


static func _shape_index(id: String) -> int:
	for i in SockCatalog.shape_count():
		if SockCatalog.shape_id(i) == id:
			return i
	return -1


## Fallback for a nearly full trait space: walks every combination once.
func _fill_first_free(pair: int) -> void:
	for shape in SockCatalog.shape_count():
		for pattern in SockCatalog.pattern_count():
			if SockCatalog.is_special(pattern):
				continue
			var info := SockCatalog.pattern(pattern)
			for heel_toe in 2:
				for base in SockCatalog.palette_size():
					var shows: bool = info["uses_accent"] or heel_toe == 1
					var accents := SockCatalog.accents_for(base) if shows else PackedInt32Array([base])
					for accent in accents:
						for count: Variant in info["counts"]:
							if _store_if_free(pair, base, accent, pattern, int(count), shape, heel_toe):
								return
	push_error("Sock trait space is exhausted")


## Copies an earlier pair and changes exactly one visible trait.
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
	var count := counts[source]
	var shape := shapes[source]
	var heel_toe := int(heel_toes[source])
	var shows := shows_accent(source)

	for trait_index in _shuffled_range(5):
		# Each candidate is [base, accent, pattern, count, shape, heel_toe].
		var options: Array[PackedInt32Array] = []
		match trait_index:
			0: # shape
				for candidate in SockCatalog.shape_count():
					if candidate != shape:
						options.append(PackedInt32Array([base, accent, pattern, count, candidate, heel_toe]))
			1: # base color, the accent stays if it still reads on the new base
				for candidate in SockCatalog.palette_size():
					if candidate == base or (shows and not SockCatalog.accents_for(candidate).has(accent)):
						continue
					options.append(PackedInt32Array([candidate, accent if shows else candidate, pattern, count, shape, heel_toe]))
			2: # accent color
				if shows:
					for candidate in SockCatalog.accents_for(base):
						if candidate != accent:
							options.append(PackedInt32Array([base, candidate, pattern, count, shape, heel_toe]))
			3: # design: another pattern or another count
				for candidate in SockCatalog.pattern_count():
					if SockCatalog.is_special(candidate):
						continue
					var info := SockCatalog.pattern(candidate)
					var needs_accent: bool = info["uses_accent"] or heel_toe == 1
					var new_accent := accent
					if needs_accent and not shows:
						new_accent = _pick(SockCatalog.accents_for(base))
					elif not needs_accent:
						new_accent = base
					for value: Variant in info["counts"]:
						var candidate_count := int(value)
						if candidate != pattern or candidate_count != count:
							options.append(PackedInt32Array([base, new_accent, candidate, candidate_count, shape, heel_toe]))
			4: # contrast heel and toe on or off
				var flipped := 1 - heel_toe
				var plain_after: bool = not SockCatalog.pattern(pattern)["uses_accent"] and flipped == 0
				var new_accent := base if plain_after else accent
				if flipped == 1 and not shows:
					new_accent = _pick(SockCatalog.accents_for(base))
				options.append(PackedInt32Array([base, new_accent, pattern, count, shape, flipped]))
		var free: Array[PackedInt32Array] = []
		for o in options:
			if not _used.has(_key(o[0], o[1], o[2], o[3], o[4], o[5])):
				free.append(o)
		if not free.is_empty():
			var o := free[_rng.randi_range(0, free.size() - 1)]
			_store(pair, o[0], o[1], o[2], o[3], o[4], o[5])
			return true
	return false


func _store_if_free(pair: int, base: int, accent: int, pattern: int, count: int, shape: int, heel_toe: int) -> bool:
	if _used.has(_key(base, accent, pattern, count, shape, heel_toe)):
		return false
	_store(pair, base, accent, pattern, count, shape, heel_toe)
	return true


func _store(pair: int, base: int, accent: int, pattern: int, count: int, shape: int, heel_toe: int) -> void:
	base_colors[pair] = base
	accent_colors[pair] = accent
	patterns[pair] = pattern
	counts[pair] = count
	shapes[pair] = shape
	heel_toes[pair] = heel_toe
	_used[_key(base, accent, pattern, count, shape, heel_toe)] = true


func _key(base: int, accent: int, pattern: int, count: int, shape: int, heel_toe: int) -> int:
	return base | accent << 8 | pattern << 16 | count << 20 | shape << 24 | heel_toe << 28


func _pick(values: PackedInt32Array) -> int:
	return values[_rng.randi_range(0, values.size() - 1)]


func _pick_count(pattern: int) -> int:
	var options: Array = SockCatalog.pattern(pattern)["counts"]
	return int(options[_rng.randi_range(0, options.size() - 1)])


func _pick_weighted(weights: PackedFloat32Array) -> int:
	return _pick_weighted_with(_rng, weights)


static func _pick_weighted_with(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0 and weights[i] > 0.0:
			return i
	# Rounding can leave a tiny rest; never land on a zero weight.
	for i in range(weights.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return i
	return 0


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
