class_name SlotSelect
extends Control
## Lists the save slots. For a new game a slot is picked first and the mode
## screen opens on top; for loading, a slot with an unfinished run opens it.
## Every filled slot can be deleted after a confirmation.

signal closed

enum Purpose { NEW_GAME, LOAD }

const CARD_SIZE := Vector2(620, 128)

var purpose := Purpose.NEW_GAME
var _list: VBoxContainer
var _sheet: Control
var _overlay: Control


static func create(for_purpose: Purpose) -> SlotSelect:
	var screen := SlotSelect.new()
	screen.purpose = for_purpose
	return screen


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(MenuBackdrop.new())
	_build()
	_fill()
	_focus_first()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill()


func _unhandled_input(event: InputEvent) -> void:
	if _overlay == null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _build() -> void:
	var center := CenterContainer.new()
	add_child(UiKit.full_rect(center))
	_sheet = StitchedPanel.new()
	center.add_child(_sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	_sheet.add_child(column)
	var title := "SLOT_TITLE_NEW" if purpose == Purpose.NEW_GAME else "SLOT_TITLE_LOAD"
	column.add_child(UiKit.label(title, &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	column.add_child(_list)
	var back := UiKit.button("MENU_BACK")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)


func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for slot in range(1, SaveManager.slot_count() + 1):
		_list.add_child(_slot_row(slot))


func _slot_row(slot: int) -> Control:
	var info := SaveManager.slot_info(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("slot", slot)
	card.disabled = purpose == Purpose.LOAD and (info.is_empty() or info.completed)
	card.pressed.connect(_on_slot_pressed.bind(slot))
	if card.disabled:
		card.modulate.a = 0.55
	row.add_child(card)

	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var heading := tr("SLOT_NAME").format({"n": slot})
	if not info.is_empty():
		heading += "  ·  " + tr(Config.mode(info.mode).get("name_key", info.mode))
	column.add_child(UiKit.label(heading, &"HeadingLabel"))
	if info.is_empty():
		column.add_child(UiKit.label("SLOT_EMPTY", &"MutedLabel"))
	else:
		column.add_child(UiKit.label(_progress_text(info)))
		column.add_child(UiKit.label(tr("SLOT_SAVED_AT").format({"date": format_date(info.saved_at)}), &"MutedLabel"))
	for label: Control in [margin, column] + column.get_children():
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var delete := UiKit.button("SLOT_DELETE", &"QuietButton")
	delete.custom_minimum_size.x = 150
	delete.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delete.pressed.connect(_on_delete.bind(slot))
	# Keeps rows aligned when a slot is empty.
	delete.modulate.a = 0.0 if info.is_empty() else 1.0
	delete.disabled = info.is_empty()
	delete.focus_mode = Control.FOCUS_NONE if info.is_empty() else Control.FOCUS_ALL
	row.add_child(delete)
	return row


func _progress_text(info: Dictionary) -> String:
	var time := UiKit.format_time(info.play_time)
	if info.completed:
		return tr("MODE_SAVE_COMPLETED").format({"time": time})
	var total := int(Config.mode(info.mode).get("pairs", 0))
	return tr("SLOT_PROGRESS").format({"found": info.pairs_found, "total": total, "time": time})


## Local date and time such as 2026-11-03 09:12.
static func format_date(unix_time: int) -> String:
	if unix_time <= 0:
		return "-"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix_time + bias)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


func _on_slot_pressed(slot: int) -> void:
	if purpose == Purpose.LOAD:
		set_process_unhandled_input(false)
		if not SaveManager.continue_run(slot):
			set_process_unhandled_input(true)
			_fill()
			_focus_first()
		return
	_open_mode_select(slot)


func _open_mode_select(slot: int) -> void:
	var screen := ModeSelect.new()
	screen.slot = slot
	_overlay = screen
	screen.closed.connect(func() -> void:
		_overlay = null
		UiKit.fade_out_and_free(screen)
		_sheet.show()
		_focus_slot(slot))
	add_child(screen)
	_sheet.hide()


func _on_delete(slot: int) -> void:
	var body := tr("SLOT_DELETE_BODY").format({"n": slot})
	var dialog := ConfirmDialog.ask(self, "SLOT_DELETE_TITLE", body, "SLOT_DELETE", "MENU_CANCEL")
	_overlay = dialog
	dialog.answered.connect(func(yes: bool) -> void:
		_overlay = null
		if yes:
			SaveManager.delete_slot(slot)
			_fill()
		_focus_slot(slot))


func _focus_first() -> void:
	for row in _list.get_children():
		var card: Button = row.get_child(0)
		if not card.disabled:
			card.grab_focus.call_deferred()
			return


func _focus_slot(slot: int) -> void:
	if slot - 1 < _list.get_child_count():
		var card: Button = _list.get_child(slot - 1).get_child(0)
		if not card.disabled:
			card.grab_focus.call_deferred()
			return
	_focus_first()
