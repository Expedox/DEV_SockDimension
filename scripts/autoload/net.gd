extends Node
## LAN watching for two players over ENet. Each plays their own game (any mode,
## any seed); the other player's cellar is drawn above a glass ceiling
## (RemoteCellar). The connection lives across menus and runs. Only the player
## pose and socks whose transform changed travel; settings in data/net.json.

signal lobby_changed
## The rival entered a run (mode_id set) or left it (mode_id empty).
signal rival_run_changed
signal rival_joined
signal rival_left
## Versus speedrun: both piles are ready, start the countdown.
signal versus_go
## Versus speedrun: the rival finished (versus_rival_time) or gave up.
signal versus_rival_done
## The rival is busy in their own run and could not take a versus invite.
signal versus_declined

const HIDDEN_BIT := 0x8000
const BYTES_PER_SOCK := 22 # u16 id, 3 x f32 origin, 4 x f16 rotation

var hosting := false
var rival_id := 0
## Lobby text key for the menu, e.g. LAN_WAITING.
var status_key := ""
## The rival's current run: enough to build the same SockSet on this side.
var rival_mode := ""
var rival_seed := 0
## Latest pose of the other player (feet position, yaw, pitch) and their count.
var rival_position := Vector3.ZERO
var rival_yaw := 0.0
var rival_pitch := 0.0
var rival_found := 0
var rival_seen := false
## Versus speedrun state, reset by start_versus() and an incoming invite.
var versus_self_ready := false
var versus_rival_ready := false
## Rival's finishing time in seconds, -1 while they are still running.
var versus_rival_time := -1.0
var versus_rival_gave_up := false

var _cfg: Dictionary
## sock_id -> Transform3D, or null for hidden; drained by RemoteCellar.
var _incoming := {}
var _renderer: SockRenderer
var _player: Node3D
var _send_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cfg = Config.net
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: _set_status("LAN_CONNECTED"))
	# Never swap the peer inside its own signal; that crashes ENet.
	multiplayer.connection_failed.connect(_drop.bind("LAN_FAILED"), CONNECT_DEFERRED)
	multiplayer.server_disconnected.connect(_on_peer_disconnected.bind(1))


func port() -> int:
	return int(_cfg.get("port", 24680))


func is_connected_lan() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer


func host() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port(), 1) != OK:
		_set_status("LAN_HOST_FAILED")
		return false
	multiplayer.multiplayer_peer = peer
	hosting = true
	_set_status("LAN_WAITING")
	return true


func join(address: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address.strip_edges(), port()) != OK:
		_set_status("LAN_FAILED")
		return false
	multiplayer.multiplayer_peer = peer
	_set_status("LAN_CONNECTING")
	return true


## Closes the connection and forgets the rival. Safe to call any time.
func leave() -> void:
	var had_rival := has_rival()
	if is_connected_lan():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	hosting = false
	rival_id = 0
	_forget_rival_run()
	_set_status("")
	if had_rival:
		rival_left.emit()


func has_rival() -> bool:
	return rival_id != 0


## True while the rival plays a run we can draw.
func rival_in_run() -> bool:
	return has_rival() and not rival_mode.is_empty()


## Own IPv4 addresses in the local network, for the host to read out.
func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			out.append(address)
	return out


## The game hands over what to send while a run is live: its sock renderer and player.
func attach(renderer: SockRenderer, player: Node3D) -> void:
	_renderer = renderer
	_player = player
	renderer.track_changes = true
	_announce_run()
	# Our copy of their cellar starts empty: ask for the whole pile again.
	if has_rival():
		_send_all.rpc_id(rival_id)


func detach(renderer: SockRenderer) -> void:
	if renderer != _renderer:
		return
	if is_instance_valid(_renderer):
		_renderer.track_changes = false
	_renderer = null
	_player = null
	if has_rival():
		_run.rpc_id(rival_id, "", 0)


## Starts a versus speedrun on both sides: same size, same seed.
func start_versus(mode_id: String) -> bool:
	if not has_rival():
		return false
	var seed_value := randi() & 0x7fffffff
	reset_versus()
	_versus_start.rpc_id(rival_id, mode_id, seed_value)
	GameState.start_speedrun(mode_id, seed_value, true)
	return true


func reset_versus() -> void:
	versus_self_ready = false
	versus_rival_ready = false
	versus_rival_time = -1.0
	versus_rival_gave_up = false


## Our pile is poured; the countdown starts once the rival's is too.
func versus_ready() -> void:
	versus_self_ready = true
	if has_rival():
		_versus_ready.rpc_id(rival_id)
	_check_go()


func versus_finished(time: float) -> void:
	if has_rival():
		_versus_finished.rpc_id(rival_id, time)


func _check_go() -> void:
	if versus_self_ready and (versus_rival_ready or not has_rival()):
		versus_self_ready = false
		versus_rival_ready = false
		versus_go.emit()


@rpc("any_peer", "call_remote", "reliable", 2)
func _versus_start(mode_id: String, seed_value: int) -> void:
	if multiplayer.get_remote_sender_id() != rival_id or not Config.is_speedrun(mode_id):
		return
	# A finished run may be left; one still being played is not thrown away.
	if GameState.in_run() and not GameState.completed:
		_versus_busy.rpc_id(rival_id)
		return
	reset_versus()
	GameState.start_speedrun(mode_id, seed_value, true)


@rpc("any_peer", "call_remote", "reliable", 2)
func _versus_busy() -> void:
	if multiplayer.get_remote_sender_id() == rival_id:
		versus_declined.emit()


@rpc("any_peer", "call_remote", "reliable", 2)
func _versus_ready() -> void:
	if multiplayer.get_remote_sender_id() != rival_id:
		return
	versus_rival_ready = true
	_check_go()


