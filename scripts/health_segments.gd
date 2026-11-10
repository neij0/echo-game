class_name HealthSegments
extends Control
## One player's health as a row of glowing pips (HUD, "silhouette + glow"):
## each segment is a short bar that fills from the start side with how much of
## it is left (a soft halo under a bright core); a partly damaged segment is
## dimmer (it refills on its own), a lost one is only a faint track. Flashes
## briefly on a hit, pulses red when health is low. Mirrors in a right-to-left
## layout (fills from the right). Created by PlayerStatus.

@export var segment_size: Vector2 = Vector2(30.0, 5.0)
@export var segment_gap: float = 7.0
@export var fill_color: Color = Color(0.5, 1.0, 0.8)
## Colour of the part of a partly damaged segment that is still there.
@export var partial_color: Color = Color(0.32, 0.62, 0.55)
@export var empty_color: Color = Color(0.5, 0.65, 0.8, 0.16)
## Halo under the fill: width (times the height) and strength.
@export var halo_scale: float = 2.6
@export var halo_alpha: float = 0.22
@export var low_color: Color = Color(1.0, 0.25, 0.2)
## Pulses per second of the low-health colour.
@export var low_pulse_speed: float = 1.4
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0)
@export var hit_flash_time: float = 0.25

var health: PlayerHealth
var _time: float = 0.0
var _flash_left: float = 0.0


func setup(target_health: PlayerHealth) -> void:
	health = target_health
	health.hit_taken.connect(_on_hit_taken)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	var count: int = health.segment_count if health else 0
	return Vector2(count * segment_size.x + maxi(count - 1, 0) * segment_gap, segment_size.y * halo_scale)


func _on_hit_taken() -> void:
	_flash_left = hit_flash_time


func _process(delta: float) -> void:
	_time += delta
	_flash_left = maxf(_flash_left - delta, 0.0)
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	if health == null:
		return
	var full: Color = fill_color
	if health.is_low():
		var pulse: float = 0.5 + 0.5 * sin(_time * TAU * low_pulse_speed)
		full = fill_color.lerp(low_color, lerpf(0.5, 1.0, pulse))
	if _flash_left > 0.0:
		full = full.lerp(hit_flash_color, _flash_left / hit_flash_time)
	var rtl: bool = is_layout_rtl()
	var y: float = size.y * 0.5
	for i: int in health.segment_count:
		var left: float = i * (segment_size.x + segment_gap)
		if rtl:
			left = size.x - left - segment_size.x
		var from := Vector2(left, y)
		draw_line(from, from + Vector2(segment_size.x, 0.0), empty_color, segment_size.y)
		var fill: float = health.get_segment_fill(i)
		if fill <= 0.0:
			continue
		var color: Color = full if fill >= 1.0 - PlayerHealth.EPSILON else partial_color
		var length: float = segment_size.x * fill
		var start := Vector2(left + segment_size.x - length, y) if rtl else from
		var end := start + Vector2(length, 0.0)
		draw_line(start, end, Color(color, halo_alpha), segment_size.y * halo_scale)
		draw_line(start, end, color, segment_size.y)
