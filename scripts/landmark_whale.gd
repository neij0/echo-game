class_name LandmarkWhale
extends Landmark
## The skeleton of a whale lying on the sand (3/4 view): a big skull with a
## long snout and dark eye hollows at one end, a spine that bends along its
## length (solid, with knobbed vertebrae), and pairs of ribs: each one leaves
## the spine, arches out and up, and curves back in and down to the sand, so
## the pairs enclose the body like a cage, longest behind the skull and
## shorter towards the tail. Some ribs are broken off, some have fallen and
## lie flat on the sand; loose vertebrae and a lower jaw bone lie around.
## The ribs have no collision: the players swim between them.
## Variation: floor_turn turns the skeleton on the floor; the variant bends
## the spine, picks the rib lengths and the debris; damage breaks and drops
## more ribs.

@export var spine_length: float = 290.0
## How far the spine bends to the side (and how many waves along it).
@export var spine_bend: float = 34.0
@export var spine_waves: float = 0.8
@export var spine_width_start: float = 22.0
@export var spine_width_end: float = 8.0
@export var spine_height: float = 14.0
@export var skull_radii: Vector2 = Vector2(70.0, 42.0)
@export var skull_height: float = 34.0
@export var snout_length: float = 50.0
## Rib pairs along the spine (share of its length where they start / end).
@export var rib_pairs: int = 8
@export var ribs_from: float = 0.06
@export var ribs_to: float = 0.62
## How far a rib reaches out on the floor, how high it arches, its width.
@export var rib_reach: float = 60.0
@export var rib_arch: float = 80.0
@export var rib_width: float = 7.0
## Share of ribs broken off / fallen flat at damage 0 and damage 1.
@export var broken_share: Vector2 = Vector2(0.1, 0.4)
@export var fallen_share: Vector2 = Vector2(0.05, 0.25)
@export var loose_vertebrae: int = 4
@export var jaw_length: float = 120.0

enum Rib { WHOLE, BROKEN, FALLEN, GONE }


# --- Layout (design space; _f turns it on the floor) ---------------------------

func _f(p: Vector2) -> Vector2:
	return p.rotated(floor_turn)


## Spine point at t (0 = behind the skull, 1 = tail tip), design space.
func _spine(t: float) -> Vector2:
	var phase: float = rand(1.0) * TAU
	var x: float = lerpf(-spine_length * 0.4, spine_length * 0.6, t)
	return Vector2(x, spine_bend * (sin(t * PI * spine_waves * 2.0 + phase) - sin(phase)))


func _spine_normal(t: float) -> Vector2:
	var direction: Vector2 = (_spine(minf(t + 0.02, 1.0)) - _spine(maxf(t - 0.02, 0.0))).normalized()
	return direction.orthogonal()


func _skull_center() -> Vector2:
	var back: Vector2 = (_spine(0.0) - _spine(0.05)).normalized()
	return _spine(0.0) + back * skull_radii.x * 0.85


func _spine_outline() -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps: int = 16
	for k: int in steps + 1:
		var t: float = float(k) / steps
		var half: float = lerpf(spine_width_start, spine_width_end, t) * 0.5
		left.append(_f(_spine(t) + _spine_normal(t) * half))
		right.append(_f(_spine(t) - _spine_normal(t) * half))
	right.reverse()
	left.append_array(right)
	return left


func _skull_outline() -> PackedVector2Array:
	var center: Vector2 = _skull_center()
	var back: Vector2 = (_spine(0.0) - _spine(0.05)).normalized()
	var points := PackedVector2Array()
	var count: int = 20
	for k: int in count:
		var angle: float = TAU * k / count
		var local := Vector2(cos(angle) * skull_radii.x, sin(angle) * skull_radii.y * (1.0 + 0.08 * sin(angle * 3.0)))
		# The front half narrows into the snout.
		if local.x > 0.0:
			var snout: float = local.x / skull_radii.x
			local = Vector2(local.x + snout * snout * snout_length, local.y * (1.0 - 0.55 * snout * snout))
		points.append(_f(center + local.rotated(back.angle())))
	return points


func _rib_state(k: int, side: float) -> Rib:
	var roll: float = rand(k * 3.7 + side * 1.3 + 5.0)
	var broken: float = lerpf(broken_share.x, broken_share.y, damage)
	var fallen: float = lerpf(fallen_share.x, fallen_share.y, damage)
	if roll < fallen * 0.3:
		return Rib.GONE
	if roll < fallen:
		return Rib.FALLEN
	if roll < fallen + broken:
		return Rib.BROKEN
	return Rib.WHOLE


