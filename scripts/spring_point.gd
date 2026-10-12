class_name SpringPoint
extends RefCounted
## A point pulled towards a target by a damped spring (procedural animation:
## antenna tips, cloak hem). Overshoots a little and settles, so things sway.

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO


func _init(start: Vector2 = Vector2.ZERO) -> void:
	position = start


## stiffness: pull per pixel of distance; damping: how fast the swing dies out.
func step(target: Vector2, stiffness: float, damping: float, delta: float) -> void:
	var acceleration: Vector2 = (target - position) * stiffness - velocity * damping
	velocity += acceleration * delta
	position += velocity * delta


func reset(at: Vector2) -> void:
	position = at
	velocity = Vector2.ZERO
