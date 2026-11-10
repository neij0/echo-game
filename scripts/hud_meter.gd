class_name HudMeter
extends Control
## A thin glowing meter for the HUD (the pressure meter, Depth Awareness): a
## faint track and a glowing fill (a wide soft halo under a bright core, like
## GlowFx lines, so it reads without bloom). Fills from the start side: right
## to left in a right-to-left layout. Optional pulse: the fill breathes (a low
## meter). Set ratio and color; it redraws itself.

@export var track_color: Color = Color(0.5, 0.65, 0.8, 0.16)
@export var thickness: float = 3.0
## Halo width (times thickness) and strength.
@export var halo_scale: float = 3.2
@export var halo_alpha: float = 0.22
## Breaths per second while pulsing.
@export var pulse_speed: float = 1.6

## 0-1.
var ratio: float = 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var color: Color = Color(0.45, 0.95, 1.0):
	set(value):
		color = value
		queue_redraw()
var pulsing: bool = false
var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if pulsing:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var y: float = size.y * 0.5
	var rtl: bool = is_layout_rtl()
	draw_line(Vector2(0.0, y), Vector2(size.x, y), track_color, thickness)
	if ratio <= 0.0:
		return
	var length: float = size.x * ratio
	var from := Vector2(size.x if rtl else 0.0, y)
	var to := from + Vector2(-length if rtl else length, 0.0)
	var strength: float = 1.0
	if pulsing:
		strength = 0.65 + 0.35 * sin(_time * TAU * pulse_speed)
	draw_line(from, to, Color(color, color.a * halo_alpha * strength), thickness * halo_scale)
	draw_line(from, to, Color(color, color.a * strength), thickness)
	# A brighter tip where the fill ends.
	draw_circle(to, thickness * 0.9, Color(color.lightened(0.35), color.a * strength))
