class_name JourneyIslandForest
extends JourneyIsland
## The Forest on the Journey screen: tree silhouettes (pines and round crowns)
## on a dark meadow, fireflies drifting between them. Step 1: a few fireflies;
## step 2: more, and lanterns; step 3: the great tree's crown glows gold (the
## marker), fireflies everywhere.

@export var firefly_color: Color = Color(0.85, 1.0, 0.45)
@export var crown_color: Color = Color(1.0, 0.82, 0.4)
@export var tree_color: Color = Color(0.015, 0.03, 0.022)
@export var firefly_count: int = 26

## {base, height, round, width} back to front.
var _trees: Array[Dictionary] = []
## {base, phase, step, order}
var _fireflies: Array[Dictionary] = []
var _lanterns: Array[Vector2] = []


func _init() -> void:
	# The great tree's crown.
	crown_height = 106.0


func _build_kind(rng: RandomNumberGenerator) -> void:
	for i: int in 16:
		var x_share: float = rng.randf_range(-0.85, 0.85)
		var y_share: float = rng.randf_range(-0.7, 0.6)
		if absf(x_share) < 0.18 and y_share < 0.2:
			continue
		var round_crown: bool = rng.randf() < 0.35
		_trees.append({"base": on_top(x_share, y_share), "height": rng.randf_range(34.0, 62.0), "round": round_crown,
			"width": rng.randf_range(12.0, 18.0)})
	_trees.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.base as Vector2).y < (b.base as Vector2).y)
	for i: int in firefly_count:
		var step: int = 1 if i < 6 else (2 if i < 15 else 3)
		_fireflies.append({"base": on_top(rng.randf_range(-0.85, 0.85), rng.randf_range(-0.8, 0.6)) + Vector2(0.0, -rng.randf_range(8.0, 50.0)),
			"phase": rng.randf() * TAU, "step": step, "order": rng.randf()})
	_lanterns = [on_top(-0.35, 0.35), on_top(0.42, 0.3), on_top(0.15, 0.55)]


func _draw_kind() -> void:
	var crown_on: float = lit(3, 0.4)
	# The great tree in the middle, behind the others in front of it.
	_draw_round_tree(on_top(0.0, -0.1), 92.0, 34.0, crown_on)
	for tree: Dictionary in _trees:
		if tree.round:
			_draw_round_tree(tree.base, tree.height, tree.width, 0.0)
		else:
			_draw_pine(tree.base, tree.height, tree.width)
	for i: int in _lanterns.size():
		var at: Vector2 = _lanterns[i]
		draw_line(at, at + Vector2(0.0, -12.0), shade(tree_color * 2.0), 1.5)
		draw_glow_dot(at + Vector2(0.0, -14.0), 2.2, crown_color, lit(2, 0.3 + 0.3 * float(i)) * (0.85 + 0.15 * sin(_time * 3.0 + i)))
	for firefly: Dictionary in _fireflies:
		var phase: float = firefly.phase
		var at: Vector2 = (firefly.base as Vector2) + Vector2(sin(_time * 0.6 + phase) * 14.0, cos(_time * 0.8 + phase * 1.3) * 8.0)
		var twinkle: float = 0.5 + 0.5 * sin(_time * 2.4 + phase * 3.0)
		draw_glow_dot(at, 1.3, firefly_color, lit(firefly.step, firefly.order) * twinkle)


func _draw_pine(base: Vector2, height: float, width: float) -> void:
	var color: Color = shade(tree_color)
	draw_line(base, base + Vector2(0.0, -height * 0.2), color, 2.0)
	for k: int in 3:
		var bottom: float = -height * (0.15 + 0.27 * float(k))
		var half: float = width * (1.0 - 0.25 * float(k))
		var shape := PackedVector2Array([base + Vector2(-half, bottom), base + Vector2(half, bottom),
			base + Vector2(0.0, bottom - height * 0.42)])
		draw_colored_polygon(shape, color)
		draw_line(shape[0], shape[2], Color(accent, line_alpha()), 1.0, true)


func _draw_round_tree(base: Vector2, height: float, width: float, glow_on: float) -> void:
	var color: Color = shade(tree_color)
	draw_line(base, base + Vector2(0.0, -height * 0.55), color, maxf(width * 0.18, 2.0))
	var crown: Vector2 = base + Vector2(0.0, -height * 0.7)
	for offset: Vector2 in [Vector2(-0.5, 0.15), Vector2(0.5, 0.2), Vector2(0.0, -0.25), Vector2(0.0, 0.25)]:
		draw_circle(crown + offset * width, width * 0.75, color)
	draw_arc(crown + Vector2(0.0, -0.25) * width, width * 0.75, PI * 1.05, PI * 1.6, 10, Color(accent, line_alpha()), 1.0, true)
	if glow_on > 0.0:
		draw_circle(crown, width * 1.6, Color(crown_color, 0.06 * glow_on))
		for k: int in 7:
			var angle: float = TAU * float(k) / 7.0 + _time * 0.2
			draw_glow_dot(crown + Vector2(cos(angle) * width * 0.8, sin(angle) * width * 0.5), 1.6, crown_color, glow_on)
		draw_glow_dot(crown, 4.0, crown_color, glow_on * 0.8)
