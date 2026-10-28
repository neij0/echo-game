class_name LandmarkWhale
extends Landmark
## The skeleton of a whale lying on the floor: a long skull with its jaw
## bones, a low spine (solid) and pairs of ribs arching up from it and down to
## the floor on both sides. The ribs have no collision: the players can swim
## between them. Some ribs are broken or missing. Pale bone, dim.

@export var skull_center: Vector2 = Vector2(-168.0, 0.0)
@export var skull_radii: Vector2 = Vector2(70.0, 34.0)
@export var skull_height: float = 30.0
## The spine from behind the skull to the tail (local x), its width at both ends.
@export var spine_from: float = -100.0
@export var spine_to: float = 200.0
@export var spine_width_start: float = 22.0
@export var spine_width_end: float = 8.0
@export var spine_height: float = 16.0
## Rib pairs along the spine: how many, how far they reach out on the floor,
## how high they arch, and how thick they are.
@export var rib_count: int = 7
@export var rib_reach: float = 92.0
@export var rib_arch: float = 84.0
@export var rib_width: float = 7.0
## Chance that one rib of a pair is missing.
@export_range(0.0, 1.0) var missing_rib_chance: float = 0.2
@export var jaw_length: float = 120.0
## Ribs sweep back towards the tail by this much (pixels at the floor).
@export var rib_sweep: float = 38.0


func _footprint_shapes() -> Array[PackedVector2Array]:
	var skull: PackedVector2Array = Landmark.ellipse(skull_center, skull_radii, 18, 0.06, 2.0)
	# A pointed snout to the left.
	skull[9] = skull_center + Vector2(-skull_radii.x * 1.25, 0.0)
	var spine := PackedVector2Array()
	var back := PackedVector2Array()
	var steps: int = 10
	for k: int in steps + 1:
		var t: float = float(k) / steps
		var x: float = lerpf(spine_from, spine_to, t)
		var half: float = lerpf(spine_width_start, spine_width_end, t) * 0.5
		var sag: float = sin(t * PI * 1.3) * 6.0
		spine.append(Vector2(x, sag - half))
		back.append(Vector2(x, sag + half))
	back.reverse()
	spine.append_array(back)
	return [skull, spine]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([skull_height, spine_height])


func _build_parts() -> void:
	var bone: Color = material_color()
	# North ribs sort behind the spine, south ribs in front of it.
	add_part(Vector2(0.0, -rib_reach), _draw_ribs.bind(-1.0, bone, -rib_reach))
	add_part(Vector2(0.0, rib_reach), _draw_ribs.bind(1.0, bone.lightened(0.05), rib_reach))
	add_part(Vector2(skull_center.x, skull_center.y + skull_radii.y + 30.0), _draw_jaws.bind(bone, skull_center.y + skull_radii.y + 30.0))
	for k: int in rib_count:
		for side: float in [-1.0, 1.0]:
			if _missing(k, side):
				continue
			add_sonar_line(_rib_line(k, side), _rib_sights(k, side))


func _rib_x(k: int) -> float:
	return lerpf(spine_from + 20.0, spine_to - 40.0, float(k) / maxf(rib_count - 1, 1))


func _missing(k: int, side: float) -> bool:
	return Landmark.hash01(k * 5.3 + side * 1.9) < missing_rib_chance


## One rib (local): from the top of the spine, arching up and out, down to
## the floor rib_reach away (side -1 = north, 1 = south). Shorter to the tail.
func _rib_line(k: int, side: float) -> PackedVector2Array:
	var t: float = float(k) / maxf(rib_count - 1, 1)
	var size: float = lerpf(1.0, 0.55, t)
	var x: float = _rib_x(k)
	var root := Vector2(x, -spine_height)
	var foot := Vector2(x + rib_sweep * size, side * rib_reach * size)
	var apex := Vector2(x + rib_sweep * 0.3 * size, side * rib_reach * size * 0.7 - rib_arch * size - spine_height)
	return Landmark.curve(root, apex, foot, 10)


## The floor points under a rib (for the sonar's line of sight).
func _rib_sights(k: int, side: float) -> PackedVector2Array:
	var line: PackedVector2Array = _rib_line(k, side)
	var sights := PackedVector2Array()
	for i: int in line.size():
		var t: float = float(i) / maxf(line.size() - 1, 1)
		sights.append(line[0].lerp(line[line.size() - 1], t) + Vector2(0.0, spine_height * (1.0 - t)))
	return sights


func _draw_ribs(part: Node2D, side: float, bone: Color, base_y: float) -> void:
	for k: int in rib_count:
		if _missing(k, side):
			continue
		var line: PackedVector2Array = _rib_line(k, side)
		for i: int in line.size():
			line[i].y -= base_y
		# A broken rib ends early.
		if Landmark.hash01(k * 2.1 + side) < 0.25:
			line = line.slice(0, 7)
		Landmark.draw_band(part, line, rib_width, rib_width * 0.5, bone)
		part.draw_polyline(line.slice(0, 6), bone.lightened(0.2), 1.0, true)


func _draw_jaws(part: Node2D, bone: Color, base_y: float) -> void:
	# Two jaw bones lying on the floor, opening forward from the skull.
	var hinge: Vector2 = skull_center + Vector2(-skull_radii.x * 0.3, skull_radii.y * 0.7) - Vector2(0.0, base_y)
	for side: float in [-1.0, 1.0]:
		var tip: Vector2 = hinge + Vector2(-jaw_length, 18.0 + side * 16.0)
		var line: PackedVector2Array = Landmark.curve(hinge, hinge.lerp(tip, 0.5) + Vector2(0.0, 10.0 + side * 6.0), tip, 8)
		Landmark.draw_band(part, line, 9.0, 4.0, bone.darkened(0.05))
		part.draw_polyline(line, bone.lightened(0.15), 1.0, true)
