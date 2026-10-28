class_name ShapeBatch
extends RefCounted
## Collects small filled shapes (dots, lines, bands, convex shapes) as
## triangles and draws them all in one call (canvas_item_add_triangle_array):
## no triangulation and no anti-aliasing geometry per shape, so things that
## redraw every frame (harmless life, swaying landmark parts, small glows)
## stay cheap. Use inside a _draw (or a draw signal) of canvas.

var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


## A convex shape (a fan from its first point).
func add_convex(points: PackedVector2Array, color_value: Color) -> void:
	var first: int = _points.size()
	for point: Vector2 in points:
		_points.append(point)
		_colors.append(color_value)
	for k: int in range(1, points.size() - 1):
		_indices.append_array([first, first + k, first + k + 1])


## A small round dot (segments around).
func add_dot(center: Vector2, radius: float, color_value: Color, segments: int = 8) -> void:
	var first: int = _points.size()
	_points.append(center)
	_colors.append(color_value)
	for k: int in segments:
		_points.append(center + Vector2.from_angle(TAU * k / segments) * radius)
		_colors.append(color_value)
	for k: int in segments:
		_indices.append_array([first, first + 1 + k, first + 1 + (k + 1) % segments])


## A straight line of the given width (a quad).
func add_line(a: Vector2, b: Vector2, color_value: Color, width: float = 1.0) -> void:
	add_segment(a, b, width, width, color_value)


## A quad from a to b, width wa at a and wb at b.
func add_segment(a: Vector2, b: Vector2, wa: float, wb: float, color_value: Color) -> void:
	if a.distance_squared_to(b) < 0.0001:
		return
	var normal: Vector2 = (b - a).normalized().orthogonal() * 0.5
	var first: int = _points.size()
	_points.append_array([a + normal * wa, b + normal * wb, b - normal * wb, a - normal * wa])
	_colors.append_array([color_value, color_value, color_value, color_value])
	_indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])


func add_polyline(points: PackedVector2Array, color_value: Color, width: float = 1.0) -> void:
	for k: int in points.size() - 1:
		add_segment(points[k], points[k + 1], width, width, color_value)


## A band along a centre line, its width going from start_width to
## end_width, with round joints.
func add_band(line: PackedVector2Array, start_width: float, end_width: float, color_value: Color) -> void:
	var count: int = line.size()
	for k: int in count - 1:
		var wa: float = lerpf(start_width, end_width, float(k) / maxf(count - 1, 1))
		var wb: float = lerpf(start_width, end_width, float(k + 1) / maxf(count - 1, 1))
		add_segment(line[k], line[k + 1], wa, wb, color_value)
		if k > 0 and wa > 1.5:
			add_dot(line[k], wa * 0.5, color_value, 6)


func is_empty() -> bool:
	return _indices.is_empty()


## Draws everything collected on canvas, then starts empty again.
func draw(canvas: CanvasItem) -> void:
	if not _indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _indices, _points, _colors)
	_points.clear()
	_colors.clear()
	_indices.clear()
