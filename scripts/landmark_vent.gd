class_name LandmarkVent
extends Landmark
## A hydrothermal vent: a low solid mound with rough chimneys standing on it.
## Their mouths glow a dim warm amber, small bubbles rise from them and
## wobble up into the dark, and a weak warm light tints the floor around.

@export var mound_radii: Vector2 = Vector2(96.0, 56.0)
@export var mound_height: float = 22.0
## Chimneys on the mound: positions (local, on the floor plan), radii, heights.
@export var chimney_positions: PackedVector2Array = PackedVector2Array([Vector2(-26.0, -8.0), Vector2(34.0, 10.0), Vector2(-62.0, 18.0)])
@export var chimney_radii: PackedFloat32Array = PackedFloat32Array([17.0, 13.0, 9.0])
@export var chimney_heights: PackedFloat32Array = PackedFloat32Array([104.0, 70.0, 40.0])
@export var mouth_color: Color = Color(1.0, 0.55, 0.2)
## Bubbles per chimney mouth, how fast and how high they rise, their size.
@export var bubbles_per_mouth: int = 7
@export var bubble_rise_speed: float = 46.0
@export var bubble_rise_height: float = 190.0
@export var bubble_radius: float = 2.4
@export var bubble_color: Color = Color(1.0, 0.85, 0.65)


func _footprint_shapes() -> Array[PackedVector2Array]:
	return [Landmark.ellipse(Vector2.ZERO, mound_radii, 18, 0.12, 5.0)]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([mound_height])


func _build_parts() -> void:
	var rock: Color = material_color()
	# Every variant has its own chimney heights (not in the footprint).
	var heights := PackedFloat32Array(chimney_heights)
	for i: int in heights.size():
		heights[i] *= lerpf(0.7, 1.25, rand(i * 2.9))
	chimney_heights = heights
	# On the mound's top, in front of it (they stand on it).
	var base_y: float = mound_radii.y + 2.0
	add_part(Vector2(0.0, base_y), _draw_chimneys.bind(rock, base_y))
	for i: int in chimney_positions.size():
		var foot: Vector2 = _chimney_foot(i)
		var r: float = chimney_radii[i]
		var mouth: Vector2 = foot - Vector2(0.0, chimney_heights[i])
		add_sonar_line(PackedVector2Array([foot + Vector2(-r, 0.0), mouth + Vector2(-r * 0.6, 0.0), mouth + Vector2(r * 0.6, 0.0), foot + Vector2(r, 0.0)]), PackedVector2Array(), 0.0)


## Where a chimney stands on the mound's top (screen position of its foot).
func _chimney_foot(i: int) -> Vector2:
	return chimney_positions[i] - Vector2(0.0, mound_height)


func _draw_chimneys(part: Node2D, rock: Color, base_y: float) -> void:
	# Back to front, so the front chimney covers the ones behind.
	var order: Array = range(chimney_positions.size())
	order.sort_custom(func(a: int, b: int) -> bool: return chimney_positions[a].y < chimney_positions[b].y)
	for i: int in order:
		var foot: Vector2 = _chimney_foot(i) - Vector2(0.0, base_y)
		var r: float = chimney_radii[i]
		var h: float = chimney_heights[i]
		var shape := PackedVector2Array()
		var steps: int = 6
		# Rough sides, narrowing upwards, with a flared mouth.
		for k: int in steps + 1:
			var t: float = float(k) / steps
			var width: float = r * lerpf(1.0, 0.6, t) + 2.0 * sin(t * 9.0 + i)
			shape.append(foot + Vector2(-width, -h * t))
		for k: int in range(steps, -1, -1):
			var t: float = float(k) / steps
			var width: float = r * lerpf(1.0, 0.6, t) + 2.0 * sin(t * 7.0 + i * 2.0)
			shape.append(foot + Vector2(width, -h * t))
		part.draw_colored_polygon(shape, rock.darkened(0.25))
		part.draw_line(foot + Vector2(-r, 0.0), foot + Vector2(-r * 0.6, -h), rock.lightened(0.12), 1.2, true)
		var mouth: Vector2 = foot - Vector2(0.0, h)
		part.draw_colored_polygon(Landmark.ellipse(mouth, Vector2(r * 0.75, r * 0.3), 10), rock.darkened(0.6))


func _has_glow() -> bool:
	return true


func _draw_glow(canvas: Node2D) -> void:
	for i: int in chimney_positions.size():
		var r: float = chimney_radii[i]
		var mouth: Vector2 = _chimney_foot(i) - Vector2(0.0, chimney_heights[i])
		var flicker: float = 0.75 + 0.25 * sin(_time * 2.3 + i * 1.7) * sin(_time * 3.1 + i)
		_batch.add_convex(Landmark.ellipse(mouth, Vector2(r * 0.6, r * 0.22), 10), glow(0.55 * flicker, mouth_color))
		_batch.add_dot(mouth - Vector2(0.0, 2.0), r * 0.9, glow(0.08 * flicker, mouth_color), 10)
		# Bubbles rising from the mouth, wobbling, fading as they go up.
		for k: int in bubbles_per_mouth:
			var phase: float = fposmod(_time * bubble_rise_speed / bubble_rise_height + Landmark.hash01(i * 7.1 + k * 1.3), 1.0)
			var wobble: float = sin(_time * 2.0 + k * 1.9 + i) * 5.0 * phase
			var at: Vector2 = mouth + Vector2(wobble + (Landmark.hash01(k + i * 3.0) - 0.5) * r, -phase * bubble_rise_height)
			var size: float = bubble_radius * (0.6 + 0.6 * Landmark.hash01(k * 2.3 + i))
			var ring := PackedVector2Array()
			for k2: int in 7:
				ring.append(at + Vector2.from_angle(TAU * k2 / 6.0) * size)
			_batch.add_polyline(ring, glow(0.4 * (1.0 - phase), bubble_color), 1.0)
	_batch.draw(canvas)
