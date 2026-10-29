class_name EchoMarkOutline
extends Node2D
## The Echo Mark skill: after a pulse front hits the creature it keeps a faint
## outline in its type colour for a few seconds (Creature.get_mark_ratio), so
## the Guardian can follow it in the dark. Only an outline: the creature is not
## hittable because of it (only Exposed, the Echo's light or his close sense).
## Hidden while the creature's body is fully visible anyway.
## Must live on a CanvasLayer with follow_viewport_enabled (drawn unlit).

@export var creature: Creature
## HDR brightness multiplier of the outline (kept low: a hint, not a reveal).
@export var energy: float = 1.3
## Opacity right after the pulse hit (fades to 0 as the mark runs out).
@export_range(0.0, 1.0) var start_alpha: float = 0.75
## Soft breathing of the outline, cycles per second.
@export var pulse_speed: float = 1.4
@export_range(0.0, 1.0) var pulse_amount: float = 0.25

var _time: float = 0.0
var _was_drawn: bool = false


func _process(delta: float) -> void:
	if creature == null:
		return
	_time += delta
	global_position = creature.global_position
	var draw_now: bool = _should_draw()
	if draw_now or _was_drawn:
		queue_redraw()
	_was_drawn = draw_now


func _should_draw() -> bool:
	return creature.get_mark_ratio() > 0.0 and creature.get_body_visibility() < 0.99


func _draw() -> void:
	if creature == null or not _should_draw():
		return
	var ratio: float = creature.get_mark_ratio()
	var breathe: float = 1.0 - pulse_amount * (0.5 + 0.5 * sin(_time * TAU * pulse_speed))
	var color: Color = creature.get_type_color()
	var outline := Color(color.r * energy, color.g * energy, color.b * energy, start_alpha * ratio * breathe)
	creature.draw_shape(self, Color(0.0, 0.0, 0.0, 0.0), outline, false)
