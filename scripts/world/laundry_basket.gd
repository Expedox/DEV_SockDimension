class_name LaundryBasket
extends Node3D
## The basket: open-top collider, detection volume and a pile that grows with each pair.

## A rigid body (a thrown single sock) dropped into the opening.
signal sock_entered(body: RigidBody3D)
## A finished pair arrived via receive_pair().
signal pair_received(total: int)

const SHADER := preload("res://shaders/cellar_basket.gdshader")

var pairs_in_basket := 0

var _config: Dictionary
var _pile: MeshInstance3D
var _pile_base_y := 0.0


func setup(config: Dictionary, color: Color, world_layer: int, detect_mask: int) -> void:
	_config = config
	position = Cellar.vec3(config["basket_position"])
	_build_visual(color)
	_build_colliders(world_layer)
	_build_detector(detect_mask)
	set_pair_count(0)


## World point a rolled-up pair should fly to.
func mouth() -> Vector3:
	return global_position + Vector3.UP * float(_config["basket_height"]) * 1.15


## World point at the current top of the pile, for the landing of a flight.
func get_pile_top() -> Vector3:
	return _pile.global_position + Vector3.UP * _pile.scale.y * 0.5


## Call when a pair lands, after its flight.
func receive_pair() -> void:
	set_pair_count(pairs_in_basket + 1)
	pair_received.emit(pairs_in_basket)


## Restores the pile height, e.g. after loading a save.
func set_pair_count(count: int) -> void:
	pairs_in_basket = count
	var fill := minf(count * float(_config["basket_pile_step"]), float(_config["basket_pile_max"]))
	var height := maxf(fill, 0.001) * float(_config["basket_height"])
	_pile.visible = count > 0
	_pile.scale = Vector3(1.0, height, 1.0)
	_pile.position.y = _pile_base_y + height * 0.5


func _build_visual(color: Color) -> void:
	var height := float(_config["basket_height"])
	var r_bottom := float(_config["basket_radius_bottom"])
	var r_top := float(_config["basket_radius"])

	var shell_material := ShaderMaterial.new()
	shell_material.shader = SHADER
	shell_material.set_shader_parameter("color", color)
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = r_top
	shell_mesh.bottom_radius = r_bottom
	shell_mesh.height = height
	shell_mesh.radial_segments = 32
	shell_mesh.rings = 1
	shell_mesh.cap_top = false
	shell_mesh.cap_bottom = false
	var shell := MeshInstance3D.new()
	shell.mesh = shell_mesh
	shell.material_override = shell_material
	shell.position.y = height * 0.5
	add_child(shell)

	var solid := StandardMaterial3D.new()
	solid.albedo_color = color
	solid.roughness = 0.45

	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = r_top - 0.03
	rim_mesh.outer_radius = r_top + 0.03
	rim_mesh.rings = 32
	rim_mesh.ring_segments = 8
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = solid
	rim.position.y = height
	add_child(rim)

	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = r_bottom
	base_mesh.bottom_radius = r_bottom
	base_mesh.height = 0.03
	base_mesh.radial_segments = 32
	var base := MeshInstance3D.new()
	base.mesh = base_mesh
	base.material_override = solid
	base.position.y = 0.015
	add_child(base)

	# Unit-height dome scaled up as pairs arrive.
	var pile_material := StandardMaterial3D.new()
	pile_material.albedo_color = Color(0.82, 0.76, 0.68)
	pile_material.roughness = 1.0
	var pile_mesh := CylinderMesh.new()
	pile_mesh.top_radius = r_bottom * 0.92
	pile_mesh.bottom_radius = r_bottom * 0.98
	pile_mesh.height = 1.0
	pile_mesh.radial_segments = 24
	_pile = MeshInstance3D.new()
	_pile.mesh = pile_mesh
	_pile.material_override = pile_material
	_pile_base_y = 0.03
	add_child(_pile)


func _build_colliders(world_layer: int) -> void:
	var height := float(_config["basket_height"])
	var r_bottom := float(_config["basket_radius_bottom"])
	var r_top := float(_config["basket_radius"])
	var thickness := float(_config["basket_wall_thickness"])
	var segments := int(_config["basket_wall_segments"])

	var body := StaticBody3D.new()
	body.name = "BasketBody"
	body.collision_layer = world_layer
	body.collision_mask = 0
	add_child(body)

	# The visible shell is a thin surface with a 3 cm rim; the wall reaches as
	# far out as the rim and the rest of its thickness goes inwards, so thrown
	# socks cannot tunnel through and nothing outside stops in mid-air.
	var outside := 0.03
	var slant := atan2(r_top - r_bottom, height)
	var radius := (r_top + r_bottom) * 0.5 + outside - thickness * 0.5
	# Chord boxes: wide enough to close the gaps between neighbours.
	var width := 2.0 * (r_top + outside) * tan(PI / segments) * 1.02
	for i in segments:
		var angle := TAU * i / segments
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, height / cos(slant), thickness)
		var part := CollisionShape3D.new()
		part.shape = shape
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, slant)
		part.transform = Transform3D(basis, Basis(Vector3.UP, angle) * Vector3(0, height * 0.5, radius))
		body.add_child(part)

	# Same size as the visible base disc.
	var bottom := CollisionShape3D.new()
	var bottom_shape := CylinderShape3D.new()
	bottom_shape.radius = r_bottom
	bottom_shape.height = 0.03
	bottom.shape = bottom_shape
	bottom.position.y = 0.015
	body.add_child(bottom)


func _build_detector(detect_mask: int) -> void:
	var height := float(_config["basket_height"])
	var inset := float(_config["basket_detect_inset"])

	var area := Area3D.new()
	area.name = "Detector"
	area.collision_layer = 0
	area.collision_mask = detect_mask
	area.monitorable = false
	area.body_entered.connect(_on_body_entered)
	add_child(area)

	var shape := CylinderShape3D.new()
	shape.radius = float(_config["basket_radius_bottom"]) - inset
	shape.height = height - inset
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = (height - inset) * 0.5 + 0.03
	area.add_child(collider)


func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		sock_entered.emit(body)
