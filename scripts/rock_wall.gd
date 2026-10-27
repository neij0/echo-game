@tool
class_name RockWall
extends StaticBody2D
## A grey-box rock wall: one polygon used for the visual, the collision and the
## light occluder. Its outline is drawn by SonarOverlay when a pulse hits it.
## Tall rocks (height > 0, 3/4 view): the polygon is the top / footprint, and
## build_faces adds a darker front face (RockFace) under every south-facing
## edge, with a rim light on the top edge. The faces are y-sorted with the
## players and creatures; everything else still uses the footprint.
## @tool only so the editor tool tools/propose_level.gd can read the walls;
## _ready does nothing in the editor.

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.45, 0.42, 0.40)
## Blocks shadow-casting lights (the pulse glow), creating hidden areas behind the rock.
@export var casts_shadow: bool = true

@export_group("Height (3/4 view)")
## Pixels the front face hangs below the south-facing edges. 0 = flat rock.
@export var height: float = 0.0
## Draw order of the footprint (a flat rock, or a tall rock's top): under
## everything that moves.
@export var flat_z_index: int = -1
## Draw order of the front faces (the y-sorted layer of players and creatures).
@export var face_z_index: int = 0
## Edges whose outward normal points down at least this much get a face.
@export_range(0.0, 1.0) var face_min_facing: float = 0.15
## Long edges are cut into faces of at most this length, so each piece sorts
## by its own height on screen.
@export var face_piece_length: float = 48.0
## How much darker than the top the face is right under the edge / at its bottom.
@export_range(0.0, 1.0) var face_darken_top: float = 0.35
@export_range(0.0, 1.0) var face_darken_bottom: float = 0.7
## Extra darkening of faces turned sideways (only straight-down faces get the full light).
@export_range(0.0, 1.0) var face_side_darken: float = 0.2
## Rim light on the top edge: the rock colour lightened by this much.
@export_range(0.0, 1.0) var rim_lift: float = 0.3
@export var rim_width: float = 2.0

## Sonar lines of the faces (sides + bottom edge of each run of faces), local.
var _face_lines: Array[PackedVector2Array] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("rock_walls")
	z_index = flat_z_index

	var visual := Polygon2D.new()
	visual.polygon = polygon
	visual.color = color
	add_child(visual)

	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	add_child(shape)

	if casts_shadow:
		var occluder_shape := OccluderPolygon2D.new()
		occluder_shape.polygon = polygon
		var occluder := LightOccluder2D.new()
		occluder.occluder = occluder_shape
		add_child(occluder)


## The outline points in global coordinates (used by SonarOverlay).
func get_global_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(to_global(point))
	return result


## The faces' outlines for the sonar, as open lines in global coordinates:
## for each run of faces, down one side, along the bottom, up the other side.
func get_face_lines() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for line: PackedVector2Array in _face_lines:
		result.append(global_transform * line)
	return result


## Builds the front faces of a tall rock (does nothing when height is 0).
## clippers: every rock footprint of the level in global coordinates (this
## rock's own included); a face is cut where other rock covers it. Call once,
## after the rock entered the tree.
func build_faces(clippers: Array[PackedVector2Array]) -> void:
	if height <= 0.0 or polygon.size() < 3:
		return
	# The faces join the y-sort of the level through this node.
	y_sort_enabled = true
	var to_local_transform: Transform2D = global_transform.affine_inverse()
	var own_index: int = -1
	var local_clippers: Array[PackedVector2Array] = []
	for clipper: PackedVector2Array in clippers:
		var local: PackedVector2Array = to_local_transform * clipper
		if own_index < 0 and local == polygon:
			own_index = local_clippers.size()
		local_clippers.append(local)
	var orientation: float = 1.0 if _doubled_area(polygon) > 0.0 else -1.0
	var count: int = polygon.size()
	var facing_edges: Array[bool] = []
	for i: int in count:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]
		var facing: float = _facing(a, b, orientation)
		facing_edges.append(facing >= face_min_facing)
		if facing < face_min_facing:
			continue
		var pieces: int = maxi(1, ceili(a.distance_to(b) / face_piece_length))
		for k: int in pieces:
			_add_face(a.lerp(b, float(k) / pieces), a.lerp(b, float(k + 1) / pieces), facing, local_clippers, own_index)
	_face_lines = _runs(facing_edges)


