class_name ConfirmDialog
extends Control
## Modal yes/no question on a stitched card. Frees itself after answering.

signal answered(yes: bool)

var _title_key: String
var _body_key: String
var _yes_key: String
var _no_key: String
var _no_button: Button


static func ask(parent: Node, title_key: String, body_key: String, yes_key := "MENU_YES", no_key := "MENU_NO") -> ConfirmDialog:
	var dialog := ConfirmDialog.new()
	dialog._title_key = title_key
	dialog._body_key = body_key
	dialog._yes_key = yes_key
	dialog._no_key = no_key
	parent.add_child(dialog)
	return dialog


func _ready() -> void:
	UiKit.full_rect(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiTheme.color("dim")
	add_child(UiKit.full_rect(dim))
	var center := CenterContainer.new()
	add_child(UiKit.full_rect(center))
	var card := StitchedPanel.new()
	card.custom_minimum_size.x = 560
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	card.add_child(column)
	column.add_child(UiKit.label(_title_key, &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var body := UiKit.label(_body_key, &"", HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 480
	column.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	_no_button = UiKit.button(_no_key)
	_no_button.custom_minimum_size.x = 200
	_no_button.pressed.connect(_answer.bind(false))
	row.add_child(_no_button)
	var yes := UiKit.button(_yes_key, &"PrimaryButton")
	yes.custom_minimum_size.x = 200
	yes.pressed.connect(_answer.bind(true))
	row.add_child(yes)
	UiKit.fade_in(self)
	_no_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)


func _answer(yes: bool) -> void:
	set_process_unhandled_input(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	answered.emit(yes)
	UiKit.fade_out_and_free(self)
