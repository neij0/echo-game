class_name LandmarkStatue
extends Landmark
## An ancient stone keeper on a plinth, holding up a small orb (a hint at the
## Ancient Light), with carved rings on two broken pillars beside it and a
## fallen pillar drum. Plinth, pillars and drum are solid. The figure has no
## face: a hood, a robe and raised arms (never creature-like). The orb glows
## very faintly.

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
## Pillars: positions (local), base radii, heights.
@export var pillar_positions: PackedVector2Array = PackedVector2Array([Vector2(-112.0, 30.0), Vector2(106.0, -20.0)])
@export var pillar_radii: PackedVector2Array = PackedVector2Array([Vector2(25.0, 18.0), Vector2(23.0, 16.0)])
@export var pillar_heights: PackedFloat32Array = PackedFloat32Array([96.0, 54.0])
## Carved rings on each pillar (shares of its height).
@export var ring_heights: PackedFloat32Array = PackedFloat32Array([0.2, 0.55, 0.85])
@export var drum_position: Vector2 = Vector2(70.0, 64.0)
@export var drum_radii: Vector2 = Vector2(30.0, 16.0)
@export var drum_height: float = 18.0


func _footprint_shapes() -> Array[PackedVector2Array]:
	var half: Vector2 = plinth_size * 0.5
	var shapes: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])]
	for i: int in pillar_positions.size():
		shapes.append(Landmark.ellipse(pillar_positions[i], pillar_radii[i], 14))
	shapes.append(Landmark.ellipse(drum_position, drum_radii, 12, 0.08, 4.0))
	return shapes


func _footprint_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array([plinth_height])
	heights.append_array(pillar_heights)
	heights.append(drum_height)
	return heights


func _build_parts() -> void:
	var stone: Color = material_color()
	var front_y: float = plinth_size.y * 0.5 + 1.0
	add_part(Vector2(0.0, front_y), _draw_figure.bind(stone, front_y))
	add_sonar_line(_figure_outline(Vector2(0.0, -plinth_height)), PackedVector2Array(), 0.0)
	for i: int in pillar_positions.size():
		var at: Vector2 = pillar_positions[i]
		var base_y: float = at.y + pillar_radii[i].y + 1.0
		add_part(Vector2(at.x, base_y), _draw_rings.bind(i, stone.darkened(0.35), Vector2(at.x, base_y)))


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


func _draw_rings(part: Node2D, index: int, color_value: Color, base: Vector2) -> void:
	var radii: Vector2 = pillar_radii[index]
	var center: Vector2 = pillar_positions[index] - base
	for share: float in ring_heights:
		var h: float = pillar_heights[index] * share
		# The visible front half of a ring around the column (an ellipse seen
		# from the front).
		var points := PackedVector2Array()
		for k: int in 13:
			var angle: float = lerpf(0.15, PI - 0.15, k / 12.0)
			points.append(center + Vector2(cos(angle) * radii.x * 0.98, sin(angle) * radii.y - h))
		part.draw_polyline(points, color_value, 1.4, true)


func _draw_glow(canvas: Node2D) -> void:
	var orb: Vector2 = _orb_center()
	var breath: float = 0.75 + 0.25 * sin(_time * 1.3)
	_batch.add_dot(orb, orb_radius * 1.9, glow(0.12 * breath), 10)
	_batch.add_dot(orb, orb_radius * 0.9, glow(0.5 * breath), 8)
	_batch.draw(canvas)
