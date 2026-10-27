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

var _bounds := Rect2()


func _ready() -> void:
	add_to_group("rock_faces")
	var first: bool = true
	for fill: PackedVector2Array in fills:
		for point: Vector2 in fill:
			var global_point: Vector2 = to_global(point)
			_bounds = Rect2(global_point, Vector2.ZERO) if first else _bounds.expand(global_point)
			first = false


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
static func is_covered(tree: SceneTree, point: Vector2, sort_y: float) -> bool:
	for node: Node in tree.get_nodes_in_group("rock_faces"):
		if (node as RockFace).covers(point, sort_y):
			return true
	return false


## The pieces in front of sort_y whose bounds touch rect (global): a quick
## first pass before testing many points.
static func pieces_near(tree: SceneTree, rect: Rect2, sort_y: float) -> Array[RockFace]:
	var result: Array[RockFace] = []
	for node: Node in tree.get_nodes_in_group("rock_faces"):
		var piece := node as RockFace
		if piece.global_position.y > sort_y and piece._bounds.intersects(rect):
			result.append(piece)
	return result


func _draw() -> void:
	for i: int in shadows.size():
		draw_polygon(shadows[i], shadow_colors[i])
	for i: int in fills.size():
		draw_polygon(fills[i], fill_colors[i])
	for i: int in lines.size():
		draw_polyline(lines[i], line_colors[i], line_widths[i], true)
