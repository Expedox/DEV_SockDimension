class_name RemoteCellar
extends Node3D
## LAN: the other player's cellar, seen from below through the glass ceiling.
## Their floor lies on top of our glass, so this node sits one room height up.
## Their run (mode and seed) arrives first, so we build the same SockSet and
## sock ids match on both sides.

var _cellar: Cellar
var _renderer: SockRenderer
var _avatar: Node3D
var _head: Node3D
var _lights: Array[OmniLight3D] = []
var _smoothing := 14.0


func setup(cellar: Cellar) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cellar = cellar
	var cfg: Dictionary = Config.net
	_smoothing = float(cfg.get("rival_smoothing", 14.0))
	position = Vector3(0.0, cellar.room_bounds().size.y + float(cfg.get("glass_thickness", 0.06)), 0.0)

	# Our lamps hang below the glass; the rival's room gets a few soft lights.
	var tint := Color(cfg.get("rival_light_color", "#ffd9a8"))
	for entry: Dictionary in cfg.get("rival_lights", []):
		var light := OmniLight3D.new()
		var p: Array = entry.position
		light.position = Vector3(p[0], p[1], p[2])
		light.omni_range = float(entry.range)
		light.light_energy = float(entry.energy)
		light.light_color = tint
		add_child(light)
		_lights.append(light)

	_avatar = _build_avatar(Color(cfg.get("rival_color", "#d9734e")))
	add_child(_avatar)
	Net.rival_run_changed.connect(_rebuild)
	Net.rival_left.connect(_rebuild)
	_rebuild()


## Drops the old rival socks and builds the ones of the rival's current run.
func _rebuild() -> void:
	if _renderer:
		_renderer.queue_free()
		_renderer = null
	var live := Net.rival_in_run()
	_cellar.set_glass_ceiling(live)
	visible = live
	_avatar.visible = false
	if not live:
		return
	var mode := Config.mode(Net.rival_mode)
	var sock_set := SockSet.generate(Net.rival_seed, int(mode.pairs), float(mode.near_pair_share))
	if sock_set == null:
		return
	var size: Array = mode.get("room_size", Config.world.room_size)
	var room := Vector3(size[0], size[1], size[2])
	_renderer = SockRenderer.new()
	_renderer.name = "RivalSocks"
	add_child(_renderer)
	_renderer.setup(sock_set, AABB(Vector3(-room.x * 0.5, -1.0, -room.z * 0.5), room + Vector3.UP),
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _process(delta: float) -> void:
	if not visible or _renderer == null:
		return
	var changes := Net.take_incoming()
	var count := _renderer.sock_count()
	for sock: int in changes:
		if sock >= count:
			continue
		var xform: Variant = changes[sock]
		if xform == null:
			_renderer.hide_sock(sock)
		else:
			_renderer.set_sock_transform(sock, xform)

	if not Net.rival_seen:
		return
	var blend := 1.0 - exp(-_smoothing * delta)
	if not _avatar.visible:
		_avatar.visible = true
		_avatar.position = Net.rival_position
		blend = 1.0
	_avatar.position = _avatar.position.lerp(Net.rival_position, blend)
	_avatar.rotation.y = lerp_angle(_avatar.rotation.y, Net.rival_yaw, blend)
	_head.rotation.x = lerp_angle(_head.rotation.x, Net.rival_pitch, blend)


## A soft figure: body, head and a little cap brim that shows where they look.
func _build_avatar(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Rival"
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = color
	cloth.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#f0c9a4")
	skin.roughness = 0.8
	var player_cfg: Dictionary = Config.player
	var height := float(player_cfg.get("capsule_height", 1.8))
	var radius := float(player_cfg.get("capsule_radius", 0.3))

	var body := CapsuleMesh.new()
	body.radius = radius
	body.height = height * 0.78
	var body_part := MeshInstance3D.new()
	body_part.mesh = body
	body_part.material_override = cloth
	body_part.position.y = body.height * 0.5
	root.add_child(body_part)

	_head = Node3D.new()
	_head.position.y = float(player_cfg.get("eye_height", 1.6))
	root.add_child(_head)
	var head := SphereMesh.new()
	head.radius = radius * 0.62
	head.height = radius * 1.24
	var head_part := MeshInstance3D.new()
	head_part.mesh = head
	head_part.material_override = skin
	_head.add_child(head_part)
	var brim := BoxMesh.new()
	brim.size = Vector3(radius * 0.9, 0.04, radius * 0.7)
	var brim_part := MeshInstance3D.new()
	brim_part.mesh = brim
	brim_part.material_override = cloth
	brim_part.position = Vector3(0.0, radius * 0.38, -radius * 0.6) # -Z is forward
	_head.add_child(brim_part)
	return root
