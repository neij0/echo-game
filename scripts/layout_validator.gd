class_name LayoutValidator
extends RefCounted
## Grid flood fill (BFS) over a stage's wall polygons, before anything is added
## to the world: is every important point reachable from the start for a body
## of the players' size, and is the stage sealed (no way out into the void)?

## Size of one grid cell in pixels.
var cell_size: float = 20.0
## Free space needed around a cell centre (player radius + a small margin).
var clearance: float = 16.0
## Extra grid space around the walls, so a leak can reach the grid border.
var border: float = 200.0
## A target counts as reached if a reached cell is within this many cells.
var target_cells: int = 2

var _origin: Vector2
var _columns: int = 0
var _rows: int = 0
var _blocked: PackedByteArray = PackedByteArray()
var _reached: PackedByteArray = PackedByteArray()
var leaked: bool = false


## Builds the grid and floods it from start. Returns false if the flood leaks
## out of the walls.
func flood(polygons: Array[PackedVector2Array], start: Vector2) -> bool:
	var bounds := Rect2(polygons[0][0], Vector2.ZERO)
	for polygon: PackedVector2Array in polygons:
		for point: Vector2 in polygon:
			bounds = bounds.expand(point)
	bounds = bounds.grow(border)
	_origin = bounds.position
	_columns = ceili(bounds.size.x / cell_size)
	_rows = ceili(bounds.size.y / cell_size)
	_blocked.resize(_columns * _rows)
	_blocked.fill(0)
	for polygon: PackedVector2Array in polygons:
		_rasterize(polygon)

	_reached.resize(_columns * _rows)
	_reached.fill(0)
	leaked = false
	var start_index: int = _index_at(start)
	if start_index < 0 or _blocked[start_index] == 1:
		return false
	var stack := PackedInt32Array([start_index])
	_reached[start_index] = 1
	while not stack.is_empty():
		var current: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x: int = current % _columns
		var y: int = current / _columns
		if x == 0 or y == 0 or x == _columns - 1 or y == _rows - 1:
			leaked = true
			continue
		for next: int in [current - 1, current + 1, current - _columns, current + _columns]:
			if _blocked[next] == 0 and _reached[next] == 0:
				_reached[next] = 1
				stack.append(next)
	return not leaked


func is_reachable(point: Vector2) -> bool:
	var cx: int = int((point.x - _origin.x) / cell_size)
	var cy: int = int((point.y - _origin.y) / cell_size)
	for oy: int in range(-target_cells, target_cells + 1):
		for ox: int in range(-target_cells, target_cells + 1):
			var x: int = cx + ox
			var y: int = cy + oy
			if x >= 0 and y >= 0 and x < _columns and y < _rows and _reached[y * _columns + x] == 1:
				return true
	return false


func _index_at(point: Vector2) -> int:
	var x: int = int((point.x - _origin.x) / cell_size)
	var y: int = int((point.y - _origin.y) / cell_size)
	if x < 0 or y < 0 or x >= _columns or y >= _rows:
		return -1
	return y * _columns + x


## Marks every cell whose centre is inside the polygon or closer than
## clearance to one of its edges.
func _rasterize(polygon: PackedVector2Array) -> void:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		box = box.expand(point)
	box = box.grow(clearance)
	var x0: int = maxi(int((box.position.x - _origin.x) / cell_size), 0)
	var y0: int = maxi(int((box.position.y - _origin.y) / cell_size), 0)
	var x1: int = mini(int((box.end.x - _origin.x) / cell_size), _columns - 1)
	var y1: int = mini(int((box.end.y - _origin.y) / cell_size), _rows - 1)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var index: int = y * _columns + x
			if _blocked[index] == 1:
				continue
			var center := Vector2(_origin.x + (x + 0.5) * cell_size, _origin.y + (y + 0.5) * cell_size)
			if Geometry2D.is_point_in_polygon(center, polygon):
				_blocked[index] = 1
	# Edges: cells near any edge, checked only along the edge itself.
	var reach: int = ceili(clearance / cell_size) + 1
	for i: int in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var steps: int = maxi(1, ceili(a.distance_to(b) / cell_size))
		for s: int in steps + 1:
			var p: Vector2 = a.lerp(b, float(s) / steps)
			var px: int = int((p.x - _origin.x) / cell_size)
			var py: int = int((p.y - _origin.y) / cell_size)
			for y: int in range(py - reach, py + reach + 1):
				for x: int in range(px - reach, px + reach + 1):
					if x < 0 or y < 0 or x >= _columns or y >= _rows:
						continue
					var index: int = y * _columns + x
					if _blocked[index] == 1:
						continue
					var center := Vector2(_origin.x + (x + 0.5) * cell_size, _origin.y + (y + 0.5) * cell_size)
					if Geometry2D.get_closest_point_to_segment(center, a, b).distance_to(center) < clearance:
						_blocked[index] = 1
