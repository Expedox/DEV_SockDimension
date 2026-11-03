class_name NetHud
extends CanvasLayer
## LAN overlay: the other player's count under our own, and a short note when
## they come or go.

var _rival: Label
var _note: Label
var _note_tween: Tween
var _shown := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.full_rect(root))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 92)
	root.add_child(UiKit.full_rect(margin))

	_rival = UiKit.label("", &"HudLabel")
	margin.add_child(_chip(_rival, Control.SIZE_SHRINK_BEGIN))
	_note = UiKit.label("", &"HudLabel", HORIZONTAL_ALIGNMENT_CENTER)
	var note_chip := _chip(_note, Control.SIZE_SHRINK_CENTER)
	note_chip.modulate.a = 0.0
	margin.add_child(note_chip)

	Net.rival_joined.connect(_show_note.bind("NET_RIVAL_JOINED"))
	Net.rival_left.connect(_show_note.bind("NET_RIVAL_LEFT"))


func _chip(label: Label, align: Control.SizeFlags) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"HudChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = align
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chip.add_child(label)
	return chip


func _process(_delta: float) -> void:
	var live := Net.rival_in_run() and (GameState.running or GameState.completed)
	_rival.get_parent().visible = live
	if not live:
		return
	var total := int(Config.mode(Net.rival_mode).pairs)
	var text := tr("HUD_RIVAL").format({"found": Net.rival_found, "total": total})
	if text != _shown:
		_shown = text
		_rival.text = text


func _show_note(key: String) -> void:
	_note.text = tr(key)
	var chip := _note.get_parent() as Control
	if _note_tween:
		_note_tween.kill()
	_note_tween = create_tween()
	_note_tween.tween_property(chip, "modulate:a", 1.0, 0.3)
	_note_tween.tween_interval(5.0)
	_note_tween.tween_property(chip, "modulate:a", 0.0, 0.8)
