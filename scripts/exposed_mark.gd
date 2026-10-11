class_name ExposedMark
extends Node2D
## A bright gold ring around a creature while it is Exposed (hit by a pulse
## front). The ring shrinks towards the body as the Exposed time runs out, so
## the Guardian can see how long he has left to land the finisher.
## Must live on a CanvasLayer with follow_viewport_enabled (drawn unlit).

@export var creature: Creature
@export var color: Color = Color(1.0, 0.78, 0.2)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 3.0
@export var width: float = 3.0
## Ring radius at the start, added to the body radius...
@export var start_extra_radius: float = 22.0
## ...and when Exposed is about to end.
@export var end_extra_radius: float = 3.0
## Small marks on the ring, like a target lock.
@export var tick_count: int = 4
@export var tick_length: float = 7.0


func _process(_delta: float) -> void:
	if creature == null:
		return
	global_position = creature.global_position
	queue_redraw()


func _draw() -> void:
	if creature == null or not creature.is_exposed():
		return
	var t: float = creature.get_exposed_ratio()
	var radius: float = creature.body_radius + lerpf(end_extra_radius, start_extra_radius, t)
	var glow := Color(color.r * energy, color.g * energy, color.b * energy, lerpf(0.5, 1.0, t))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, glow, width, true)
	for i: int in tick_count:
		var direction: Vector2 = Vector2.from_angle(TAU * i / tick_count + PI * 0.25)
		draw_line(direction * radius, direction * (radius + tick_length), glow, width, true)
