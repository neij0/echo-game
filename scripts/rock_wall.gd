@tool
class_name RockWall
extends StaticBody2D
## A grey-box rock wall: one polygon used for the visual, the collision and the
## light occluder. Its outline is drawn by SonarOverlay when a pulse hits it.
## Tall rocks (height > 0, classic 3/4 view): the polygon is the BASE of the
## rock (collision, occluder, navigation and sonar stay there, so players stop
## at the foot of the rock like at a real wall). build_faces draws the rock
## standing on it: a lighter top surface (the base shifted up by height) and a
## darker front face rising from every south-facing base edge. All pieces are
## RockFace nodes y-sorted with the players and creatures by their base, so
## the rock covers whatever stands behind (north of) it.
## @tool only so the editor tool tools/propose_level.gd can read the walls;
## _ready does nothing in the editor.

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.45, 0.42, 0.40)
## Blocks shadow-casting lights (the pulse glow), creating hidden areas behind the rock.
@export var casts_shadow: bool = true

@export_group("Height (3/4 view)")
## Pixels the rock rises above its base. 0 = flat rock.
@export var height: float = 0.0
## Draw order of a flat rock: under everything that moves.
@export var flat_z_index: int = -1
## Draw order of a tall rock's pieces (the y-sorted layer of players and creatures).
@export var face_z_index: int = 0
## Tall rocks: only the base edges facing away from a light cast its shadow,
## so the top and the front face are lit by a light in front of the rock.
@export var tall_occluder_culled: bool = true
## Tall rocks: base edges within this distance of another rock (a seal against
## a wall) cast no shadow, so touching rocks light like one rock.
@export var occluder_join_margin: float = 2.0
## Base edges whose outward normal points down at least this much get a face.
@export_range(0.0, 1.0) var face_min_facing: float = 0.15
## Width of the top strips and longest face piece: each piece sorts by its
## own base, so large irregular rocks sort correctly.
@export var face_piece_length: float = 48.0

@export_group("Light and Colour (3/4 view)")
## The top surface (lit from above): the rock colour lightened by this much.
@export_range(0.0, 1.0) var top_lift: float = 0.12
## How much darker than the rock colour the face is under the rim / at the base.
@export_range(0.0, 1.0) var face_darken_top: float = 0.3
@export_range(0.0, 1.0) var face_darken_bottom: float = 0.75
## Extra darkening of faces turned sideways (only straight-down faces get the full light).
@export_range(0.0, 1.0) var face_side_darken: float = 0.2
## Rim light on the top edge of the face: the rock colour lightened by this much.
@export_range(0.0, 1.0) var rim_lift: float = 0.45
@export var rim_width: float = 2.0

@export_group("Surface Detail (3/4 view)")
## Horizontal bands of a face (more = finer colour variation).
@export var face_rows: int = 4
## Colour variation over the face (share of brightness, + or -).
@export_range(0.0, 0.5) var color_variation: float = 0.12
## Size of one colour patch, in pixels along the rock.
@export var variation_scale: float = 36.0
## Heights (0 = top of the face, 1 = base) of the horizontal strata lines.
@export var strata_heights: PackedFloat32Array = PackedFloat32Array([0.3, 0.55, 0.8])
## How far a stratum wanders up and down (pixels).
@export var strata_wobble: float = 2.5
@export_range(0.0, 1.0) var strata_darken: float = 0.4
@export_range(0.0, 1.0) var strata_alpha: float = 0.55
## Chance that a stratum is missing on one face piece (broken lines).
@export_range(0.0, 1.0) var strata_gap_chance: float = 0.3
## Chance of a short vertical crack on one face piece.
@export_range(0.0, 1.0) var crack_chance: float = 0.22
@export_range(0.0, 1.0) var crack_darken: float = 0.55
## The face's bottom edge is raised by up to this much (irregular, not a ruler line).
@export var edge_jitter: float = 3.0
## Dark band on the floor where the face meets it.
@export var contact_shadow_size: float = 14.0
@export_range(0.0, 1.0) var contact_shadow_alpha: float = 0.6