func _rib_t(k: int) -> float:
	return lerpf(ribs_from, ribs_to, float(k) / maxf(rib_pairs - 1, 1))


## Rib size: largest a little behind the skull, shrinking to the tail, each a bit different.
func _rib_size(k: int, side: float) -> float:
	var t: float = float(k) / maxf(rib_pairs - 1, 1)
	var profile: float = sin(lerpf(0.55, 1.0, 1.0 - t) * PI * 0.5 + 0.3) * lerpf(1.0, 0.55, t)
	return profile * lerpf(0.85, 1.12, rand(k * 2.3 + side + 9.0))


## A standing rib as 3/4 points and the floor points under them. u runs from
## the spine (0) to the tip on the sand (1); the outward distance swells and
## comes back in, so each pair curves inward like a cage.
func _rib(k: int, side: float, reach_end: float) -> Array[PackedVector2Array]:
	var t: float = _rib_t(k)
	var root: Vector2 = _spine(t) + _spine_normal(t) * side * spine_width_start * 0.4
	var out: Vector2 = _spine_normal(t) * side
	var back: Vector2 = (_spine(minf(t + 0.05, 1.0)) - _spine(t)).normalized()
	var size: float = _rib_size(k, side)
	var screen := PackedVector2Array()
	var floor_points := PackedVector2Array()
	var steps: int = 10
	for i: int in steps + 1:
		var u: float = reach_end * float(i) / steps
		var outward: float = rib_reach * size * sin(u * PI * 0.72) / sin(PI * 0.72)
		var floor_point: Vector2 = _f(root + out * outward + back * 18.0 * size * u * u)
		var z: float = spine_height * (1.0 - u) + rib_arch * size * sin(u * PI)
		floor_points.append(floor_point)
		screen.append(Landmark.project(floor_point, z))
	return [screen, floor_points]


## A fallen rib lying flat on the sand next to where it stood.
func _fallen_rib(k: int, side: float) -> PackedVector2Array:
	var t: float = _rib_t(k)
	var start: Vector2 = _spine(t) + _spine_normal(t) * side * (rib_reach * 0.5 + 20.0 * rand(k + 30.0))
	var direction: Vector2 = _spine_normal(t).rotated(lerpf(-1.2, 1.2, rand(k * 1.9 + side + 31.0))) * side
	var length: float = rib_reach * 1.2 * _rib_size(k, side)
	var bend: Vector2 = direction.orthogonal() * length * 0.25
	var line := PackedVector2Array()
	for point: Vector2 in Landmark.curve(start, start + direction * length * 0.5 + bend, start + direction * length, 8):
		line.append(_f(point))
	return line


func _footprint_shapes() -> Array[PackedVector2Array]:
	return [_skull_outline(), _spine_outline()]


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array([skull_height, spine_height])


# --- Parts ---------------------------------------------------------------------

func _build_parts() -> void:
	var bone: Color = material_color()
	for k: int in rib_pairs:
		for side: float in [-1.0, 1.0]:
			var state: Rib = _rib_state(k, side)
			if state == Rib.GONE:
				continue
			if state == Rib.FALLEN:
				var line: PackedVector2Array = _fallen_rib(k, side)
				var base: Vector2 = Vector2(line[line.size() / 2].x, _max_y(line) + 1.0)
				add_part(base, _draw_bone.bind(line, base, rib_width, rib_width * 0.5, bone.darkened(0.05)))
				add_sonar_line(line, line)
				continue
			var reach: float = 1.0 if state == Rib.WHOLE else lerpf(0.4, 0.7, rand(k * 5.1 + side))
			var rib: Array[PackedVector2Array] = _rib(k, side, reach)
			var tip: Vector2 = rib[1][rib[1].size() - 1]
			# Sorted on its foot on the sand (or below its broken end).
			var base := Vector2(tip.x, maxf(tip.y, rib[1][0].y) + 1.0)
			add_part(base, _draw_bone.bind(rib[0], base, rib_width, rib_width * 0.55, bone))
			add_sonar_line(rib[0], rib[1])
	# Knobbed vertebrae along the spine.
	var spine_front: float = _max_y(_spine_outline()) + 1.0
	add_part(Vector2(0.0, spine_front), _draw_vertebrae.bind(bone, spine_front))
	# Eye hollows and the snout ridge on the skull.
	var skull_front: float = _max_y(_skull_outline()) + 1.0
	add_part(Vector2(_f(_skull_center()).x, skull_front), _draw_skull.bind(bone, Vector2(_f(_skull_center()).x, skull_front)))
	# The lower jaw lying on the sand beside the skull, and loose vertebrae.
	var jaw: PackedVector2Array = _jaw_line()
	var jaw_base := Vector2(jaw[jaw.size() / 2].x, _max_y(jaw) + 1.0)
	add_part(jaw_base, _draw_bone.bind(jaw, jaw_base, 11.0, 5.0, bone.darkened(0.04)))
	add_sonar_line(jaw, jaw)
	var loose_base: Vector2 = _f(_spine(0.85)) + Vector2(0.0, 60.0)
	add_part(loose_base, _draw_loose.bind(bone, loose_base))


