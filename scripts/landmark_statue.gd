class_name LandmarkStatue
extends Landmark
## An ancient stone keeper on a plinth, holding up a small orb (a hint at the
## Ancient Light), beside old carved columns (LandmarkColumn: fluted, chipped,
## cracked, leaning, mostly broken with jagged tops), fallen column drums and
## stone chips on the floor. Plinth, column slabs and drums are solid. The
## figure has no face: a hood, a robe and raised arms (never creature-like).
## The orb glows very faintly.
## Variation: damage decides how many columns still stand and how broken they
## are; the variant picks their heights, leans, spots and the debris.

@export var plinth_size: Vector2 = Vector2(96.0, 62.0)
@export var plinth_height: float = 26.0
## The figure on the plinth: robe height, robe width at the hem / shoulders,
## head (hood) radius, and how high the orb is held above the shoulders.
@export var robe_height: float = 112.0
@export var hem_width: float = 50.0
@export var shoulder_width: float = 24.0
@export var hood_radius: float = 11.0
@export var orb_lift: float = 34.0
@export var orb_radius: float = 8.0
## Column spots (local), shaft radii (half width, depth), the height range and
## the most a column leans (pixels at the top).
@export var pillar_positions: PackedVector2Array = PackedVector2Array([Vector2(-112.0, 30.0), Vector2(106.0, -20.0)])
@export var pillar_radii: Vector2 = Vector2(21.0, 15.0)
@export var pillar_height_min: float = 52.0
@export var pillar_height_max: float = 112.0
@export var max_lean: float = 12.0
## Above this damage only the first column still stands.
@export_range(0.0, 1.0) var one_column_damage: float = 0.7
## Below this damage the first column keeps its capital (not broken).
@export_range(0.0, 1.0) var intact_damage: float = 0.25
## The low slab each column stands on (solid), and the spot jitter.
@export var slab_height: float = 8.0
@export var spot_jitter: float = 10.0
## Fallen drums: the first spot (local), length and radius ranges.
@export var drum_position: Vector2 = Vector2(70.0, 64.0)
@export var drum_length_min: float = 46.0
@export var drum_length_max: float = 72.0
@export var drum_radius: float = 15.0
## Above this damage a second drum lies on the floor.
@export_range(0.0, 1.0) var second_drum_damage: float = 0.4
@export var chip_count: int = 6


func _pillar_count() -> int:
	return 1 if damage > one_column_damage else pillar_positions.size()


func _pillar_spot(i: int) -> Vector2:
	return pillar_positions[i] + Vector2(rand(i * 3.1) - 0.5, rand(i * 5.7) - 0.5) * 2.0 * spot_jitter


func _pillar_height(i: int) -> float:
	var height: float = lerpf(pillar_height_min, pillar_height_max, rand(i * 2.3 + 1.0))
	return height * lerpf(1.0, 0.7, damage) if _pillar_broken(i) else pillar_height_max


func _pillar_broken(i: int) -> bool:
	return i > 0 or damage >= intact_damage


func _pillar_lean(i: int) -> float:
	return (rand(i * 7.9 + 2.0) - 0.5) * 2.0 * max_lean


## Fallen drums: [center, direction, length] each.
func _drums() -> Array[Array]:
	var drums: Array[Array] = []
	var count: int = 2 if damage > second_drum_damage else 1
	for i: int in count:
		var center: Vector2 = drum_position + Vector2(-60.0 * i, 14.0 * i) + Vector2(rand(i + 11.0) - 0.5, rand(i + 13.0) - 0.5) * 24.0
		var direction: Vector2 = Vector2.from_angle(lerpf(-0.5, 0.5, rand(i + 17.0)))
		drums.append([center, direction, lerpf(drum_length_min, drum_length_max, rand(i + 19.0))])
	return drums


func _footprint_shapes() -> Array[PackedVector2Array]:
	var half: Vector2 = plinth_size * 0.5
	var shapes: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])]
	for i: int in _pillar_count():
		shapes.append(Landmark.ellipse(_pillar_spot(i), pillar_radii * 1.3, 14, 0.06, i + 1.0))
	for drum: Array in _drums():
		shapes.append(LandmarkColumn.lying_footprint(drum[0], drum[1], drum[2], drum_radius * 2.0))
	return shapes


func _footprint_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array([plinth_height])
	for _i: int in _pillar_count():
		heights.append(slab_height)
	for _drum: Array in _drums():
		heights.append(0.0)
	return heights


func _build_parts() -> void:
	var stone: Color = material_color()
	var front_y: float = plinth_size.y * 0.5 + 1.0
	add_part(Vector2(0.0, front_y), _draw_figure.bind(stone, front_y))
	add_sonar_line(_figure_outline(Vector2(0.0, -plinth_height)), PackedVector2Array(), 0.0)
	for i: int in _pillar_count():
		var spot: Vector2 = _pillar_spot(i)
		var base_y: float = spot.y + pillar_radii.y * 1.3 + 1.0
		var foot: Vector2 = spot - Vector2(0.0, slab_height)
		add_part(Vector2(spot.x, base_y), _draw_column.bind(i, foot, stone, Vector2(spot.x, base_y)))
		var line: PackedVector2Array = LandmarkColumn.outline(foot, pillar_radii, _pillar_height(i), _pillar_lean(i), _pillar_broken(i), i + variant * 3.0)
		add_sonar_line(line, LandmarkColumn.sights(line, spot))
	for drum: Array in _drums():
		var center: Vector2 = drum[0]
		var base := Vector2(center.x, center.y + drum_radius + 1.0)
		add_part(base, _draw_drum.bind(drum, stone, base))
	add_part(drum_position + Vector2(0.0, 30.0), _draw_debris.bind(stone, drum_position + Vector2(0.0, 30.0)))


