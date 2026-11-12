class_name RockMesher
extends RefCounted
## Turns a rock outline of a 2D room floor plan (any simple polygon, concave
## too) into a 3D rock: straight sides from the floor up to its height and a
## top. The height is one value, or a value per outline point (height_at: a
## rock rising and falling along its length, dropping near a doorway; split
## long edges first with subdivide so the height can change along them). Outlines are on the floor plane (x, z) in world units. Sides get
## smooth normals round gentle bends and a hard edge at sharp corners, so a
## curved wall is lit as a curve and the sonar only outlines real corners.

## Points closer than this are merged.
const MERGE_DISTANCE: float = 0.001


## The mesh of one rock. smooth_degrees: corners sharper than this stay hard.
## height_at (optional): Callable(point: Vector2) -> float, the height at each
## outline point; height is used where it is not given.
static func rock_mesh(outline: PackedVector2Array, height: float, smooth_degrees: float, height_at: Callable = Callable()) -> ArrayMesh:
	var points: PackedVector2Array = _clean(outline)
	var count: int = points.size()
	if count < 3:
		return ArrayMesh.new()
	var heights := PackedFloat32Array()
	for point: Vector2 in points:
		heights.append(maxf(height_at.call(point) as float, 0.01) if height_at.is_valid() else height)

	# Outward normal of every edge i -> i + 1 (the sign comes from the winding).
	var area: float = 0.0
	for i: int in count:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		area += a.x * b.y - b.x * a.y
	var side: float = 1.0 if area > 0.0 else -1.0
	var edge_normals := PackedVector2Array()
	for i: int in count:
		var along: Vector2 = points[(i + 1) % count] - points[i]
		edge_normals.append(along.orthogonal().normalized() * side)

	var smooth_dot: float = cos(deg_to_rad(smooth_degrees))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in count:
		var j: int = (i + 1) % count
		var face: Vector2 = edge_normals[i]
		var at_a: Vector2 = _corner_normal(edge_normals[(i + count - 1) % count], face, smooth_dot)
		var at_b: Vector2 = _corner_normal(edge_normals[j], face, smooth_dot)
		var a0 := Vector3(points[i].x, 0.0, points[i].y)
		var b0 := Vector3(points[j].x, 0.0, points[j].y)
		var a1 := a0 + Vector3.UP * heights[i]
		var b1 := b0 + Vector3.UP * heights[j]
		var normal_a := Vector3(at_a.x, 0.0, at_a.y)
		var normal_b := Vector3(at_b.x, 0.0, at_b.y)
		var facing := Vector3(face.x, 0.0, face.y)
		_triangle(tool, a0, b0, b1, normal_a, normal_b, normal_b, facing)
		_triangle(tool, a0, b1, a1, normal_a, normal_b, normal_a, facing)

	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		push_warning("RockMesher: a rock outline could not be triangulated; it has no top.")
	# Top: smooth normals averaged from the triangles round each point (a
	# sloping top is lit as a slope).
	var top_normals: Array[Vector3] = []
	top_normals.resize(count)
	top_normals.fill(Vector3.ZERO)
	for i: int in range(0, indices.size(), 3):
		var face_normal: Vector3 = _face_normal(points, heights, indices[i], indices[i + 1], indices[i + 2])
		for k: int in 3:
			top_normals[indices[i + k]] += face_normal
	for i: int in range(0, indices.size(), 3):
		var corner := PackedVector3Array()
		var normals: Array[Vector3] = []
		for k: int in 3:
			var index: int = indices[i + k]
			corner.append(Vector3(points[index].x, heights[index], points[index].y))
			normals.append(top_normals[index].normalized() if top_normals[index].length() > 0.0 else Vector3.UP)
		_triangle(tool, corner[0], corner[1], corner[2], normals[0], normals[1], normals[2], Vector3.UP)
	return tool.commit()


## The outline with every edge longer than max_length split into equal pieces.
static func subdivide(outline: PackedVector2Array, max_length: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count: int = outline.size()
	for i: int in count:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		var pieces: int = maxi(1, ceili(a.distance_to(b) / maxf(max_length, 0.01)))
		for k: int in pieces:
			result.append(a.lerp(b, float(k) / pieces))
	return result


## Upward normal of a top triangle (its points raised to their heights).
static func _face_normal(points: PackedVector2Array, heights: PackedFloat32Array, ia: int, ib: int, ic: int) -> Vector3:
	var a := Vector3(points[ia].x, heights[ia], points[ia].y)
	var b := Vector3(points[ib].x, heights[ib], points[ib].y)
	var c := Vector3(points[ic].x, heights[ic], points[ic].y)
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.y < 0.0:
		normal = -normal
	return normal.normalized() if normal.length() > 0.0 else Vector3.UP


## A solid rock: the mesh plus a collider of the same shape (wall layer).
static func rock_body(outline: PackedVector2Array, height: float, smooth_degrees: float, material: Material, height_at: Callable = Callable()) -> StaticBody3D:
	var mesh: ArrayMesh = rock_mesh(outline, height, smooth_degrees, height_at)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	body.add_child(instance)
	if mesh.get_surface_count() > 0:
		var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		shape.backface_collision = true
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
	return body


## The normal a side face uses at a corner it shares with a neighbour face:
## blended if the bend is gentle, its own if the corner is sharp.
static func _corner_normal(neighbour: Vector2, own: Vector2, smooth_dot: float) -> Vector2:
	if neighbour.dot(own) >= smooth_dot:
		return (neighbour + own).normalized()
	return own


static func _clean(outline: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in outline:
		if points.is_empty() or points[points.size() - 1].distance_to(point) > MERGE_DISTANCE:
			points.append(point)
	if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) <= MERGE_DISTANCE:
		points.remove_at(points.size() - 1)
	return points


## Adds a triangle whose front (clockwise in Godot) looks along facing.
static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal_a: Vector3, normal_b: Vector3, normal_c: Vector3, facing: Vector3) -> void:
	var counter_clockwise: bool = (b - a).cross(c - a).dot(facing) > 0.0
	tool.set_normal(normal_a)
	tool.add_vertex(a)
	if counter_clockwise:
		tool.set_normal(normal_c)
		tool.add_vertex(c)
		tool.set_normal(normal_b)
		tool.add_vertex(b)
	else:
		tool.set_normal(normal_b)
		tool.add_vertex(b)
		tool.set_normal(normal_c)
		tool.add_vertex(c)
