class_name CreatureEcho
extends Node2D
## The sonar "echo" of a creature: a glowing silhouette in its type colour that
## appears when the pulse front passes over the creature, then fades out. Uses
## the creature's own shape (Creature.draw_shape) while it exists.
## Must live on a CanvasLayer with follow_viewport_enabled, so the world's
## CanvasModulate darkness does not dim it.

@export var color: Color = Color(1.0, 0.15, 0.12)
## HDR brightness multiplier right at the hit (above 1.0 = blooms).
@export var start_energy: float = 4.0
## HDR brightness multiplier at the end of the fade.
@export var end_energy: float = 1.2
@export var fade_time: float = 1.5
## Opacity of the filled body compared to its outline.
@export_range(0.0, 1.0) var fill_alpha: float = 0.45
@export var outline_width: float = 2.0
## Seconds the echo follows the creature before freezing where it was, so the
## player can read which way it is moving. 0 = freeze immediately.
@export var follow_time: float = 0.4

var _target: Node2D
var _radius: float = 0.0
var _time_left: float = 0.0


func flash(target: Node2D, radius: float) -> void:
	_target = target
	_radius = radius
	_time_left = fade_time
	global_position = target.global_position
	queue_redraw()


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	if fade_time - _time_left <= follow_time and is_instance_valid(_target):
		global_position = _target.global_position
	queue_redraw()


func _draw() -> void:
	if _time_left <= 0.0:
		return
	var t: float = _time_left / fade_time
	var energy: float = lerpf(end_energy, start_energy, t * t)
	var glow := Color(color.r * energy, color.g * energy, color.b * energy, t)
	var fill := Color(glow, t * fill_alpha)
	if is_instance_valid(_target) and _target is Creature:
		(_target as Creature).draw_shape(self, fill, glow, false)
		return
	draw_circle(Vector2.ZERO, _radius, fill)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, glow, outline_width, true)
