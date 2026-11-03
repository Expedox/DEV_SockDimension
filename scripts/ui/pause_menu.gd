extends CanvasLayer
## Esc menu during a run: Resume, Save, Achievements, Settings, Main Menu, Quit. Pauses the
## tree while open and also opens when the window loses focus.

var _root: Control
var _buttons: VBoxContainer
var _settings: SettingsPanel
var _achievements: AchievementsMenu
var _sheet: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	_build()
	_root.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if is_open():
		# Sub screens handle their own Esc.
		if _settings == null and _achievements == null:
			get_viewport().set_input_as_handled()
			resume()
	elif _can_open():
		get_viewport().set_input_as_handled()
		open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _can_open():
		open()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.show()
	UiKit.fade_in(_root)
	_buttons.get_child(0).grab_focus.call_deferred()


func resume() -> void:
	_close_settings()
	_close_achievements()
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_open() -> bool:
	return GameState.running and not get_tree().paused and not is_open()


func _build() -> void:
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	add_child(UiKit.full_rect(_root))
	var dim := ColorRect.new()
	dim.color = UiTheme.color("dim")
	_root.add_child(UiKit.full_rect(dim))
	var center := CenterContainer.new()
	_root.add_child(UiKit.full_rect(center))
	var sheet := StitchedPanel.new()
	center.add_child(sheet)
	_sheet = sheet
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	sheet.add_child(column)
	column.add_child(UiKit.label("PAUSE_TITLE", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	column.add_child(_buttons)
	_add("MENU_RESUME", resume, &"PrimaryButton")
	_add("MENU_SAVE", SaveManager.save_current)
	_add("MENU_ACHIEVEMENTS", _open_achievements)
	_add("MENU_SETTINGS", _open_settings)
	_add("MENU_MAIN_MENU", _to_main_menu)
	_add("MENU_QUIT", SaveManager.save_and_quit, &"QuietButton")


func _add(key: String, action: Callable, variation := &"") -> void:
	var b := UiKit.button(key, variation)
	b.pressed.connect(func() -> void: action.call())
	_buttons.add_child(b)


func _open_settings() -> void:
	if _settings:
		return
	_settings = SettingsPanel.new()
	_settings.with_backdrop = false
	_sheet.hide()
	_settings.closed.connect(func() -> void:
		_close_settings()
		_buttons.get_child(3).grab_focus())
	_root.add_child(_settings)


func _open_achievements() -> void:
	if _achievements or _settings:
		return
	_achievements = AchievementsMenu.new()
	_achievements.with_backdrop = false
	_sheet.hide()
	_achievements.closed.connect(func() -> void:
		_close_achievements()
		_buttons.get_child(2).grab_focus())
	_root.add_child(_achievements)


func _close_achievements() -> void:
	if _achievements:
		UiKit.fade_out_and_free(_achievements)
		_achievements = null
		_sheet.show()


func _close_settings() -> void:
	if _settings:
		UiKit.fade_out_and_free(_settings)
		_settings = null
		_sheet.show()


func _to_main_menu() -> void:
	SaveManager.save_current()
	GameState.to_main_menu()
