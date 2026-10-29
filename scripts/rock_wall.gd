@tool
class_name RockWall
extends StaticBody2D
## A grey-box rock wall: one polygon used for the visual, the collision and the
## light occluder. Its outline is drawn by SonarOverlay when a pulse hits it.
## Tall rocks (height > 0, classic 3/4 view): the polygon is the BASE of the
## rock (collision, occluder and navigation stay there, so players stop at
## the foot of the rock like at a real wall). The sonar outlines what the eye
## sees instead (get_sonar_lines): the top, the face sides, the front base.
## build_faces draws the rock standing on it: a lighter top surface (the base
## shifted up by the height at each point and drawn in a little, so the base is
## wider than the top) and a darker front face rising from every south-facing
## base edge. The height varies along the rock (height_at) and drops near the
## doorways (clear_zones). All pieces are RockFace nodes y-sorted with the
## players and creatures by their base, so the rock covers whatever stands
## behind (north of) it.
## @tool only so the editor tool tools/propose_level.gd can read the walls;
## _ready does nothing in the editor.

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.45, 0.42, 0.40)
## Blocks shadow-casting lights (the pulse glow), creating hidden areas behind the rock.
@export var casts_shadow: bool = true
## A flat rock (height 0) is drawn as its polygon; false = collision only
## (a landmark draws that solid part itself, e.g. a fallen column drum).
@export var draw_flat: bool = true

@export_group("Height (3/4 view)")
## Pixels the rock rises above its base (its middle height). 0 = flat rock.
@export var height: float = 0.0
## The height varies by up to this much (+ or -) along the rock (height_at).
@export var height_spread: float = 0.0
## Size of one rise or dip of the height, in pixels along the rock.
@export var height_wave: float = 200.0
## A steady tilt: the height changes by this much per pixel (global x / y)
## away from slope_origin (a wreck's bow raised, its stern sunk in the sand).
@export var height_slope: Vector2 = Vector2.ZERO
## The top is drawn this much inside the base (the base is a little wider).
## Not where the rock touches other rock, so touching tops stay joined.
@export var top_inset: float = 5.0
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
## Tall rocks: sonar outline within this distance of another rock (a seal a
## few pixels behind the wall's face, the room's edge) is left out, so the
## seams between rocks do not show.
@export var sonar_side_margin: float = 6.0
## Spacing of the points of the sonar outline (each gets its own line of sight).
@export var sonar_point_spacing: float = 12.0
## Base edges whose outward normal points down at least this much get a face
## (near 0: every edge facing down at all, so the outline has no steps).
@export_range(0.0, 1.0) var face_min_facing: float = 0.02
## Width of the top strips and longest face piece: each piece sorts by its
## own base, so large irregular rocks sort correctly.
@export var face_piece_length: float = 64.0

@export_group("Light and Colour (3/4 view)")
## The top surface (lit from above): the rock colour lightened by this much.
## Clearly lighter than the floor, so the top never reads as floor.
@export_range(0.0, 1.0) var top_lift: float = 0.36
## The tops are also on this light layer, lit by the raised copy of each
## player's light (PlayerLight.top_light_layer, same number).
@export var top_light_layer: int = 2
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

@export_group("Grain (3/4 view)")
## Rock grain multiplied over the top and the faces (SurfaceTextures): how
## dark its darkest specks get, their size, the share of horizontal streaks
## (strata), and the pixels after which it repeats.
@export_range(0.0, 1.0) var grain_strength: float = 0.32
@export var grain_frequency: float = 0.06
@export_range(0.0, 1.0) var grain_streaks: float = 0.4
@export var grain_size: int = 256
@export var grain_seed: int = 11

@export_group("Ground Shadow (3/4 view)")
## Soft dark band on the floor around the base, wider and darker below the
## front face, so the rock sits on the floor. Under players and creatures.
@export var ground_shadow_size: float = 16.0
@export_range(0.0, 1.0) var ground_shadow_alpha: float = 0.35
@export var front_shadow_size: float = 34.0
@export_range(0.0, 1.0) var front_shadow_alpha: float = 0.55
@export var ground_shadow_z_index: int = -2

