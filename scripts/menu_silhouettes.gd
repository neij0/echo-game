class_name MenuSilhouettes
extends Node2D
## The main menu's small Echo and Guardian, seen from behind on a dark ledge,
## looking up at the Journey tower, against a soft light (backlight_*): dark
## silhouettes with a few glowing parts
## (her antenna tips and the gold glow of her core, his cold rim and antlers),
## drawn in code with gentle motion (antennae sway, cloak hem, a slow bob).
## The origin is the middle of the ledge's top.

@export var ledge_width: float = 230.0
@export var ledge_depth: float = 70.0
@export var ledge_color: Color = Color(0.012, 0.018, 0.03)
@export var rim_color: Color = Color(0.4, 0.6, 0.8)
@export var body_color: Color = Color(0.01, 0.012, 0.02)
@export var echo_glow: Color = Color(1.0, 0.8, 0.45)
@export var antenna_color: Color = Color(0.45, 0.95, 1.0)
@export var guardian_rim: Color = Color(0.5, 0.65, 1.0)
## Where they stand on the ledge (the Echo, then the Guardian).
@export var echo_offset: Vector2 = Vector2(-26.0, -2.0)
@export var guardian_offset: Vector2 = Vector2(24.0, 0.0)
@export var glow_energy: float = 2.2
## A soft light behind them (from the tower above), so the dark shapes read.
@export var backlight_color: Color = Color(0.35, 0.55, 0.85)
@export var backlight_radius: float = 110.0
@export var backlight_alpha: float = 0.16

var _time: float = 0.0
var _ledge: PackedVector2Array = PackedVector2Array()
var _backlight: GradientTexture2D


func _ready() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	_backlight = GradientTexture2D.new()
	_backlight.gradient = gradient
	_backlight.fill = GradientTexture2D.FILL_RADIAL
	_backlight.fill_from = Vector2(0.5, 0.5)
	_backlight.fill_to = Vector2(1.0, 0.5)
	_backlight.use_hdr = true
	var count: int = 18
	for i: int in count + 1:
		var t: float = float(i) / float(count)
		var x: float = lerpf(-ledge_width * 0.5, ledge_width * 0.5, t)
		_ledge.append(Vector2(x, -sin(PI * t) * 6.0 + sin(t * 17.0) * 1.5))
	_ledge.append(Vector2(ledge_width * 0.35, ledge_depth))
	_ledge.append(Vector2(0.0, ledge_depth * 1.2))
	_ledge.append(Vector2(-ledge_width * 0.4, ledge_depth * 0.9))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var light_rect := Rect2(Vector2(-backlight_radius, -34.0 - backlight_radius), Vector2.ONE * backlight_radius * 2.0)
	draw_texture_rect(_backlight, light_rect, false, Color(backlight_color, backlight_alpha))
	draw_colored_polygon(_ledge, ledge_color)
	draw_polyline(_ledge.slice(0, 19), Color(rim_color, 0.25), 1.2, true)
	_draw_guardian(guardian_offset)
	_draw_echo(echo_offset + Vector2(0.0, sin(_time * 1.6) * 1.5 - 4.0))


func _hdr(color: Color, alpha: float) -> Color:
	return Color(color.r * glow_energy, color.g * glow_energy, color.b * glow_energy, alpha)


func _draw_echo(at: Vector2) -> void:
	# The core's warm glow seen through her (from behind).
	GlowFx.dot(self, at + Vector2(0.0, -10.0), 2.5, _hdr(echo_glow, 0.35))
	# Tail curling down to one side.
	var tail := PackedVector2Array()
	for i: int in 9:
		var t: float = float(i) / 8.0
		tail.append(at + Vector2(sin(t * 2.5 + _time * 1.2) * 4.0 + t * 7.0, t * 12.0))
	draw_polyline(tail, body_color, 2.0, true)
	draw_circle(at + Vector2(0.0, -9.0), 7.0, body_color)
	draw_circle(at + Vector2(0.0, -17.0), 5.0, body_color)
	# Long ears.
	for side: float in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([at + Vector2(side * 2.0, -19.0), at + Vector2(side * 9.0, -27.0),
			at + Vector2(side * 4.0, -18.0)]), body_color)
	# Antennae, looking up: tips glowing, swaying.
	for side: float in [-1.0, 1.0]:
		var base: Vector2 = at + Vector2(side * 1.5, -21.0)
		var tip: Vector2 = base + Vector2(side * 4.0 + sin(_time * 1.3 + side) * 1.5, -11.0)
		draw_line(base, tip, body_color, 1.0, true)
		GlowFx.dot(self, tip, 1.2, _hdr(antenna_color, 0.9))
	draw_arc(at + Vector2(0.0, -9.0), 7.0, PI * 1.1, PI * 1.9, 8, Color(echo_glow, 0.25), 1.0, true)


func _draw_guardian(at: Vector2) -> void:
	var sway: float = sin(_time * 1.1) * 1.5
	var cloak := PackedVector2Array([at + Vector2(-7.0, -40.0), at + Vector2(7.0, -40.0), at + Vector2(12.0 + sway, 0.0),
		at + Vector2(4.0, 2.0 + sway * 0.3), at + Vector2(-4.0, 1.0), at + Vector2(-12.0 + sway, 0.0)])
	draw_colored_polygon(cloak, body_color)
	draw_circle(at + Vector2(0.0, -45.0), 6.0, body_color)
	# Antlers, branching up.
	for side: float in [-1.0, 1.0]:
		var base: Vector2 = at + Vector2(side * 3.0, -49.0)
		var mid: Vector2 = base + Vector2(side * 7.0, -9.0)
		var top: Vector2 = mid + Vector2(side * 3.0, -9.0)
		draw_polyline(PackedVector2Array([base, mid, top]), body_color, 1.8, true)
		draw_line(mid, mid + Vector2(side * 7.0, -3.0), body_color, 1.4, true)
		draw_line(mid.lerp(top, 0.5), mid.lerp(top, 0.5) + Vector2(-side * 3.0, -5.0), body_color, 1.2, true)
		draw_polyline(PackedVector2Array([base, mid, top]), Color(guardian_rim, 0.25), 0.8, true)
	# The cold rim on the cloak's edges.
	draw_line(cloak[0], cloak[5], Color(guardian_rim, 0.35), 1.0, true)
	draw_line(cloak[1], cloak[2], Color(guardian_rim, 0.35), 1.0, true)
	# The sword hanging at his side.
	draw_line(at + Vector2(10.0, -22.0), at + Vector2(16.0, 4.0), body_color, 2.0, true)
	draw_line(at + Vector2(10.0, -22.0), at + Vector2(16.0, 4.0), Color(echo_glow, 0.15), 0.8, true)
