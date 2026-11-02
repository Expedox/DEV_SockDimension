extends RefCounted
## Stand-ins for the player and the sock field, following NOTES.md.


class FakeSock extends RigidBody3D:
	var sock_id := -1


class FakePlayer extends Node:
	var held: Node = null
	var aimed: Node = null
	var wiggles := 0

	func held_sock() -> Node:
		return held

	func aimed_sock() -> Node:
		return aimed

	func release_held() -> void:
		held = null

	func wiggle_held() -> void:
		wiggles += 1


class FakeField extends Node:
	var renderer: SockRenderer
	var set_aside_ids := PackedInt32Array()
	var removed_ids := PackedInt32Array()

	func set_aside(sock) -> void:
		set_aside_ids.append(sock.sock_id)

	func remove_pair(a, b) -> void:
		removed_ids.append(a.sock_id)
		removed_ids.append(b.sock_id)

	func sock_at(collider: Object):
		return collider if collider is FakeSock else null


class FakeWorld extends RefCounted:
	func capture_world() -> Dictionary:
		return {"socks": {"ids": PackedInt32Array([1, 2])}, "player": {"held": -1}}