@export_group("Top Detail (3/4 view)")
## Light variation over the top (share of brightness, + or -), in patches of
## top_variation_scale pixels; the top is cut into cells of top_cell_size.
@export_range(0.0, 0.5) var top_variation: float = 0.1
@export var top_variation_scale: float = 70.0
@export var top_cell_size: float = 96.0
## Small details on the top: one try per detail_spacing pixels (each way), each
## kept with detail_chance, never closer than detail_margin to the top's edge.
@export var detail_spacing: float = 46.0
@export_range(0.0, 1.0) var detail_chance: float = 0.16
@export var detail_margin: float = 14.0
## Shares of the kept details (the rest are barnacles).
@export_range(0.0, 1.0) var crack_share: float = 0.4
@export_range(0.0, 1.0) var moss_share: float = 0.35
@export var top_crack_length: float = 26.0
@export_range(0.0, 1.0) var top_crack_darken: float = 0.45
@export var moss_color: Color = Color(0.3, 0.42, 0.3)
## How far the moss colour replaces the top colour, and its patch size.
@export_range(0.0, 1.0) var moss_strength: float = 0.4
@export var moss_radius: float = 9.0
@export_range(0.0, 1.0) var barnacle_lift: float = 0.35
@export var barnacle_radius: float = 2.2

## Doorway corridors (global, set by the LevelBuilder): within clear_distance
## of them the rock drops to clear_height, so its top never hides a doorway or
## the players walking through it.
var clear_zones: Array[Rect2] = []
## Global point where height_slope adds nothing.
var slope_origin: Vector2 = Vector2.ZERO
var clear_height: float = 10.0
var clear_distance: float = 140.0

## Sonar outline of a tall rock (global): the visible lines, the point the
## line of sight is checked to for each of their points (on the base), and
## whether that check may pass through this rock (the top is seen from above).
var _sonar_lines: Array[PackedVector2Array] = []
var _sonar_sights: Array[PackedVector2Array] = []
var _sonar_through_self: Array[bool] = []
var _orientation: float = 1.0
var _base_occluder: LightOccluder2D
## Height above each point of the top outline (while building).
var _top_heights := PackedFloat32Array()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("rock_walls")
	z_index = flat_z_index

	# A tall rock is drawn by its pieces (build_faces), not by the base.
	if height <= 0.0 and draw_flat:
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


## What the sonar outlines of a tall rock, as open lines in global
## coordinates: the top surface's outline, the vertical sides at the ends of
## each run of faces and the front base edge where the faces meet the floor.
## The part of the base hidden under the top is never included, nor the lines
## along which this rock touches another one (a seal against a wall, the rock
## of the next room or the outer rock beyond the room's edge).
## Empty for a flat rock (the sonar uses get_global_outline).
func get_sonar_lines() -> Array[PackedVector2Array]:
	return _sonar_lines


## For each point of get_sonar_lines(): where the line of sight is checked
## (straight below it, on the base).
func get_sonar_sights() -> Array[PackedVector2Array]:
	return _sonar_sights


## For each line of get_sonar_lines(): true if its line of sight may pass
## through this rock (the top outline seen from above, the face sides).
func get_sonar_through_self() -> Array[bool]:
	return _sonar_through_self


## Builds the drawn pieces of a tall rock (does nothing when height is 0).
## Works in global space (screen up), so a turned room still stands upright.
## others: every rock base of the level, global (this one may be included).
## room: the rect of the room this rock belongs to, global (empty = none);
## beyond its edges lies other rock. other_bounds: the bounds of others (same
## order; computed here when empty). Call once, after the rock entered the tree.
func build_faces(others: Array[PackedVector2Array], room: Rect2, other_bounds: Array[Rect2] = []) -> void:
	if height <= 0.0 or polygon.size() < 3:
		return
	# The pieces join the y-sort of the level through this node.
	y_sort_enabled = true
	var outline: PackedVector2Array = get_global_outline()
	if other_bounds.is_empty():
		other_bounds = _bounds_list(others)
	var base_cutters: Array[PackedVector2Array] = _cutters(outline, others, other_bounds, occluder_join_margin)
	_open_occluder(outline, base_cutters)
	_orientation = 1.0 if _doubled_area(outline) > 0.0 else -1.0
	# Where this rock touches other rock (another base, the next room or the
	# outer rock beyond the room's edge).
	var touch_cutters: Array[PackedVector2Array] = base_cutters.duplicate()
	var sonar_cutters: Array[PackedVector2Array] = _cutters(outline, others, other_bounds, sonar_side_margin)
	if room.has_area():
		touch_cutters.append_array(_beyond(room.grow(-occluder_join_margin)))
		sonar_cutters.append_array(_beyond(room.grow(-sonar_side_margin)))
	# Short edges, so the height can change along the rock; one top point per base point.
	var base: PackedVector2Array = _densified(outline, face_piece_length)
	var top: PackedVector2Array = _top_outline(base, touch_cutters)
	_add_top(top)
	var count: int = base.size()
	var faces: Array[PackedVector2Array] = []
	var face_base_ys := PackedFloat32Array()
	for i: int in count:
		var next: int = (i + 1) % count
		var facing: float = _facing(base[i], base[next], _orientation)
		if facing >= face_min_facing:
			_add_face(base[i], base[next], top[i], top[next], facing)
			faces.append(PackedVector2Array([base[i], base[next], top[next], top[i]]))
			face_base_ys.append(maxf(base[i].y, base[next].y))
	_add_ground_shadow(base, touch_cutters)
	_build_sonar_lines(outline, top, faces, face_base_ys, sonar_cutters)


