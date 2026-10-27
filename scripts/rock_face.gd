class_name RockFace
extends Node2D
## The front face under one south-facing piece of a tall rock's edge (3/4
## view), built by RockWall.build_faces. The node sits at the bottom of the
## face, so the y-sort draws a character whose position is above that line
## (inside the face band) behind the face, and one below it in front.
## Drawn in the world and lit by real lights. Visual only: collision,
## occluders, navigation and sonar use the rock footprint (RockWall.polygon).

## The face (the clipped quad, may be several pieces), in this node's space.
var polygons: Array[PackedVector2Array] = []
## The rim light along the top edge (clipped too), in this node's space.
var rims: Array[PackedVector2Array] = []
## The footprint edge this face hangs from, in this node's space (gradient).
var edge_from: Vector2
var edge_to: Vector2
var height: float = 1.0
var top_color: Color
var bottom_color: Color
var rim_color: Color
var rim_width: float = 2.0

var _bounds := Rect2()


func _ready() -> void:
	add_to_group("rock_faces")
	var first: bool = true
	for polygon: PackedVector2Array in polygons:
		for point: Vector2 in polygon:
			var global_point: Vector2 = to_global(point)
			_bounds = Rect2(global_point, Vector2.ZERO) if first else _bounds.expand(global_point)
			first = false


## True if this face is drawn over the given point (global): the point is in
## the face band, so a character there is behind the rock.
func covers(point: Vector2) -> bool:
	if not _bounds.has_point(point):
		return false
	var local: Vector2 = to_local(point)
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(local, polygon):
			return true
	return false


## True if any tall rock's face covers the point (used to fade glow layers,
## which are drawn above the world, while their owner is behind a rock).
static func is_covered(tree: SceneTree, point: Vector2) -> bool:
	for node: Node in tree.get_nodes_in_group("rock_faces"):
		if (node as RockFace).covers(point):
			return true
	return false


func _draw() -> void:
	for polygon: PackedVector2Array in polygons:
		var colors := PackedColorArray()
		for point: Vector2 in polygon:
			var depth: float = clampf((point.y - _edge_y_at(point.x)) / height, 0.0, 1.0)
			colors.append(top_color.lerp(bottom_color, depth))
		draw_polygon(polygon, colors)
	for rim: PackedVector2Array in rims:
		draw_polyline(rim, rim_color, rim_width)


## Height of the footprint edge above x (the top of the face there).
func _edge_y_at(x: float) -> float:
	if is_equal_approx(edge_from.x, edge_to.x):
		return minf(edge_from.y, edge_to.y)
	var t: float = clampf((x - edge_from.x) / (edge_to.x - edge_from.x), 0.0, 1.0)
	return lerpf(edge_from.y, edge_to.y, t)
