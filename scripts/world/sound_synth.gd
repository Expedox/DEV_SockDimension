class_name SoundSynth
extends RefCounted
## Renders the layered recipes from data/sfx.json into 16-bit mono clips.

const PEAK := 0.9


static func render(recipe: Dictionary, sample_rate: int, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layers: Array = recipe.get("layers", [])

	var length := 0.0
	for layer: Dictionary in layers:
		length = maxf(length, float(layer.get("delay", 0.0)) + float(layer.get("duration", 0.1)))
	var mix := PackedFloat32Array()
	mix.resize(ceili(length * sample_rate))
	mix.fill(0.0)

	for layer: Dictionary in layers:
		match String(layer.get("type", "tone")):
			"noise":
				_mix_noise(mix, layer, sample_rate, rng)
			_:
				_mix_tone(mix, layer, sample_rate)

	_normalize(mix)
	return _to_stream(mix, sample_rate)


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
		mix[start + i] += sample * gain * _envelope(i * dt, t, attack, curve)


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
		mix[start + i] += sample * gain * _envelope(i * dt, t, attack, curve)


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
