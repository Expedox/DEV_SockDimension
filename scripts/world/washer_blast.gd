class_name WasherBlast
extends Node3D
## The washing machine is the tear into the Sock Dimension. Once its first
## socks are paired it rumbles, shakes harder and harder and bursts: a flash,
## a cloud of foam and every other sock flies out across the cellar.
## Timings and look in data/world.json -> washer_blast.

## The machine bursts now; the field should start throwing socks.
signal burst

var _cfg: Dictionary
var _machine: Node3D
var _rest: Vector3
var _flash: OmniLight3D
var _foam: GPUParticles3D
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


## machine: the washer body to shake. Place this node at the lid centre.
func setup(machine: Node3D) -> void:
	_machine = machine
	_rest = machine.position
	_cfg = Config.world.get("washer_blast", {})
	_build()
	set_process(false)


func start() -> void:
	Events.rain_started.emit()
	Sfx.play("washer_rumble", global_position)
	set_process(true)
	var build_up := float(_cfg.get("shake_seconds", 2.0))
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "_shake", float(_cfg.get("shake_amount", 0.06)), build_up)
	tween.tween_callback(_burst)


func _process(_delta: float) -> void:
	if _machine == null:
		return
	var s := _shake
	_machine.position = _rest + Vector3(_rng.randf_range(-s, s), _rng.randf_range(0.0, s), _rng.randf_range(-s, s))
	_machine.rotation.z = _rng.randf_range(-s, s) * 0.6


func _burst() -> void:
	Sfx.play("washer_boom", global_position)
	_foam.restart()
	_foam.emitting = true
	burst.emit()
	var tween := create_tween()
	_flash.light_energy = float(_cfg.get("flash_energy", 8.0))
	tween.tween_property(_flash, "light_energy", 0.0, float(_cfg.get("flash_seconds", 0.8)))
	# The machine settles back down, still trembling a little.
	tween.parallel().tween_property(self, "_shake", 0.0, float(_cfg.get("calm_seconds", 2.5)))
	tween.tween_callback(func() -> void:
		set_process(false)
		_machine.position = _rest
		_machine.rotation.z = 0.0)


func _build() -> void:
	_flash = OmniLight3D.new()
	_flash.light_color = Color(_cfg.get("flash_color", "#d9c4ff"))
	_flash.light_energy = 0.0
	_flash.omni_range = float(_cfg.get("flash_range", 12.0))
	_flash.position.y = 0.6
	add_child(_flash)

	_foam = GPUParticles3D.new()
	_foam.name = "Foam"
	_foam.emitting = false
	_foam.one_shot = true
	_foam.explosiveness = 0.9
	_foam.amount = int(_cfg.get("foam_count", 140))
	_foam.lifetime = float(_cfg.get("foam_lifetime", 3.0))
	_foam.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.5
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 0.4
	process.scale_max = 1.2
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 0.9))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_texture := CurveTexture.new()
	fade_texture.curve = fade
	process.scale_curve = fade_texture
	_foam.process_material = process
	var bubble := SphereMesh.new()
	bubble.radius = 0.09
	bubble.height = 0.18
	bubble.radial_segments = 8
	bubble.rings = 4
	var bubble_material := StandardMaterial3D.new()
	bubble_material.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_material.roughness = 0.2
	bubble.material = bubble_material
	_foam.draw_pass_1 = bubble
	add_child(_foam)