## Sonar lines of the faces (sides + top edge of each run of faces), global.
var _face_lines: Array[PackedVector2Array] = []
var _orientation: float = 1.0
var _base_occluder: LightOccluder2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("rock_walls")
	z_index = flat_z_index

	# A tall rock is drawn by its pieces (build_faces), not by the base.
	if height <= 0.0:
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
		if height > 0.0 and tall_occluder_culled:
			occluder_shape.cull_mode = _tall_cull_mode()
		_base_occluder = LightOccluder2D.new()
		_base_occluder.occluder = occluder_shape
		add_child(_base_occluder)


## The outline points in global coordinates (used by SonarOverlay).
func get_global_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(to_global(point))
	return result


## The faces' outlines for the sonar, as open lines in global coordinates:
## for each run of faces, up one side, along the top edge, down the other side.
func get_face_lines() -> Array[PackedVector2Array]:
	return _face_lines


## Builds the drawn pieces of a tall rock (does nothing when height is 0).
## Works in global space (screen up), so a turned room still stands upright.
## others: every rock base of the level, global (this one may be included).
## Call once, after the rock entered the tree.
func build_faces(others: Array[PackedVector2Array]) -> void:
	if height <= 0.0 or polygon.size() < 3:
		return
	# The pieces join the y-sort of the level through this node.
	y_sort_enabled = true
	var base: PackedVector2Array = get_global_outline()
	_open_occluder(base, others)
	_orientation = 1.0 if _doubled_area(base) > 0.0 else -1.0
	_add_top(base)
	var count: int = base.size()
	var facing_edges: Array[bool] = []
	for i: int in count:
		var a: Vector2 = base[i]
		var b: Vector2 = base[(i + 1) % count]
		var facing: float = _facing(a, b, _orientation)
		facing_edges.append(facing >= face_min_facing)
		if facing < face_min_facing:
			continue
		var pieces: int = maxi(1, ceili(a.distance_to(b) / face_piece_length))
		for k: int in pieces:
			_add_face(a.lerp(b, float(k) / pieces), a.lerp(b, float(k + 1) / pieces), facing)
	_face_lines = _runs(base, facing_edges)


## Cull the edges facing the light: the shadow starts at the far side of the
## rock, so its top and front face are lit by a light in front of it.
func _tall_cull_mode() -> OccluderPolygon2D.CullMode:
	return OccluderPolygon2D.CULL_CLOCKWISE if Geometry2D.is_polygon_clockwise(polygon) else OccluderPolygon2D.CULL_COUNTER_CLOCKWISE


## Replaces the closed occluder by open lines along the base edges that no
## other rock touches (an edge inside a wall would shade the wall itself).
func _open_occluder(base: PackedVector2Array, others: Array[PackedVector2Array]) -> void:
	if _base_occluder == null or not tall_occluder_culled:
		return
	var reach: Rect2 = _bounds_of(base).grow(occluder_join_margin)
	var cutters: Array[PackedVector2Array] = []
	for other: PackedVector2Array in others:
		if _same_outline(other, base) or not reach.intersects(_bounds_of(other)):
			continue
		cutters.append_array(Geometry2D.offset_polygon(other, occluder_join_margin))
	if cutters.is_empty():
		return
	# Edge by edge: the cut may reverse a piece, but the cull mode needs the
	# outline's own direction. Pieces that follow on are joined into one line.
	var lines: Array[PackedVector2Array] = []
	var count: int = base.size()
	for i: int in count:
		var a: Vector2 = base[i]
		var b: Vector2 = base[(i + 1) % count]
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([a, b])]
		for cutter: PackedVector2Array in cutters:
			var kept: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces:
				kept.append_array(Geometry2D.clip_polyline_with_polygon(piece, cutter))
			pieces = kept
		# Keep the original order along the edge, from a to b.
		pieces.sort_custom(func(p: PackedVector2Array, q: PackedVector2Array) -> bool: return minf(a.distance_to(p[0]), a.distance_to(p[-1])) < minf(a.distance_to(q[0]), a.distance_to(q[-1])))
		for piece: PackedVector2Array in pieces:
			if (piece[-1] - piece[0]).dot(b - a) < 0.0:
				piece.reverse()
			if not lines.is_empty() and lines[-1][-1].distance_squared_to(piece[0]) < 0.01:
				lines[-1].append(piece[-1])
			else:
				lines.append(piece)
	_base_occluder.queue_free()
	_base_occluder = null
	var to_local_transform: Transform2D = global_transform.affine_inverse()
	for line: PackedVector2Array in lines:
		if line.size() < 2:
			continue
		var shape := OccluderPolygon2D.new()
		shape.closed = false
		shape.polygon = to_local_transform * line
		shape.cull_mode = _tall_cull_mode()
		var occluder := LightOccluder2D.new()
		occluder.occluder = shape
		add_child(occluder)


