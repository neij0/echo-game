class_name JourneyIslandCaves
extends JourneyIsland
## The Caves on the Journey screen: a rocky top with boulders and a cave mouth in
## the hanging rock, stalactites hanging inside it and under the rock, crystals
## glowing deep inside. Step 1: a couple of crystals in the cave; step 2: more,
## and the stalactite tips; step 3: a great amber crystal on top (the marker).

@export var crystal_color: Color = Color(1.0, 0.62, 0.28)
@export var crystal_alt_color: Color = Color(0.75, 0.55, 1.0)
@export var mouth_center: Vector2 = Vector2(-10.0, 78.0)
@export var mouth_size: Vector2 = Vector2(70.0, 52.0)

var _mouth: PackedVector2Array = PackedVector2Array()
## {base, height, width, step, order, color}
var _inner: Array[Dictionary] = []
## {top, length, width, step, order}
var _stalactites: Array[Dictionary] = []
## {center, radius}
var _boulders: Array[Dictionary] = []


func _build_kind(rng: RandomNumberGenerator) -> void:
	for i: int in 21:
		var angle: float = PI + PI * float(i) / 20.0
		var jitter: float = 1.0 + rng.randf_range(-0.08, 0.08)
		_mouth.append(mouth_center + Vector2(cos(angle) * mouth_size.x, sin(angle) * mouth_size.y) * jitter)
	_mouth.append(mouth_center + Vector2(mouth_size.x * 0.7, mouth_size.y * 0.25))
	_mouth.append(mouth_center + Vector2(-mouth_size.x * 0.7, mouth_size.y * 0.25))
	var inner: Array = [[-0.45, 1, 0.0], [0.35, 1, 0.5], [-0.1, 2, 0.1], [0.6, 2, 0.5], [-0.7, 2, 0.8], [0.12, 3, 0.2]]
	for i: int in inner.size():
		var height: float = rng.randf_range(14.0, 26.0)
		_inner.append({"base": mouth_center + Vector2(inner[i][0] * mouth_size.x, mouth_size.y * 0.2), "height": height,
			"width": height * 0.25, "step": inner[i][1], "order": inner[i][2], "color": crystal_alt_color if i % 2 else crystal_color})
	for i: int in 7:
		var x: float = lerpf(-0.75, 0.75, float(i) / 6.0) * mouth_size.x
		var top_y: float = mouth_center.y - sqrt(maxf(1.0 - pow(x / mouth_size.x, 2.0), 0.0)) * mouth_size.y
		_stalactites.append({"top": Vector2(x, top_y + 2.0), "length": rng.randf_range(8.0, 18.0), "width": rng.randf_range(2.5, 4.5),
			"step": 2, "order": rng.randf()})
	for i: int in 6:
		var depth: float = rng.randf_range(0.45, 0.85)
		var x: float = rng.randf_range(-0.5, 0.5) * half_width * (1.0 - depth * 0.6)
		_stalactites.append({"top": Vector2(x, hang_depth * depth), "length": rng.randf_range(16.0, 30.0), "width": rng.randf_range(4.0, 7.0),
			"step": 2, "order": rng.randf()})
	for p: Vector2 in [Vector2(-0.6, -0.2), Vector2(-0.45, 0.1), Vector2(0.55, -0.3), Vector2(0.7, 0.05), Vector2(0.3, 0.4)]:
		_boulders.append({"center": on_top(p.x, p.y), "radius": rng.randf_range(9.0, 16.0)})


func _draw_under_kind() -> void:
	var on: float = overall()
	# The cave mouth: a deep hollow lit from inside.
	draw_colored_polygon(_mouth, Color(0.004, 0.006, 0.01))
	if on > 0.0:
		draw_circle(mouth_center + Vector2(0.0, mouth_size.y * 0.1), mouth_size.y * 0.8, Color(crystal_color, 0.07 * on))
	for crystal: Dictionary in _inner:
		draw_crystal(crystal.base, crystal.height, crystal.width, crystal.color, lit(crystal.step, crystal.order))
	var outline := _mouth.duplicate()
	draw_polyline(outline, Color(accent, line_alpha()), 1.2, true)
	for stalactite: Dictionary in _stalactites:
		var top: Vector2 = stalactite.top
		var tip: Vector2 = top + Vector2(0.0, stalactite.length)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-stalactite.width, 0.0), top + Vector2(stalactite.width, 0.0), tip]),
			shade(rock_color * 0.8))
		draw_glow_dot(tip, 1.4, crystal_color, lit(stalactite.step, stalactite.order) * (0.6 + 0.4 * sin(_time * 1.7 + top.x)))


func _draw_kind() -> void:
	for boulder: Dictionary in _boulders:
		var center: Vector2 = boulder.center
		var radius: float = boulder.radius
		var shape := PackedVector2Array()
		for i: int in 12:
			var angle: float = PI + PI * float(i) / 11.0
			shape.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.8))
		draw_colored_polygon(shape, shade(rock_color * 1.6))
		draw_polyline(shape, Color(accent, line_alpha()), 1.0, true)
	# The marker: a great amber crystal on top.
	var marker_on: float = lit(3, 0.5)
	var base: Vector2 = on_top(0.05, 0.05)
	draw_crystal(base + Vector2(-14.0, 4.0), 30.0, 7.0, crystal_alt_color, lit(3, 0.2), -4.0)
	draw_crystal(base, 62.0, 13.0, crystal_color, marker_on, 3.0)
	draw_crystal(base + Vector2(16.0, 5.0), 26.0, 6.0, crystal_color, lit(3, 0.3), 5.0)
	if marker_on > 0.0:
		draw_glow_dot(base + Vector2(3.0, -62.0), 3.5, crystal_color, marker_on * (0.8 + 0.2 * sin(_time * 2.5)))
