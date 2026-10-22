class_name HealthSegments
extends Control
## One player's health as a row of segments (HUD). Each segment fills from left
## to right with how much of it is left; a partly damaged segment is drawn in a
## dimmer colour (it refills on its own), lost ones show only their frame.
## Flashes briefly on a hit, pulses red when health is low. Created by
## PlayerStatus.

@export var segment_size: Vector2 = Vector2(40.0, 12.0)
@export var segment_gap: float = 5.0
@export var fill_color: Color = Color(0.45, 1.0, 0.75)
## Colour of the part of a partly damaged segment that is still there.
@export var partial_color: Color = Color(0.3, 0.65, 0.55)
@export var empty_color: Color = Color(0.1, 0.12, 0.18, 0.85)
@export var frame_color: Color = Color(0.6, 0.75, 0.8, 0.5)
@export var frame_width: float = 1.0
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
	return Vector2(count * segment_size.x + maxi(count - 1, 0) * segment_gap, segment_size.y)


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
	for i: int in health.segment_count:
		var rect := Rect2(Vector2(i * (segment_size.x + segment_gap), 0.0), segment_size)
		draw_rect(rect, empty_color)
		var fill: float = health.get_segment_fill(i)
		if fill > 0.0:
			var color: Color = full if fill >= 1.0 - PlayerHealth.EPSILON else partial_color
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), color)
		draw_rect(rect, frame_color, false, frame_width)
