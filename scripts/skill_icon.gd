class_name SkillIcon
extends Control
## A skill's small vector icon (no image files): a dark disc with a simple shape
## in the skill's colour, rank dots below it, and for active skills a dark
## sweep while it recharges. Used by the HUD (PlayerStatus) and the skill
## choice screen. The shape and colour come from the SkillDefinition.

enum Shape { RINGS, HOURGLASS, BUBBLES, LURE, EYE, ARC, SHIELD, STAR, CHEVRONS, HEART, LINK, SHARD, REFILL }

@export var background_color: Color = Color(0.04, 0.06, 0.1, 0.9)
@export var border_color: Color = Color(0.35, 0.42, 0.55)
## Border while an active skill is in use (held / running).
@export var in_use_color: Color = Color(1.0, 0.85, 0.45)
@export var cooldown_color: Color = Color(0.0, 0.0, 0.0, 0.65)
@export var rank_color: Color = Color(1.0, 0.85, 0.45)
@export var empty_rank_color: Color = Color(0.3, 0.33, 0.4)
@export var line_width: float = 2.0

var definition: SkillDefinition
## Owned rank (0 = not owned yet, e.g. a card offering rank 1).
var rank: int = 0
## Rank shown highlighted on a card ("this pick gives rank 2").
var preview_rank: int = 0
## 0 = ready, 1 = just used (active skills).
var cooldown_ratio: float = 0.0
var in_use: bool = false


func setup(skill: SkillDefinition, owned_rank: int, icon_size: float) -> void:
	definition = skill
	rank = owned_rank
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


func set_state(ratio: float, using: bool) -> void:
	if is_equal_approx(ratio, cooldown_ratio) and using == in_use:
		return
	cooldown_ratio = ratio
	in_use = using
	queue_redraw()


func _draw() -> void:
	if definition == null:
		return
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(center, radius, background_color)
	draw_arc(center, radius, 0.0, TAU, 32, in_use_color if in_use else border_color, 1.5, true)
	_draw_shape(definition.icon_shape, center, radius * 0.6, definition.icon_color)
	if cooldown_ratio > 0.0:
		_draw_sweep(center, radius, cooldown_ratio)
	if definition.max_rank > 1:
		_draw_ranks(center, radius)


## A dark pie over the part still recharging (clockwise from the top).
func _draw_sweep(center: Vector2, radius: float, ratio: float) -> void:
	var points := PackedVector2Array([center])
	var steps: int = 24
	for i: int in steps + 1:
		var angle: float = -PI * 0.5 + TAU * ratio * float(i) / steps
		points.append(center + Vector2.from_angle(angle) * radius)
	draw_colored_polygon(points, cooldown_color)


func _draw_ranks(center: Vector2, radius: float) -> void:
	var shown: int = maxi(rank, preview_rank)
	var spacing: float = radius * 0.4
	for i: int in definition.max_rank:
		var x: float = (float(i) - (definition.max_rank - 1) * 0.5) * spacing
		var lit: bool = i < shown
		draw_circle(center + Vector2(x, radius * 0.78), maxf(radius * 0.12, 1.5), rank_color if lit else empty_rank_color)