## Height of the rock above base point p (global): its middle height with a
## slow rise and fall along the rock, dropping to clear_height near a doorway.
func height_at(p: Vector2) -> float:
	var h: float = height + height_spread * _noise2(p / maxf(height_wave, 1.0)) + height_slope.dot(p - slope_origin)
	if not clear_zones.is_empty():
		var distance: float = INF
		for zone: Rect2 in clear_zones:
			var dx: float = maxf(maxf(zone.position.x - p.x, p.x - zone.end.x), 0.0)
			var dy: float = maxf(maxf(zone.position.y - p.y, p.y - zone.end.y), 0.0)
			distance = minf(distance, Vector2(dx, dy).length())
		var f: float = clampf(distance / maxf(clear_distance, 1.0), 0.0, 1.0)
		h = lerpf(minf(clear_height, h), h, f * f * (3.0 - 2.0 * f))
	return maxf(h, 0.0)


## The top outline: every base point raised by its height and moved in by
## top_inset (not where the rock touches other rock).
func _top_outline(base: PackedVector2Array, touch_cutters: Array[PackedVector2Array]) -> PackedVector2Array:
	var count: int = base.size()
	var top := PackedVector2Array()
	_top_heights.clear()
	var touch_bounds: Array[Rect2] = _bounds_list(touch_cutters)
	for i: int in count:
		var p: Vector2 = base[i]
		var into_prev: Vector2 = _inward(base[(i - 1 + count) % count], p)
		var into_next: Vector2 = _inward(p, base[(i + 1) % count])
		var inward: Vector2 = (into_prev + into_next).normalized()
		var inset: float = 0.0 if _inside_any(p, touch_cutters, touch_bounds) else top_inset
		# Mitre, limited so a sharp corner does not shoot out.
		inset /= maxf(inward.dot(into_next), 0.5)
		var h: float = height_at(p)
		_top_heights.append(h)
		top.append(p + inward * inset - Vector2(0.0, h))
	return top


func _inward(a: Vector2, b: Vector2) -> Vector2:
	var direction: Vector2 = (b - a).normalized()
	return -Vector2(direction.y, -direction.x) * _orientation


## The outlines near this one (not itself), grown by margin: lines inside
## them are where two rocks touch.
func _cutters(outline: PackedVector2Array, others: Array[PackedVector2Array], other_bounds: Array[Rect2], margin: float) -> Array[PackedVector2Array]:
	var reach: Rect2 = _bounds_of(outline).grow(margin)
	var cutters: Array[PackedVector2Array] = []
	for i: int in others.size():
		var other: PackedVector2Array = others[i]
		if not reach.intersects(other_bounds[i]) or _same_outline(other, outline):
			continue
		cutters.append_array(Geometry2D.offset_polygon(other, margin))
	return cutters


## Cull the edges facing the light: the shadow starts at the far side of the
## rock, so its top and front face are lit by a light in front of it.
func _tall_cull_mode() -> OccluderPolygon2D.CullMode:
	return OccluderPolygon2D.CULL_CLOCKWISE if Geometry2D.is_polygon_clockwise(polygon) else OccluderPolygon2D.CULL_COUNTER_CLOCKWISE


