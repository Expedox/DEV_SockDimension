class_name PairController
extends Node
## The pair action: checks held against aimed sock, then sends a match to the
## basket or reports a miss. A match only counts on landing. Until then both
## socks stay in the field's save data, so a save in mid-flight loses nothing.

const DATA_PATH := "res://data/pairs.json"

# Player, SockField and Sock are used by their NOTES.md interface only, so this
# script does not depend on those scripts being loaded first.
var _player: Node
var _field: Node
var _basket: LaundryBasket
var _socks: SockSet
var _tuning: Dictionary
var _next_attempt_msec := 0
## Socks thrown and not touched since; only these count as basket shots.
var _thrown := {}
var _lifted_after_load := false


func _ready() -> void:
	_tuning = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	Events.sock_thrown.connect(_on_sock_thrown)
	Events.sock_grabbed.connect(_on_sock_grabbed)


func setup(player: Node, field: Node, cellar: Cellar, socks: SockSet) -> void:
	_player = player
	_field = field
	_basket = cellar.basket
	_socks = socks
	_basket.set_pair_count(GameState.pairs_found)
	_basket.sock_entered.connect(_on_sock_entered_basket)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pair") and not event.is_echo():
		_try_pair()


func _try_pair() -> void:
	if _player == null or not GameState.running:
		return
	var held = _player.held_sock()
	var aimed = _player.aimed_sock()
	if held == null or aimed == null:
		return
	if _socks.is_match(held.sock_id, aimed.sock_id):
		_send_to_basket(held, aimed)
	elif Time.get_ticks_msec() >= _next_attempt_msec:
		_miss(held, aimed)


func _miss(held, aimed) -> void:
	_next_attempt_msec = Time.get_ticks_msec() + int(float(_tuning.attempt_cooldown_seconds) * 1000.0)
	_player.wiggle_held()
	Sfx.play("mismatch")
	GameState.register_mismatch(_socks.is_near_miss(held.sock_id, aimed.sock_id))


func _send_to_basket(held, aimed) -> void:
	var starts: Array[Transform3D] = [held.global_transform, aimed.global_transform]
	var info := _socks.sock_info(held.sock_id)
	_player.release_held()
	_field.set_aside(held)
	_field.set_aside(aimed)
	Sfx.play("match")

	var flight := PairFlight.new()
	add_child(flight)
	flight.landed.connect(_on_flight_landed.bind(held, aimed, info))
	flight.launch(_field.renderer, PackedInt32Array([held.sock_id, aimed.sock_id]), starts,
			PackedColorArray([SockCatalog.colors()[info.base_color], SockCatalog.colors()[info.accent_color]]),
			_basket.mouth(), _basket.get_pile_top(), _tuning)


func _on_flight_landed(a, b, info: Dictionary) -> void:
	_field.remove_pair(a, b)
	_basket.receive_pair()
	_lift_basket_socks()
	Sfx.play("plop")
	GameState.register_match(info.pair_id, info.base_color, info.pattern)


## The pile grows under loose socks lying in the basket; keep them on top.
func _lift_basket_socks() -> void:
	if _field.has_method("lift_onto"):
		_field.lift_onto(_basket.global_position, _basket.inner_radius(), _basket.floor_height())


func _process(_delta: float) -> void:
	# Once after loading: socks from older saves may sit inside the pile.
	if not _lifted_after_load and _field != null and _field.has_method("is_ready") and _field.is_ready():
		_lifted_after_load = true
		_lift_basket_socks()


func _on_sock_thrown(sock_id: int) -> void:
	_thrown[sock_id] = true


func _on_sock_grabbed(sock_id: int) -> void:
	_thrown.erase(sock_id)


func _on_sock_entered_basket(body: RigidBody3D) -> void:
	var sock = _field.sock_at(body)
	if sock != null and _thrown.erase(sock.sock_id):
		Events.sock_in_basket.emit(sock.sock_id)
