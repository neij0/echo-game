class_name LandmarkArch
extends Landmark
## A broken stone arch: two carved pillars (solid) the players can swim
## between, the arch's band of cut stones curving over the gap from the
## taller pillar and breaking off before it reaches the other one, and a
## fallen block lying on the floor beside it.

@export var pillar_spacing: float = 200.0
@export var pillar_radii: Vector2 = Vector2(30.0, 22.0)
@export var left_height: float = 104.0
@export var right_height: float = 82.0
## The arch: how high its top rises above the left pillar, its band width,
## the share of the span that still stands, and the stub on the right pillar.
@export var arch_rise: float = 74.0
@export var band_width: float = 28.0
@export_range(0.1, 1.0) var standing_share: float = 0.62
@export_range(0.0, 0.5) var stub_share: float = 0.14
@export var stone_count: int = 11
@export var block_position: Vector2 = Vector2(118.0, 62.0)
@export var block_radii: Vector2 = Vector2(34.0, 19.0)
@export var block_height: float = 22.0


func _footprint_shapes() -> Array[PackedVector2Array]:
	return [
		Landmark.ellipse(Vector2(-pillar_spacing * 0.5, 0.0), pillar_radii, 14, 0.05, 1.0),
		Landmark.ellipse(Vector2(pillar_spacing * 0.5, 0.0), pillar_radii, 14, 0.05, 2.0),
		Landmark.ellipse(block_position, block_radii, 10, 0.12, 3.0),
	]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([left_height, right_height, block_height])


func _build_parts() -> void:
	var stone: Color = material_color()
	var base_y: float = pillar_radii.y + 1.0
	add_part(Vector2(0.0, base_y), _draw_arch.bind(stone, base_y))
	var line: PackedVector2Array = _arch_line()
	add_sonar_line(line.slice(0, _standing_count() + 1), PackedVector2Array(), 0.0)
	add_sonar_line(line.slice(line.size() - _stub_count() - 1), PackedVector2Array(), 0.0)


## The arch's centre line from the left pillar's top to the right one's.
func _arch_line() -> PackedVector2Array:
	var a := Vector2(-pillar_spacing * 0.5, -left_height)
	var b := Vector2(pillar_spacing * 0.5, -right_height)
	var top := Vector2(0.0, -left_height - arch_rise)
	return Landmark.curve(a, top * 2.0 - a.lerp(b, 0.5), b, 16)


func _standing_count() -> int:
	return roundi(16 * standing_share)


func _stub_count() -> int:
	return maxi(roundi(16 * stub_share), 1)


func _draw_arch(part: Node2D, stone: Color, base_y: float) -> void:
	var line: PackedVector2Array = _arch_line()
	for i: int in line.size():
		line[i].y -= base_y
	for piece: PackedVector2Array in [line.slice(0, _standing_count() + 1), line.slice(line.size() - _stub_count() - 1)]:
		Landmark.draw_band(part, piece, band_width, band_width * 0.9, stone.darkened(0.08))
		# Lit top edge and the joints between the cut stones.
		var upper := PackedVector2Array()
		for k: int in piece.size():
			var before: Vector2 = piece[maxi(k - 1, 0)]
			var after: Vector2 = piece[mini(k + 1, piece.size() - 1)]
			upper.append(piece[k] - (after - before).normalized().orthogonal() * band_width * 0.5)
		part.draw_polyline(upper, stone.lightened(0.2), 1.2, true)
	var standing: int = _standing_count()
	for k: int in stone_count:
		var index: int = roundi(float(k) / stone_count * 16.0)
		if index > standing and index < line.size() - _stub_count() - 1:
			continue
		var at: Vector2 = line[clampi(index, 0, line.size() - 1)]
		var across: Vector2 = (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]).normalized().orthogonal() * band_width * 0.5
		part.draw_line(at - across, at + across, stone.darkened(0.4), 1.2, true)
	# The broken end: a jagged edge.
	var end: Vector2 = line[standing]
	part.draw_colored_polygon(PackedVector2Array([end + Vector2(-2.0, -band_width * 0.5), end + Vector2(9.0, -band_width * 0.2), end + Vector2(3.0, 2.0), end + Vector2(8.0, band_width * 0.45), end + Vector2(-2.0, band_width * 0.5)]), stone.darkened(0.08))
	# Carved bands on the pillars (front halves).
	for side: float in [-1.0, 1.0]:
		var center := Vector2(side * pillar_spacing * 0.5, -base_y)
		var h: float = left_height if side < 0.0 else right_height
		for share: float in [0.25, 0.8]:
			var points := PackedVector2Array()
			for k: int in 13:
				var angle: float = lerpf(0.15, PI - 0.15, k / 12.0)
				points.append(center + Vector2(cos(angle) * pillar_radii.x, sin(angle) * pillar_radii.y - h * share))
			part.draw_polyline(points, stone.darkened(0.35), 1.4, true)