## Replaces the closed occluder by open lines along the base edges that no
## other rock touches (an edge inside a wall would shade the wall itself).
func _open_occluder(base: PackedVector2Array, cutters: Array[PackedVector2Array]) -> void:
	if _base_occluder == null or not tall_occluder_culled:
		return
	if cutters.is_empty():
		return
	# Edge by edge: the cut may reverse a piece, but the cull mode needs the
	# outline's own direction. Pieces that follow on are joined into one line.
	var lines: Array[PackedVector2Array] = []
	var cutter_bounds: Array[Rect2] = _bounds_list(cutters)
	var count: int = base.size()
	for i: int in count:
		var a: Vector2 = base[i]
		var b: Vector2 = base[(i + 1) % count]
		var pieces: Array[PackedVector2Array] = _clipped(PackedVector2Array([a, b]), cutters, cutter_bounds)
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
## under it (the lowest point of the strip plus the lowest height there, so it
## never sorts in front of a character standing at the rock's foot). Each strip
## is cut into cells for the light variation, then the details go on top.
func _add_top(top: PackedVector2Array) -> void:
	var bounds: Rect2 = _bounds_of(top)
	var top_color: Color = color.lightened(top_lift)
	var size: float = face_piece_length
	var pieces: Array[RockFace] = []
	var parts: Array[PackedVector2Array] = []
	var x_start: float = floorf(bounds.position.x / size) * size
	var lowest: PackedFloat32Array = _lowest_heights(top, x_start, size)
	var x: float = x_start
	while x < bounds.end.x:
		var strip := _rect_polygon(Rect2(x, bounds.position.y - 1.0, size, bounds.size.y + 2.0))
		for part: PackedVector2Array in Geometry2D.intersect_polygons(top, strip):
			# A strip cut from a simple outline has no holes (so the point order
			# says nothing: some outlines run the other way); only degenerate
			# slivers are skipped.
			if Geometry2D.triangulate_polygon(part).is_empty():
				continue
			var part_bounds: Rect2 = _bounds_of(part)
			var base_y: float = part_bounds.end.y + lowest[roundi((x - x_start) / size)] - 0.5
			var piece: RockFace = _new_piece(base_y)
			piece.global_bounds = part_bounds
			piece.light_mask = 1 | (1 << (top_light_layer - 1))
			# Lighter than the floor only near a light (TopLightFalloff).
			piece.material = TopLightFalloff.material()
			var y: float = floorf(part_bounds.position.y / top_cell_size) * top_cell_size
			while y < part_bounds.end.y:
				for cell: PackedVector2Array in Geometry2D.intersect_polygons(part, _rect_polygon(Rect2(x, y, size, top_cell_size))):
					if not _drawable(cell):
						continue
					var colors := PackedColorArray()
					for point: Vector2 in cell:
						var patch: float = 1.0 + top_variation * _noise2(point / top_variation_scale)
						colors.append(Color(top_color.r * patch, top_color.g * patch, top_color.b * patch))
					piece.fills.append(_moved(cell, -Vector2(0.0, base_y)))
					piece.fill_colors.append(colors)
				y += top_cell_size
			pieces.append(piece)
			parts.append(part)
		x += size
	_add_top_details(top, top_color, pieces, parts)
	for piece: RockFace in pieces:
		add_child(piece)


## For every strip (from x0, strip_width wide) the smallest height of the top
## edges that cross it, in one pass over the outline.
func _lowest_heights(top: PackedVector2Array, x0: float, strip_width: float) -> PackedFloat32Array:
	var bounds: Rect2 = _bounds_of(top)
	var strips: int = ceili((bounds.end.x - x0) / strip_width) + 1
	var lowest := PackedFloat32Array()
	lowest.resize(strips)
	lowest.fill(height)
	var seen := PackedByteArray()
	seen.resize(strips)
	seen.fill(0)
	for i: int in top.size():
		var next: int = (i + 1) % top.size()
		var h: float = minf(_top_heights[i], _top_heights[next])
		var first: int = clampi(floori((minf(top[i].x, top[next].x) - x0) / strip_width), 0, strips - 1)
		var last: int = clampi(floori((maxf(top[i].x, top[next].x) - x0) / strip_width), 0, strips - 1)
		for k: int in range(first, last + 1):
			lowest[k] = h if seen[k] == 0 else minf(lowest[k], h)
			seen[k] = 1
	return lowest


