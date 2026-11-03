extends Node
## Starts a real laundry day run headless and quits once the pile is ready:
##   godot --headless --path . res://scenes/dev/smoke_run.tscn

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene != self:
		return
	# Survive the scene change by moving under the root as a plain node.
	var keeper := Node.new()
	keeper.set_script(get_script())
	keeper.set_meta("keeper", true)
	get_tree().root.add_child.call_deferred(keeper)
	GameState.start_new.call_deferred("laundry_day", "7")


func _enter_tree() -> void:
	if not has_meta("keeper"):
		return
	Events.pile_ready.connect(_on_ready_pile)


func _on_ready_pile() -> void:
	await get_tree().create_timer(1.0).timeout
	var field := get_tree().get_first_node_in_group("sock_field") as SockField
	print("SMOKE ready: %d socks, pour %.1f s, summit %s, saved %d" % [field.body_count(),
			field.pour_seconds, field.surface_height(), field.capture().ids.size()])
	get_tree().quit()