func _add_face(a: Vector2, b: Vector2, facing: float, clippers: Array[PackedVector2Array], own_index: int) -> void:
	var down := Vector2(0.0, height)
	var quad := PackedVector2Array([a, b, b + down, a + down])
	var bounds := Rect2(a, Vector2.ZERO).expand(b).expand(b + down).expand(a + down)
	var pieces: Array[PackedVector2Array] = [quad]
	var rims: Array[PackedVector2Array] = [PackedVector2Array([a, b])]
	for i: int in clippers.size():
		var clipper: PackedVector2Array = clippers[i]
		var clipper_bounds: Rect2 = _bounds_of(clipper)
		# A rock entirely inside the face would cut a hole: too small to matter.
		if not bounds.intersects(clipper_bounds) or bounds.encloses(clipper_bounds):
			continue
		var kept: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			for part: PackedVector2Array in Geometry2D.clip_polygons(piece, clipper):
				# A cut can leave a degenerate sliver that cannot be drawn.
				if not Geometry2D.triangulate_polygon(part).is_empty():
					kept.append(part)
		pieces = kept
		# The rim lies on this rock's own outline: only other rocks cut it.
		if i != own_index:
			var kept_rims: Array[PackedVector2Array] = []
			for rim: PackedVector2Array in rims:
				kept_rims.append_array(Geometry2D.clip_polyline_with_polygon(rim, clipper))
			rims = kept_rims
	if pieces.is_empty():
		return

	var face := RockFace.new()
	face.name = "Face"
	# The node sits at the bottom of the face: the y-sort line.
	var anchor := Vector2((a.x + b.x) * 0.5, maxf(a.y, b.y) + height)
	face.position = anchor
	face.z_as_relative = false
	face.z_index = face_z_index
	for piece: PackedVector2Array in pieces:
		face.polygons.append(_moved(piece, -anchor))
	for rim: PackedVector2Array in rims:
		face.rims.append(_moved(rim, -anchor))
	face.edge_from = a - anchor
	face.edge_to = b - anchor
	face.height = height
	var side: float = face_side_darken * (1.0 - facing)
	face.top_color = color.darkened(face_darken_top + side)
	face.bottom_color = color.darkened(face_darken_bottom + side)
	face.rim_color = color.lightened(rim_lift)
	face.rim_width = rim_width
	add_child(face)


## Sonar lines of every run of consecutive facing edges.
func _runs(facing_edges: Array[bool]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var count: int = facing_edges.size()
	var down := Vector2(0.0, height)
	for start: int in count:
		# A run starts at a facing edge whose previous edge does not face.
		if not facing_edges[start] or facing_edges[(start - 1 + count) % count]:
			continue
		var bottom := PackedVector2Array([polygon[start]])
		var i: int = start
		while facing_edges[i % count] and bottom.size() <= count:
			bottom.append(polygon[i % count] + down)
			i += 1
		bottom.append(polygon[i % count] + down)
		bottom.append(polygon[i % count])
		result.append(bottom)
	return result


## Downward share of the edge's outward normal (1 = faces straight down).
static func _facing(a: Vector2, b: Vector2, orientation: float) -> float:
	var direction: Vector2 = (b - a).normalized()
	return Vector2(direction.y, -direction.x).y * orientation


## Twice the signed area (positive = the outline turns clockwise on screen).
static func _doubled_area(points: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i: int in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		sum += a.x * b.y - b.x * a.y
	return sum


static func _bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


static func _moved(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(point + offset)
	return result
