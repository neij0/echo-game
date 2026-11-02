class_name JourneyIslandDesert
extends JourneyIsland
## The Desert on the Journey screen: dunes and the ruins of an old city (broken
## pillars, an arch, a wall with windows), sand drifting over them. Step 1: a
## camp fire; step 2: the windows and runes glow; step 3: the obelisk's
## capstone burns like a beacon (the marker).

@export var fire_color: Color = Color(1.0, 0.6, 0.25)
@export var rune_color: Color = Color(1.0, 0.82, 0.45)
@export var sand_color: Color = Color(0.09, 0.07, 0.045)
@export var ruin_color: Color = Color(0.04, 0.032, 0.025)

## Each dune: the points of its silhouette (from left to right on its base).
var _dunes: Array[PackedVector2Array] = []
## {base, width, height, broken}
var _pillars: Array[Dictionary] = []
## {at, step, order}
var _windows: Array[Dictionary] = []
## {y, phase, speed, length}
var _streaks: Array[Dictionary] = []


func _build_kind(rng: RandomNumberGenerator) -> void:
	for d: Array in [[-0.55, -0.35, 0.5, 18.0], [0.35, -0.5, 0.55, 22.0], [-0.1, 0.35, 0.6, 14.0]]:
		var center: Vector2 = on_top(d[0], d[1])
		var half: float = float(d[2]) * half_width * 0.5
		var dune := PackedVector2Array()
		for i: int in 15:
			var t: float = float(i) / 14.0
			var rise: float = pow(sin(PI * t), 1.6) * float(d[3]) * (1.0 + 0.25 * sin(t * 5.0))
			dune.append(center + Vector2(lerpf(-half, half, t), -rise))
		_dunes.append(dune)
	for p: Array in [[-0.62, 0.1, 9.0, 42.0, true], [-0.48, 0.2, 9.0, 30.0, true], [0.62, 0.05, 10.0, 48.0, false], [0.75, 0.25, 8.0, 26.0, true]]:
		_pillars.append({"base": on_top(p[0], p[1]), "width": p[2], "height": p[3], "broken": p[4]})
	for i: int in 4:
		_windows.append({"at": on_top(0.18, 0.12) + Vector2(-22.0 + 15.0 * float(i), -16.0 - 9.0 * float(i % 2)),
			"step": 2, "order": float(i) / 4.0})
	for i: int in 6:
		_streaks.append({"y": rng.randf_range(-0.8, 0.6) * top_depth - rng.randf_range(0.0, 30.0), "phase": rng.randf(),
			"speed": rng.randf_range(0.08, 0.16), "length": rng.randf_range(20.0, 40.0)})


