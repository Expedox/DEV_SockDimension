class_name SoundSynth
extends RefCounted
## Renders the layered recipes from data/sfx.json into 16-bit mono clips.

const PEAK := 0.9


static func render(recipe: Dictionary, sample_rate: int, seed_value: int) -> AudioStreamWAV:
	var mix := _render_layers(recipe, sample_rate, seed_value, 0.0)
	_normalize(mix)
	return _to_stream(mix, sample_rate)


## Renders a seamless loop: layers marked "sustain" hold their level, and the
## tail is cross-faded into the head so the seam cannot be heard.
static func render_loop(recipe: Dictionary, sample_rate: int, seed_value: int) -> AudioStreamWAV:
	var length := float(recipe.get("loop_seconds", 4.0))
	var fade := float(recipe.get("crossfade_seconds", 0.5))
	var mix := _render_layers(recipe, sample_rate, seed_value, length + fade)
	var body := ceili(length * sample_rate)
	var fade_count := mini(ceili(fade * sample_rate), mix.size() - body)
	for i in fade_count:
		var t := float(i) / fade_count
		mix[i] = mix[i] * sqrt(t) + mix[body + i] * sqrt(1.0 - t)
	mix.resize(body)
	_normalize(mix)
	var stream := _to_stream(mix, sample_rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = body
	return stream


static func _render_layers(recipe: Dictionary, sample_rate: int, seed_value: int, min_length: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layers: Array = recipe.get("layers", [])

	var length := min_length
	for layer: Dictionary in layers:
		length = maxf(length, float(layer.get("delay", 0.0)) + float(layer.get("duration", 0.1)))
	var mix := PackedFloat32Array()
	mix.resize(ceili(length * sample_rate))
	mix.fill(0.0)

	for layer: Dictionary in layers:
		if layer.get("sustain", false):
			layer = layer.duplicate()
			layer["duration"] = length
		match String(layer.get("type", "tone")):
			"noise":
				_mix_noise(mix, layer, sample_rate, rng)
			"crackle":
				_mix_crackle(mix, layer, sample_rate, rng)
			_:
				_mix_tone(mix, layer, sample_rate)
	return mix


static func _mix_tone(mix: PackedFloat32Array, layer: Dictionary, sample_rate: int) -> void:
	var start := int(float(layer.get("delay", 0.0)) * sample_rate)
	var count := mini(int(float(layer.get("duration", 0.1)) * sample_rate), mix.size() - start)
	var freq_start := float(layer.get("freq_start", 440.0))
	var freq_end := float(layer.get("freq_end", freq_start))
	var vibrato_hz := float(layer.get("vibrato_hz", 0.0))
	var vibrato_depth := float(layer.get("vibrato_depth", 0.0))
	var harmonics: Array = layer.get("harmonics", [1.0])
	var gain := float(layer.get("gain", 0.5))
	var attack := float(layer.get("attack", 0.005))
	var curve := float(layer.get("curve", 4.0))
	var sustain := bool(layer.get("sustain", false))
	var tremolo_hz := float(layer.get("tremolo_hz", 0.0))
	var tremolo_depth := float(layer.get("tremolo_depth", 0.0))
	var dt := 1.0 / sample_rate
	var phase := 0.0

	for i in count:
		var t := float(i) / count
		var freq := lerpf(freq_start, freq_end, t)
		if vibrato_hz > 0.0:
			freq *= 1.0 + vibrato_depth * sin(TAU * vibrato_hz * i * dt)
		phase += TAU * freq * dt
		var sample := 0.0
		for h in harmonics.size():
			sample += float(harmonics[h]) * sin(phase * (h + 1))
		var level := 1.0 if sustain else _envelope(i * dt, t, attack, curve)
		if tremolo_hz > 0.0:
			level *= 1.0 - tremolo_depth * (0.5 + 0.5 * sin(TAU * tremolo_hz * i * dt))
		mix[start + i] += sample * gain * level


static func _mix_noise(
	mix: PackedFloat32Array, layer: Dictionary, sample_rate: int, rng: RandomNumberGenerator
) -> void:
	var start := int(float(layer.get("delay", 0.0)) * sample_rate)
	var count := mini(int(float(layer.get("duration", 0.1)) * sample_rate), mix.size() - start)
	var cutoff_start := float(layer.get("cutoff_start", 800.0))
	var cutoff_end := float(layer.get("cutoff_end", cutoff_start))
	var damping := 1.0 / maxf(float(layer.get("resonance", 0.7)), 0.1)
	var bandpass := String(layer.get("filter", "lowpass")) == "bandpass"
	var gain := float(layer.get("gain", 0.5))
	var attack := float(layer.get("attack", 0.005))
	var curve := float(layer.get("curve", 4.0))
	var sustain := bool(layer.get("sustain", false))
	# Slow random swells, e.g. for a room tone that breathes a little.
	var drift_hz := float(layer.get("drift_hz", 0.0))
	var drift_depth := float(layer.get("drift_depth", 0.0))
	var drift_phase := rng.randf() * TAU
	var dt := 1.0 / sample_rate
	var low := 0.0
	var band := 0.0

	# State-variable filter so the cutoff can sweep per sample.
	for i in count:
		var t := float(i) / count
		var cutoff := lerpf(cutoff_start, cutoff_end, t)
		var f := 2.0 * sin(PI * minf(cutoff * dt, 0.2))
		var high := rng.randf_range(-1.0, 1.0) - low - damping * band
		band += f * high
		low += f * band
		var sample := band if bandpass else low
		var level := 1.0 if sustain else _envelope(i * dt, t, attack, curve)
		if drift_hz > 0.0:
			level *= 1.0 - drift_depth * (0.5 + 0.5 * sin(TAU * drift_hz * i * dt + drift_phase))
		mix[start + i] += sample * gain * level


## Scattered short blips, e.g. rain drops on glass or socks tumbling in a drum.
## Each blip is a damped sine with a random pitch; "pulse_hz" bunches them up
## into regular waves (a drum turning), "density" is blips per second.
static func _mix_crackle(
	mix: PackedFloat32Array, layer: Dictionary, sample_rate: int, rng: RandomNumberGenerator
) -> void:
	var start := int(float(layer.get("delay", 0.0)) * sample_rate)
	var count := mini(int(float(layer.get("duration", 0.1)) * sample_rate), mix.size() - start)
	var density := float(layer.get("density", 20.0))
	var freq_min := float(layer.get("freq_min", 2000.0))
	var freq_max := float(layer.get("freq_max", 5000.0))
	var decay := float(layer.get("decay", 0.01))
	var gain := float(layer.get("gain", 0.3))
	var gain_jitter := float(layer.get("gain_jitter", 0.7))
	var pulse_hz := float(layer.get("pulse_hz", 0.0))
	var pulse_depth := float(layer.get("pulse_depth", 0.0))
	var dt := 1.0 / sample_rate
	var tail := ceili(decay * 6.0 * sample_rate)
	var chance := density * dt

	for i in count:
		var p := chance
		if pulse_hz > 0.0:
			p *= 1.0 - pulse_depth * (0.5 - 0.5 * cos(TAU * pulse_hz * i * dt))
		if rng.randf() >= p:
			continue
		var freq := freq_min * pow(freq_max / freq_min, rng.randf())
		var amp := gain * (1.0 - gain_jitter * rng.randf())
		var phase := rng.randf() * TAU
		for k in mini(tail, count - i):
			var t := k * dt
			mix[start + i + k] += amp * exp(-t / decay) * sin(phase + TAU * freq * t)


static func _envelope(seconds: float, t: float, attack: float, curve: float) -> float:
	var rise := minf(seconds / maxf(attack, 0.0001), 1.0)
	var fall := exp(-curve * t) * (1.0 - t * t * t * t)
	return rise * fall


static func _normalize(mix: PackedFloat32Array) -> void:
	var peak := 0.0
	for sample in mix:
		peak = maxf(peak, absf(sample))
	if peak <= 0.0:
		return
	var scale := PEAK / peak
	for i in mix.size():
		mix[i] *= scale


static func _to_stream(mix: PackedFloat32Array, sample_rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(mix.size() * 2)
	for i in mix.size():
		bytes.encode_s16(i * 2, clampi(int(mix[i] * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream
