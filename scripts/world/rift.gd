class_name Rift
extends Node3D
## Glowing tear under the cellar ceiling that the pile rains out of. Opens with
## a swell of light and sound, sheds sparks while socks fall, then shrinks to a
## faint scar. Look and timings in data/world.json -> rift.

signal opened

const TEAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 edge_color : source_color;
uniform vec4 core_color : source_color;
uniform float open_amount = 0.0;
uniform float energy = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, f));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = TIME;
	// Jagged lens: widest in the middle, zig-zag along its length.
	float along = 1.0 - p.x * p.x;
	float jag = (noise(p.x * 9.0 + t * 0.7) - 0.5) * 0.35 + (noise(p.x * 23.0 - t) - 0.5) * 0.12;
	float width = max(along, 0.0) * 0.55 * open_amount;
	float d = abs(p.y - jag * along) - width;
	float core = 1.0 - smoothstep(-0.06, 0.0, d);
	float glow = exp(-max(d, 0.0) * 9.0) * along * open_amount;
	float swirl = 0.5 + 0.5 * sin(p.x * 14.0 + p.y * 20.0 - t * 3.0);
	vec3 col = edge_color.rgb * glow * (0.7 + 0.3 * swirl) + core_color.rgb * core * (0.8 + 0.2 * swirl);
	ALBEDO = col * energy;
	ALPHA = clamp(max(core, glow), 0.0, 1.0);
}
"""

var _cfg: Dictionary
var _tear: MeshInstance3D
var _material: ShaderMaterial
var _light: OmniLight3D
var _sparks: GPUParticles3D


func _ready() -> void:
	_cfg = Config.world.get("rift", {})
	_build()
	visible = false


## Tears the rift open; emits opened once it is wide enough to pour.
func open() -> void:
	visible = true
	Events.rain_started.emit()
	Sfx.play("rift_open", global_position)
	var seconds := float(_cfg.get("open_seconds", 2.0))
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_open, 0.0, 1.0, seconds)
	tween.parallel().tween_property(_light, "light_energy", float(_cfg.get("light_energy", 4.0)), seconds)
	tween.tween_callback(func() -> void:
		_sparks.emitting = true
		opened.emit())


## Shrinks to a faint scar once the pile is in.
func close() -> void:
	_sparks.emitting = false
	var seconds := float(_cfg.get("close_seconds", 3.0))
	var scar := float(_cfg.get("scar_amount", 0.12))
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_open, 1.0, scar, seconds)
	tween.parallel().tween_property(_light, "light_energy", float(_cfg.get("light_energy", 4.0)) * scar, seconds)
	Sfx.play("rift_close", global_position)


## Shown already shut down to a scar, for loaded games after the rain.
func show_scar() -> void:
	visible = true
	var scar := float(_cfg.get("scar_amount", 0.12))
	_set_open(scar)
	_light.light_energy = float(_cfg.get("light_energy", 4.0)) * scar


func _set_open(amount: float) -> void:
	_material.set_shader_parameter("open_amount", amount)


func _build() -> void:
	var size := Cellar.vec3(_cfg.get("size", [5.0, 0.0, 2.6]))
	var edge := Color(_cfg.get("edge_color", "#8d6fff"))
	var core := Color(_cfg.get("core_color", "#fff3d6"))

	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = TEAR_SHADER
	_material.shader = shader
	_material.set_shader_parameter("edge_color", edge)
	_material.set_shader_parameter("core_color", core)
	_material.set_shader_parameter("energy", float(_cfg.get("tear_energy", 1.6)))
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.z)
	quad.orientation = PlaneMesh.FACE_Y
	_tear = MeshInstance3D.new()
	_tear.name = "Tear"
	_tear.mesh = quad
	_tear.material_override = _material
	_tear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tear.rotation.y = deg_to_rad(float(_cfg.get("yaw_degrees", 20.0)))
	add_child(_tear)

	_light = OmniLight3D.new()
	_light.light_color = edge.lerp(Color.WHITE, 0.3)
	_light.light_energy = 0.0
	_light.omni_range = float(_cfg.get("light_range", 10.0))
	_light.position.y = -0.4
	_light.shadow_enabled = false
	add_child(_light)

	_sparks = GPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.emitting = false
	_sparks.amount = int(_cfg.get("spark_count", 160))
	_sparks.lifetime = float(_cfg.get("spark_lifetime", 1.6))
	_sparks.visibility_aabb = AABB(Vector3(-size.x, -8.0, -size.x), Vector3(size.x * 2.0, 9.0, size.x * 2.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(size.x * 0.35, 0.05, size.z * 0.2)
	process.direction = Vector3.DOWN
	process.spread = 12.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.5
	process.gravity = Vector3(0.0, -4.0, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.0
	_sparks.process_material = process
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.05, 0.05)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.albedo_color = edge.lerp(core, 0.5)
	spark_mesh.material = spark_material
	_sparks.draw_pass_1 = spark_mesh
	add_child(_sparks)