## Cracks, moss patches and barnacle clusters scattered over the top, each in
## the strip piece it lies on (same rock = same look every attempt).
func _add_top_details(top: PackedVector2Array, top_color: Color, pieces: Array[RockFace], parts: Array[PackedVector2Array]) -> void:
	# Shrinking a simple outline gives no holes, only pieces.
	var inner: Array[PackedVector2Array] = Geometry2D.offset_polygon(top, -detail_margin)
	if inner.is_empty():
		return
	var bounds: Rect2 = _bounds_of(top)
	var crack_color: Color = top_color.darkened(top_crack_darken)
	var moss: Color = top_color.lerp(moss_color, moss_strength)
	var barnacle: Color = top_color.lightened(barnacle_lift)
	var gy: float = floorf(bounds.position.y / detail_spacing) * detail_spacing
	while gy < bounds.end.y:
		var gx: float = floorf(bounds.position.x / detail_spacing) * detail_spacing
		while gx < bounds.end.x:
			var key: float = gx * 0.371 + gy * 1.913
			var p := Vector2(gx + detail_spacing * _hash(key + 3.1), gy + detail_spacing * _hash(key + 7.7))
			gx += detail_spacing
			if _hash(key) > detail_chance or not _inside_any(p, inner):
				continue
			var index: int = -1
			for i: int in parts.size():
				if Geometry2D.is_point_in_polygon(p, parts[i]):
					index = i
					break
			if index < 0:
				continue
			var piece: RockFace = pieces[index]
			# From global space into the piece's space.
			var offset := Vector2(0.0, -_piece_base_y(piece))
			var kind: float = _hash(key + 13.3)
			if kind < crack_share:
				var angle: float = TAU * _hash(key + 17.9)
				var length: float = top_crack_length * (0.6 + 0.6 * _hash(key + 19.1))
				var crack := PackedVector2Array()
				for step: int in 4:
					var sway: Vector2 = Vector2.from_angle(angle + PI * 0.5) * 3.0 * _noise(key + step * 2.3) * minf(step, 1.0)
					crack.append(p + Vector2.from_angle(angle) * length * (step / 3.0 - 0.5) + sway + offset)
				_add_line(piece, crack, crack_color, 1.0)
			elif kind < crack_share + moss_share:
				var radius: float = moss_radius * (0.7 + 0.6 * _hash(key + 23.7))
				_add_fill(piece, _blob(p + offset, radius, key), moss)
			else:
				for k: int in 3 + int(_hash(key + 29.3) * 3.0):
					var spot: Vector2 = p + Vector2.from_angle(TAU * _hash(key + k * 5.1)) * barnacle_radius * 3.0 * _hash(key + k * 3.3)
					_add_fill(piece, _blob(spot + offset, barnacle_radius * (0.6 + 0.6 * _hash(key + k)), key + k), barnacle)
		gy += detail_spacing


## One flat-coloured shape (skipped if too small to be drawn).
static func _add_fill(piece: RockFace, shape: PackedVector2Array, fill_color: Color) -> void:
	if not _drawable(shape):
		return
	piece.fills.append(shape)
	piece.fill_colors.append(_repeated(fill_color, shape.size()))


## False for slivers the renderer cannot triangulate (tiny or degenerate).
static func _drawable(shape: PackedVector2Array) -> bool:
	return absf(_doubled_area(shape)) >= 2.0 and not Geometry2D.triangulate_polygon(shape).is_empty()


## The global y line a piece sorts on (its transform is a pure move from
## global space, see _new_piece).
func _piece_base_y(piece: RockFace) -> float:
	return (global_transform * piece.transform).origin.y


