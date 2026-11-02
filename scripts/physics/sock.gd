class_name Sock
extends RigidBody3D
## One sock in the pile. No mesh of its own: SockField draws it through the
## SockRenderer and gets told here when it falls asleep or wakes up.

var sock_id := -1
var field: SockField


func _init() -> void:
	sleeping_state_changed.connect(_on_sleeping_state_changed)


func _on_sleeping_state_changed() -> void:
	if field != null:
		field._on_sock_sleep_changed(self)
