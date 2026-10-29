class_name LandmarkWreck
extends Landmark
## A sunken ship broken in two, lying in the sand (3/4 view): the bow half
## with its pointed, curved hull tilted up out of the sand (RockWall
## height_slope: high bow, sunk break) and a bowsprit sticking out of it; a
## gap where the planks are torn away and the curved frames (ribs) stand out
## of the sand; the sunk stern piece behind it. The broken mast lies across
## the hull onto the sand with its yard and a rope; barrels, a cabin fragment
## and loose planks are scattered around. Hull pieces, cabin and upright
## barrels are solid.
## Variation: floor_turn turns the whole wreck on the floor; damage widens the
## gap, sinks the hull, breaks more frames and drops the stern piece when
## wrecked; the variant picks the mast's fall, the frames and the debris.

@export var hull_turn_degrees: float = -8.0
## The bow half: from the bow tip (x) to the break (x), its beam (half width)
## and how far the bow narrows (share of the length).
@export var bow_x: float = -170.0
@export var break_x: float = 30.0
@export var beam: float = 56.0
@export_range(0.1, 1.0) var bow_share: float = 0.62
## Height at the bow tip and at the break (intact; damage sinks the break).
@export var bow_height: float = 72.0
@export var break_height: float = 32.0
@export var damage_sink: float = 16.0
## The gap with the frames (intact .. wrecked width), frame spacing and size.
@export var gap_min: float = 48.0
@export var gap_max: float = 92.0
@export var frame_spacing: float = 19.0
@export var frame_width: float = 6.0
## The stern piece: its length, height, extra turn and narrowing; it is gone
## above stern_gone_damage.
@export var stern_length: float = 92.0
@export var stern_height: float = 26.0
@export var stern_turn_degrees: float = 9.0
@export_range(0.0, 1.0) var stern_gone_damage: float = 0.85
@export var bowsprit_length: float = 62.0
@export var bowsprit_rise: float = 34.0
@export var mast_width: float = 11.0
@export var mast_length_min: float = 120.0
@export var mast_length_max: float = 160.0
@export var stump_height: float = 30.0
@export var barrel_radius: float = 12.0
@export var barrel_height: float = 22.0
@export var cabin_size: Vector2 = Vector2(46.0, 30.0)
@export var cabin_height: float = 30.0
@export var plank_rows: PackedFloat32Array = PackedFloat32Array([0.28, 0.55, 0.8])
@export_range(0.0, 1.0) var plank_darken: float = 0.45
@export var loose_planks: int = 4


# --- Layout (design space; _f turns it onto the floor) -------------------------

func _f(p: Vector2) -> Vector2:
	return p.rotated(floor_turn + deg_to_rad(hull_turn_degrees))


func _gap() -> float:
	return lerpf(gap_min, gap_max, damage)


func _break_height() -> float:
	return break_height - damage_sink * damage


## Height of the bow half's deck edge above design point p.
func _hull_h(p: Vector2) -> float:
	var slope: float = (_break_height() - bow_height) / (break_x - bow_x)
	return bow_height + (p.x - bow_x) * slope


func _half(x: float) -> float:
	var t: float = clampf((x - bow_x) / ((break_x - bow_x) * bow_share), 0.0, 1.0)
	return maxf(beam * pow(sin(t * PI * 0.5), 1.15), 1.5)


## A gentle curve of the keel line (the hull is not a straight box).
func _keel_y(x: float) -> float:
	return 7.0 * sin((x - bow_x) / (break_x - bow_x) * PI)


func _has_stern() -> bool:
	return damage < stern_gone_damage


func _stern_start() -> float:
	return break_x + _gap()


func _stern_point(p: Vector2) -> Vector2:
	var center := Vector2(_stern_start() + stern_length * 0.5, 0.0)
	return center + (p - center).rotated(deg_to_rad(stern_turn_degrees))


