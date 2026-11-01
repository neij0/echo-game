class_name HitShapes
extends RefCounted
## Geometry for hurtboxes and attack hitboxes (world polygons), and the shape
## entries of the F2 debug view (HitboxDebugDraw). Nodes in DEBUG_GROUP answer
## get_debug_shapes() -> Array[Dictionary] (debug_shape entries).

enum Kind { HURT, HIT }

const DEBUG_GROUP: StringName = &"debug_hitboxes"
## Points of a circle polygon.
const CIRCLE_POINTS: int = 24


static func circle(center: Vector2, radius: float, points: int = CIRCLE_POINTS) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i: int in points:
		polygon.append(center + Vector2.from_angle(TAU * float(i) / float(points)) * radius)
	return polygon


## A swing's reach: the pie slice from `from` along `direction`.
static func sector(from: Vector2, direction: Vector2, reach: float, half_arc: float, points: int = 12) -> PackedVector2Array:
	var polygon := PackedVector2Array([from])
	var start: float = direction.angle() - half_arc
	for i: int in points + 1:
		polygon.append(from + Vector2.from_angle(start + 2.0 * half_arc * float(i) / float(points)) * reach)
	return polygon


## Distance from point to the polygon's edge: negative inside.
static func signed_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return INF
	var best: float = INF
	for i: int in polygon.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		best = minf(best, point.distance_to(closest))
	return -best if Geometry2D.is_point_in_polygon(point, polygon) else best


## True if the two polygons overlap.
static func overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	return not Geometry2D.intersect_polygons(a, b).is_empty()


static func debug_shape(polygon: PackedVector2Array, kind: Kind, active: bool, label: String = "") -> Dictionary:
	return {"polygon": polygon, "kind": kind, "active": active, "label": label}