func _draw_column(part: Node2D, i: int, foot: Vector2, stone: Color, base: Vector2) -> void:
	LandmarkColumn.draw_standing(part, foot - base, pillar_radii, _pillar_height(i), _pillar_lean(i), _pillar_broken(i), i + variant * 3.0, stone)


func _draw_drum(part: Node2D, drum: Array, stone: Color, base: Vector2) -> void:
	LandmarkColumn.draw_lying(part, (drum[0] as Vector2) - base, drum[1], drum[2], drum_radius, variant + 0.5, stone)


func _draw_debris(part: Node2D, stone: Color, base: Vector2) -> void:
	LandmarkColumn.draw_chips(part, drum_position - base + Vector2(-30.0, -10.0), roundi(chip_count * (0.5 + damage)), 60.0, variant * 1.3, stone)


func _has_glow() -> bool:
	return true


func _orb_center() -> Vector2:
	return Vector2(0.0, -plinth_height - robe_height - orb_lift)


func _figure_outline(foot: Vector2) -> PackedVector2Array:
	var shoulders: Vector2 = foot - Vector2(0.0, robe_height)
	var orb: Vector2 = _orb_center()
	return PackedVector2Array([
		foot + Vector2(-hem_width * 0.5, 0.0),
		shoulders + Vector2(-shoulder_width * 0.5, 0.0),
		orb + Vector2(-orb_radius - 4.0, 4.0),
		orb + Vector2(0.0, -orb_radius - 2.0),
		orb + Vector2(orb_radius + 4.0, 4.0),
		shoulders + Vector2(shoulder_width * 0.5, 0.0),
		foot + Vector2(hem_width * 0.5, 0.0),
	])


func _draw_figure(part: Node2D, stone: Color, base_y: float) -> void:
	var foot := Vector2(0.0, -plinth_height - base_y)
	var shoulders: Vector2 = foot - Vector2(0.0, robe_height)
	var orb: Vector2 = _orb_center() - Vector2(0.0, base_y)
	# Robe: a long trapezoid with soft folds.
	var robe := PackedVector2Array([foot + Vector2(-hem_width * 0.5, 0.0), shoulders + Vector2(-shoulder_width * 0.5, 0.0),
		shoulders + Vector2(shoulder_width * 0.5, 0.0), foot + Vector2(hem_width * 0.5, 0.0), foot + Vector2(0.0, 3.0)])
	part.draw_colored_polygon(robe, stone.darkened(0.12))
	for k: int in 3:
		var x: float = lerpf(-0.3, 0.3, k / 2.0)
		part.draw_line(shoulders + Vector2(x * shoulder_width, 6.0), foot + Vector2(x * hem_width, -2.0), stone.darkened(0.35), 1.2, true)
	# Lit edge on one side (light from above).
	part.draw_line(shoulders + Vector2(-shoulder_width * 0.5, 0.0), foot + Vector2(-hem_width * 0.5, 0.0), stone.lightened(0.2), 1.2, true)
	# Raised arms up to the orb.
	for side: float in [-1.0, 1.0]:
		var arm: PackedVector2Array = Landmark.curve(shoulders + Vector2(side * shoulder_width * 0.45, 4.0), shoulders + Vector2(side * shoulder_width * 1.1, -orb_lift * 0.6), orb + Vector2(side * orb_radius * 0.9, 4.0), 6)
		Landmark.draw_band(part, arm, 8.0, 5.0, stone.darkened(0.08))
	# Hood: a pointed round shape, no face.
	var hood: PackedVector2Array = Landmark.ellipse(shoulders - Vector2(0.0, hood_radius * 0.8), Vector2(hood_radius, hood_radius * 1.15), 12)
	part.draw_colored_polygon(hood, stone.darkened(0.2))
	part.draw_colored_polygon(Landmark.ellipse(shoulders - Vector2(0.0, hood_radius * 0.6), Vector2(hood_radius * 0.55, hood_radius * 0.7), 10), stone.darkened(0.55))
	# The orb (its faint glow is on the glow layer).
	part.draw_circle(orb, orb_radius, stone.lightened(0.15))
	# Carved ring on the plinth's front face.
	var face_mid := Vector2(0.0, -plinth_height * 0.5 - 1.0)
	part.draw_arc(face_mid, plinth_height * 0.32, 0.0, TAU, 16, stone.darkened(0.4), 1.2, true)
	part.draw_line(face_mid + Vector2(-plinth_size.x * 0.38, 0.0), face_mid + Vector2(-plinth_height * 0.4, 0.0), stone.darkened(0.4), 1.0, true)
	part.draw_line(face_mid + Vector2(plinth_height * 0.4, 0.0), face_mid + Vector2(plinth_size.x * 0.38, 0.0), stone.darkened(0.4), 1.0, true)


func _draw_glow(canvas: Node2D) -> void:
	var orb: Vector2 = _orb_center()
	var breath: float = 0.75 + 0.25 * sin(_time * 1.3)
	_batch.add_dot(orb, orb_radius * 1.9, glow(0.12 * breath), 10)
	_batch.add_dot(orb, orb_radius * 0.9, glow(0.5 * breath), 8)
	_batch.draw(canvas)
