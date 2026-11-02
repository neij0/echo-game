class_name GlowFx
extends RefCounted
## Drawing helpers shared by the menus' "silhouette + glow" effects (GlowButton,
## the skill cards, PulseReveal): a sonar ripple, a wavy glowing line and a
## soft glowing dot. They glow without bloom too (screens above the bloom
## layers): each is a wide faint stroke under a thin bright one.

const RIPPLE_SEGMENTS: int = 48


## A sonar ripple out of center: rings rings, ring_gap seconds apart, each
## growing to reach over duration (fast first, then slower) and fading out.
static func ripple(canvas: CanvasItem, center: Vector2, age: float, duration: float, reach: float, color: Color,
		rings: int = 2, ring_gap: float = 0.14, width: float = 1.6) -> void:
	for k: int in rings:
		var t: float = (age - ring_gap * float(k)) / duration
		if t <= 0.0 or t >= 1.0:
			continue
		var radius: float = reach * (1.0 - pow(1.0 - t, 2.5))
		var alpha: float = color.a * (1.0 - t) * (1.0 if k == 0 else 0.5)
		canvas.draw_arc(center, radius, 0.0, TAU, RIPPLE_SEGMENTS, Color(color, alpha * 0.3), width * 3.5, true)
		canvas.draw_arc(center, radius, 0.0, TAU, RIPPLE_SEGMENTS, Color(color, alpha), width, true)


## Points of a gentle wave from from_point to to_point (phase in cycles); the
## wave flattens towards both ends, so the line starts and ends cleanly.
static func wave_points(from_point: Vector2, to_point: Vector2, phase: float, wavelength: float, amplitude: float,
		step: float = 3.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var length: float = from_point.distance_to(to_point)
	if length < 1.0:
		return points
	var along: Vector2 = (to_point - from_point) / length
	var normal: Vector2 = along.orthogonal()
	var count: int = maxi(int(length / step), 2)
	for i: int in count + 1:
		var d: float = length * float(i) / float(count)
		var taper: float = sin(PI * clampf(d / length, 0.0, 1.0))
		var offset: float = sin(TAU * (d / wavelength - phase)) * amplitude * taper
		points.append(from_point + along * d + normal * offset)
	return points


## A glowing line along points: a wide faint halo under a thin bright core.
static func glow_line(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	canvas.draw_polyline(points, Color(color, color.a * 0.18), width * 5.0, true)
	canvas.draw_polyline(points, Color(color, color.a * 0.35), width * 2.2, true)
	canvas.draw_polyline(points, color, width, true)


## A soft glowing dot (a few fading circles round a bright core).
static func dot(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	for k: int in 4:
		var share: float = 1.0 - float(k) / 4.0
		canvas.draw_circle(center, radius * (1.0 + 2.2 * share), Color(color, color.a * 0.07))
	canvas.draw_circle(center, radius, color)