## A small soft-edged round patch of 7 points around center.
static func _blob(center: Vector2, radius: float, key: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k: int in 7:
		var r: float = radius * (0.75 + 0.35 * _hash(key + k * 1.7))
		points.append(center + Vector2.from_angle(TAU * k / 7.0) * r)
	return points


static func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


## The front face over one south-facing base edge (a -> b), global, up to
## the top edge above it (at -> bt).
func _add_face(a: Vector2, b: Vector2, at: Vector2, bt: Vector2, facing: float) -> void:
	# A very short edge has nothing to show (and its shapes cannot be drawn).
	if absf(a.x - b.x) < 1.0:
		return
	var origin := Vector2(0.0, maxf(a.y, b.y))
	var piece: RockFace = _new_piece(origin.y)
	piece.global_bounds = _bounds_of(PackedVector2Array([a, b, at, bt]))
	var side: float = face_side_darken * (1.0 - facing)
	var top_color: Color = color.darkened(face_darken_top + side)
	var bottom_color: Color = color.darkened(face_darken_bottom + side)
	var mid: Vector2 = a.lerp(b, 0.5)
	var seed_value: float = mid.x * 0.731 + mid.y * 1.137
	var edge := PackedVector2Array([a, b, at, bt])

	# Contact shadow on the floor (from just inside the raised bottom edge).
	var shade := Color(0.0, 0.0, 0.0, contact_shadow_alpha)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	var lift := Vector2(0.0, -edge_jitter)
	var drop := Vector2(0.0, contact_shadow_size)
	var contact: PackedVector2Array = _moved(PackedVector2Array([a + lift, b + lift, b + drop, a + drop]), -origin)
	if _drawable(contact):
		piece.shadows.append(contact)
		piece.shadow_colors.append(PackedColorArray([shade, shade, clear, clear]))

	# Horizontal bands: vertical gradient (darker to the base) and colour patches.
	for row: int in face_rows:
		var t0: float = float(row) / face_rows
		var t1: float = float(row + 1) / face_rows
		var points := PackedVector2Array([_face_point(edge, 0.0, t0), _face_point(edge, 1.0, t0), _face_point(edge, 1.0, t1)])
		var colors := PackedColorArray([_face_color(a, t0, top_color, bottom_color), _face_color(b, t0, top_color, bottom_color), _face_color(b, t1, top_color, bottom_color)])
		if row == face_rows - 1:
			# The irregular bottom edge gets a middle point too.
			points.append(_face_point(edge, 0.5, t1))
			colors.append(_face_color(mid, t1, top_color, bottom_color))
		points.append(_face_point(edge, 0.0, t1))
		colors.append(_face_color(a, t1, top_color, bottom_color))
		if not _drawable(points):
			continue
		piece.fills.append(_moved(points, -origin))
		piece.fill_colors.append(colors)

	# Strata: dark wavy lines along the rock, broken here and there.
	for k: int in strata_heights.size():
		if _hash(seed_value + k * 17.0) < strata_gap_chance:
			continue
		var t: float = strata_heights[k]
		var line := PackedVector2Array()
		for u: float in [0.0, 0.5, 1.0]:
			var wobble: float = strata_wobble * _noise(a.lerp(b, u).x / 19.0 + k * 7.3)
			line.append(_face_point(edge, u, t) + Vector2(0.0, wobble) - origin)
		var stratum: Color = top_color.lerp(bottom_color, t).darkened(strata_darken)
		_add_line(piece, line, Color(stratum, strata_alpha), 1.0)

	# Now and then a short crack from the rim downwards.
	if _hash(seed_value + 91.0) < crack_chance:
		var u_start: float = 0.3 + 0.4 * _hash(seed_value + 5.0)
		var end_t: float = 0.45 + 0.4 * _hash(seed_value + 11.0)
		var crack := PackedVector2Array()
		for step: int in 4:
			var t: float = lerpf(0.04, end_t, step / 3.0)
			var sway: float = 3.0 * _noise(seed_value + step * 2.7) * minf(step, 1.0)
			crack.append(_face_point(edge, u_start, t) + Vector2(sway, 0.0) - origin)
		_add_line(piece, crack, top_color.darkened(crack_darken), 1.0)

	# Rim light where the top meets the face.
	_add_line(piece, PackedVector2Array([at - origin, bt - origin]), color.lightened(rim_lift), rim_width)
	add_child(piece)


## A point of the face over edge = [a, b, at, bt]: u along the edge (0 = a),
## t = 0 at the top edge, 1 at the base (raised a little by the irregular edge).
func _face_point(edge: PackedVector2Array, u: float, t: float) -> Vector2:
	var bottom: Vector2 = edge[0].lerp(edge[1], u)
	var point: Vector2 = edge[2].lerp(edge[3], u).lerp(bottom, t)
	if t >= 1.0:
		point.y -= edge_jitter * (0.5 + 0.5 * _noise(bottom.x / 11.0 + 3.0))
	return point


func _face_color(p: Vector2, t: float, top_color: Color, bottom_color: Color) -> Color:
	var patch: float = 1.0 + color_variation * _noise(p.x / variation_scale + t * 2.3)
	var c: Color = top_color.lerp(bottom_color, t)
	return Color(c.r * patch, c.g * patch, c.b * patch, c.a)


## A new piece on the y-sort line base_y (global), axis-aligned in global
## space even when the room is turned. Fill it, then add it as a child (its
## _ready measures the fills).
func _new_piece(base_y: float) -> RockFace:
	# No name: thousands of siblings with one name make every add_child search
	# for a free one.
	var piece := RockFace.new()
	piece.z_as_relative = false
	piece.z_index = face_z_index
	piece.texture = SurfaceTextures.rock_grain(grain_size, grain_strength, grain_frequency, grain_streaks, grain_seed)
	piece.texture_size = grain_size
	piece.transform = global_transform.affine_inverse() * Transform2D(0.0, Vector2(0.0, base_y))
	return piece


static func _add_line(piece: RockFace, line: PackedVector2Array, line_color: Color, width: float) -> void:
	piece.lines.append(line)
	piece.line_colors.append(line_color)
	piece.line_widths.append(width)


## The ground shadow: a band along every base edge (wider and darker the
## more the edge faces down) plus a small fan at each outer corner, on the
## floor under everything that moves. Not where the rock touches other rock.
func _add_ground_shadow(base: PackedVector2Array, touch_cutters: Array[PackedVector2Array]) -> void:
	var piece := RockFace.new()
	piece.covers_things = false
	piece.z_as_relative = false
	piece.z_index = ground_shadow_z_index
	piece.transform = global_transform.affine_inverse()
	var touch_bounds: Array[Rect2] = _bounds_list(touch_cutters)
	var count: int = base.size()
	var normals := PackedVector2Array()
	var sizes := PackedFloat32Array()
	var shades := PackedColorArray()
	for i: int in count:
		var a: Vector2 = base[i]
		var b: Vector2 = base[(i + 1) % count]
		var down: float = clampf(_facing(a, b, _orientation), 0.0, 1.0)
		normals.append(-_inward(a, b))
		sizes.append(lerpf(ground_shadow_size, front_shadow_size, down))
		shades.append(Color(0.0, 0.0, 0.0, lerpf(ground_shadow_alpha, front_shadow_alpha, down)))
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	for i: int in count:
		var out: Vector2 = normals[i] * sizes[i]
		for part: PackedVector2Array in _clipped(PackedVector2Array([base[i], base[(i + 1) % count]]), touch_cutters, touch_bounds):
			var first: Vector2 = part[0]
			var last: Vector2 = part[part.size() - 1]
			var band := PackedVector2Array([first, last, last + out, first + out])
			if first.distance_squared_to(last) < 1.0 or not _drawable(band):
				continue
			piece.shadows.append(band)
			piece.shadow_colors.append(PackedColorArray([shades[i], shades[i], clear, clear]))
		# Outer corner: fill the wedge between this edge's band and the previous one's.
		var previous: int = (i - 1 + count) % count
		var p: Vector2 = base[i]
		var fan := PackedVector2Array([p, p + normals[previous] * sizes[previous], p + out])
		if not _drawable(fan) or _inside_any(p, touch_cutters, touch_bounds) or Geometry2D.is_point_in_polygon((fan[1] + fan[2]) * 0.5, base):
			continue
		piece.shadows.append(fan)
		piece.shadow_colors.append(PackedColorArray([shades[i], clear, clear]))
	add_child(piece)


## The sonar outline (see get_sonar_lines), global: the outer silhouette of
## the drawn rock (the top and every face as one shape: top outline, face
## sides, front base edge) and the rim where a face meets the top, where no
## face in front hides it. Never the lines inside the shape (a concave rock's
## hidden edges) and never where the rock touches other rock: a point whose
## base point lies inside a cutter is left out.
func _build_sonar_lines(outline: PackedVector2Array, top: PackedVector2Array, faces: Array[PackedVector2Array], face_base_ys: PackedFloat32Array, cutters: Array[PackedVector2Array]) -> void:
	_sonar_lines.clear()
	_sonar_sights.clear()
	_sonar_through_self.clear()
	var cutter_bounds: Array[Rect2] = _bounds_list(cutters)
	# The silhouette: the top merged with every face (they share the rim).
	var silhouette: PackedVector2Array = top
	for face: PackedVector2Array in faces:
		if absf(_doubled_area(face)) < 2.0:
			continue
		var merged: PackedVector2Array = _largest(Geometry2D.merge_polygons(silhouette, face))
		if not merged.is_empty():
			silhouette = merged
	var loop: PackedVector2Array = _densified(silhouette, sonar_point_spacing)
	loop.append(loop[0])
	_add_sonar_run(loop, outline, cutters, cutter_bounds)
	# Rims: the top edge of each face, unless a face in front covers it.
	var face_bounds: Array[Rect2] = _bounds_list(faces)
	for f: int in faces.size():
		var at: Vector2 = faces[f][3]
		var bt: Vector2 = faces[f][2]
		var steps: int = maxi(1, ceili(at.distance_to(bt) / sonar_point_spacing))
		var rim := PackedVector2Array()
		for k: int in steps + 1:
			# Just inside the ends: the corners touch the neighbouring faces.
			var point: Vector2 = at.lerp(bt, clampf(float(k) / steps, 0.02, 0.98))
			var hidden: bool = false
			for g: int in faces.size():
				if face_base_ys[g] > face_base_ys[f] + 0.5 and face_bounds[g].has_point(point) and Geometry2D.is_point_in_polygon(point, faces[g]):
					hidden = true
					break
			if hidden:
				_add_sonar_run(rim, outline, cutters, cutter_bounds)
				rim = PackedVector2Array()
			else:
				rim.append(point)
		_add_sonar_run(rim, outline, cutters, cutter_bounds)


## Adds a run of outline points as sonar lines. Each point gets the point its
## line of sight is checked to: on the front base edge the point itself (it
## must not be seen through the rock), else the base straight below it (the
## ray may pass through this rock: the top and the sides are seen from above).
## A point whose sight point lies over a cutter (other rock) splits the run.
func _add_sonar_run(points: PackedVector2Array, outline: PackedVector2Array, cutters: Array[PackedVector2Array], cutter_bounds: Array[Rect2]) -> void:
	var line := PackedVector2Array()
	var sights := PackedVector2Array()
	var line_on_base: bool = false
	for point: Vector2 in points:
		var on_base: bool = Geometry2D.is_point_in_polygon(point + Vector2(0.0, -2.0), outline) and not Geometry2D.is_point_in_polygon(point + Vector2(0.0, 2.0), outline)
		var sight: Vector2 = point if on_base else point + Vector2(0.0, height_at(point))
		if _inside_any(sight, cutters, cutter_bounds):
			_add_sonar_line(line, sights, not line_on_base)
			line = PackedVector2Array()
			sights = PackedVector2Array()
			continue
		if not line.is_empty() and on_base != line_on_base:
			# The kind of point changes: a new line, joined to the old one.
			var joint: Vector2 = line[line.size() - 1]
			var joint_sight: Vector2 = sights[sights.size() - 1]
			_add_sonar_line(line, sights, not line_on_base)
			line = PackedVector2Array([joint])
			sights = PackedVector2Array([joint if on_base else joint_sight])
		line.append(point)
		sights.append(sight)
		line_on_base = on_base
	_add_sonar_line(line, sights, not line_on_base)


static func _largest(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area: float = 0.0
	for polygon: PackedVector2Array in polygons:
		var area: float = absf(_doubled_area(polygon))
		if area > best_area:
			best_area = area
			best = polygon
	return best


## Four bands around rect (outside it), as polygons.
static func _beyond(rect: Rect2) -> Array[PackedVector2Array]:
	var far: float = maxf(rect.size.x, rect.size.y)
	var outer: Rect2 = rect.grow(far)
	var bands: Array[Rect2] = [
		Rect2(outer.position, Vector2(outer.size.x, rect.position.y - outer.position.y)),
		Rect2(Vector2(outer.position.x, rect.end.y), Vector2(outer.size.x, outer.end.y - rect.end.y)),
		Rect2(Vector2(outer.position.x, rect.position.y), Vector2(rect.position.x - outer.position.x, rect.size.y)),
		Rect2(Vector2(rect.end.x, rect.position.y), Vector2(outer.end.x - rect.end.x, rect.size.y)),
	]
	var result: Array[PackedVector2Array] = []
	for band: Rect2 in bands:
		result.append(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]))
	return result