## The top surface, cut into vertical strips; each strip sorts by the base
## right under it (the lowest point of the strip plus the height).
func _add_top(base: PackedVector2Array) -> void:
	var up := Vector2(0.0, -height)
	var top: PackedVector2Array = _moved(base, up)
	var bounds: Rect2 = _bounds_of(top)
	var top_color: Color = color.lightened(top_lift)
	var x: float = floorf(bounds.position.x / face_piece_length) * face_piece_length
	while x < bounds.end.x:
		var strip := PackedVector2Array([
			Vector2(x, bounds.position.y - 1.0), Vector2(x + face_piece_length, bounds.position.y - 1.0),
			Vector2(x + face_piece_length, bounds.end.y + 1.0), Vector2(x, bounds.end.y + 1.0),
		])
		for part: PackedVector2Array in Geometry2D.intersect_polygons(top, strip):
			# A cut can leave a degenerate sliver that cannot be drawn.
			if Geometry2D.triangulate_polygon(part).is_empty():
				continue
			# Just above the face pieces on the same base, so the rim stays on top.
			var base_y: float = _bounds_of(part).end.y + height - 0.5
			var piece: RockFace = _new_piece(base_y)
			piece.fills.append(_moved(part, -Vector2(0.0, base_y)))
			piece.fill_colors.append(_repeated(top_color, part.size()))
			add_child(piece)
		x += face_piece_length


## The front face over one piece (a -> b) of a south-facing base edge, global.
func _add_face(a: Vector2, b: Vector2, facing: float) -> void:
	if is_equal_approx(a.x, b.x):
		return
	var origin := Vector2(0.0, maxf(a.y, b.y))
	var piece: RockFace = _new_piece(origin.y)
	var side: float = face_side_darken * (1.0 - facing)
	var top_color: Color = color.darkened(face_darken_top + side)
	var bottom_color: Color = color.darkened(face_darken_bottom + side)
	var mid: Vector2 = a.lerp(b, 0.5)
	var seed_value: float = mid.x * 0.731 + mid.y * 1.137

	# Contact shadow on the floor (from just inside the raised bottom edge).
	var shade := Color(0.0, 0.0, 0.0, contact_shadow_alpha)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	var lift := Vector2(0.0, -edge_jitter)
	var drop := Vector2(0.0, contact_shadow_size)
	piece.shadows.append(_moved(PackedVector2Array([a + lift, b + lift, b + drop, a + drop]), -origin))
	piece.shadow_colors.append(PackedColorArray([shade, shade, clear, clear]))

	# Horizontal bands: vertical gradient (darker to the base) and colour patches.
	for row: int in face_rows:
		var t0: float = float(row) / face_rows
		var t1: float = float(row + 1) / face_rows
		var points := PackedVector2Array([_face_point(a, t0), _face_point(b, t0), _face_point(b, t1)])
		var colors := PackedColorArray([_face_color(a, t0, top_color, bottom_color), _face_color(b, t0, top_color, bottom_color), _face_color(b, t1, top_color, bottom_color)])
		if row == face_rows - 1:
			# The irregular bottom edge gets a middle point too.
			points.append(_face_point(mid, t1))
			colors.append(_face_color(mid, t1, top_color, bottom_color))
		points.append(_face_point(a, t1))
		colors.append(_face_color(a, t1, top_color, bottom_color))
		if Geometry2D.triangulate_polygon(points).is_empty():
			continue
		piece.fills.append(_moved(points, -origin))
		piece.fill_colors.append(colors)

	# Strata: dark wavy lines along the rock, broken here and there.
	for k: int in strata_heights.size():
		if _hash(seed_value + k * 17.0) < strata_gap_chance:
			continue
		var t: float = strata_heights[k]
		var line := PackedVector2Array()
		for point: Vector2 in [a, mid, b]:
			var wobble: float = strata_wobble * _noise(point.x / 19.0 + k * 7.3)
			line.append(_face_point(point, t) + Vector2(0.0, wobble) - origin)
		var stratum: Color = top_color.lerp(bottom_color, t).darkened(strata_darken)
		_add_line(piece, line, Color(stratum, strata_alpha), 1.0)

	# Now and then a short crack from the rim downwards.
	if _hash(seed_value + 91.0) < crack_chance:
		var start: Vector2 = a.lerp(b, 0.3 + 0.4 * _hash(seed_value + 5.0))
		var end_t: float = 0.45 + 0.4 * _hash(seed_value + 11.0)
		var crack := PackedVector2Array()
		for step: int in 4:
			var t: float = lerpf(0.04, end_t, step / 3.0)
			var sway: float = 3.0 * _noise(seed_value + step * 2.7) * minf(step, 1.0)
			crack.append(_face_point(start, t) + Vector2(sway, 0.0) - origin)
		_add_line(piece, crack, top_color.darkened(crack_darken), 1.0)

	# Rim light where the top meets the face.
	_add_line(piece, PackedVector2Array([_face_point(a, 0.0) - origin, _face_point(b, 0.0) - origin]), color.lightened(rim_lift), rim_width)
	add_child(piece)


