class_name LandmarkColumn
extends RefCounted
## Drawing helpers for the ancient stone columns of the landmarks (statue,
## arch), so they read as old carved stone and never as barrels: a shaft
## with flutes, a lit side, chipped edges and cracks, a slight lean, a base
## ring, and either a carved capital or a jagged broken top with its lighter
## fracture surface; plus fallen column drums lying on the floor.
## Static (drawn once). key makes each column different.


## A standing column on foot (part space: the top of its base slab).
## radii: the shaft's half width and its depth (the ellipse seen from above).
static func draw_standing(canvas: CanvasItem, foot: Vector2, radii: Vector2, height: float, lean: float, broken: bool, key: float, stone: Color) -> void:
	var tops: PackedVector2Array = _top_edge(foot, radii, height, lean, broken, key)
	var shaft: PackedVector2Array = outline(foot, radii, height, lean, broken, key)
	# Close it along the front of the base (the round foot).
	for k: int in range(1, 6):
		var angle: float = PI * k / 6.0
		shaft.append(foot + Vector2(cos(angle) * radii.x, sin(angle) * radii.y * 0.5))
	canvas.draw_colored_polygon(shaft, stone.darkened(0.18))
	# Lit left side (light from above-left) and the flutes, leaning with the shaft.
	var low_top: float = tops[0].y
	for point: Vector2 in tops:
		low_top = maxf(low_top, point.y)
	var lit := PackedVector2Array([foot + Vector2(-radii.x * 0.92, 0.0), Vector2(foot.x - radii.x * 0.84 + lean, low_top + 2.0),
		Vector2(foot.x - radii.x * 0.38 + lean, low_top + 2.0), foot + Vector2(-radii.x * 0.4, 0.0)])
	canvas.draw_colored_polygon(lit, stone.lightened(0.04))
	for share: float in [-0.6, -0.15, 0.3, 0.7]:
		var bottom: Vector2 = foot + Vector2(radii.x * share, radii.y * 0.45 * sqrt(1.0 - share * share) - 6.0)
		canvas.draw_line(bottom, Vector2(foot.x + radii.x * share * 0.92 + lean, low_top + 3.0), stone.darkened(0.42), 1.0, true)
	# Base ring.
	canvas.draw_colored_polygon(PackedVector2Array([foot + Vector2(-radii.x * 1.12, 0.0), foot + Vector2(-radii.x * 1.12, -7.0),
		foot + Vector2(radii.x * 1.12, -7.0), foot + Vector2(radii.x * 1.12, 0.0), foot + Vector2(0.0, radii.y * 0.5)]), stone.darkened(0.08))
	canvas.draw_line(foot + Vector2(-radii.x * 1.12, -7.0), foot + Vector2(radii.x * 1.12, -7.0), stone.lightened(0.12), 1.0, true)
	if broken:
		# The fracture surface: lighter, following the jagged edge, seen from above.
		for k: int in tops.size() - 1:
			var a: Vector2 = tops[k]
			var b: Vector2 = tops[k + 1]
			var ta: float = float(k) / (tops.size() - 1)
			var tb: float = float(k + 1) / (tops.size() - 1)
			var back_a: Vector2 = a - Vector2(0.0, radii.y * 0.9 * sin(PI * ta))
			var back_b: Vector2 = b - Vector2(0.0, radii.y * 0.9 * sin(PI * tb))
			if absf(a.x - b.x) > 0.5:
				canvas.draw_colored_polygon(PackedVector2Array([a, b, back_b, back_a]), stone.lightened(0.14 - 0.1 * Landmark.hash01(key + k)))
		canvas.draw_polyline(tops, stone.lightened(0.25), 1.0, true)
	else:
		# A classical capital: a flaring cushion (echinus) under a square slab
		# (abacus) whose flat top is seen from above.
		var top: Vector2 = tops[tops.size() / 2]
		var half: float = radii.x * 1.45
		var flare := PackedVector2Array([top + Vector2(-radii.x * 0.92, 0.0), top + Vector2(-half * 0.95, -7.0), top + Vector2(half * 0.95, -7.0), top + Vector2(radii.x * 0.92, 0.0)])
		canvas.draw_colored_polygon(flare, stone.darkened(0.12))
		var slab_bottom: Vector2 = top - Vector2(0.0, 7.0)
		var slab_top: Vector2 = slab_bottom - Vector2(0.0, 8.0)
		canvas.draw_colored_polygon(PackedVector2Array([slab_bottom + Vector2(-half, 0.0), slab_top + Vector2(-half, 0.0), slab_top + Vector2(half, 0.0), slab_bottom + Vector2(half, 0.0)]), stone.darkened(0.06))
		var depth := Vector2(0.0, -radii.y * 1.6)
		canvas.draw_colored_polygon(PackedVector2Array([slab_top + Vector2(-half, 0.0), slab_top + Vector2(half, 0.0), slab_top + Vector2(half, 0.0) + depth, slab_top + Vector2(-half, 0.0) + depth]), stone.lightened(0.1))
		canvas.draw_line(slab_top + Vector2(-half, 0.0), slab_top + Vector2(half, 0.0), stone.lightened(0.22), 1.0, true)
		# A chipped corner.
		canvas.draw_colored_polygon(PackedVector2Array([slab_top + Vector2(half, 0.0) + depth, slab_top + Vector2(half - 7.0, 0.0) + depth, slab_top + Vector2(half, 0.0) + depth * 0.5]), stone.darkened(0.3))
	# Cracks from the top (or a chip) down the shaft.
	for c: int in 1 + int(Landmark.hash01(key + 5.0) * 2.0):
		var start_share: float = lerpf(-0.6, 0.6, Landmark.hash01(key + c * 3.3))
		var crack := PackedVector2Array()
		var depth: float = height * lerpf(0.25, 0.5, Landmark.hash01(key + c * 7.1))
		for step: int in 5:
			var t: float = step / 4.0
			var y: float = low_top + 4.0 + depth * t
			var along: float = (foot.y - y) / maxf(height, 1.0)
			crack.append(Vector2(foot.x + radii.x * start_share + lean * along + 3.0 * sin(step * 2.1 + key), y))
		canvas.draw_polyline(crack, stone.darkened(0.55), 1.0, true)


