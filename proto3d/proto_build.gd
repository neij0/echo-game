class_name ProtoBuild
extends RefCounted
## Mesh helpers for the 3D prototype: irregular rocks as faceted prisms (a
## footprint polygon pulled up to a height, the top drawn in a little) and
## their collision.


## An irregular closed outline round the origin (x, z).
static func rock_outline(radius: Vector2, points: int, jitter: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for i: int in points:
		var angle: float = (float(i) + rng.randf_range(-0.25, 0.25)) / float(points) * TAU
		var reach: float = 1.0 + rng.randf_range(-jitter, jitter)
		outline.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * reach)
	return outline


static func box_outline(half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)])


## A faceted prism standing on base: each top point is pulled towards the
## centre by top_inset (a share) and its height varies by height_jitter (a
## share), so no two rocks are alike. Flat normals: every face reads as a facet.
static func prism_mesh(base: PackedVector2Array, height: float, top_inset: float, height_jitter: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var center := Vector2.ZERO
	for point: Vector2 in base:
		center += point
	center /= float(base.size())
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	for point: Vector2 in base:
		bottom.append(Vector3(point.x, 0.0, point.y))
		var drawn_in: Vector2 = center + (point - center) * (1.0 - top_inset)
		top.append(Vector3(drawn_in.x, height * (1.0 + rng.randf_range(-height_jitter, height_jitter)), drawn_in.y))
	var top_height: float = 0.0
	for point: Vector3 in top:
		top_height += point.y / float(top.size())
	var top_center := Vector3(center.x, top_height, center.y)
	var floor_center := Vector3(center.x, 0.0, center.y)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in base.size():
		var j: int = (i + 1) % base.size()
		var outward: Vector3 = (bottom[i] + bottom[j]) * 0.5 - floor_center
		var side_normal: Vector3 = _facing(bottom[i], bottom[j], top[j], outward)
		_triangle(tool, bottom[i], bottom[j], top[j], side_normal)
		_triangle(tool, bottom[i], top[j], top[i], side_normal)
		_triangle(tool, top[i], top[j], top_center, _facing(top[i], top[j], top_center, Vector3.UP))
	return tool.commit()


## A solid rock: its mesh and a collider on its footprint (straight sides, so
## characters stop at its foot).
static func rock_body(base: PackedVector2Array, height: float, mesh: ArrayMesh, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	body.add_child(instance)
	var points := PackedVector3Array()
	for point: Vector2 in base:
		points.append(Vector3(point.x, 0.0, point.y))
		points.append(Vector3(point.x, height, point.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body


## The triangle's normal on the side of hint.
static func _facing(a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> Vector3:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	return normal if normal.dot(hint) >= 0.0 else -normal


## Adds a triangle whose front (clockwise in Godot) looks along normal.
static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var counter_clockwise: bool = (b - a).cross(c - a).dot(normal) > 0.0
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.add_vertex(c if counter_clockwise else b)
	tool.set_normal(normal)
	tool.add_vertex(b if counter_clockwise else c)
