class_name MenuBackdrop
extends Control
## Menu background: a soft knit rib with socks drifting slowly down in front of it.

const KNIT_SHADER := """
shader_type canvas_item;
uniform vec4 base_color;
uniform vec4 rib_color;
uniform vec4 glow_color;

void fragment() {
	vec2 p = FRAGCOORD.xy;
	float rib = sin(p.x * 0.19 + sin(p.y * 0.05) * 1.4);
	float row = sin(p.y * 0.42 + floor(p.x * 0.03) * 3.14);
	float knit = smoothstep(0.1, 0.9, rib) * (0.65 + 0.35 * row);
	vec3 col = mix(base_color.rgb, rib_color.rgb, knit * 0.55);
	float vignette = 1.0 - smoothstep(0.25, 1.0, distance(UV, vec2(0.5, 0.42)));
	col = mix(col * 0.72, col + glow_color.rgb * 0.12, vignette);
	COLOR = vec4(col, 1.0);
}
"""

## Outline of a sock in unit space, cuff at the top and toe to the right.
const SOCK_OUTLINE: Array[Vector2] = [
	Vector2(-0.34, -1.0), Vector2(0.20, -1.0), Vector2(0.22, 0.20), Vector2(0.34, 0.30),
	Vector2(0.72, 0.36), Vector2(0.90, 0.48), Vector2(0.92, 0.66), Vector2(0.78, 0.80),
	Vector2(0.20, 0.82), Vector2(-0.14, 0.76), Vector2(-0.32, 0.56), Vector2(-0.36, 0.22),
]
const BASE_SOCK_SIZE := 46.0

var _socks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var knit := ColorRect.new()
	knit.set_anchors_preset(Control.PRESET_FULL_RECT)
	knit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knit.show_behind_parent = true
	var shader := Shader.new()
	shader.code = KNIT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", UiTheme.color("backdrop_dark"))
	mat.set_shader_parameter("rib_color", UiTheme.color("backdrop_rib"))
	mat.set_shader_parameter("glow_color", UiTheme.color("mustard"))
	knit.material = mat
	add_child(knit)
	_rng.randomize()
	for i in int(UiTheme.data().backdrop.sock_count):
		_socks.append(_new_sock(true))


func _process(delta: float) -> void:
	_time += delta
	var bottom := size.y + BASE_SOCK_SIZE * 3.0
	for i in _socks.size():
		var sock := _socks[i]
		sock.pos.y += sock.speed * delta
		sock.angle += sock.spin * delta
		if sock.pos.y > bottom:
			_socks[i] = _new_sock(false)
	queue_redraw()


func _draw() -> void:
	var sway := float(UiTheme.data().backdrop.sway)
	for sock in _socks:
		var offset: float = sin(_time * 0.5 + sock.phase) * sway
		var xform := Transform2D(sock.angle, Vector2.ONE * sock.scale * BASE_SOCK_SIZE, 0.0, sock.pos + Vector2(offset, 0.0))
		draw_set_transform_matrix(xform)
		_draw_sock(sock.tint, sock.accent)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_sock(tint: Color, accent: Color) -> void:
	draw_colored_polygon(PackedVector2Array(SOCK_OUTLINE), tint)
	draw_rect(Rect2(-0.34, -1.0, 0.54, 0.22), accent)
	draw_rect(Rect2(-0.335, -0.56, 0.545, 0.12), accent)
	draw_rect(Rect2(-0.335, -0.26, 0.55, 0.12), accent)


func _new_sock(anywhere: bool) -> Dictionary:
	var cfg: Dictionary = UiTheme.data().backdrop
	var colors: Array = UiTheme.data().sock_colors
	var depth := _rng.randf()
	var w := maxf(size.x, 1280.0)
	var h := maxf(size.y, 720.0)
	# Farther socks are smaller, slower and fade into the wall.
	var alpha := lerpf(0.16, 0.5, depth)
	var tint := Color.html(colors[_rng.randi() % colors.size()])
	var accent := Color.html(colors[_rng.randi() % colors.size()])
	tint.a = alpha
	accent.a = alpha
	return {
		"pos": Vector2(_rng.randf() * w, _rng.randf() * h if anywhere else -BASE_SOCK_SIZE * 3.0),
		"speed": lerpf(cfg.fall_speed_min, cfg.fall_speed_max, depth),
		"scale": lerpf(cfg.sock_scale_min, cfg.sock_scale_max, depth),
		"angle": _rng.randf() * TAU,
		"spin": _rng.randf_range(-0.35, 0.35),
		"phase": _rng.randf() * TAU,
		"tint": tint,
		"accent": accent,
	}