## A point of the face above base point p: t = 0 at the top edge, 1 at the
## base (raised a little by the irregular edge).
func _face_point(p: Vector2, t: float) -> Vector2:
	var y: float = -height * (1.0 - t)
	if t >= 1.0:
		y -= edge_jitter * (0.5 + 0.5 * _noise(p.x / 11.0 + 3.0))
	return p + Vector2(0.0, y)


func _face_color(p: Vector2, t: float, top_color: Color, bottom_color: Color) -> Color:
	var patch: float = 1.0 + color_variation * _noise(p.x / variation_scale + t * 2.3)
	var c: Color = top_color.lerp(bottom_color, t)
	return Color(c.r * patch, c.g * patch, c.b * patch, c.a)


## A new piece on the y-sort line base_y (global), axis-aligned in global
## space even when the room is turned. Fill it, then add it as a child (its
## _ready measures the fills).
func _new_piece(base_y: float) -> RockFace:
	var piece := RockFace.new()
	piece.name = "Piece"
	piece.z_as_relative = false
	piece.z_index = face_z_index
	piece.transform = global_transform.affine_inverse() * Transform2D(0.0, Vector2(0.0, base_y))
	return piece


static func _add_line(piece: RockFace, line: PackedVector2Array, line_color: Color, width: float) -> void:
	piece.lines.append(line)
	piece.line_colors.append(line_color)
	piece.line_widths.append(width)


## Sonar lines of every run of consecutive facing edges (global).
func _runs(base: PackedVector2Array, facing_edges: Array[bool]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var count: int = facing_edges.size()
	var up := Vector2(0.0, -height)
	for start: int in count:
		# A run starts at a facing edge whose previous edge does not face.
		if not facing_edges[start] or facing_edges[(start - 1 + count) % count]:
			continue
		var line := PackedVector2Array([base[start]])
		var i: int = start
		while facing_edges[i % count] and line.size() <= count:
			line.append(base[i % count] + up)
			i += 1
		line.append(base[i % count] + up)
		line.append(base[i % count])
		result.append(line)
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


## True if both outlines have the same points (up to float noise).
static func _same_outline(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i].distance_squared_to(b[i]) > 0.01:
			return false
	return true


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


static func _repeated(value: Color, count: int) -> PackedColorArray:
	var result := PackedColorArray()
	for i: int in count:
		result.append(value)
	return result


## Stable pseudo-random value in [0, 1) for a number (same rock = same look).
static func _hash(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)


## Smooth value noise in [-1, 1].
static func _noise(x: float) -> float:
	var cell: float = floorf(x)
	var f: float = x - cell
	return lerpf(_hash(cell), _hash(cell + 1.0), f * f * (3.0 - 2.0 * f)) * 2.0 - 1.0
