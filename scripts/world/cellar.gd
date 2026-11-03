class_name Cellar
extends Node3D
## Builds the laundry cellar from data/world.json: shell, lights, props and basket.

const FLOOR_SHADER := preload("res://shaders/cellar_floor.gdshader")
const WALL_SHADER := preload("res://shaders/cellar_wall.gdshader")
const WOOD_SHADER := preload("res://shaders/cellar_wood.gdshader")
const CLOTH_SHADER := preload("res://shaders/cellar_cloth.gdshader")
const WINDOW_SHADER := preload("res://shaders/cellar_window.gdshader")
const DUST_SHADER := preload("res://shaders/cellar_dust.gdshader")
const WORLD_LAYER := 1
const SOCK_LAYER := 2

signal sock_entered_basket(body: Node3D)

var basket: LaundryBasket

var _data: Dictionary
var _colors: Dictionary
var _room_size := Vector3.ONE
var _ambience_rng := RandomNumberGenerator.new()
var _env: Environment
var _dust: Array[GPUParticles3D] = []
var _dust_material: ShaderMaterial
var _quality := ""
## Per window: glass material, light and its config, for the time of day.
var _windows: Array[Dictionary] = []


static func vec3(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func _ready() -> void:
	_data = Config.world
	_colors = _data["colors"]
	_room_size = vec3(_data["room_size"])
	_build_shell()
	_build_environment()
	for lamp: Dictionary in _data["lamps"]:
		_build_lamp(lamp)
	for window: Dictionary in _data.get("windows", []):
		_build_window(window)
	_build_beams()
	_build_washing_machine()
	_build_pipes()
	_build_fairy_lights()
	_build_shelf()
	_build_lost_found()
	_build_clothesline()
	_build_basket()
	_build_ambience()
	apply_quality()
	Settings.changed.connect(apply_quality)


## Feet position and level facing for a fresh game (-Z points towards the pile).
func player_spawn() -> Transform3D:
	var from := vec3(_data["player_spawn"])
	var target := Vector3(0.0, from.y, 0.0)
	return Transform3D.IDENTITY.translated(from).looking_at(target, Vector3.UP)


## Centre of the washing machine's lid, turned like the machine. Local X runs
## along its width, Z along its depth.
func washer_top() -> Transform3D:
	var size := vec3(_data["washer_size"])
	var basis := Basis(Vector3.UP, deg_to_rad(float(_data["washer_yaw_degrees"])))
	return Transform3D(basis, vec3(_data["washer_position"]) + Vector3.UP * size.y)


## The washing machine body, for shaking it.
func washer() -> Node3D:
	return get_node("WashingMachine")


## Lid size of the washing machine (x width, z depth).
func washer_lid() -> Vector2:
	var size := vec3(_data["washer_size"])
	return Vector2(size.x, size.z)


## World point a rolled-up pair should fly to.
func basket_mouth() -> Vector3:
	return basket.mouth()


## Inside of the room; anything outside this has escaped.
func room_bounds() -> AABB:
	return AABB(Vector3(-_room_size.x * 0.5, 0.0, -_room_size.z * 0.5), _room_size)


func _color(key: String) -> Color:
	return Color(_colors[key])


func _build_shell() -> void:
	var size := _room_size
	var t := float(_data["shell_thickness"])
	var half := size * 0.5

	var floor_material := ShaderMaterial.new()
	floor_material.shader = FLOOR_SHADER
	floor_material.set_shader_parameter("base_color", _color("floor"))
	floor_material.set_shader_parameter("dark_color", _color("floor_dark"))

	var wall_material := ShaderMaterial.new()
	wall_material.shader = WALL_SHADER
	wall_material.set_shader_parameter("brick_color", _color("wall"))
	wall_material.set_shader_parameter("mortar_color", _color("wall_mortar"))
	wall_material.set_shader_parameter("band_color", _color("wall_band"))
	wall_material.set_shader_parameter("grime_color", _color("wall_grime"))
	wall_material.set_shader_parameter("band_height", float(_data["wall_band_height"]))

	var ceiling_material := _wood(1, 0.16, _color("ceiling"), _color("wood_dark"))

	# Thick slabs, so a hard throw cannot tunnel out of the room.
	var outer := Vector2(size.x + t * 2.0, size.z + t * 2.0)
	_add_solid("Floor", Vector3(outer.x, t, outer.y), Vector3(0, -t * 0.5, 0), floor_material)
	_add_solid("Ceiling", Vector3(outer.x, t, outer.y), Vector3(0, size.y + t * 0.5, 0), ceiling_material)
	var wall_y := size.y * 0.5
	_add_solid("WallNorth", Vector3(outer.x, size.y, t), Vector3(0, wall_y, -half.z - t * 0.5), wall_material)
	_add_solid("WallSouth", Vector3(outer.x, size.y, t), Vector3(0, wall_y, half.z + t * 0.5), wall_material)
	_add_solid("WallEast", Vector3(t, size.y, size.z), Vector3(half.x + t * 0.5, wall_y, 0), wall_material)
	_add_solid("WallWest", Vector3(t, size.y, size.z), Vector3(-half.x - t * 0.5, wall_y, 0), wall_material)


func _add_solid(node_name: String, size: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(instance)
	return body


func _build_environment() -> void:
	var config: Dictionary = _data["environment"]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(config["background"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(config["ambient"])
	env.ambient_light_energy = float(config["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(config["tonemap_exposure"])
	env.tonemap_white = float(config.get("tonemap_white", 1.0))

	# Contact shadows in the pile and in the room corners.
	env.ssao_enabled = bool(config["ssao"])
	env.ssao_radius = float(config.get("ssao_radius", 1.0))
	env.ssao_intensity = float(config.get("ssao_intensity", 2.0))
	env.ssao_power = float(config.get("ssao_power", 1.5))
	env.ssao_detail = 0.6
	env.ssao_light_affect = float(config.get("ssao_light_affect", 0.2))
	# Short-range bounce light, so the socks tint their surroundings.
	env.ssil_enabled = bool(config.get("ssil", false))
	env.ssil_radius = float(config.get("ssil_radius", 4.0))
	env.ssil_intensity = float(config.get("ssil_intensity", 1.0))

	env.glow_enabled = bool(config["glow"])
	env.glow_intensity = float(config.get("glow_intensity", 0.5))
	env.glow_bloom = float(config.get("glow_bloom", 0.02))
	env.glow_hdr_threshold = float(config.get("glow_threshold", 1.0))
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# A little dust in the air: light cones under the lamps, dark far corners.
	env.volumetric_fog_enabled = bool(config.get("volumetric_fog", false))
	env.volumetric_fog_density = float(config.get("fog_density", 0.01))
	env.volumetric_fog_albedo = Color(config.get("fog_albedo", "#d9c3a5"))
	env.volumetric_fog_anisotropy = float(config.get("fog_anisotropy", 0.4))
	env.volumetric_fog_length = float(config.get("fog_length", 40.0))
	env.volumetric_fog_ambient_inject = 0.0

	env.adjustment_enabled = true
	env.adjustment_saturation = float(config.get("saturation", 1.0))
	env.adjustment_contrast = float(config.get("contrast", 1.0))

	_env = env
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	add_child(world)


func _build_lamp(config: Dictionary) -> void:
	var spot_xz: Array = config["position"]
	var mount := Vector3(spot_xz[0], _room_size.y, spot_xz[1])
	var drop := float(config["drop"])
	var radius := float(config["shade_radius"])
	var color := Color(config["color"])

	var lamp := static_body("Lamp")
	lamp.position = mount
	add_child(lamp)

	var cord_material := StandardMaterial3D.new()
	cord_material.albedo_color = Color(0.08, 0.08, 0.08)
	var cord_mesh := CylinderMesh.new()
	cord_mesh.top_radius = 0.012
	cord_mesh.bottom_radius = 0.012
	cord_mesh.height = drop
	cord_mesh.radial_segments = 6
	cord_mesh.rings = 1
	_add_solid_part(lamp, cord_mesh, cord_material, Vector3(0, -drop * 0.5, 0))

	var shade_material := StandardMaterial3D.new()
	shade_material.albedo_color = _color("lamp_shade")
	shade_material.metallic = 0.3
	shade_material.roughness = 0.45
	shade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = radius * 0.16
	shade_mesh.bottom_radius = radius
	shade_mesh.height = radius * 0.6
	shade_mesh.radial_segments = 24
	shade_mesh.rings = 1
	shade_mesh.cap_top = true
	shade_mesh.cap_bottom = false
	var shade := _add_solid_part(lamp, shade_mesh, shade_material, Vector3(0, -drop - radius * 0.3, 0))
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var bulb_material := StandardMaterial3D.new()
	bulb_material.albedo_color = color
	bulb_material.emission_enabled = true
	bulb_material.emission = color
	bulb_material.emission_energy_multiplier = float(config.get("bulb_glow", 8.0))
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = radius * 0.22
	bulb_mesh.height = radius * 0.44
	bulb_mesh.radial_segments = 12
	bulb_mesh.rings = 6
	var bulb := _add_solid_part(lamp, bulb_mesh, bulb_material, Vector3(0, -drop - radius * 0.5, 0))
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var light_y := -drop - radius * 0.55
	# The shade throws a warm cone downwards; a weak fill lights the rest of the room.
	var spot := SpotLight3D.new()
	spot.name = "Cone"
	spot.position.y = light_y
	spot.rotation.x = -PI * 0.5
	spot.light_color = color
	spot.light_energy = float(config["energy"])
	spot.spot_range = float(config["range"])
	spot.spot_angle = float(config.get("spot_angle", 60.0))
	spot.spot_angle_attenuation = float(config.get("spot_softness", 0.6))
	spot.spot_attenuation = float(config["attenuation"])
	spot.light_size = float(config.get("light_size", 0.1))
	spot.light_volumetric_fog_energy = float(config.get("fog_energy", 1.0))
	spot.shadow_enabled = bool(config["shadow"])
	spot.shadow_blur = float(config.get("shadow_blur", 1.5))
	spot.shadow_bias = 0.04
	lamp.add_child(spot)

	var fill_energy := float(config.get("fill_energy", 0.0))
	if fill_energy > 0.0:
		var fill := OmniLight3D.new()
		fill.name = "Fill"
		fill.position.y = light_y + radius * 0.3
		fill.light_color = color
		fill.light_energy = fill_energy
		fill.omni_range = float(config.get("fill_range", config["range"]))
		fill.omni_attenuation = float(config.get("fill_attenuation", 1.4))
		fill.light_volumetric_fog_energy = 0.0
		fill.light_specular = 0.2
		fill.shadow_enabled = false
		lamp.add_child(fill)

	# Dust floating in the cone, from just under the shade down to the floor.
	var height := _room_size.y + light_y
	var reach := minf(tan(deg_to_rad(spot.spot_angle)) * height * 0.6, float(config.get("dust_radius", 3.5)))
	_add_dust(lamp, Transform3D(Basis(), Vector3(0, light_y - height * 0.5, 0)),
		Vector3(reach, height * 0.5, reach), int(config.get("dust", 0)))


func _build_washing_machine() -> void:
	var size := vec3(_data["washer_size"])

	var body := _add_solid("WashingMachine", size, vec3(_data["washer_position"]) + Vector3.UP * size.y * 0.5,
			_plain(_color("machine_body"), 0.35))
	body.rotation.y = deg_to_rad(float(_data["washer_yaw_degrees"]))
	body.get_child(1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var front := size.z * 0.5
	var trim := _plain(_color("machine_trim"), 0.3, 0.6)
	var panel_height := size.y * 0.14
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(size.x * 0.96, panel_height, 0.03)
	_add_solid_part(body, panel_mesh, _plain(_color("machine_panel"), 0.5),
			Vector3(0, size.y * 0.5 - panel_height * 0.6, front + 0.012))

	var drawer_mesh := BoxMesh.new()
	drawer_mesh.size = Vector3(size.x * 0.3, panel_height * 0.65, 0.02)
	_add_solid_part(body, drawer_mesh, trim, Vector3(-size.x * 0.28, size.y * 0.5 - panel_height * 0.6, front + 0.032))

	var knob_mesh := CylinderMesh.new()
	knob_mesh.top_radius = panel_height * 0.32
	knob_mesh.bottom_radius = panel_height * 0.36
	knob_mesh.height = 0.04
	knob_mesh.radial_segments = 20
	_add_solid_part(body, knob_mesh, trim, Vector3(size.x * 0.3, size.y * 0.5 - panel_height * 0.6, front + 0.04),
			Vector3(PI * 0.5, 0, 0))

	var door_y := -size.y * 0.09
	var door_radius := size.x * 0.33
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = door_radius * 0.82
	ring_mesh.outer_radius = door_radius
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 12
	_add_solid_part(body, ring_mesh, trim, Vector3(0, door_y, front + 0.03), Vector3(PI * 0.5, 0, 0))

	var glass_material := _plain(_color("machine_glass"), 0.08, 0.2)
	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = door_radius * 0.84
	glass_mesh.bottom_radius = door_radius * 0.84
	glass_mesh.height = 0.03
	glass_mesh.radial_segments = 32
	_add_solid_part(body, glass_mesh, glass_material, Vector3(0, door_y, front + 0.012), Vector3(PI * 0.5, 0, 0))


func _build_pipes() -> void:
	# A run of pipes under the ceiling; solid, so thrown socks bounce off them.
	var size := _room_size
	var material := _plain(_color("pipe"), 0.45, 0.7)
	var body := static_body("Pipes")
	add_child(body)
	for i in 3:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06 + i * 0.02
		mesh.bottom_radius = mesh.top_radius
		mesh.height = size.x
		mesh.radial_segments = 10
		mesh.rings = 1
		var pipe := _add_solid_part(body, mesh, material,
				Vector3(0, size.y - 0.5 - i * 0.04, -size.z * 0.5 + 0.5 + i * 0.32), Vector3(0, 0, PI * 0.5))
		pipe.name = "Pipe%d" % i
		pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_window(config: Dictionary) -> void:
	# A small high cellar window; its light follows the time of day (Daylight).
	var half := _room_size * 0.5
	var size := Vector2(config["size"][0], config["size"][1])
	var at := Vector3(float(config["x"]), float(config["y"]), -half.z)
	var color := Color(config["color"])

	var window := static_body("Window")
	window.position = at
	add_child(window)

	var glass_material := ShaderMaterial.new()
	glass_material.shader = WINDOW_SHADER
	glass_material.set_shader_parameter("sky", color)
	glass_material.set_shader_parameter("glow", float(config.get("glow", 1.5)))
	glass_material.set_shader_parameter("rain", float(config.get("rain", 1.0)))
	var glass_mesh := QuadMesh.new()
	glass_mesh.size = size
	_add_part(window, glass_mesh, glass_material, Vector3(0, 0, 0.01))

	var frame_material := _wood(2, 0.08, _color("window_frame"), _color("wood_dark"), false)
	var bar := 0.07
	var depth := 0.12
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(bar, size.y + bar * 2.0, depth)
		_add_solid_part(window, post, frame_material, Vector3(side * (size.x + bar) * 0.5, 0, depth * 0.5))
		var rail := BoxMesh.new()
		rail.size = Vector3(size.x + bar * 2.0, bar, depth)
		_add_solid_part(window, rail, frame_material, Vector3(0, side * (size.y + bar) * 0.5, depth * 0.5))
	var mullion := BoxMesh.new()
	mullion.size = Vector3(bar * 0.6, size.y, depth * 0.6)
	_add_solid_part(window, mullion, frame_material, Vector3(0, 0, depth * 0.3))
	var sill := BoxMesh.new()
	sill.size = Vector3(size.x + bar * 4.0, 0.05, 0.3)
	_add_solid_part(window, sill, frame_material, Vector3(0, -size.y * 0.5 - bar - 0.025, 0.15))

	var light := SpotLight3D.new()
	light.name = "Moonlight"
	light.position = Vector3(0, 0, 0.1)
	# Turned to face into the room (+Z), then tilted down towards the floor.
	light.rotation = Vector3(-deg_to_rad(float(config.get("tilt_degrees", 40.0))), PI, 0.0)
	light.light_color = color
	light.light_energy = float(config["energy"])
	light.spot_range = float(config["range"])
	light.spot_angle = float(config.get("spot_angle", 30.0))
	light.spot_angle_attenuation = 0.8
	light.light_volumetric_fog_energy = float(config.get("fog_energy", 2.0))
	light.light_specular = 0.3
	light.shadow_enabled = false
	window.add_child(light)
	_windows.append({"glass": glass_material, "light": light, "config": config})

	# Dust along the moonbeam, so the cone shows up as a slanted shaft.
	var beam_length := float(_data.get("dust", {}).get("window_reach", 5.0))
	_add_dust(window, light.transform * Transform3D(Basis(), Vector3(0, 0, -beam_length * 0.5)),
		Vector3(size.x * 0.6, size.y * 0.8, beam_length * 0.5), int(config.get("dust", 0)))


## Time of day from Daylight.sample(): sky in the glass, colour and strength of
## the shaft, a little more ambient light by day. Window values are night scale.
func apply_daylight(state: Dictionary) -> void:
	if state.is_empty():
		return
	var energy := float(state.energy)
	for entry: Dictionary in _windows:
		var config: Dictionary = entry.config
		var glass: ShaderMaterial = entry.glass
		var light: SpotLight3D = entry.light
		glass.set_shader_parameter("sky", state.sky)
		glass.set_shader_parameter("glow", float(config.get("glow", 1.5)) * float(state.glow))
		light.light_color = state.light
		light.light_energy = float(config["energy"]) * energy
		light.light_volumetric_fog_energy = float(config.get("fog_energy", 2.0)) * sqrt(energy)
	if _env:
		_env.ambient_light_energy = float(_data["environment"]["ambient_energy"]) * float(state.ambient)


func _build_beams() -> void:
	# Joists under the plank ceiling, running along X like the pipes.
	var size := _room_size
	var beam := vec3(_data["beam_size"])
	var spacing := float(_data["beam_spacing"])
	var material := _wood(0, 0.3, _color("beam"), _color("wood_dark"), false)
	var z := -size.z * 0.5 + spacing
	var index := 0
	var body := static_body("Beams")
	add_child(body)
	while z < size.z * 0.5 - spacing * 0.5:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x, beam.y, beam.z)
		var part := _add_solid_part(body, mesh, material, Vector3(0, size.y - beam.y * 0.5, z))
		part.name = "Beam%d" % index
		z += spacing
		index += 1


func _build_fairy_lights() -> void:
	# A sagging string of warm bulbs along the back wall; glow only, no real lights.
	var config: Dictionary = _data.get("fairy_lights", {})
	if config.is_empty():
		return
	var half := _room_size * 0.5
	var from_x := float(config["from_x"])
	var to_x := float(config["to_x"])
	var height := float(config["height"])
	var span := float(config["span"])
	var sag := float(config["sag"])
	var count := int(config["count"])
	var z := -half.z + 0.12

	var points := PackedVector3Array()
	for i in count:
		var x := lerpf(from_x, to_x, float(i) / (count - 1))
		var t := fposmod(x - from_x, span) / span
		points.append(Vector3(x, height - sag * 4.0 * t * (1.0 - t), z))

	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.028
	bulb_mesh.height = 0.07
	bulb_mesh.radial_segments = 8
	bulb_mesh.rings = 4
	# Instance colours are clamped to 0..1, so the shader multiplies them up for the glow.
	var bulb_shader := Shader.new()
	bulb_shader.code = "shader_type spatial;\nrender_mode unshaded;\nuniform float glow = 4.0;\n" \
			+ "void fragment() { ALBEDO = COLOR.rgb * glow; }\n"
	var bulb_material := ShaderMaterial.new()
	bulb_material.shader = bulb_shader
	bulb_material.set_shader_parameter("glow", float(config["glow"]))
	bulb_mesh.material = bulb_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = bulb_mesh
	multimesh.instance_count = count
	var tints: Array = config["colors"]
	for i in count:
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i] + Vector3.DOWN * 0.04))
		multimesh.set_instance_color(i, Color(tints[i % tints.size()]))
	var bulbs := MultiMeshInstance3D.new()
	bulbs.name = "FairyLights"
	bulbs.multimesh = multimesh
	bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulbs)

	var wire := ImmediateMesh.new()
	wire.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		wire.surface_add_vertex(point)
	wire.surface_end()
	var wire_material := StandardMaterial3D.new()
	wire_material.albedo_color = Color(0.05, 0.05, 0.04)
	var wire_instance := MeshInstance3D.new()
	wire_instance.mesh = wire
	wire_instance.material_override = wire_material
	wire_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wire_instance)


func _build_shelf() -> void:
	# Wooden shelf against the west wall with boxes and preserve jars.
	var config: Dictionary = _data.get("shelf", {})
	if config.is_empty():
		return
	var size := vec3(config["size"])
	var half := _room_size * 0.5
	var at := Vector3(-half.x + size.z * 0.5 + 0.02, 0, float(config["z"]))
	var boards := int(config["boards"])
	var wood := _wood(1, 0.14, _color("shelf"), _color("wood_dark"), false)

	# Every post, board, box and jar is solid on its own. Width (size.x) runs
	# along the wall (Z), depth (size.z) into the room (X).
	var body := static_body("Shelf")
	body.position = at
	add_child(body)

	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(size.z, size.y, 0.05)
		_add_solid_part(body, post, wood, Vector3(0, size.y * 0.5, side * (size.x * 0.5 - 0.025))).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var box_colors := [_color("cardboard"), _color("cardboard").darkened(0.15), _color("cardboard").lightened(0.1)]
	var jar_material := _plain(_color("jar"), 0.15)
	jar_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jar_material.albedo_color.a = 0.55
	var lid_material := _plain(_color("jar_lid"), 0.4, 0.6)
	for b in boards:
		var y := 0.12 + b * (size.y - 0.2) / (boards - 1)
		var board := BoxMesh.new()
		board.size = Vector3(size.z, 0.03, size.x)
		_add_solid_part(body, board, wood, Vector3(0, y, 0))
		if b == boards - 1:
			continue
		# Fill the board from one end to the other with a random mix of boxes and jars.
		var cursor := -size.x * 0.5 + 0.1
		while cursor < size.x * 0.5 - 0.3:
			if rng.randf() < 0.55:
				var box_size := Vector3(rng.randf_range(0.25, size.z * 0.9), rng.randf_range(0.18, 0.34), rng.randf_range(0.25, 0.45))
				var box := BoxMesh.new()
				box.size = box_size
				var color: Color = box_colors[rng.randi() % box_colors.size()]
				var box_at := Vector3(0, y + 0.015 + box_size.y * 0.5, cursor + box_size.z * 0.5)
				_add_solid_part(body, box, _plain(color, 0.95), box_at, Vector3(0, rng.randf_range(-0.08, 0.08), 0))
				cursor += box_size.z + rng.randf_range(0.04, 0.15)
			else:
				for j in rng.randi_range(2, 4):
					var jar := CylinderMesh.new()
					jar.top_radius = 0.05
					jar.bottom_radius = 0.055
					jar.height = rng.randf_range(0.14, 0.2)
					jar.radial_segments = 12
					var jar_at := Vector3(rng.randf_range(-0.08, 0.08), y + 0.015 + jar.height * 0.5, cursor + 0.06)
					_add_solid_part(body, jar, jar_material, jar_at)
					var lid := CylinderMesh.new()
					lid.top_radius = 0.052
					lid.bottom_radius = 0.052
					lid.height = 0.02
					lid.radial_segments = 12
					_add_solid_part(body, lid, lid_material, jar_at + Vector3.UP * (jar.height * 0.5 + 0.01))
					cursor += 0.13
				cursor += 0.08


func _build_lost_found() -> void:
	# Open cardboard crate where socks that escaped the room turn up again.
	var config: Dictionary = _data.get("lost_found", {})
	if config.is_empty():
		return
	var size := vec3(config["size"])
	var t := float(config["wall_thickness"])
	var body := StaticBody3D.new()
	body.name = "LostAndFound"
	body.position = vec3(config["position"])
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	var card := _plain(_color("cardboard"), 0.95)
	var inside := _plain(_color("cardboard").darkened(0.3), 0.95)
	var parts := [
		[Vector3(size.x, t, size.z), Vector3(0, t * 0.5, 0), inside],
		[Vector3(size.x, size.y, t), Vector3(0, size.y * 0.5, size.z * 0.5 - t * 0.5), card],
		[Vector3(size.x, size.y, t), Vector3(0, size.y * 0.5, -size.z * 0.5 + t * 0.5), card],
		[Vector3(t, size.y, size.z - t * 2.0), Vector3(size.x * 0.5 - t * 0.5, size.y * 0.5, 0), card],
		[Vector3(t, size.y, size.z - t * 2.0), Vector3(-size.x * 0.5 + t * 0.5, size.y * 0.5, 0), card],
	]
	for part: Array in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		_add_part(body, box, part[2], part[1]).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var shape := BoxShape3D.new()
		shape.size = part[0]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = part[1]
		body.add_child(collider)
	# The label faces the middle of the room.
	var label := Label3D.new()
	label.text = String(config["label_key"])
	label.pixel_size = float(config["label_pixel_size"])
	label.modulate = Color(config["label_color"])
	label.outline_size = 0
	label.shaded = true
	label.font_size = 48
	var toward := -body.position * Vector3(1, 0, 1)
	var front := Vector3(0, 0, signf(toward.z)) if absf(toward.z) >= absf(toward.x) else Vector3(signf(toward.x), 0, 0)
	var half_depth := size.z * 0.5 if front.z != 0.0 else size.x * 0.5
	label.position = front * (half_depth + 0.005) + Vector3.UP * size.y * 0.55
	body.add_child(label)
	label.look_at(label.global_position + front, Vector3.UP)
	label.rotate_object_local(Vector3.UP, PI)


func _build_clothesline() -> void:
	# A line across the washer corner with towels and shirts drying on it.
	var config: Dictionary = _data.get("clothesline", {})
	if config.is_empty():
		return
	var from := vec3(config["from"])
	var to := vec3(config["to"])
	var sag := float(config["sag"])
	var line_material := _plain(Color(0.85, 0.82, 0.75), 0.9)
	var segments := 10
	var previous := from
	for i in range(1, segments + 1):
		var t := float(i) / segments
		var point := from.lerp(to, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var cord := CylinderMesh.new()
		cord.top_radius = 0.006
		cord.bottom_radius = 0.006
		cord.height = previous.distance_to(point)
		cord.radial_segments = 4
		cord.rings = 1
		var piece := MeshInstance3D.new()
		piece.mesh = cord
		piece.material_override = line_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		piece.look_at_from_position((previous + point) * 0.5, point, Vector3.UP)
		piece.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		previous = point

	var direction := (to - from).normalized()
	var yaw := atan2(-direction.z, direction.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var colors: Array = config["laundry"]
	var t := 0.12
	var index := 0
	while t < 0.9:
		var width := rng.randf_range(0.35, 0.7)
		var height := rng.randf_range(0.45, 0.8)
		var at := from.lerp(to, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t) + height * 0.5)
		var cloth := QuadMesh.new()
		cloth.size = Vector2(width, height)
		cloth.subdivide_width = 20
		cloth.subdivide_depth = 2
		var material := ShaderMaterial.new()
		material.shader = CLOTH_SHADER
		material.set_shader_parameter("color", Color(colors[index % colors.size()]))
		material.set_shader_parameter("folds", roundf(width * 7.0))
		material.set_shader_parameter("seed", rng.randf() * 10.0)
		var part := _add_part(self, cloth, material, at)
		part.rotation = Vector3(rng.randf_range(-0.04, 0.04), yaw, rng.randf_range(-0.03, 0.03))
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Two pegs on top.
		for side in [-0.38, 0.38]:
			var peg := BoxMesh.new()
			peg.size = Vector3(0.018, 0.07, 0.025)
			var peg_part := _add_part(part, peg, _plain(_color("shelf"), 0.8), Vector3(side * width, height * 0.5, 0))
			peg_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t += (width + rng.randf_range(0.15, 0.4)) / from.distance_to(to)
		index += 1


func _build_ambience() -> void:
	# Quiet room tone, the washer churning, rain at the windows and now and then a drip or a pipe knock.
	var config: Dictionary = _data.get("ambience", {})
	if config.is_empty():
		return
	for entry: Dictionary in config.get("loops", []):
		var at: Variant = vec3(entry["position"]) if entry.has("position") else null
		Sfx.start_loop(String(entry["loop"]), self, at)
	_ambience_rng.randomize()
	for entry: Dictionary in config["random_sounds"]:
		var timer := Timer.new()
		timer.name = "%sTimer" % String(entry["sound"]).to_pascal_case()
		timer.one_shot = true
		add_child(timer)
		timer.timeout.connect(_on_ambient_timer.bind(timer, entry))
		timer.start(_ambience_rng.randf_range(float(entry["min_seconds"]), float(entry["max_seconds"])))


## Applies the graphics preset from the settings: screen-space shadows, fog
## detail, shadow filtering and how much dust floats in the light.
func apply_quality() -> void:
	var presets: Dictionary = _data.get("quality", {})
	if presets.is_empty() or Settings.graphics_quality == _quality:
		return
	_quality = Settings.graphics_quality
	var preset: Dictionary = presets.get(_quality, presets.get("high", {}))
	var config: Dictionary = _data["environment"]
	_env.ssao_enabled = bool(config["ssao"]) and bool(preset.get("ssao", true))
	_env.ssil_enabled = bool(config.get("ssil", false)) and bool(preset.get("ssil", true))
	_env.volumetric_fog_enabled = bool(config.get("volumetric_fog", false)) and bool(preset.get("volumetric_fog", true))
	RenderingServer.environment_set_ssao_quality(
		int(preset.get("ssao_quality", 2)) as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 2, 50.0, 300.0)
	var fog_volume: Array = preset.get("fog_volume", [64, 64])
	RenderingServer.environment_set_volumetric_fog_volume_size(int(fog_volume[0]), int(fog_volume[1]))
	RenderingServer.positional_soft_shadow_filter_set_quality(
		int(preset.get("soft_shadows", 2)) as RenderingServer.ShadowQuality)
	get_viewport().positional_shadow_atlas_size = int(preset.get("shadow_atlas", 4096))
	var dust_scale := float(preset.get("dust", 1.0))
	for emitter in _dust:
		var amount := roundi(int(emitter.get_meta("full_amount")) * dust_scale)
		emitter.visible = amount > 0
		emitter.emitting = amount > 0
		if amount > 0 and emitter.amount != amount:
			emitter.amount = amount
			emitter.restart()


func _add_dust(parent: Node3D, at: Transform3D, extents: Vector3, amount: int) -> void:
	if amount <= 0 or not _data.has("dust"):
		return
	var config: Dictionary = _data["dust"]
	if _dust_material == null:
		_dust_material = ShaderMaterial.new()
		_dust_material.shader = DUST_SHADER
		_dust_material.set_shader_parameter("tint", Color(config.get("tint", "#ffe6c4")))
		_dust_material.set_shader_parameter("strength", float(config.get("strength", 0.6)))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 180.0
	var speed: Array = config.get("speed", [0.005, 0.03])
	process.initial_velocity_min = float(speed[0])
	process.initial_velocity_max = float(speed[1])
	process.gravity = Vector3(0, -float(config.get("sink", 0.003)), 0)
	process.damping_min = 0.0
	process.damping_max = 0.002
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.0
	process.turbulence_noise_scale = 4.0
	process.turbulence_noise_speed_random = 0.1
	process.turbulence_influence_min = float(config.get("turbulence", 0.08)) * 0.5
	process.turbulence_influence_max = float(config.get("turbulence", 0.08))
	var size: Array = config.get("size", [0.008, 0.018])
	process.scale_min = float(size[0])
	process.scale_max = float(size[1])
	# Fade in and out so no mote pops into view.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color.WHITE)
	fade.add_point(0.8, Color.WHITE)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _dust_material

	var emitter := GPUParticles3D.new()
	emitter.name = "Dust"
	emitter.transform = at
	emitter.amount = amount
	emitter.lifetime = float(config.get("lifetime", 16.0))
	emitter.preprocess = emitter.lifetime
	emitter.randomness = 1.0
	emitter.local_coords = false
	emitter.process_material = process
	emitter.draw_pass_1 = quad
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(-extents - Vector3.ONE * 0.5, extents * 2.0 + Vector3.ONE)
	emitter.set_meta("full_amount", amount)
	parent.add_child(emitter)
	_dust.append(emitter)


func _on_ambient_timer(timer: Timer, entry: Dictionary) -> void:
	var spots: Array = entry["positions"]
	Sfx.play(String(entry["sound"]), vec3(spots[_ambience_rng.randi() % spots.size()]))
	timer.start(_ambience_rng.randf_range(float(entry["min_seconds"]), float(entry["max_seconds"])))


func _wood(axis: int, plank: float, color: Color, dark: Color, seams: bool = true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WOOD_SHADER
	material.set_shader_parameter("wood_color", color)
	material.set_shader_parameter("wood_dark", dark)
	material.set_shader_parameter("plank_width", plank)
	material.set_shader_parameter("grain_axis", axis)
	material.set_shader_parameter("seams", seams)
	return material


func _build_basket() -> void:
	basket = LaundryBasket.new()
	basket.name = "LaundryBasket"
	add_child(basket)
	basket.sock_entered.connect(func(body: RigidBody3D) -> void: sock_entered_basket.emit(body))
	basket.setup(_data, _color("basket"), WORLD_LAYER, SOCK_LAYER)


func _plain(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _add_part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part


## A visible part that is also solid: the collider is built from the same mesh
## and sits exactly where the mesh sits, so nothing hits thin air.
func _add_solid_part(body: CollisionObject3D, mesh: Mesh, material: Material, at: Vector3,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var part := _add_part(body, mesh, material, at)
	part.rotation = rot
	add_collider(body, mesh, part.transform)
	return part


## Static body on the world layer, for props.
static func static_body(node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	return body


static func add_collider(body: CollisionObject3D, mesh: Mesh, xform: Transform3D) -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	collider.shape = shape_for(mesh)
	collider.transform = xform
	body.add_child(collider)
	return collider


## Collision shape with exactly the outline of a primitive mesh. Boxes and
## straight cylinders use the matching primitive, tapered cylinders their
## convex hull, everything else (rings) the mesh triangles.
static func shape_for(mesh: Mesh) -> Shape3D:
	if mesh is BoxMesh:
		var box := BoxShape3D.new()
		box.size = (mesh as BoxMesh).size
		return box
	if mesh is CylinderMesh and is_equal_approx(mesh.top_radius, mesh.bottom_radius):
		var cylinder := CylinderShape3D.new()
		cylinder.radius = mesh.top_radius
		cylinder.height = mesh.height
		return cylinder
	if mesh is CylinderMesh:
		return mesh.create_convex_shape(true, false)
	if mesh is SphereMesh and is_equal_approx(mesh.radius * 2.0, mesh.height):
		var sphere := SphereShape3D.new()
		sphere.radius = mesh.radius
		return sphere
	return mesh.create_trimesh_shape()
