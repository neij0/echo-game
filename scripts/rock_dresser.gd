class_name RockDresser
extends RefCounted
## Dresses a room's rock with the pieces of a rock kit (WorldLook), so walls
## read as natural rock instead of an extruded outline: pieces stand side by
## side along every rock outline (their height follows the rock's height
## there, so they stay low near doorways), more lie on top of wide rock, and
## pebbles lie on the sand along the walls. Only looks: the room's own rock
## mesh stays underneath as the core and its colliders (the outline) are the
## only solid thing. A piece is kept inside the outline except for
## WorldLook.piece_overhang. One MultiMesh per kit piece and room.

## Pieces closer than this to the room's edge are skipped (the neighbour room
## and the outer rock continue there).
const BORDER_MARGIN: float = 0.1
## A piece shrunk below this reach (world units) is left out.
const MIN_REACH: float = 0.22


## rocks: {"outline": PackedVector2Array on the floor plane (world units),
## "height_at": Callable(point: Vector2) -> float (units)}. bounds: the room.
static func dress(look: WorldLook, rocks: Array[Dictionary], bounds: Rect2, material: Material, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Dressing"
	if look == null or look.get_pieces().is_empty():
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Dictionary = {}
	var inner: Rect2 = bounds.grow(-BORDER_MARGIN)
	for rock: Dictionary in rocks:
		var outline: PackedVector2Array = rock["outline"]
		if outline.size() < 3:
			continue
		var height_at: Callable = rock["height_at"]
		_wall_pieces(look, outline, height_at, inner, rng, placed)
		_top_pieces(look, outline, height_at, inner, rng, placed)
	for piece: Dictionary in look.get_pieces():
		var transforms: Array = placed.get(piece["name"], [])
		if transforms.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = piece["mesh"]
		multimesh.instance_count = transforms.size()
		for i: int in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = String(piece["name"])
		instance.multimesh = multimesh
		instance.material_override = material
		root.add_child(instance)
	return root


## Number of pieces under a dressing node (reports).
static func count_pieces(dressing: Node3D) -> int:
	var total: int = 0
	for child: Node in dressing.get_children():
		var instance := child as MultiMeshInstance3D
		if instance and instance.multimesh:
			total += instance.multimesh.instance_count
	return total


static func _wall_pieces(look: WorldLook, outline: PackedVector2Array, height_at: Callable, inner: Rect2, rng: RandomNumberGenerator, placed: Dictionary) -> void:
	var count: int = outline.size()
	var area: float = 0.0
	for i: int in count:
		area += outline[i].x * outline[(i + 1) % count].y - outline[(i + 1) % count].x * outline[i].y
	var side: float = 1.0 if area > 0.0 else -1.0
	var pebbles: Array[Dictionary] = look.pieces_of(PackedStringArray(["pebbles"]))
	var pebble_chance: float = look.piece_spacing / maxf(look.pebble_spacing, 0.01)
	var at: float = rng.randf() * look.piece_spacing
	for i: int in count:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		var length: float = a.distance_to(b)
		if length < 0.0001:
			continue
		var outward: Vector2 = (b - a).orthogonal().normalized() * side
		while at < length:
			var point: Vector2 = a.lerp(b, at / length)
			at += look.piece_spacing * rng.randf_range(0.8, 1.2)
			if not inner.has_point(point):
				continue
			_wall_piece(look, outline, point, outward, height_at.call(point) as float, rng, placed)
			if not pebbles.is_empty() and rng.randf() < pebble_chance:
				var pebble: Dictionary = pebbles[rng.randi() % pebbles.size()]
				var spot: Vector2 = point + outward * rng.randf_range(0.15, look.pebble_reach)
				var size: float = rng.randf_range(look.pebble_scale_min, look.pebble_scale_max)
				_add(placed, pebble, _transform(spot, 0.0, Vector3(size, size, size), 0.0, rng))
		at -= length


static func _wall_piece(look: WorldLook, outline: PackedVector2Array, point: Vector2, outward: Vector2, height: float, rng: RandomNumberGenerator, placed: Dictionary) -> void:
	var piece: Dictionary = _pick(look, height, rng)
	if piece.is_empty():
		return
	var width: float = rng.randf_range(look.piece_scale_min, look.piece_scale_max)
	if height < look.low_height:
		width *= clampf(height / maxf(look.low_height, 0.01), 0.35, 1.0)
	# Shrink the piece until it stays inside the outline (but for the overhang).
	var reach: float = float(piece["reach"]) * width
	var middle: Vector2 = point - outward * reach * look.piece_inset
	for attempt: int in 2:
		reach = minf(reach, _clearance(outline, middle) + look.piece_overhang)
		if reach < MIN_REACH:
			return
		middle = point - outward * reach * look.piece_inset
	width = reach / float(piece["reach"])
	var tall: float = clampf(height * rng.randf_range(look.piece_height_min, look.piece_height_max) / float(piece["height"]),
		look.height_scale_min, look.height_scale_max)
	_add(placed, piece, _transform(middle, 0.0, Vector3(width, tall, width), look.piece_tilt, rng))


static func _top_pieces(look: WorldLook, outline: PackedVector2Array, height_at: Callable, inner: Rect2, rng: RandomNumberGenerator, placed: Dictionary) -> void:
	var pieces: Array[Dictionary] = look.pieces_of(look.top_kinds)
	if look.top_spacing <= 0.0 or pieces.is_empty():
		return
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		bounds = bounds.expand(point)
	var step: float = look.top_spacing
	var x: float = bounds.position.x + step * 0.5
	while x < bounds.end.x:
		var y: float = bounds.position.y + step * 0.5
		while y < bounds.end.y:
			var point := Vector2(x, y) + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * step * 0.7
			y += step
			if not inner.has_point(point):
				continue
			var clear: float = _clearance(outline, point)
			if clear < look.top_clearance:
				continue
			var piece: Dictionary = pieces[rng.randi() % pieces.size()]
			var reach: float = minf(float(piece["reach"]) * rng.randf_range(look.piece_scale_min, look.piece_scale_max), clear + look.piece_overhang * 0.5)
			var width: float = reach / float(piece["reach"])
			var tall: float = width * rng.randf_range(0.7, 1.3)
			var lift: float = (height_at.call(point) as float) - float(piece["height"]) * tall * look.top_sunk
			_add(placed, piece, _transform(point, lift, Vector3(width, tall, width), look.piece_tilt * 1.6, rng))
		x += step


## A piece for rock of this height: the low kinds near doorways, else one
## kind by weight (tall kinds only where the rock is tall) and one of its
## pieces.
static func _pick(look: WorldLook, height: float, rng: RandomNumberGenerator) -> Dictionary:
	if height < look.low_height:
		var low: Array[Dictionary] = look.pieces_of(look.low_kinds)
		return low[rng.randi() % low.size()] if not low.is_empty() else {}
	var kinds: Array[String] = []
	var total: float = 0.0
	for kind: String in look.kind_weights:
		if height < look.tall_height and kind in look.tall_kinds:
			continue
		if look.pieces_of(PackedStringArray([kind])).is_empty():
			continue
		kinds.append(kind)
		total += float(look.kind_weights[kind])
	var roll: float = rng.randf() * total
	for kind: String in kinds:
		roll -= float(look.kind_weights[kind])
		if roll <= 0.0:
			var options: Array[Dictionary] = look.pieces_of(PackedStringArray([kind]))
			return options[rng.randi() % options.size()]
	return {}


## Distance from a point to the outline: positive inside, negative outside.
static func _clearance(outline: PackedVector2Array, point: Vector2) -> float:
	var nearest: float = INF
	var count: int = outline.size()
	for i: int in count:
		var close: Vector2 = Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % count])
		nearest = minf(nearest, close.distance_squared_to(point))
	var distance: float = sqrt(nearest)
	return distance if Geometry2D.is_point_in_polygon(point, outline) else -distance


## A piece standing at a floor point, lifted, scaled along its own axes,
## turned any way round and leaning up to tilt_degrees.
static func _transform(at: Vector2, lift: float, size: Vector3, tilt_degrees: float, rng: RandomNumberGenerator) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if tilt_degrees > 0.0:
		var lean_axis := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, rng.randf() * TAU)
		basis = Basis(lean_axis, deg_to_rad(rng.randf_range(-tilt_degrees, tilt_degrees))) * basis
	return Transform3D(basis * Basis.from_scale(size), Vector3(at.x, lift, at.y))


static func _add(placed: Dictionary, piece: Dictionary, transform: Transform3D) -> void:
	var piece_name: String = piece["name"]
	if not placed.has(piece_name):
		placed[piece_name] = []
	(placed[piece_name] as Array).append(transform)
