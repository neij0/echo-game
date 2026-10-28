class_name LandmarkWreck
extends Landmark
## A section of a sunken ship's hull lying on the floor, a little turned: a
## pointed bow, a broken stern with the frames (ribs) sticking up out of it,
## plank lines along its side, a mast stump on the deck and the fallen mast
## lying on the floor beside it. The hull is solid (its base).

@export var hull_length: float = 330.0
@export var hull_width: float = 100.0
@export var hull_height: float = 58.0
## Turn of the hull on the floor (degrees).
@export var hull_turn_degrees: float = -10.0
## Share of the length over which the bow narrows to its point.
@export_range(0.05, 0.9) var bow_share: float = 0.38
## Frames sticking up out of the broken stern: how many, how high, how wide.
@export var frame_count: int = 4
@export var frame_height: float = 64.0
@export var frame_width: float = 7.0
@export var mast_stump_height: float = 46.0
@export var mast_width: float = 13.0
## The fallen mast on the floor: start, end (local) and its cross spar.
@export var fallen_mast_from: Vector2 = Vector2(-40.0, 112.0)
@export var fallen_mast_to: Vector2 = Vector2(190.0, 70.0)
@export var spar_length: float = 70.0
@export var plank_rows: PackedFloat32Array = PackedFloat32Array([0.3, 0.62])
@export_range(0.0, 1.0) var plank_darken: float = 0.45

var _north := PackedVector2Array()
var _south := PackedVector2Array()


func _footprint_shapes() -> Array[PackedVector2Array]:
	_make_edges()
	var outline := PackedVector2Array(_north)
	# The broken stern: a jagged edge from the north side down to the south side.
	var stern_n: Vector2 = _north[_north.size() - 1]
	var stern_s: Vector2 = _south[_south.size() - 1]
	for k: int in [1, 2, 3]:
		var t: float = k / 4.0
		outline.append(stern_n.lerp(stern_s, t) + _turned(Vector2(-14.0 if k % 2 == 1 else 6.0, 0.0)))
	var south_back := PackedVector2Array(_south)
	south_back.reverse()
	outline.append_array(south_back)
	return [outline]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([hull_height])


## The hull's two long edges, bow (left) to stern (right), turned.
func _make_edges() -> void:
	_north.clear()
	_south.clear()
	var steps: int = 14
	for k: int in steps + 1:
		var t: float = float(k) / steps
		var x: float = lerpf(-hull_length * 0.5, hull_length * 0.5, t)
		var bow: float = clampf(t / bow_share, 0.0, 1.0)
		var half: float = hull_width * 0.5 * pow(sin(bow * PI * 0.5), 0.7)
		half = maxf(half, 1.5)
		_north.append(_turned(Vector2(x, -half)))
		_south.append(_turned(Vector2(x, half)))


func _turned(p: Vector2) -> Vector2:
	return p.rotated(deg_to_rad(hull_turn_degrees))


func _build_parts() -> void:
	var wood: Color = material_color()
	var lowest_south: float = -INF
	for p: Vector2 in _south:
		lowest_south = maxf(lowest_south, p.y)
	# Plank lines over the side (in front of the hull's own face pieces).
	add_part(Vector2(0.0, lowest_south + 1.0), _draw_planks.bind(wood.darkened(plank_darken), lowest_south + 1.0))
	# Frames out of the broken stern: north ones behind the deck, south ones in front.
	for side: int in 2:
		var edge: PackedVector2Array = _north if side == 0 else _south
		var base_y: float = edge[edge.size() - 2].y + (1.0 if side == 1 else -1.0)
		add_part(Vector2(0.0, base_y), _draw_frames.bind(edge, wood.lightened(0.08), base_y))
		for k: int in frame_count:
			var root: Vector2 = _frame_root(edge, k)
			var tip: Vector2 = root + Vector2(4.0, -_frame_height(k))
			add_sonar_line(Landmark.curve(root, root.lerp(tip, 0.5) + Vector2(-6.0, 0.0), tip, 4), PackedVector2Array(), hull_height)
	# Mast stump on the deck, in front of the deck top.
	var deck: Vector2 = _turned(Vector2(-hull_length * 0.08, 0.0))
	add_part(Vector2(deck.x, lowest_south + 2.0), _draw_stump.bind(deck, wood, lowest_south + 2.0))
	add_sonar_line(PackedVector2Array([deck - Vector2(0.0, hull_height), deck - Vector2(0.0, hull_height + mast_stump_height)]), PackedVector2Array(), hull_height + mast_stump_height)
	# The fallen mast on the floor.
	var mast_base: Vector2 = fallen_mast_from.lerp(fallen_mast_to, 0.5)
	add_part(Vector2(mast_base.x, maxf(fallen_mast_from.y, fallen_mast_to.y)), _draw_fallen_mast.bind(wood, maxf(fallen_mast_from.y, fallen_mast_to.y), mast_base.x))
	add_sonar_line(PackedVector2Array([fallen_mast_from, fallen_mast_to]))


