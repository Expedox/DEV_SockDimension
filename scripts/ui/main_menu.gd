extends Control
## Title screen: Continue, New Game, Achievements, Settings, Quit. Sub screens
## open on top and hand control back when they close.

var _menu: Control
var _title: Label
var _continue_button: Button
var _continue_info: Label
var _continue_mode := ""
var _overlay: Control
var _time := 0.0


func _ready() -> void:
	UiKit.full_rect(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	add_child(MenuBackdrop.new())
	_build()
	_refresh_continue()
	UiKit.fade_in(_menu)
	_first_button().grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_continue()


func _process(delta: float) -> void:
	# The title sways a little, like laundry on a line.
	_time += delta
	if _title:
		_title.rotation = sin(_time * 0.8) * 0.018
		_title.position.y = sin(_time * 1.3) * 4.0


func _build() -> void:
	_menu = Control.new()
	add_child(UiKit.full_rect(_menu))
	var center := CenterContainer.new()
	_menu.add_child(UiKit.full_rect(center))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 34)
	center.add_child(column)

	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(900, 130)
	column.add_child(title_box)
	_title = UiKit.label("GAME_TITLE", &"TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.resized.connect(func() -> void: _title.pivot_offset = _title.size * 0.5)
	title_box.add_child(_title)

	var sheet := StitchedPanel.new()
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(sheet)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	sheet.add_child(buttons)

	_continue_button = UiKit.button("MENU_CONTINUE", &"PrimaryButton")
	_continue_button.pressed.connect(_on_continue)
	buttons.add_child(_continue_button)
	_continue_info = UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
	buttons.add_child(_continue_info)
	_add(buttons, "MENU_NEW_GAME", _open_mode_select)
	_add(buttons, "MENU_ACHIEVEMENTS", _open_achievements)
	_add(buttons, "MENU_SETTINGS", _open_settings)
	_add(buttons, "MENU_QUIT", SaveManager.save_and_quit, &"QuietButton")


func _add(parent: Control, key: String, action: Callable, variation := &"") -> void:
	var b := UiKit.button(key, variation)
	b.pressed.connect(action)
	parent.add_child(b)


func _refresh_continue() -> void:
	_continue_mode = SaveManager.latest_save()
	var has_run := not _continue_mode.is_empty()
	_continue_button.visible = has_run
	_continue_info.visible = has_run
	if has_run:
		var info := SaveManager.save_info(_continue_mode)
		var mode := Config.mode(_continue_mode)
		_continue_info.text = tr("MENU_CONTINUE_INFO").format({
			"mode": tr(mode.name_key), "found": info.pairs_found, "total": int(mode.pairs)})


func _first_button() -> Button:
	for child in _continue_button.get_parent().get_children():
		if child is Button and child.visible:
			return child
	return _continue_button


func _on_continue() -> void:
	if not SaveManager.continue_run(_continue_mode):
		_refresh_continue()


func _open_mode_select() -> void:
	_open(ModeSelect.new())


func _open_achievements() -> void:
	_open(AchievementsMenu.new())


func _open_settings() -> void:
	_open(SettingsPanel.new())


## Shows a sub screen over the menu until it emits closed.
func _open(screen: Control) -> void:
	if _overlay:
		return
	_overlay = screen
	var focus_back := get_viewport().gui_get_focus_owner()
	screen.connect("closed", func() -> void:
		_overlay = null
		UiKit.fade_out_and_free(screen)
		_menu.show()
		UiKit.fade_in(_menu)
		_refresh_continue()
		if is_instance_valid(focus_back) and focus_back.is_visible_in_tree():
			focus_back.grab_focus()
		else:
			_first_button().grab_focus())
	add_child(screen)
	_menu.hide()
	UiKit.fade_in(screen)