func _draw_kind() -> void:
	var on: float = overall()
	for dune: PackedVector2Array in _dunes:
		var shape := dune.duplicate()
		shape.append(dune[dune.size() - 1] + Vector2(0.0, 4.0))
		shape.append(dune[0] + Vector2(0.0, 4.0))
		draw_colored_polygon(shape, shade(sand_color * 1.4))
		draw_polyline(dune, Color(accent, line_alpha()), 1.2, true)
	# The wall with windows, the arch, the pillars.
	var wall_base: Vector2 = on_top(0.18, 0.12)
	var wall := PackedVector2Array([wall_base + Vector2(-34.0, 0.0), wall_base + Vector2(30.0, 0.0), wall_base + Vector2(30.0, -30.0),
		wall_base + Vector2(14.0, -36.0), wall_base + Vector2(4.0, -30.0), wall_base + Vector2(-12.0, -38.0), wall_base + Vector2(-34.0, -32.0)])
	draw_colored_polygon(wall, shade(ruin_color))
	draw_polyline(wall, Color(accent, line_alpha()), 1.0, true)
	for window: Dictionary in _windows:
		var window_on: float = lit(window.step, window.order)
		var at: Vector2 = window.at
		draw_rect(Rect2(at - Vector2(2.5, 4.0), Vector2(5.0, 8.0)), Color(0.0, 0.0, 0.0, 0.6).lerp(glow(rune_color, 1.0, 1.6), window_on))
	_draw_arch(on_top(-0.25, -0.15), 46.0, 40.0)
	for pillar: Dictionary in _pillars:
		_draw_pillar(pillar.base, pillar.width, pillar.height, pillar.broken)
	# The camp fire.
	var fire_on: float = lit(1, 0.0)
	var fire: Vector2 = on_top(-0.05, 0.5)
	if fire_on > 0.0:
		var flicker: float = 0.8 + 0.2 * sin(_time * 11.0) * sin(_time * 7.3)
		draw_circle(fire, 26.0, Color(fire_color, 0.07 * fire_on))
		draw_colored_polygon(PackedVector2Array([fire + Vector2(-4.0, 0.0), fire + Vector2(4.0, 0.0), fire + Vector2(0.0, -11.0 * flicker)]),
			glow(fire_color, fire_on))
		draw_glow_dot(fire + Vector2(0.0, -3.0), 2.5, fire_color, fire_on * flicker)
	# The marker: an obelisk whose capstone burns.
	var obelisk_base: Vector2 = on_top(0.42, -0.35)
	var obelisk := PackedVector2Array([obelisk_base + Vector2(-8.0, 0.0), obelisk_base + Vector2(8.0, 0.0), obelisk_base + Vector2(5.0, -70.0),
		obelisk_base + Vector2(0.0, -80.0), obelisk_base + Vector2(-5.0, -70.0)])
	draw_colored_polygon(obelisk, shade(ruin_color))
	draw_polyline(obelisk, Color(accent, line_alpha()), 1.0, true)
	var beacon_on: float = lit(3, 0.4)
	draw_glow_dot(obelisk_base + Vector2(0.0, -76.0), 3.5, rune_color, beacon_on * (0.85 + 0.15 * sin(_time * 2.0)))
	if beacon_on > 0.0:
		draw_circle(obelisk_base + Vector2(0.0, -76.0), 30.0, Color(rune_color, 0.06 * beacon_on))
	# Sand drifting in the wind.
	if light > 0.0:
		for streak: Dictionary in _streaks:
			var t: float = fposmod(_time * float(streak.speed) + float(streak.phase), 1.0)
			var x: float = lerpf(-half_width, half_width, t)
			draw_line(Vector2(x, streak.y), Vector2(x + float(streak.length), float(streak.y) - 2.0),
				Color(accent, 0.12 * on * sin(PI * t)), 1.0, true)


func _draw_pillar(base: Vector2, width: float, height: float, broken: bool) -> void:
	var half: float = width * 0.5
	var top: float = -height
	var shape := PackedVector2Array([base + Vector2(-half, 0.0), base + Vector2(half, 0.0)])
	if broken:
		shape.append(base + Vector2(half, top + 6.0))
		shape.append(base + Vector2(half * 0.2, top + 1.0))
		shape.append(base + Vector2(-half * 0.4, top + 8.0))
		shape.append(base + Vector2(-half, top))
	else:
		shape.append(base + Vector2(half, top))
		shape.append(base + Vector2(half + 3.0, top - 4.0))
		shape.append(base + Vector2(-half - 3.0, top - 4.0))
		shape.append(base + Vector2(-half, top))
	draw_colored_polygon(shape, shade(ruin_color))
	draw_line(base + Vector2(-half, 0.0), base + Vector2(-half, top), Color(accent, line_alpha()), 1.0, true)


func _draw_arch(base: Vector2, width: float, height: float) -> void:
	var half: float = width * 0.5
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i: int in 11:
		var angle: float = PI + PI * float(i) / 10.0
		outer.append(base + Vector2(cos(angle) * half, -height * 0.6 + sin(angle) * height * 0.4))
		inner.append(base + Vector2(cos(angle) * half * 0.62, -height * 0.6 + sin(angle) * height * 0.28))
	var shape := PackedVector2Array([base + Vector2(-half, 0.0)])
	shape.append_array(outer)
	shape.append(base + Vector2(half, 0.0))
	shape.append(base + Vector2(half * 0.62, 0.0))
	inner.reverse()
	shape.append_array(inner)
	shape.append(base + Vector2(-half * 0.62, 0.0))
	draw_colored_polygon(shape, shade(ruin_color))
	draw_polyline(outer, Color(accent, line_alpha()), 1.0, true)
