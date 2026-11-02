class_name Cellar
extends Node3D
## Builds the laundry cellar from data/world.json: shell, lights, props and basket.

const FLOOR_SHADER := preload("res://shaders/cellar_floor.gdshader")
const WALL_SHADER := preload("res://shaders/cellar_wall.gdshader")
const WORLD_LAYER := 1
const SOCK_LAYER := 2

signal sock_entered_basket(body: Node3D)

var basket: LaundryBasket

var _data: Dictionary
var _colors: Dictionary
var _room_size := Vector3.ONE


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
	_build_washing_machine()
	_build_pipes()
	_build_basket()


## Feet position and level facing for a fresh game (-Z points towards the pile).
func player_spawn() -> Transform3D:
	var from := vec3(_data["player_spawn"])
	var target := Vector3(0.0, from.y, 0.0)
	return Transform3D.IDENTITY.translated(from).looking_at(target, Vector3.UP)


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
	floor_material.set_shader_parameter("rug_a", _color("rug_a"))
	floor_material.set_shader_parameter("rug_b", _color("rug_b"))
	floor_material.set_shader_parameter("rug_c", _color("rug_c"))
	floor_material.set_shader_parameter("rug_radius", float(_data["rug_radius"]))

	var wall_material := ShaderMaterial.new()
	wall_material.shader = WALL_SHADER
	wall_material.set_shader_parameter("brick_color", _color("wall"))
	wall_material.set_shader_parameter("mortar_color", _color("wall_mortar"))
	wall_material.set_shader_parameter("band_color", _color("wall_band"))
	wall_material.set_shader_parameter("band_height", float(_data["wall_band_height"]))

	var ceiling_material := StandardMaterial3D.new()
	ceiling_material.albedo_color = _color("ceiling")
	ceiling_material.roughness = 1.0

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
	env.ssao_enabled = bool(config["ssao"])
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.0
	env.glow_enabled = bool(config["glow"])
	env.glow_intensity = 0.5
	env.glow_bloom = 0.02

	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	add_child(world)


func _build_lamp(config: Dictionary) -> void:
	var spot: Array = config["position"]
	var mount := Vector3(spot[0], _room_size.y, spot[1])
	var drop := float(config["drop"])
	var radius := float(config["shade_radius"])
	var color := Color(config["color"])

	var lamp := Node3D.new()
	lamp.name = "Lamp"
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
	var cord := MeshInstance3D.new()
	cord.mesh = cord_mesh
	cord.material_override = cord_material
	cord.position.y = -drop * 0.5
	lamp.add_child(cord)

	var shade_material := StandardMaterial3D.new()
	shade_material.albedo_color = _color("lamp_shade")
	shade_material.metallic = 0.4
	shade_material.roughness = 0.5
	shade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = radius * 0.16
	shade_mesh.bottom_radius = radius
	shade_mesh.height = radius * 0.6
	shade_mesh.radial_segments = 24
	shade_mesh.rings = 1
	shade_mesh.cap_top = true
	shade_mesh.cap_bottom = false
	var shade := MeshInstance3D.new()
	shade.mesh = shade_mesh
	shade.material_override = shade_material
	shade.position.y = -drop - radius * 0.3
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(shade)

	var bulb_material := StandardMaterial3D.new()
	bulb_material.albedo_color = color
	bulb_material.emission_enabled = true
	bulb_material.emission = color
	bulb_material.emission_energy_multiplier = 6.0
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = radius * 0.22
	bulb_mesh.height = radius * 0.44
	bulb_mesh.radial_segments = 12
	bulb_mesh.rings = 6
	var bulb := MeshInstance3D.new()
	bulb.mesh = bulb_mesh
	bulb.material_override = bulb_material
	bulb.position.y = -drop - radius * 0.5
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(bulb)

	var light := OmniLight3D.new()
	light.position.y = -drop - radius * 0.7
	light.light_color = color
	light.light_energy = float(config["energy"])
	light.omni_range = float(config["range"])
	light.omni_attenuation = float(config["attenuation"])
	light.shadow_enabled = bool(config["shadow"])
	lamp.add_child(light)


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
	_add_part(body, panel_mesh, _plain(_color("machine_panel"), 0.5),
			Vector3(0, size.y * 0.5 - panel_height * 0.6, front + 0.012))

	var drawer_mesh := BoxMesh.new()
	drawer_mesh.size = Vector3(size.x * 0.3, panel_height * 0.65, 0.02)
	_add_part(body, drawer_mesh, trim, Vector3(-size.x * 0.28, size.y * 0.5 - panel_height * 0.6, front + 0.032))

	var knob_mesh := CylinderMesh.new()
	knob_mesh.top_radius = panel_height * 0.32
	knob_mesh.bottom_radius = panel_height * 0.36
	knob_mesh.height = 0.04
	knob_mesh.radial_segments = 20
	var knob := _add_part(body, knob_mesh, trim, Vector3(size.x * 0.3, size.y * 0.5 - panel_height * 0.6, front + 0.04))
	knob.rotation.x = PI * 0.5

	var door_y := -size.y * 0.09
	var door_radius := size.x * 0.33
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = door_radius * 0.82
	ring_mesh.outer_radius = door_radius
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 12
	var ring := _add_part(body, ring_mesh, trim, Vector3(0, door_y, front + 0.03))
	ring.rotation.x = PI * 0.5

	var glass_material := _plain(_color("machine_glass"), 0.08, 0.2)
	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = door_radius * 0.84
	glass_mesh.bottom_radius = door_radius * 0.84
	glass_mesh.height = 0.03
	glass_mesh.radial_segments = 32
	var glass := _add_part(body, glass_mesh, glass_material, Vector3(0, door_y, front + 0.012))
	glass.rotation.x = PI * 0.5


func _build_pipes() -> void:
	# A run of pipes under the ceiling, only for looks.
	var size := _room_size
	var material := _plain(_color("pipe"), 0.45, 0.7)
	for i in 3:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06 + i * 0.02
		mesh.bottom_radius = mesh.top_radius
		mesh.height = size.x
		mesh.radial_segments = 10
		mesh.rings = 1
		var pipe := MeshInstance3D.new()
		pipe.name = "Pipe%d" % i
		pipe.mesh = mesh
		pipe.material_override = material
		pipe.rotation.z = PI * 0.5
		pipe.position = Vector3(0, size.y - 0.35 - i * 0.04, -size.z * 0.5 + 0.5 + i * 0.32)
		pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pipe)


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