## The column's silhouette as an open line (left side up, the top, right
## side down), with chips cut into both edges; for the sonar too.
static func outline(foot: Vector2, radii: Vector2, height: float, lean: float, broken: bool, key: float) -> PackedVector2Array:
	var tops: PackedVector2Array = _top_edge(foot, radii, height, lean, broken, key)
	var points := PackedVector2Array([foot + Vector2(-radii.x, 0.0)])
	_add_chips(points, foot + Vector2(-radii.x, 0.0), tops[0], 1.0, key)
	points.append_array(tops)
	_add_chips(points, tops[tops.size() - 1], foot + Vector2(radii.x, 0.0), -1.0, key + 9.0)
	points.append(foot + Vector2(radii.x, 0.0))
	return points


## The floor points straight below an outline (for the sonar's line of sight).
static func sights(points: PackedVector2Array, foot: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(Vector2(point.x, foot.y + 2.0))
	return result


## The top edge from left to right: flat for a capital, jagged and lower on
## one side when broken.
static func _top_edge(foot: Vector2, radii: Vector2, height: float, lean: float, broken: bool, key: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count: int = 7
	var low_side: float = 1.0 if Landmark.hash01(key + 1.1) < 0.5 else -1.0
	for k: int in count:
		var t: float = float(k) / (count - 1)
		var x: float = lerpf(-radii.x * 0.9, radii.x * 0.9, t)
		var drop: float = 0.0
		if broken:
			var side: float = (t - 0.5) * 2.0 * low_side
			drop = height * (0.06 + 0.1 * maxf(side, 0.0) + 0.09 * Landmark.hash01(key + k * 2.7))
			if k % 2 == 1:
				drop += 5.0
		points.append(Vector2(foot.x + x + lean, foot.y - height + drop))
	return points


## Two small chips (notches) along an edge from a to b; inward = +1 on the
## left edge (cut to the right), -1 on the right edge.
static func _add_chips(points: PackedVector2Array, a: Vector2, b: Vector2, inward: float, key: float) -> void:
	for c: int in 2:
		# One chip in the lower half, one in the upper half (in order along the edge).
		var t: float = lerpf(0.15, 0.42, Landmark.hash01(key + c * 4.3)) if c == 0 else lerpf(0.58, 0.88, Landmark.hash01(key + 8.8))
		var size: float = 4.0 + 4.0 * Landmark.hash01(key + c * 1.9)
		var along: Vector2 = (b - a).normalized()
		var at: Vector2 = a.lerp(b, t)
		points.append(at - along * size)
		points.append(at + Vector2(inward * size * 0.8, 0.0))
		points.append(at + along * size * 0.6)


## A fallen column drum lying on the floor along direction (unit, floor
## plane): its body, the flutes along it and the broken end facing the view.
static func draw_lying(canvas: CanvasItem, center: Vector2, direction: Vector2, length: float, radius: float, key: float, stone: Color) -> void:
	var a: Vector2 = center - direction * length * 0.5
	var b: Vector2 = center + direction * length * 0.5
	# The axis lies radius above the floor; seen from the 3/4 view the body is
	# a band between its lower and upper silhouette with round ends.
	var axis_a: Vector2 = a - Vector2(0.0, radius)
	var axis_b: Vector2 = b - Vector2(0.0, radius)
	var across: Vector2 = Vector2(0.0, radius)
	var far_end: Vector2 = axis_a if a.y < b.y else axis_b
	var near_end: Vector2 = axis_b if a.y < b.y else axis_a
	var end_radii := Vector2(radius * absf(direction.y) * 0.9 + radius * 0.35, radius)
	canvas.draw_colored_polygon(Landmark.ellipse(far_end, end_radii, 12), stone.darkened(0.3))
	canvas.draw_colored_polygon(PackedVector2Array([axis_a + across, axis_b + across, axis_b - across, axis_a - across]), stone.darkened(0.2))
	# Rounded shading: a lit band along the top, darker towards the floor.
	canvas.draw_colored_polygon(PackedVector2Array([axis_a - across * 0.25, axis_b - across * 0.25, axis_b - across * 0.95, axis_a - across * 0.95]), stone.lightened(0.04))
	canvas.draw_colored_polygon(PackedVector2Array([axis_a + across * 0.55, axis_b + across * 0.55, axis_b + across, axis_a + across]), stone.darkened(0.4))
	for share: float in [-0.6, 0.0, 0.5]:
		canvas.draw_line(axis_a + across * share, axis_b + across * share, stone.darkened(0.45), 1.0, true)
	# The near end shows its round, broken face.
	canvas.draw_colored_polygon(Landmark.ellipse(near_end, end_radii, 12, 0.14, key), stone.lightened(0.1))
	canvas.draw_polyline(Landmark.curve(near_end - across * 0.8, near_end + Vector2(end_radii.x * 0.4, 0.0), near_end + across * 0.6, 4), stone.darkened(0.4), 1.0, true)


## The floor footprint of a lying drum (a low solid block under it).
static func lying_footprint(center: Vector2, direction: Vector2, length: float, radius: float) -> PackedVector2Array:
	var along: Vector2 = direction * length * 0.5
	var across: Vector2 = direction.orthogonal() * radius * 0.5
	return PackedVector2Array([center - along - across, center + along - across, center + along + across, center - along + across])


## Small stone chips scattered on the floor around center (count, spread).
static func draw_chips(canvas: CanvasItem, center: Vector2, count: int, spread: float, key: float, stone: Color) -> void:
	for i: int in count:
		var at: Vector2 = center + Vector2.from_angle(TAU * Landmark.hash01(key + i * 1.7)) * spread * sqrt(Landmark.hash01(key + i * 3.1))
		var size: float = 3.0 + 5.0 * Landmark.hash01(key + i * 5.3)
		var chip := PackedVector2Array([at + Vector2(-size, 0.0), at + Vector2(-size * 0.3, -size * 0.8), at + Vector2(size * 0.7, -size * 0.5), at + Vector2(size, 0.0)])
		canvas.draw_colored_polygon(chip, stone.darkened(0.15))
		canvas.draw_line(chip[1], chip[2], stone.lightened(0.15), 1.0, true)