## Edges of the bow half (design space): north and south, bow to break.
func _bow_edges() -> Array[PackedVector2Array]:
	var north := PackedVector2Array()
	var south := PackedVector2Array()
	var steps: int = 14
	for k: int in steps + 1:
		var x: float = lerpf(bow_x, break_x, float(k) / steps)
		north.append(Vector2(x, _keel_y(x) - _half(x)))
		south.append(Vector2(x, _keel_y(x) + _half(x)))
	return [north, south]


func _bow_outline() -> PackedVector2Array:
	var edges: Array[PackedVector2Array] = _bow_edges()
	var outline := PackedVector2Array(edges[0])
	# The torn break: a jagged edge from the north side to the south side.
	var a: Vector2 = edges[0][edges[0].size() - 1]
	var b: Vector2 = edges[1][edges[1].size() - 1]
	for k: int in [1, 2, 3, 4]:
		outline.append(a.lerp(b, k / 5.0) + Vector2(-16.0 * rand(k * 1.3) - 2.0 if k % 2 == 1 else 6.0 * rand(k * 2.1), 0.0))
	var south := PackedVector2Array(edges[1])
	south.reverse()
	outline.append_array(south)
	return outline


func _stern_outline() -> PackedVector2Array:
	var x0: float = _stern_start()
	var points := PackedVector2Array()
	# Jagged front (towards the gap), the sides narrowing to a flat transom.
	var half0: float = beam * 0.95
	var half1: float = beam * 0.72
	points.append(Vector2(x0, -half0))
	points.append(Vector2(x0 + stern_length, -half1))
	points.append(Vector2(x0 + stern_length, half1))
	points.append(Vector2(x0, half0))
	for k: int in [1, 2, 3]:
		points.append(Vector2(x0 + (10.0 * rand(k + 30.0) if k % 2 == 1 else -6.0), half0 - half0 * 2.0 * k / 4.0))
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(_stern_point(point))
	return result


## Debris spots (design space, before the turn): upright barrels and the
## fallen cabin; every variant moves them a little.
func _barrels() -> PackedVector2Array:
	var spots := PackedVector2Array([Vector2(-96.0, 96.0), Vector2(break_x + _gap() * 0.5, -96.0)])
	if damage > 0.35:
		spots.append(Vector2(-20.0, -104.0))
	for i: int in spots.size():
		spots[i] += Vector2(rand(i * 3.7 + 40.0) - 0.5, rand(i * 5.3 + 41.0) - 0.5) * 30.0
	return spots


func _cabin_center() -> Vector2:
	return Vector2(_stern_start() + stern_length * 0.4, 100.0) + Vector2(rand(44.0) - 0.5, rand(45.0) - 0.5) * 30.0


func _cabin_outline() -> PackedVector2Array:
	var half: Vector2 = cabin_size * 0.5
	var turn: float = lerpf(-0.5, 0.5, rand(46.0))
	var result := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		result.append(_f(_cabin_center() + corner.rotated(turn)))
	return result


func _footprint_shapes() -> Array[PackedVector2Array]:
	var shapes: Array[PackedVector2Array] = [_mapped(_bow_outline())]
	if _has_stern():
		shapes.append(_mapped(_stern_outline()))
	shapes.append(_cabin_outline())
	for spot: Vector2 in _barrels():
		shapes.append(Landmark.ellipse(_f(spot), Vector2(barrel_radius, barrel_radius * 0.8), 10))
	return shapes


func _footprint_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array([_hull_h(Vector2.ZERO)])
	if _has_stern():
		heights.append(stern_height - damage_sink * 0.5 * damage)
	heights.append(cabin_height)
	for _spot: Vector2 in _barrels():
		heights.append(barrel_height)
	return heights


func _footprint_slopes() -> PackedVector2Array:
	var slope: float = (_break_height() - bow_height) / (break_x - bow_x)
	return PackedVector2Array([_f(Vector2(slope, 0.0))])


