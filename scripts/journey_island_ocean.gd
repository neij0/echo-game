class_name JourneyIslandOcean
extends JourneyIsland
## The Ocean on the Journey screen: a slab of dark water with glowing corals and
## crystals, bubbles rising from it and glowing spots on the rock under it.
## Step 1: a few corals; step 2: more corals, crystal clusters, the spots;
## step 3: a tall crystal spire with a beam of light (the world's marker).

@export var coral_color: Color = Color(0.3, 1.0, 0.85)
@export var coral_alt_color: Color = Color(0.75, 0.5, 1.0)
@export var crystal_color: Color = Color(0.45, 0.95, 1.0)
@export var bubble_count: int = 16
@export var bubble_rise: float = 130.0
@export var spire_height: float = 96.0
@export var beam_height: float = 110.0

## {base, step, order, color, branches: Array[PackedVector2Array]}
var _corals: Array[Dictionary] = []
## {base, height, width, step, order, lean}
var _crystals: Array[Dictionary] = []
## {x, phase, speed, size}
var _bubbles: Array[Dictionary] = []
## {at, step, order}
var _spots: Array[Dictionary] = []


func _build_kind(rng: RandomNumberGenerator) -> void:
	var corals: Array = [
		[Vector2(-0.68, -0.1), 1, 0.0], [Vector2(0.6, 0.25), 1, 0.5], [Vector2(-0.25, 0.45), 2, 0.0],
		[Vector2(0.78, -0.3), 2, 0.4], [Vector2(0.25, -0.45), 2, 0.8], [Vector2(-0.82, 0.3), 3, 0.3],
	]
	for i: int in corals.size():
		var base: Vector2 = on_top(corals[i][0].x, corals[i][0].y)
		var branches: Array[PackedVector2Array] = []
		for b: int in rng.randi_range(3, 5):
			var angle: float = -PI * 0.5 + rng.randf_range(-0.9, 0.9)
			var length: float = rng.randf_range(14.0, 26.0)
			var mid: Vector2 = base + Vector2.from_angle(angle) * length * 0.5
			var tip: Vector2 = mid + Vector2.from_angle(angle + rng.randf_range(-0.5, 0.5)) * length * 0.6
			branches.append(PackedVector2Array([base, mid, tip]))
		_corals.append({"base": base, "step": corals[i][1], "order": corals[i][2],
			"color": coral_alt_color if i % 3 == 2 else coral_color, "branches": branches})
	var crystals: Array = [
		[Vector2(-0.42, -0.35), 30.0, 2, 0.1], [Vector2(-0.34, -0.2), 22.0, 2, 0.3], [Vector2(-0.5, -0.15), 18.0, 2, 0.5],
		[Vector2(0.42, -0.1), 26.0, 2, 0.7], [Vector2(0.5, 0.05), 17.0, 2, 0.9], [Vector2(0.08, 0.3), 20.0, 3, 0.0],
	]
	for c: Array in crystals:
		_crystals.append({"base": on_top(c[0].x, c[0].y), "height": c[1], "width": c[1] * 0.22, "step": c[2], "order": c[3],
			"lean": rng.randf_range(-5.0, 5.0)})
	for i: int in bubble_count:
		_bubbles.append({"x": rng.randf_range(-0.7, 0.7) * half_width, "phase": rng.randf(), "speed": rng.randf_range(0.12, 0.25),
			"size": rng.randf_range(1.2, 2.8)})
	for i: int in 9:
		var depth: float = rng.randf_range(0.15, 0.6)
		var width_here: float = half_width * (1.0 - depth) * 0.7
		_spots.append({"at": Vector2(rng.randf_range(-width_here, width_here), hang_depth * depth + top_depth),
			"step": 2 if i < 5 else 3, "order": rng.randf()})


func _draw_under_kind() -> void:
	for spot: Dictionary in _spots:
		var on: float = lit(spot.step, spot.order)
		draw_glow_dot(spot.at, 1.6, coral_color if int(spot.order * 10.0) % 2 == 0 else coral_alt_color,
			on * (0.6 + 0.4 * sin(_time * 1.3 + spot.order * 9.0)))


func _draw_kind() -> void:
	var on: float = overall()
	# Waves on the water slab.
	for k: int in 3:
		var y: float = top_depth * (-0.45 + 0.42 * float(k))
		var width_here: float = half_width * (0.75 - absf(-0.45 + 0.42 * float(k)) * 0.4)
		var wave := PackedVector2Array()
		for i: int in 13:
			var t: float = float(i) / 12.0
			wave.append(Vector2(lerpf(-width_here, width_here, t), y + sin(t * TAU * 2.0 + _time * 0.8 + k) * 1.6))
		draw_polyline(wave, Color(accent, 0.05 + 0.18 * on), 1.0, true)
	for coral: Dictionary in _corals:
		var coral_on: float = lit(coral.step, coral.order)
		var stem: Color = shade(Color(0.03, 0.06, 0.07)).lerp(Color(coral.color, 0.6), coral_on * 0.5)
		for branch: PackedVector2Array in coral.branches:
			draw_polyline(branch, stem, 2.0, true)
			draw_glow_dot(branch[2], 1.8, coral.color, coral_on * (0.75 + 0.25 * sin(_time * 2.0 + branch[2].x)))
	for crystal: Dictionary in _crystals:
		draw_crystal(crystal.base, crystal.height, crystal.width, crystal_color, lit(crystal.step, crystal.order), crystal.lean)
	# The marker: a tall crystal spire with a beam of light.
	var spire_on: float = lit(3, 0.4)
	var spire_base: Vector2 = on_top(-0.05, -0.05)
	draw_crystal(spire_base, spire_height, spire_height * 0.14, crystal_color, spire_on)
	if spire_on > 0.0:
		var top: Vector2 = spire_base + Vector2(0.0, -spire_height)
		var half: float = 3.0
		draw_polygon(PackedVector2Array([top + Vector2(-half, 0.0), top + Vector2(half, 0.0), top + Vector2(half * 3.0, -beam_height),
			top + Vector2(-half * 3.0, -beam_height)]),
			PackedColorArray([glow(crystal_color, 0.22 * spire_on, 1.6), glow(crystal_color, 0.22 * spire_on, 1.6), Color(crystal_color, 0.0),
				Color(crystal_color, 0.0)]))
		draw_glow_dot(top, 4.0, crystal_color, spire_on)
	# Bubbles: more as it lights up.
	var shown: int = int(round(float(bubble_count) * on)) if light > 0.0 else 0
	for i: int in shown:
		var bubble: Dictionary = _bubbles[i]
		var t: float = fposmod(_time * float(bubble.speed) + float(bubble.phase), 1.0)
		var at := Vector2(float(bubble.x) + sin(t * TAU + float(bubble.phase) * 6.0) * 4.0, -t * bubble_rise)
		draw_arc(at, bubble.size, 0.0, TAU, 10, glow(accent, 0.6 * (1.0 - t), 1.6), 1.0, true)