static func _max_y(points: PackedVector2Array) -> float:
	var lowest: float = -INF
	for point: Vector2 in points:
		lowest = maxf(lowest, point.y)
	return lowest


func _jaw_line() -> PackedVector2Array:
	var center: Vector2 = _skull_center()
	var side: float = 1.0 if rand(40.0) < 0.5 else -1.0
	var hinge: Vector2 = center + Vector2(-skull_radii.x * 0.2, side * (skull_radii.y + 22.0))
	var direction: Vector2 = (center - _spine(0.0)).normalized().rotated(side * lerpf(0.15, 0.6, rand(41.0)))
	var line := PackedVector2Array()
	for point: Vector2 in Landmark.curve(hinge, hinge + direction * jaw_length * 0.5 + direction.orthogonal() * side * 18.0, hinge + direction * jaw_length, 9):
		line.append(_f(point))
	return line


func _draw_bone(part: Node2D, line: PackedVector2Array, base: Vector2, start_width: float, end_width: float, bone: Color) -> void:
	var local := PackedVector2Array()
	for point: Vector2 in line:
		local.append(point - base)
	Landmark.draw_band(part, local, start_width, end_width, bone.darkened(0.08))
	# Lit upper edge.
	var lit := PackedVector2Array()
	for point: Vector2 in local:
		lit.append(point - Vector2(0.0, start_width * 0.25))
	part.draw_polyline(lit, bone.lightened(0.15), 1.0, true)


func _draw_vertebrae(part: Node2D, bone: Color, base_y: float) -> void:
	var count: int = 22
	for k: int in count:
		var t: float = float(k) / (count - 1)
		var at: Vector2 = Landmark.project(_f(_spine(t)), spine_height) - Vector2(0.0, base_y)
		var size: float = lerpf(7.0, 3.0, t)
		part.draw_colored_polygon(Landmark.ellipse(at - Vector2(0.0, size * 0.6), Vector2(size * 0.8, size * 0.9), 8), bone.lightened(0.04))
		part.draw_line(at - Vector2(size * 0.8, 0.0), at + Vector2(size * 0.8, 0.0), bone.darkened(0.35), 1.0, true)


func _draw_skull(part: Node2D, bone: Color, base: Vector2) -> void:
	var center: Vector2 = Landmark.project(_f(_skull_center()), skull_height) - base
	var forward: Vector2 = _f((_skull_center() - _spine(0.0)).normalized())
	for side: float in [-1.0, 1.0]:
		var eye: Vector2 = center + forward * skull_radii.x * 0.25 + forward.orthogonal() * side * skull_radii.y * 0.45
		part.draw_colored_polygon(Landmark.ellipse(eye, Vector2(10.0, 6.0), 10, 0.15, side), bone.darkened(0.7))
	part.draw_line(center - forward * skull_radii.x * 0.3, center + forward * (skull_radii.x + snout_length * 0.8), bone.lightened(0.18), 1.5, true)
	part.draw_line(center + forward.orthogonal() * skull_radii.y * 0.2, center + forward * skull_radii.x * 0.9, bone.darkened(0.3), 1.0, true)


func _draw_loose(part: Node2D, bone: Color, base: Vector2) -> void:
	for i: int in loose_vertebrae + roundi(damage * 3.0):
		var at: Vector2 = _f(_spine(lerpf(0.7, 1.15, rand(i * 2.1 + 50.0))) + Vector2(rand(i * 3.3 + 51.0) - 0.5, rand(i * 4.7 + 52.0) - 0.5) * 120.0) - base
		var size: float = 4.0 + 4.0 * rand(i + 53.0)
		part.draw_colored_polygon(Landmark.ellipse(at, Vector2(size, size * 0.7), 8, 0.2, i), bone.darkened(0.05))
		part.draw_line(at - Vector2(size * 1.6, 0.0), at + Vector2(size * 1.6, 0.0), bone.darkened(0.1), 2.0, true)
