class_name LandmarkClam
extends Landmark
## A giant clam, open: the solid lower shell with a scalloped lip, the upper
## shell standing open behind it with radiating ribs, a soft frilled mantle
## inside and a small pearl with a very faint glow.

@export var shell_radii: Vector2 = Vector2(82.0, 46.0)
@export var shell_height: float = 28.0
## The open upper shell: its height above the hinge, its width.
@export var lid_height: float = 120.0
@export var lid_width: float = 176.0
@export var lid_ribs: int = 9
@export var scallops: int = 9
@export var pearl_radius: float = 7.0
@export var mantle_color: Color = Color(0.36, 0.3, 0.46)


func _footprint_shapes() -> Array[PackedVector2Array]:
	return [Landmark.ellipse(Vector2.ZERO, shell_radii, 20, 0.04, 6.0)]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([shell_height])


func _build_parts() -> void:
	var shell: Color = material_color()
	# Every variant opens its upper shell differently (not in the footprint).
	lid_height *= lerpf(0.7, 1.15, rand(1.0))
	lid_width *= lerpf(0.9, 1.1, rand(2.0))
	# The upper shell stands at the back (behind the lower shell's top).
	var hinge_y: float = -shell_radii.y + 1.0
	add_part(Vector2(0.0, hinge_y), _draw_lid.bind(shell, hinge_y))
	# The mantle, pearl and lip lie on top of the lower shell.
	var front_y: float = shell_radii.y + 1.0
	add_part(Vector2(0.0, front_y), _draw_inside.bind(shell, front_y))
	add_sonar_line(_lid_outline(), PackedVector2Array(), 0.0)


func _hinge() -> Vector2:
	return Vector2(0.0, -shell_radii.y * 0.6 - shell_height)


## The upper shell's fan outline (local), from one hinge side round the top.
func _lid_outline() -> PackedVector2Array:
	var hinge: Vector2 = _hinge()
	var points := PackedVector2Array()
	var steps: int = scallops * 2
	for k: int in steps + 1:
		var t: float = float(k) / steps
		var angle: float = lerpf(PI * 1.05, PI * 1.95, t)
		var scallop: float = 1.0 + 0.05 * cos(t * scallops * TAU)
		points.append(hinge + Vector2(cos(angle) * lid_width * 0.5, sin(angle) * lid_height) * scallop)
	return points


func _draw_lid(part: Node2D, shell: Color, base_y: float) -> void:
	var offset := Vector2(0.0, base_y)
	var hinge: Vector2 = _hinge() - offset
	var outline: PackedVector2Array = _lid_outline()
	var fan := PackedVector2Array([hinge])
	for point: Vector2 in outline:
		fan.append(point - offset)
	part.draw_colored_polygon(fan, shell.darkened(0.18))
	for k: int in lid_ribs:
		var t: float = (k + 0.5) / lid_ribs
		var rim: Vector2 = outline[roundi(t * (outline.size() - 1))] - offset
		part.draw_line(hinge, hinge.lerp(rim, 0.97), shell.darkened(0.4), 1.4, true)
	var rim_line := PackedVector2Array()
	for point: Vector2 in outline:
		rim_line.append(point - offset)
	part.draw_polyline(rim_line, shell.lightened(0.2), 1.4, true)


func _draw_inside(part: Node2D, shell: Color, base_y: float) -> void:
	var top := Vector2(0.0, -shell_height - base_y)
	# The soft mantle filling the lower shell's top.
	part.draw_colored_polygon(Landmark.ellipse(top, shell_radii * 0.72, 18, 0.08, 1.0), mantle_color.lerp(rock_color, 0.3).darkened(0.25))
	var frill := PackedVector2Array()
	for k: int in 25:
		var angle: float = TAU * k / 24.0
		var wave: float = 1.0 + 0.08 * sin(angle * 9.0)
		frill.append(top + Vector2(cos(angle) * shell_radii.x * 0.72, sin(angle) * shell_radii.y * 0.72) * wave)
	part.draw_polyline(frill, mantle_color.lerp(rock_color, 0.3), 1.5, true)
	part.draw_circle(top + Vector2(0.0, -2.0), pearl_radius, shell.lightened(0.3))
	# The lower shell's scalloped front lip.
	var lip := PackedVector2Array()
	for k: int in scallops * 2 + 1:
		var t: float = float(k) / (scallops * 2)
		var angle: float = lerpf(0.05, PI - 0.05, t)
		var bump: float = 3.0 * absf(sin(t * scallops * PI))
		lip.append(top + Vector2(cos(angle) * shell_radii.x, sin(angle) * shell_radii.y - bump))
	part.draw_polyline(lip, shell.lightened(0.18), 1.5, true)


func _has_glow() -> bool:
	return true


func _draw_glow(canvas: Node2D) -> void:
	var pearl: Vector2 = Vector2(0.0, -shell_height - 2.0)
	var breath: float = 0.7 + 0.3 * sin(_time * 0.8)
	_batch.add_dot(pearl, pearl_radius * 2.0, glow(0.1 * breath), 10)
	_batch.add_dot(pearl, pearl_radius * 0.7, glow(0.4 * breath), 8)
	_batch.draw(canvas)