func _mapped(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(_f(point))
	return result


# --- Parts ---------------------------------------------------------------------

func _build_parts() -> void:
	var wood: Color = material_color()
	var edges: Array[PackedVector2Array] = _bow_edges()
	var front_y: float = _lowest_y(_mapped(_bow_outline())) + 1.0
	add_part(Vector2(0.0, front_y), _draw_hull_detail.bind(edges, wood, front_y))
	if _has_stern():
		var stern_front: float = _lowest_y(_mapped(_stern_outline())) + 1.0
		add_part(Vector2(_f(_stern_point(Vector2(_stern_start() + stern_length * 0.5, 0.0))).x, stern_front), _draw_stern_detail.bind(wood, stern_front))
	_add_frames(wood)
	_add_bowsprit(wood)
	_add_mast(wood)
	var cabin_front: float = _lowest_y(_cabin_outline()) + 1.0
	add_part(Vector2(_f(_cabin_center()).x, cabin_front), _draw_cabin.bind(wood, cabin_front))
	for spot: Vector2 in _barrels():
		var floor_spot: Vector2 = _f(spot)
		add_part(floor_spot + Vector2(0.0, barrel_radius * 0.8 + 1.0), _draw_barrel_hoops.bind(wood, floor_spot + Vector2(0.0, barrel_radius * 0.8 + 1.0), floor_spot))
	add_part(_f(Vector2(break_x, 130.0)), _draw_loose.bind(wood, _f(Vector2(break_x, 130.0))))


static func _lowest_y(points: PackedVector2Array) -> float:
	var lowest: float = -INF
	for point: Vector2 in points:
		lowest = maxf(lowest, point.y)
	return lowest


## Plank lines along the bow half's side and deck, the torn plank ends at
## the break, and a hatch on the deck.
func _draw_hull_detail(part: Node2D, edges: Array[PackedVector2Array], wood: Color, base_y: float) -> void:
	var offset := Vector2(0.0, base_y)
	var dark: Color = wood.darkened(plank_darken)
	for side: int in 2:
		var edge: PackedVector2Array = edges[side]
		for row: float in plank_rows:
			var line := PackedVector2Array()
			for p: Vector2 in edge:
				line.append(Landmark.project(_f(p), _hull_h(p) * (1.0 - row)) - offset)
			part.draw_polyline(line, Color(dark, 0.8), 1.4, true)
			# Torn plank ends sticking out past the break.
			var end: Vector2 = edge[edge.size() - 1]
			var stub: float = 6.0 + 22.0 * rand(row * 9.0 + side)
			part.draw_line(Landmark.project(_f(end), _hull_h(end) * (1.0 - row)) - offset, Landmark.project(_f(end + Vector2(stub, 0.0)), _hull_h(end) * (1.0 - row) - 2.0) - offset, wood.lightened(0.1), 2.0, true)
	# Deck planks along the length, and a dark hatch.
	for share: float in [-0.5, 0.0, 0.5]:
		var line := PackedVector2Array()
		for k: int in range(3, edges[0].size()):
			var p: Vector2 = edges[0][k].lerp(edges[1][k], 0.5 + share * 0.5)
			line.append(Landmark.project(_f(p), _hull_h(p)) - offset)
		part.draw_polyline(line, Color(dark, 0.6), 1.0, true)
	var hatch := PackedVector2Array()
	for corner: Vector2 in [Vector2(-70.0, -14.0), Vector2(-40.0, -14.0), Vector2(-40.0, 14.0), Vector2(-70.0, 14.0)]:
		hatch.append(Landmark.project(_f(corner), _hull_h(corner)) - offset)
	part.draw_colored_polygon(hatch, wood.darkened(0.7))
	# The gunwale: a lit rail along the deck edge.
	for side: int in 2:
		var rail := PackedVector2Array()
		for p: Vector2 in edges[side]:
			rail.append(Landmark.project(_f(p), _hull_h(p)) - offset)
		part.draw_polyline(rail, wood.lightened(0.22), 1.5, true)


func _draw_stern_detail(part: Node2D, wood: Color, base_y: float) -> void:
	var x0: float = _stern_start()
	var h: float = stern_height - damage_sink * 0.5 * damage
	var base_x: float = _f(_stern_point(Vector2(x0 + stern_length * 0.5, 0.0))).x
	var offset := Vector2(base_x, base_y)
	for side: float in [-1.0, 1.0]:
		for row: float in plank_rows:
			var a: Vector2 = _f(_stern_point(Vector2(x0 + 6.0, side * beam * 0.92)))
			var b: Vector2 = _f(_stern_point(Vector2(x0 + stern_length, side * beam * 0.72)))
			part.draw_line(Landmark.project(a, h * (1.0 - row)) - offset, Landmark.project(b, h * (1.0 - row)) - offset, Color(wood.darkened(plank_darken), 0.8), 1.4, true)
	# The transom's window frames.
	var transom: Vector2 = _f(_stern_point(Vector2(x0 + stern_length, 0.0)))
	for k: int in 2:
		var at: Vector2 = Landmark.project(transom + Vector2(0.0, -8.0 + k * 16.0), h * 0.55) - offset
		part.draw_colored_polygon(PackedVector2Array([at + Vector2(-3.0, -5.0), at + Vector2(3.0, -5.0), at + Vector2(3.0, 5.0), at + Vector2(-3.0, 5.0)]), wood.darkened(0.75))


## The frames in the gap: curved timbers rising out of the sand in pairs, from
## the keel out and up like the hull's ribs; some broken, some gone.
func _add_frames(wood: Color) -> void:
	var count: int = maxi(int(_gap() / frame_spacing), 2)
	for k: int in count:
		var x: float = break_x + 12.0 + k * (_gap() - 18.0) / maxf(count - 1, 1)
		for side: float in [-1.0, 1.0]:
			if rand(k * 4.1 + side) < 0.15 + 0.3 * damage:
				continue
			var line: PackedVector2Array = _frame_line(x, side, k)
			var floor_points: PackedVector2Array = _frame_floor(x, side, line.size())
			var base: Vector2 = floor_points[floor_points.size() - 1] + Vector2(0.0, side)
			add_part(base, _draw_frame.bind(line, wood.lightened(0.06), base))
			add_sonar_line(line, floor_points)


## How far up a frame still reaches (1 = whole, less = broken).
func _frame_reach(k: int, side: float) -> float:
	return 1.0 if rand(k * 2.7 + side * 3.0) > 0.35 + 0.4 * damage else lerpf(0.45, 0.8, rand(k + side))


func _frame_floor(x: float, side: float, count: int) -> PackedVector2Array:
	var reach: float = _frame_reach(int(x), side)
	var result := PackedVector2Array()
	for i: int in count:
		var u: float = reach * float(i) / (count - 1)
		result.append(_f(Vector2(x + 2.0 * u, side * beam * 0.95 * sin(u * PI * 0.5))))
	return result


func _frame_line(x: float, side: float, k: int) -> PackedVector2Array:
	var reach: float = _frame_reach(int(x), side)
	var height: float = _break_height() * lerpf(1.1, 0.75, rand(k * 1.9 + 50.0))
	var line := PackedVector2Array()
	var steps: int = 7
	for i: int in steps + 1:
		var u: float = reach * float(i) / steps
		var floor_point: Vector2 = _f(Vector2(x + 2.0 * u, side * beam * 0.95 * sin(u * PI * 0.5)))
		line.append(Landmark.project(floor_point, height * (1.0 - cos(u * PI * 0.5)) + 4.0))
	return line


func _draw_frame(part: Node2D, line: PackedVector2Array, wood: Color, base: Vector2) -> void:
	var local := PackedVector2Array()
	for point: Vector2 in line:
		local.append(point - base)
	Landmark.draw_band(part, local, frame_width, frame_width * 0.7, wood)
	part.draw_polyline(local, wood.lightened(0.18), 1.0, true)


func _add_bowsprit(wood: Color) -> void:
	var tip := Vector2(bow_x, _keel_y(bow_x))
	var root: Vector2 = Landmark.project(_f(tip + Vector2(8.0, 0.0)), _hull_h(tip) - 2.0)
	var end: Vector2 = Landmark.project(_f(tip - Vector2(bowsprit_length, 0.0)), _hull_h(tip) + bowsprit_rise)
	var base: Vector2 = _f(tip) + Vector2(0.0, 2.0)
	add_part(base, _draw_bowsprit.bind(root - base, end - base, wood))
	add_sonar_line(PackedVector2Array([root, end]), PackedVector2Array([_f(tip), _f(tip - Vector2(bowsprit_length, 0.0))]))


func _draw_bowsprit(part: Node2D, root: Vector2, end: Vector2, wood: Color) -> void:
	Landmark.draw_band(part, PackedVector2Array([root, end]), 8.0, 4.0, wood.darkened(0.1))
	part.draw_line(root, end, wood.lightened(0.18), 1.0, true)
	# A torn stay rope hanging from its tip.
	part.draw_polyline(Landmark.curve(end, end + Vector2(10.0, 26.0), end + Vector2(22.0, 30.0), 6), wood.darkened(0.3), 1.0, true)


## The mast: a broken stump on the deck and the mast lying across the hull
## onto the sand (falling to either side, by the variant), with its yard.
func _add_mast(wood: Color) -> void:
	var foot := Vector2(-64.0, _keel_y(-64.0))
	var deck: Vector2 = Landmark.project(_f(foot), _hull_h(foot))
	add_part(_f(foot) + Vector2(0.0, _half(-64.0) + 2.0), _draw_stump.bind(deck - (_f(foot) + Vector2(0.0, _half(-64.0) + 2.0)), wood))
	add_sonar_line(PackedVector2Array([deck, deck - Vector2(0.0, stump_height)]), PackedVector2Array([_f(foot), _f(foot)]))
	var fall: float = lerpf(0.9, 1.6, rand(60.0)) * (1.0 if rand(61.0) < 0.6 else -1.0)
	var length: float = lerpf(mast_length_min, mast_length_max, rand(62.0))
	var start := foot + Vector2(12.0, 0.0)
	var end: Vector2 = start + Vector2.from_angle(fall) * length
	var a: Vector2 = Landmark.project(_f(start), _hull_h(start) + 4.0)
	var b: Vector2 = _f(end)
	var base := Vector2(maxf(a.x, b.x) * 0.5 + minf(a.x, b.x) * 0.5, maxf(_f(start).y, b.y) + 2.0)
	add_part(base, _draw_fallen_mast.bind(a - base, b - base, _f(Vector2.from_angle(fall)), wood))
	add_sonar_line(PackedVector2Array([a, b]), PackedVector2Array([_f(start), b]))


func _draw_stump(part: Node2D, deck: Vector2, wood: Color) -> void:
	var top: Vector2 = deck - Vector2(0.0, stump_height)
	Landmark.draw_band(part, PackedVector2Array([deck, top]), mast_width, mast_width * 0.9, wood.darkened(0.12))
	part.draw_colored_polygon(PackedVector2Array([top + Vector2(-mast_width * 0.45, 0.0), top + Vector2(-2.0, -8.0), top + Vector2(2.0, -2.0), top + Vector2(mast_width * 0.45, -10.0), top + Vector2(mast_width * 0.45, 0.0)]), wood.darkened(0.12))
	part.draw_line(deck + Vector2(-mast_width * 0.5, 0.0), top + Vector2(-mast_width * 0.45, 0.0), wood.lightened(0.2), 1.0, true)


func _draw_fallen_mast(part: Node2D, a: Vector2, b: Vector2, direction: Vector2, wood: Color) -> void:
	Landmark.draw_band(part, PackedVector2Array([a, b]), mast_width, mast_width * 0.8, wood.darkened(0.15))
	var along: Vector2 = (b - a).normalized()
	part.draw_line(a - along.orthogonal() * mast_width * 0.35, b - along.orthogonal() * mast_width * 0.3, wood.lightened(0.18), 1.5, true)
	# The yard lying across it near its end, and a rope coiled on the sand.
	var yard_at: Vector2 = a.lerp(b, 0.78)
	var yard: Vector2 = direction.orthogonal() * 34.0
	Landmark.draw_band(part, PackedVector2Array([yard_at - yard, yard_at + yard]), 6.0, 5.0, wood.darkened(0.2))
	var rope := PackedVector2Array()
	for k: int in 13:
		var t: float = k / 12.0
		rope.append(b + Vector2(cos(t * TAU * 1.4) * (10.0 + 14.0 * t), sin(t * TAU * 1.4) * (5.0 + 6.0 * t) + 8.0))
	part.draw_polyline(rope, wood.lightened(0.05), 1.2, true)


func _draw_cabin(part: Node2D, wood: Color, base_y: float) -> void:
	var outline: PackedVector2Array = _cabin_outline()
	var offset := Vector2(_f(_cabin_center()).x, base_y)
	# A dark window and a door frame on its front face.
	var front: Vector2 = Vector2.ZERO
	for point: Vector2 in outline:
		front += point / outline.size()
	front.y = _lowest_y(outline)
	var window: Vector2 = Landmark.project(front, cabin_height * 0.55) - offset
	part.draw_colored_polygon(PackedVector2Array([window + Vector2(-6.0, -5.0), window + Vector2(6.0, -5.0), window + Vector2(6.0, 5.0), window + Vector2(-6.0, 5.0)]), wood.darkened(0.75))
	part.draw_line(window + Vector2(0.0, -5.0), window + Vector2(0.0, 5.0), wood.darkened(0.2), 1.0, true)
	var roof_edge: Vector2 = Landmark.project(front, cabin_height) - offset
	part.draw_line(roof_edge + Vector2(-cabin_size.x * 0.45, 0.0), roof_edge + Vector2(cabin_size.x * 0.45, 0.0), wood.lightened(0.2), 1.5, true)


func _draw_barrel_hoops(part: Node2D, wood: Color, base: Vector2, spot: Vector2) -> void:
	var center: Vector2 = spot - base
	for share: float in [0.22, 0.78]:
		var points := PackedVector2Array()
		for k: int in 11:
			var angle: float = lerpf(0.1, PI - 0.1, k / 10.0)
			points.append(center + Vector2(cos(angle) * barrel_radius, sin(angle) * barrel_radius * 0.8 - barrel_height * share))
		part.draw_polyline(points, wood.darkened(0.5), 1.4, true)


## Loose planks on the sand (and a lying barrel when wrecked).
func _draw_loose(part: Node2D, wood: Color, base: Vector2) -> void:
	var count: int = loose_planks + roundi(damage * 3.0)
	for i: int in count:
		var at: Vector2 = _f(Vector2(lerpf(bow_x, _stern_start() + stern_length, rand(i * 2.3 + 70.0)), (90.0 + 50.0 * rand(i * 3.1 + 71.0)) * (1.0 if rand(i + 72.0) < 0.6 else -1.0))) - base
		var direction: Vector2 = Vector2.from_angle(TAU * rand(i * 1.1 + 73.0))
		var length: float = 26.0 + 30.0 * rand(i + 74.0)
		var across: Vector2 = direction.orthogonal() * 3.5
		var a: Vector2 = at - direction * length * 0.5
		var b: Vector2 = at + direction * length * 0.5
		part.draw_colored_polygon(PackedVector2Array([a - across, b - across, b + across, a + across]), wood.darkened(0.2))
		part.draw_line(a - across, b - across, wood.lightened(0.12), 1.0, true)
