class_name LandmarkArch
extends Landmark
## A broken stone arch: two carved columns (LandmarkColumn) the players can
## swim between, each on a solid slab. The left one keeps its capital and
## carries the arch's band of cut stones, curving over the gap and breaking
## off in mid air; the right one is broken off with a jagged top. Fallen arch
## stones lie under the break, with a solid block among them.
## Variation: damage decides how much of the span still stands and how short
## the broken column is; the variant picks leans and the debris layout.

@export var pillar_spacing: float = 200.0
@export var pillar_radii: Vector2 = Vector2(24.0, 17.0)
@export var left_height: float = 104.0
@export var right_height: float = 82.0
@export var slab_height: float = 8.0
@export var max_lean: float = 6.0
## The arch: how high its top rises above the left column, its band width,
## and the share of the span still standing (intact .. wrecked).
@export var arch_rise: float = 74.0
@export var band_width: float = 28.0
@export_range(0.1, 1.0) var standing_share_intact: float = 0.8
@export_range(0.1, 1.0) var standing_share_wrecked: float = 0.4
@export var stone_count: int = 11
## The solid fallen block (local), its radii, and the loose stones around it.
@export var block_position: Vector2 = Vector2(96.0, 62.0)
@export var block_radii: Vector2 = Vector2(30.0, 17.0)
@export var block_height: float = 20.0
@export var loose_stones: int = 4

const ARCH_POINTS: int = 16


func _block_spot() -> Vector2:
	return block_position + Vector2(rand(3.0) - 0.5, rand(5.0) - 0.5) * 40.0


func _right_height() -> float:
	return right_height * lerpf(0.95, 0.6, damage)


func _lean(side: int) -> float:
	return (rand(side * 2.9 + 7.0) - 0.5) * 2.0 * max_lean


func _footprint_shapes() -> Array[PackedVector2Array]:
	return [
		Landmark.ellipse(Vector2(-pillar_spacing * 0.5, 0.0), pillar_radii * 1.3, 14, 0.05, 1.0),
		Landmark.ellipse(Vector2(pillar_spacing * 0.5, 0.0), pillar_radii * 1.3, 14, 0.05, 2.0),
		Landmark.ellipse(_block_spot(), block_radii, 10, 0.18, 3.0 + variant),
	]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([slab_height, slab_height, block_height])


func _build_parts() -> void:
	var stone: Color = material_color()
	var base_y: float = pillar_radii.y * 1.3 + 1.0
	for side: int in 2:
		var x: float = (side - 0.5) * pillar_spacing
		add_part(Vector2(x, base_y), _draw_column.bind(side, stone, Vector2(x, base_y)))
		var line: PackedVector2Array = LandmarkColumn.outline(Vector2(x, -slab_height), pillar_radii, _column_height(side), _lean(side), side == 1, side + variant * 2.0)
		add_sonar_line(line, LandmarkColumn.sights(line, Vector2(x, 0.0)))
	# The span sorts in front of both columns (it rests on the left capital).
	add_part(Vector2(0.0, base_y + 1.0), _draw_arch.bind(stone, base_y + 1.0))
	var line: PackedVector2Array = _arch_line().slice(0, _standing_count() + 1)
	var sights := PackedVector2Array()
	for point: Vector2 in line:
		sights.append(Vector2(point.x, 2.0))
	add_sonar_line(line, sights)
	add_part(_block_spot() + Vector2(0.0, block_radii.y + 30.0), _draw_stones.bind(stone, _block_spot() + Vector2(0.0, block_radii.y + 30.0)))


func _column_height(side: int) -> float:
	return left_height if side == 0 else _right_height()


## The arch's centre line from the left capital over the gap towards where
## the right column once stood (at the left column's full height).
func _arch_line() -> PackedVector2Array:
	var a := Vector2(-pillar_spacing * 0.5 + _lean(0), -slab_height - left_height - 11.0)
	var b := Vector2(pillar_spacing * 0.5, a.y)
	var top := Vector2(0.0, a.y - arch_rise)
	return Landmark.curve(a, top * 2.0 - a.lerp(b, 0.5), b, ARCH_POINTS)


func _standing_count() -> int:
	return roundi(ARCH_POINTS * lerpf(standing_share_intact, standing_share_wrecked, damage))


func _draw_column(part: Node2D, side: int, stone: Color, base: Vector2) -> void:
	var foot := Vector2((side - 0.5) * pillar_spacing, -slab_height) - base
	LandmarkColumn.draw_standing(part, foot, pillar_radii, _column_height(side), _lean(side), side == 1, side + variant * 2.0, stone)


func _draw_arch(part: Node2D, stone: Color, base_y: float) -> void:
	var line: PackedVector2Array = _arch_line()
	for i: int in line.size():
		line[i].y -= base_y
	var standing: int = _standing_count()
	var piece: PackedVector2Array = line.slice(0, standing + 1)
	Landmark.draw_band(part, piece, band_width, band_width * 0.9, stone.darkened(0.08))
	# Lit top edge and the joints between the cut stones.
	var upper := PackedVector2Array()
	for k: int in piece.size():
		var before: Vector2 = piece[maxi(k - 1, 0)]
		var after: Vector2 = piece[mini(k + 1, piece.size() - 1)]
		upper.append(piece[k] - (after - before).normalized().orthogonal() * band_width * 0.5)
	part.draw_polyline(upper, stone.lightened(0.2), 1.2, true)
	for k: int in stone_count:
		var index: int = roundi(float(k) / stone_count * ARCH_POINTS)
		if index >= standing:
			break
		var at: Vector2 = line[index]
		var across: Vector2 = (line[index + 1] - line[maxi(index - 1, 0)]).normalized().orthogonal() * band_width * 0.5
		part.draw_line(at - across, at + across, stone.darkened(0.4), 1.2, true)
	# The broken end: a jagged edge.
	var end: Vector2 = line[standing]
	var along: Vector2 = (line[standing] - line[standing - 1]).normalized()
	var across_end: Vector2 = along.orthogonal() * band_width * 0.5
	part.draw_colored_polygon(PackedVector2Array([end - across_end, end - across_end * 0.3 + along * 9.0, end + along * 3.0, end + across_end * 0.5 + along * 7.0, end + across_end]), stone.darkened(0.08))


func _draw_stones(part: Node2D, stone: Color, base: Vector2) -> void:
	# Cut stones of the fallen span: wedge blocks lying on the floor.
	for i: int in loose_stones:
		var at: Vector2 = _block_spot() - base + Vector2((rand(i * 3.3 + 20.0) - 0.5) * 140.0, -30.0 + (rand(i * 1.7 + 21.0) - 0.3) * 50.0)
		var size: float = 9.0 + 7.0 * rand(i + 23.0)
		var tilt: float = (rand(i + 25.0) - 0.5) * 0.8
		var block := PackedVector2Array([Vector2(-size, 0.0), Vector2(-size * 0.8, -size * 0.9), Vector2(size * 0.8, -size * 1.05), Vector2(size, 0.0)])
		for k: int in block.size():
			block[k] = at + block[k].rotated(tilt)
		part.draw_colored_polygon(block, stone.darkened(0.15))
		part.draw_line(block[1], block[2], stone.lightened(0.15), 1.0, true)
	LandmarkColumn.draw_chips(part, _block_spot() - base + Vector2(0.0, -26.0), 4 + roundi(damage * 4.0), 70.0, variant + 2.0, stone)