func _draw_shape(shape: Shape, c: Vector2, r: float, color: Color) -> void:
	var w: float = line_width
	match shape:
		Shape.RINGS:
			draw_circle(c, r * 0.18, color)
			draw_arc(c, r * 0.55, 0.0, TAU, 24, color, w, true)
			draw_arc(c, r * 0.95, -0.9, 0.9, 12, color, w, true)
			draw_arc(c, r * 0.95, PI - 0.9, PI + 0.9, 12, color, w, true)
		Shape.HOURGLASS:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.6, -r), c + Vector2(-r * 0.6, r),
				c + Vector2(r * 0.6, r), c + Vector2(-r * 0.6, -r)]), color, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.75), c + Vector2(r * 0.3, r * 0.75), c + Vector2(0.0, r * 0.2)]), color)
		Shape.BUBBLES:
			draw_arc(c + Vector2(-r * 0.25, r * 0.3), r * 0.5, 0.0, TAU, 20, color, w, true)
			draw_arc(c + Vector2(r * 0.45, -r * 0.35), r * 0.32, 0.0, TAU, 16, color, w, true)
			draw_arc(c + Vector2(-r * 0.2, -r * 0.75), r * 0.18, 0.0, TAU, 12, color, w, true)
		Shape.LURE:
			draw_dashed_line(c + Vector2(-r, r * 0.7), c + Vector2(r * 0.4, -r * 0.3), color, w, r * 0.25)
			draw_circle(c + Vector2(r * 0.5, -r * 0.4), r * 0.2, color)
			draw_arc(c + Vector2(r * 0.5, -r * 0.4), r * 0.5, 0.0, TAU, 20, color, w * 0.75, true)
		Shape.EYE:
			draw_arc(c + Vector2(0.0, r * 0.55), r, -PI * 0.8, -PI * 0.2, 16, color, w, true)
			draw_arc(c - Vector2(0.0, r * 0.55), r, PI * 0.2, PI * 0.8, 16, color, w, true)
			draw_circle(c, r * 0.25, color)
		Shape.ARC:
			draw_arc(c + Vector2(0.0, r * 0.4), r, -PI * 0.9, -PI * 0.1, 20, color, w * 1.5, true)
			draw_line(c + Vector2(0.0, r * 0.9), c + Vector2(0.0, -r * 0.2), color, w, true)
		Shape.SHIELD:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.7), c + Vector2(0.0, -r), c + Vector2(r * 0.8, -r * 0.7),
				c + Vector2(r * 0.65, r * 0.3), c + Vector2(0.0, r), c + Vector2(-r * 0.65, r * 0.3), c + Vector2(-r * 0.8, -r * 0.7)]), color, w, true)
		Shape.STAR:
			for i: int in 4:
				var direction: Vector2 = Vector2.from_angle(PI * 0.5 * i + PI * 0.25)
				draw_line(c + direction * r * 0.25, c + direction * r, color, w, true)
			draw_arc(c, r * 0.3, 0.0, TAU, 16, color, w, true)
		Shape.CHEVRONS:
			for i: int in 2:
				var x: float = (float(i) - 0.5) * r * 0.8
				draw_polyline(PackedVector2Array([c + Vector2(x - r * 0.35, -r * 0.7), c + Vector2(x + r * 0.35, 0.0),
					c + Vector2(x - r * 0.35, r * 0.7)]), color, w * 1.3, true)
		Shape.HEART:
			draw_line(c + Vector2(0.0, -r * 0.8), c + Vector2(0.0, r * 0.8), color, w * 1.6, true)
			draw_line(c + Vector2(-r * 0.8, 0.0), c + Vector2(r * 0.8, 0.0), color, w * 1.6, true)
			draw_arc(c, r, 0.0, TAU, 24, color, w * 0.6, true)
		Shape.LINK:
			draw_arc(c + Vector2(-r * 0.35, 0.0), r * 0.5, 0.0, TAU, 20, color, w, true)
			draw_arc(c + Vector2(r * 0.35, 0.0), r * 0.5, 0.0, TAU, 20, color, w, true)
		Shape.SHARD:
			var diamond := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r * 0.55, 0.0), c + Vector2(0.0, r), c + Vector2(-r * 0.55, 0.0)])
			draw_colored_polygon(diamond, Color(color, 0.35))
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), color, w, true)
		Shape.REFILL:
			draw_arc(c, r * 0.8, -PI * 0.3, PI * 1.5, 24, color, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.5, -r * 0.95), c + Vector2(r * 0.95, -r * 0.45),
				c + Vector2(r * 0.35, -r * 0.35)]), color)
