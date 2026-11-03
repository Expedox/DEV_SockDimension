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
var _smoke: GPUParticles3D
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


## machine: the washer body to shake. Place this node at the lid centre.
func setup(machine: Node3D) -> void:
	_machine = machine
	_rest = machine.position
	_cfg = Config.world.get("washer_blast", {})
	_build()
	set_process(false)


## The broken machine smokes until every pair is found.
func set_smoking(on: bool) -> void:
	_smoke.emitting = on


## Every pair found: the machine is fixed. Smoke stops, a little happy jolt.
func repair() -> void:
	set_smoking(false)
	Sfx.play("match", global_position)
	set_process(true)
	_shake = 0.02
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "_shake", 0.0, 0.6)
	tween.tween_callback(func() -> void:
		set_process(false)
		_machine.position = _rest
		_machine.rotation.z = 0.0)


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
	set_smoking(true)
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
	_build_smoke()


func _build_smoke() -> void:
	_smoke = GPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.emitting = false
	_smoke.amount = int(_cfg.get("smoke_count", 36))
	_smoke.lifetime = float(_cfg.get("smoke_lifetime", 4.5))
	_smoke.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.direction = Vector3.UP
	process.spread = 18.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0.15, 0.25, 0.05)
	process.damping_min = 0.1
	process.damping_max = 0.2
	process.angle_min = -180.0
	process.angle_max = 180.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 0.55))
	fade.add_point(0.6, Color(1, 1, 1, 0.3))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	_smoke.process_material = process

	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var puff_texture := GradientTexture2D.new()
	puff_texture.gradient = puff
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(0.5, 0.0)
	puff_texture.width = 64
	puff_texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(_cfg.get("smoke_color", "#5a5560"))
	material.albedo_texture = puff_texture
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(_cfg.get("smoke_size", 1.1))
	quad.material = material
	_smoke.draw_pass_1 = quad
	_smoke.position.y = 0.1
	add_child(_smoke)
