extends Node3D
## Walks the player headless into the pile and over loose socks and prints
## how far it got and how high it climbed:
##   godot --headless --fixed-fps 60 --path . res://scenes/dev/walk_test.tscn

var _field: SockField
var _player: Player


func _ready() -> void:
	var mode := Config.mode("laundry_day")
	add_child(load("res://scenes/cellar.tscn").instantiate())
	_field = SockField.new()
	add_child(_field)
	_field.pour(SockSet.generate(5, int(mode.pairs), 0.2), mode)
	await Events.pile_ready
	# A few loose socks and a small clump on the path in front of the pile.
	_player = load("res://scenes/player.tscn").instantiate()
	add_child(_player)
	_player.setup(_field)
	GameState.running = true
	var top := _field.surface_height()
	print("Pile summit %.2f m" % top.y)

	await _walk("loose socks and pile edge", Vector3(0, 0.05, 7.5), Vector3(0, 0, -1), 1.2)
	await _walk("into the pile towards the top", Vector3(0, 0.05, 4.5), Vector3(0, 0, -1), 3.0)
	get_tree().quit()


func _walk(label: String, from: Vector3, direction: Vector3, seconds: float) -> void:
	_player.place(Transform3D(Basis.looking_at(direction), from))
	await get_tree().physics_frame
	Input.action_press("move_forward")
	var highest := from.y
	var frames := int(seconds * 60.0)
	for i in frames:
		await get_tree().physics_frame
		highest = maxf(highest, _player.global_position.y)
	Input.action_release("move_forward")
	var p := _player.global_position
	print("%s: walked %.2f m of %.2f m, now at height %.2f, highest %.2f" % [label,
			((p - from) * Vector3(1, 0, 1)).length(), float(Config.player.speed) * seconds, p.y, highest])