@rpc("any_peer", "call_remote", "reliable", 2)
func _versus_finished(time: float) -> void:
	if multiplayer.get_remote_sender_id() != rival_id:
		return
	versus_rival_time = time
	versus_rival_done.emit()


## The rival left the versus run before finishing it.
func _rival_quit_versus() -> void:
	if GameState.versus and versus_rival_time < 0.0 and not versus_rival_gave_up:
		versus_rival_gave_up = true
		versus_rival_done.emit()
		# Nobody left to wait for.
		_check_go()


## Hands the changed rival socks to the caller and forgets them.
func take_incoming() -> Dictionary:
	var out := _incoming
	_incoming = {}
	return out


func _process(delta: float) -> void:
	if not has_rival() or not is_instance_valid(_player):
		return
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = 1.0 / float(_cfg.get("send_hz", 20))
	_pose.rpc_id(rival_id, _player.global_position, _player.get("_yaw"), _player.get("_pitch"), GameState.pairs_found)
	if is_instance_valid(_renderer):
		var ids := _renderer.take_changes(int(_cfg.get("socks_per_send", 600)))
		if not ids.is_empty():
			_socks.rpc_id(rival_id, encode_socks(_renderer, ids))


## Tells the rival which run we play and resends the whole pile.
func _announce_run() -> void:
	if not has_rival() or not is_instance_valid(_renderer):
		return
	_run.rpc_id(rival_id, GameState.mode_id, GameState.seed_value)
	_renderer.mark_all_changed()


# Run and socks share channel 2, so socks never arrive before the run they belong to.
@rpc("any_peer", "call_remote", "reliable", 2)
func _run(mode_id: String, seed_value: int) -> void:
	if multiplayer.get_remote_sender_id() != rival_id:
		return
	# Leaving the versus run itself counts as giving up; leaving an older run does not.
	var left_versus := mode_id.is_empty() and rival_mode == GameState.mode_id and rival_seed == GameState.seed_value
	_forget_rival_run()
	if left_versus:
		_rival_quit_versus()
	if mode_id.is_empty() or Config.mode(mode_id).is_empty():
		rival_mode = ""
	else:
		rival_mode = mode_id
		rival_seed = seed_value
	rival_run_changed.emit()


@rpc("any_peer", "call_remote", "reliable", 2)
func _socks(data: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != rival_id or rival_mode.is_empty():
		return
	decode_socks(data, _incoming)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _pose(at: Vector3, yaw: float, pitch: float, found: int) -> void:
	if multiplayer.get_remote_sender_id() != rival_id:
		return
	rival_position = at
	rival_yaw = yaw
	rival_pitch = pitch
	rival_found = found
	rival_seen = true


@rpc("any_peer", "call_remote", "reliable", 2)
func _send_all() -> void:
	if multiplayer.get_remote_sender_id() == rival_id and is_instance_valid(_renderer):
		_renderer.mark_all_changed()


@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int) -> void:
	if protocol != int(_cfg.get("protocol", 1)):
		_set_status("LAN_VERSION_MISMATCH")


static func encode_socks(renderer: SockRenderer, ids: PackedInt32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(ids.size() * BYTES_PER_SOCK)
	var at := 0
	for sock in ids:
		var hidden := renderer.is_hidden(sock)
		data.encode_u16(at, sock | (HIDDEN_BIT if hidden else 0))
		if not hidden:
			var xform := renderer.get_sock_transform(sock)
			var q := xform.basis.orthonormalized().get_rotation_quaternion()
			data.encode_float(at + 2, xform.origin.x)
			data.encode_float(at + 6, xform.origin.y)
			data.encode_float(at + 10, xform.origin.z)
			data.encode_half(at + 14, q.x)
			data.encode_half(at + 16, q.y)
			data.encode_half(at + 18, q.z)
			data.encode_half(at + 20, q.w)
		at += BYTES_PER_SOCK
	return data


static func decode_socks(data: PackedByteArray, into: Dictionary) -> void:
	for at in range(0, data.size() - BYTES_PER_SOCK + 1, BYTES_PER_SOCK):
		var word := data.decode_u16(at)
		var sock := word & ~HIDDEN_BIT
		if word & HIDDEN_BIT:
			into[sock] = null
			continue
		var q := Quaternion(data.decode_half(at + 14), data.decode_half(at + 16),
				data.decode_half(at + 18), data.decode_half(at + 20)).normalized()
		into[sock] = Transform3D(Basis(q), Vector3(data.decode_float(at + 2),
				data.decode_float(at + 6), data.decode_float(at + 10)))


func _on_peer_connected(id: int) -> void:
	if rival_id != 0:
		return
	rival_id = id
	_hello.rpc_id(id, int(_cfg.get("protocol", 1)))
	_set_status("LAN_CONNECTED")
	rival_joined.emit()
	_announce_run()


func _on_peer_disconnected(id: int) -> void:
	if id != rival_id:
		return
	rival_id = 0
	_forget_rival_run()
	_rival_quit_versus()
	rival_left.emit()
	if hosting:
		_set_status("LAN_WAITING")
	else:
		_drop.call_deferred("LAN_LEFT")


func _drop(status: String) -> void:
	leave()
	_set_status(status)


func _forget_rival_run() -> void:
	var had_run := not rival_mode.is_empty()
	rival_mode = ""
	rival_seed = 0
	rival_seen = false
	rival_found = 0
	_incoming.clear()
	if had_run:
		rival_run_changed.emit()


func _set_status(key: String) -> void:
	status_key = key
	lobby_changed.emit()
