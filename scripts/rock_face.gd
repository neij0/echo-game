class_name RockFace
extends Node2D
## One drawn piece of a tall rock (3/4 view), built by RockWall.build_faces:
## either a strip of the top surface or the front face over one piece of a
## south-facing base edge (with its strata, cracks, rim light and the contact
## shadow on the floor). The node sits on the rock's base (the bottom of the
## rock in that column), so the y-sort draws a character standing north of
## the rock (behind it) under the piece and one standing south over it.
## Drawn in the world and lit by real lights. Visual only: collision,
## occluders, navigation and sonar use the base footprint (RockWall.polygon).

## Filled shapes in this node's space, each with one colour per point.
var fills: Array[PackedVector2Array] = []
var fill_colors: Array[PackedColorArray] = []
## Lines drawn over the fills (strata, cracks, rim light).
var lines: Array[PackedVector2Array] = []
var line_colors: Array[Color] = []
var line_widths: Array[float] = []
## Fills drawn first that do not hide what is behind (the contact shadow).
var shadows: Array[PackedVector2Array] = []
var shadow_colors: Array[PackedColorArray] = []
## Multiplied over the fills (rock grain), repeating every texture_size
## pixels in global space, so neighbouring pieces continue the same grain.
var texture: Texture2D
var texture_size: float = 256.0
## False for a piece that never hides anything (the ground shadow): it stays
## out of the cover tests.
var covers_things: bool = true

## Size of one cell of the lookup grid (global pixels).
const GRID_CELL: float = 256.0

## Every piece in the tree by grid cell (Vector2i -> Array of RockFace), so a
## cover test only looks at the pieces near the point.
static var _grid: Dictionary = {}

## The fills' bounds in global space, if the builder knows them (else they
## are measured in _ready).
var global_bounds := Rect2()

var _bounds := Rect2()
var _cells: Array[Vector2i] = []


func _ready() -> void:
	if texture:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if not covers_things:
		return
	_bounds = global_bounds
	if not _bounds.has_area():
		var first: bool = true
		for fill: PackedVector2Array in fills:
			for point: Vector2 in fill:
				var global_point: Vector2 = to_global(point)
				_bounds = Rect2(global_point, Vector2.ZERO) if first else _bounds.expand(global_point)
				first = false
	_cells = _cells_of(_bounds)
	for cell: Vector2i in _cells:
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(self)


func _exit_tree() -> void:
	for cell: Vector2i in _cells:
		var list: Array = _grid.get(cell, [])
		list.erase(self)
		if list.is_empty():
			_grid.erase(cell)
	_cells.clear()


static func _cells_of(rect: Rect2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(floori(rect.position.y / GRID_CELL), floori(rect.end.y / GRID_CELL) + 1):
		for x: int in range(floori(rect.position.x / GRID_CELL), floori(rect.end.x / GRID_CELL) + 1):
			cells.append(Vector2i(x, y))
	return cells


## True if this piece is drawn over the given point (global) for something
## standing at sort_y: the piece is in front (its base is lower on screen).
func covers(point: Vector2, sort_y: float) -> bool:
	if global_position.y <= sort_y or not _bounds.has_point(point):
		return false
	var local: Vector2 = to_local(point)
	for fill: PackedVector2Array in fills:
		if Geometry2D.is_point_in_polygon(local, fill):
			return true
	return false


## True if any tall rock covers the point for something standing at sort_y
## (used to fade glow layers, which are drawn above the world, and to show
## the occluded players' outlines).
static func is_covered(_tree: SceneTree, point: Vector2, sort_y: float) -> bool:
	var cell := Vector2i(floori(point.x / GRID_CELL), floori(point.y / GRID_CELL))
	for piece: RockFace in _grid.get(cell, []):
		if piece.covers(point, sort_y):
			return true
	return false


## The pieces in front of sort_y whose bounds touch rect (global): a quick
## first pass before testing many points.
static func pieces_near(_tree: SceneTree, rect: Rect2, sort_y: float) -> Array[RockFace]:
	var result: Array[RockFace] = []
	for cell: Vector2i in _cells_of(rect):
		for piece: RockFace in _grid.get(cell, []):
			if piece.global_position.y > sort_y and piece._bounds.intersects(rect) and not result.has(piece):
				result.append(piece)
	return result


func _draw() -> void:
	for i: int in shadows.size():
		draw_polygon(shadows[i], shadow_colors[i])
	for i: int in fills.size():
		if texture == null:
			draw_polygon(fills[i], fill_colors[i])
			continue
		var uvs := PackedVector2Array()
		for point: Vector2 in fills[i]:
			uvs.append((point + global_position) / texture_size)
		draw_polygon(fills[i], fill_colors[i], uvs, texture)
	for i: int in lines.size():
		draw_polyline(lines[i], line_colors[i], line_widths[i], true)
