class_name AchievementToast
extends CanvasLayer
## Small window in the bottom-right corner, one unlock at a time, with a chime.

const LAYER := 100
const MARGIN := 24.0
const WIDTH := 340.0
const SLIDE_DISTANCE := 60.0
const SLIDE_SECONDS := 0.3
const DEFAULT_HOLD_SECONDS := 4.0
const SFX_BUS := &"SFX"
const MIX_RATE := 22050
const CHIME_NOTES_HZ: Array[float] = [659.25, 880.0]
const CHIME_NOTE_SECONDS := 0.32
const CHIME_NOTE_GAP_SECONDS := 0.12
const CHIME_VOLUME := 0.35

var _queue: Array[Dictionary] = []
var _busy := false
var _panel: PanelContainer
var _name_label: Label
var _description_label: Label
var _player: AudioStreamPlayer


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Takes translation keys, so the text follows the language at display time.
func enqueue(name_key: String, description_key: String) -> void:
	_queue.append({"name": name_key, "description": description_key})
	if not _busy:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var entry: Dictionary = _queue.pop_front()
	_name_label.text = tr(entry.name)
	_description_label.text = tr(entry.description)
	_panel.show()
	_panel.modulate.a = 0.0
	_set_slide(SLIDE_DISTANCE)
	if AudioServer.get_bus_index(SFX_BUS) != -1:
		_player.bus = SFX_BUS
	_player.play()

	var hold: float = DEFAULT_HOLD_SECONDS
	if get_parent() is AchievementService:
		hold = float(get_parent().params.get("toast_seconds", DEFAULT_HOLD_SECONDS))
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_slide, SLIDE_DISTANCE, 0.0, SLIDE_SECONDS)
	tween.parallel().tween_property(_panel, "modulate:a", 1.0, SLIDE_SECONDS)
	tween.tween_interval(hold)
	tween.tween_property(_panel, "modulate:a", 0.0, SLIDE_SECONDS)
	tween.tween_callback(_panel.hide)
	tween.tween_callback(_show_next)


func _set_slide(amount: float) -> void:
	_panel.offset_left = -MARGIN - WIDTH + amount
	_panel.offset_right = -MARGIN + amount


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = -MARGIN
	_panel.offset_bottom = -MARGIN
	_panel.custom_minimum_size.x = WIDTH
	_panel.theme = UiTheme.get_theme()
	_panel.theme_type_variation = &"CardPanel"
	_panel.hide()
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	_panel.add_child(rows)

	var header := Label.new()
	header.text = "ACHIEVEMENTS_TOAST_HEADER"
	header.theme_type_variation = &"MutedLabel"
	rows.add_child(header)

	_name_label = Label.new()
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_name_label)

	_description_label = Label.new()
	_description_label.theme_type_variation = &"MutedLabel"
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_description_label)

	_player = AudioStreamPlayer.new()
	_player.stream = _make_chime()
	add_child(_player)


## Two soft rising bell notes, overlapping.
func _make_chime() -> AudioStreamWAV:
	var note_count := CHIME_NOTES_HZ.size()
	var seconds := CHIME_NOTE_GAP_SECONDS * (note_count - 1) + CHIME_NOTE_SECONDS
	var frames := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for note in note_count:
		var start := int(note * CHIME_NOTE_GAP_SECONDS * MIX_RATE)
		var length := int(CHIME_NOTE_SECONDS * MIX_RATE)
		for i in length:
			var t := float(i) / MIX_RATE
			var envelope := exp(-t * 9.0) * minf(t * 200.0, 1.0)
			var wave := sin(TAU * CHIME_NOTES_HZ[note] * t) \
					+ 0.3 * sin(TAU * CHIME_NOTES_HZ[note] * 2.0 * t)
			samples[start + i] += wave * envelope * CHIME_VOLUME

	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = bytes
	return stream
