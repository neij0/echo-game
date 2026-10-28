class_name LandmarkCoralTree
extends Landmark
## A giant branching coral rising from a solid foot: dark branches that sway
## very gently towards their ends, with small, dim glowing tips and a weak
## teal light (no big light source).

@export var foot_radii: Vector2 = Vector2(36.0, 22.0)
@export var foot_height: float = 24.0
## The trunk, how many times the branches split, how far they spread.
@export var trunk_length: float = 92.0
@export var trunk_width: float = 20.0
@export var levels: int = 4
@export var spread_degrees: float = 34.0
## Each level's branches are this share of the one before (length, width).
@export_range(0.3, 1.0) var length_share: float = 0.72
@export_range(0.3, 1.0) var width_share: float = 0.62
@export var sway_amount: float = 5.0
## Sway cycles per second.
@export var sway_speed: float = 0.12
@export var tip_radius: float = 3.0
@export var tree_seed: float = 3.0

## Branches: [from, to, width, level] in the trunk's space (origin = foot top).
var _branches: Array[Array] = []


func _footprint_shapes() -> Array[PackedVector2Array]:
	return [Landmark.ellipse(Vector2.ZERO, foot_radii, 14, 0.1, tree_seed)]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([foot_height])


func _build_parts() -> void:
	_branches.clear()
	_grow(Vector2.ZERO, -PI * 0.5, trunk_length, trunk_width, 0, tree_seed)
	var base_y: float = foot_radii.y + 1.0
	add_part(Vector2(0.0, base_y), _draw_tree.bind(material_color(), base_y), true)
	for branch: Array in _branches:
		if int(branch[3]) <= 1:
			add_sonar_line(PackedVector2Array([_foot_top() + (branch[0] as Vector2), _foot_top() + (branch[1] as Vector2)]), PackedVector2Array(), 0.0)


func _foot_top() -> Vector2:
	return Vector2(0.0, -foot_height)


func _grow(from: Vector2, angle: float, length: float, width: float, level: int, key: float) -> void:
	var bend: float = (Landmark.hash01(key) - 0.5) * 0.4
	var to: Vector2 = from + Vector2.from_angle(angle + bend) * length
	_branches.append([from, to, width, level])
	if level >= levels:
		return
	var count: int = 2 if Landmark.hash01(key + 1.3) < 0.7 else 3
	for i: int in count:
		var share: float = (float(i) / (count - 1)) - 0.5
		var turn: float = deg_to_rad(spread_degrees) * share * 2.0 + (Landmark.hash01(key + i * 2.9) - 0.5) * 0.3
		_grow(to, angle + turn, length * length_share * (0.85 + 0.3 * Landmark.hash01(key + i * 4.1)), width * width_share, level + 1, key * 1.7 + i * 3.3 + 0.7)


## Sway offset of a point at this level (more towards the ends).
func _sway(level: int, index: int) -> Vector2:
	var amount: float = sway_amount * pow(float(level) / maxf(levels, 1), 1.5)
	return Vector2(sin(_time * TAU * sway_speed + index * 0.7) * amount, 0.0)


func _draw_tree(part: Node2D, wood: Color, base_y: float) -> void:
	var origin: Vector2 = _foot_top() - Vector2(0.0, base_y)
	for i: int in _branches.size():
		var branch: Array = _branches[i]
		var level: int = branch[3]
		var a: Vector2 = origin + (branch[0] as Vector2) + _sway(maxi(level - 1, 0), i)
		var b: Vector2 = origin + (branch[1] as Vector2) + _sway(level, i)
		var width: float = branch[2]
		_batch.add_segment(a, b, width, width * width_share, wood.darkened(0.1 + 0.05 * level))
		_batch.add_line(a + Vector2(-width * 0.3, 0.0), b + Vector2(-width * 0.2, 0.0), wood.lightened(0.12), 1.0)
		_batch.add_dot(b, width * width_share * 0.5, wood.darkened(0.1 + 0.05 * level), 6)
	_batch.draw(part)


func _has_glow() -> bool:
	return true


func _draw_glow(canvas: Node2D) -> void:
	for i: int in _branches.size():
		var branch: Array = _branches[i]
		if int(branch[3]) < levels:
			continue
		var tip: Vector2 = _foot_top() + (branch[1] as Vector2) + _sway(levels, i)
		var breath: float = 0.6 + 0.4 * sin(_time * 0.9 + i * 1.3)
		_batch.add_dot(tip, tip_radius * 2.2, glow(0.1 * breath), 8)
		_batch.add_dot(tip, tip_radius, glow(0.55 * breath), 6)
	_batch.draw(canvas)
