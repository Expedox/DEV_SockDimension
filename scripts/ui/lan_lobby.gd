class_name LanLobby
extends Control
## LAN: host or join a second player in the same network. Each player then
## plays their own game and sees the other one above a glass ceiling. Closing
## this screen keeps the connection; Disconnect ends it.

signal closed

const LAST_ADDRESS_PATH := "user://lan.cfg"

var _address: LineEdit
var _status: Label
var _addresses: Label
var _host_button: Button
var _join_button: Button
var _leave_button: Button


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(MenuBackdrop.new())
	_build()
	Net.lobby_changed.connect(_refresh)
	_refresh()
	_host_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _build() -> void:
	var center := CenterContainer.new()
	add_child(UiKit.full_rect(center))
	var sheet := StitchedPanel.new()
	center.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	column.custom_minimum_size.x = 640
	sheet.add_child(column)
	column.add_child(UiKit.label("LAN_TITLE", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var intro := UiKit.label("LAN_INTRO", &"", HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)

	_host_button = UiKit.button("LAN_HOST", &"PrimaryButton")
	_host_button.pressed.connect(func() -> void: Net.host())
	column.add_child(_host_button)
	_addresses = UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_addresses)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	_address = LineEdit.new()
	_address.placeholder_text = "LAN_ADDRESS_PLACEHOLDER"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.max_length = 64
	_address.text = _last_address()
	_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	row.add_child(_address)
	_join_button = UiKit.button("LAN_JOIN")
	_join_button.pressed.connect(_on_join)
	row.add_child(_join_button)

	_status = UiKit.label("", &"", HORIZONTAL_ALIGNMENT_CENTER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	column.add_child(buttons)
	_leave_button = UiKit.button("LAN_DISCONNECT", &"QuietButton")
	_leave_button.pressed.connect(func() -> void: Net.leave())
	buttons.add_child(_leave_button)
	var back := UiKit.button("MENU_BACK")
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)


func _on_join() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		return
	var file := ConfigFile.new()
	file.set_value("lan", "address", address)
	file.save(LAST_ADDRESS_PATH)
	Net.join(address)


func _last_address() -> String:
	var file := ConfigFile.new()
	if file.load(LAST_ADDRESS_PATH) != OK:
		return ""
	return str(file.get_value("lan", "address", ""))


func _refresh() -> void:
	var busy := Net.is_connected_lan()
	_leave_button.visible = busy
	_host_button.disabled = Net.hosting
	_addresses.visible = Net.hosting
	_addresses.text = tr("LAN_YOUR_ADDRESS").format({"address": ", ".join(Net.local_addresses())})
	_status.text = tr(Net.status_key).format({"port": Net.port()}) if not Net.status_key.is_empty() else ""
