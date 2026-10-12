class_name VerletChain
extends RefCounted
## A chain of points that trails behind its anchor (verlet integration with
## fixed segment lengths): tails and similar flowing parts. Points are in
## world coordinates.

var points: PackedVector2Array = PackedVector2Array()
var segment_length: float = 5.0
## Share of each point's velocity kept per step (lower = stiffer in water).
var damping: float = 0.9
## Length correction passes per step (more = less stretchy).
var iterations: int = 3

var _previous: PackedVector2Array = PackedVector2Array()


func _init(count: int, length: float, start: Vector2, direction: Vector2) -> void:
	segment_length = length
	points.resize(count)
	_previous.resize(count)
	reset(start, direction)


## Lays the chain out straight from start along direction.
func reset(start: Vector2, direction: Vector2) -> void:
	for i: int in points.size():
		points[i] = start + direction.normalized() * segment_length * i
		_previous[i] = points[i]


## Moves the first point to anchor and lets the rest follow. force is an
## acceleration (pixels per second squared) applied to every free point.
func step(anchor: Vector2, force: Vector2, delta: float) -> void:
	if points.is_empty():
		return
	points[0] = anchor
	_previous[0] = anchor
	var push: Vector2 = force * delta * delta
	for i: int in range(1, points.size()):
		var moved: Vector2 = (points[i] - _previous[i]) * damping
		_previous[i] = points[i]
		points[i] += moved + push
	for _pass: int in iterations:
		for i: int in range(1, points.size()):
			var offset: Vector2 = points[i] - points[i - 1]
			var length: float = offset.length()
			if length > 0.0:
				points[i] = points[i - 1] + offset / length * segment_length