func _add_sonar_line(line: PackedVector2Array, sights: PackedVector2Array, through_self: bool) -> void:
	if line.size() < 2 or line.size() != sights.size():
		return
	_sonar_lines.append(line)
	_sonar_sights.append(sights)
	_sonar_through_self.append(through_self)


## The parts of an open line outside every cutter.
## bounds: the cutters' bounds (_bounds_list), to skip the far ones quickly.
static func _clipped(line: PackedVector2Array, cutters: Array[PackedVector2Array], bounds: Array[Rect2] = []) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [line]
	var line_bounds: Rect2 = _bounds_of(line)
	for c: int in cutters.size():
		var cutter: PackedVector2Array = cutters[c]
		if not bounds.is_empty() and not bounds[c].intersects(line_bounds, true):
			continue
		var kept: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			kept.append_array(Geometry2D.clip_polyline_with_polygon(piece, cutter))
		pieces = kept
	return pieces


static func _inside_any(point: Vector2, cutters: Array[PackedVector2Array], bounds: Array[Rect2] = []) -> bool:
	for c: int in cutters.size():
		if not bounds.is_empty() and not bounds[c].has_point(point):
			continue
		if Geometry2D.is_point_in_polygon(point, cutters[c]):
			return true
	return false


static func _bounds_list(polygons: Array[PackedVector2Array]) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for polygon: PackedVector2Array in polygons:
		result.append(_bounds_of(polygon))
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


## Smooth 2D value noise in [-1, 1].
static func _noise2(p: Vector2) -> float:
	var cell := Vector2(floorf(p.x), floorf(p.y))
	var f: Vector2 = p - cell
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var top_row: float = lerpf(_hash(cell.x * 57.0 + cell.y * 113.0), _hash((cell.x + 1.0) * 57.0 + cell.y * 113.0), f.x)
	var bottom_row: float = lerpf(_hash(cell.x * 57.0 + (cell.y + 1.0) * 113.0), _hash((cell.x + 1.0) * 57.0 + (cell.y + 1.0) * 113.0), f.x)
	return lerpf(top_row, bottom_row, f.y) * 2.0 - 1.0


## The outline with extra points, so no edge is longer than max_length.
static func _densified(points: PackedVector2Array, max_length: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i: int in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var pieces: int = maxi(1, ceili(a.distance_to(b) / max_length))
		for k: int in pieces:
			result.append(a.lerp(b, float(k) / pieces))
	return result