func _frame_root(edge: PackedVector2Array, k: int) -> Vector2:
	var index: int = edge.size() - 2 - k
	return edge[index] - Vector2(0.0, hull_height)


func _frame_height(k: int) -> float:
	# Broken frames: each one a different length.
	return frame_height * (0.55 + 0.45 * Landmark.hash01(k * 3.7 + 1.0))


func _draw_planks(part: Node2D, color_value: Color, base_y: float) -> void:
	for row: float in plank_rows:
		var line := PackedVector2Array()
		for k: int in _south.size():
			# Only where the side faces down (the bow's tip has no face).
			line.append(_south[k] - Vector2(0.0, hull_height * row) - Vector2(0.0, base_y))
		part.draw_polyline(line, Color(color_value, 0.8), 1.5, true)
	# Seams across the planks every few points.
	for k: int in range(3, _south.size() - 1, 3):
		var p: Vector2 = _south[k] - Vector2(0.0, base_y)
		part.draw_line(p - Vector2(0.0, hull_height * 0.95), p - Vector2(0.0, hull_height * 0.05), Color(color_value, 0.5), 1.0, true)


func _draw_frames(part: Node2D, edge: PackedVector2Array, color_value: Color, base_y: float) -> void:
	for k: int in frame_count:
		var root: Vector2 = _frame_root(edge, k) - Vector2(0.0, base_y)
		var tip: Vector2 = root + Vector2(4.0, -_frame_height(k))
		var line: PackedVector2Array = Landmark.curve(root, root.lerp(tip, 0.5) + Vector2(-6.0, 0.0), tip, 6)
		Landmark.draw_band(part, line, frame_width, frame_width * 0.55, color_value)
		part.draw_polyline(line, color_value.lightened(0.15), 1.0, true)


func _draw_stump(part: Node2D, deck: Vector2, color_value: Color, base_y: float) -> void:
	var foot: Vector2 = deck - Vector2(0.0, hull_height + base_y)
	var top: Vector2 = foot - Vector2(0.0, mast_stump_height)
	Landmark.draw_band(part, PackedVector2Array([foot, top]), mast_width, mast_width * 0.85, color_value.darkened(0.1))
	# The broken top: a jagged cap.
	part.draw_colored_polygon(PackedVector2Array([top + Vector2(-mast_width * 0.45, 0.0), top + Vector2(-2.0, -7.0), top + Vector2(2.0, -2.0), top + Vector2(mast_width * 0.45, -9.0), top + Vector2(mast_width * 0.45, 0.0)]), color_value.darkened(0.1))
	part.draw_line(foot + Vector2(-mast_width * 0.5, 0.0), top + Vector2(-mast_width * 0.45, 0.0), color_value.lightened(0.2), 1.0, true)


func _draw_fallen_mast(part: Node2D, color_value: Color, base_y: float, base_x: float) -> void:
	var offset := Vector2(base_x, base_y)
	var a: Vector2 = fallen_mast_from - offset
	var b: Vector2 = fallen_mast_to - offset
	# Lying on the floor: a round log seen from above, lit edge on top.
	Landmark.draw_band(part, PackedVector2Array([a, b]), mast_width, mast_width * 0.8, color_value.darkened(0.15))
	var along: Vector2 = (b - a).normalized()
	part.draw_line(a - along.orthogonal() * mast_width * 0.35, b - along.orthogonal() * mast_width * 0.3, color_value.lightened(0.18), 1.5, true)
	var spar_at: Vector2 = a.lerp(b, 0.62)
	var spar: Vector2 = along.rotated(1.2) * spar_length * 0.5
	Landmark.draw_band(part, PackedVector2Array([spar_at - spar, spar_at + spar]), mast_width * 0.5, mast_width * 0.45, color_value.darkened(0.2))
