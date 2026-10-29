class_name SkillIcon
extends Control
## A skill's small vector icon (no image files): a dark disc with a simple shape
## in the skill's colour and rank dots below it. Used by the HUD (PlayerStatus,
## also for the Echo's pulse via setup_custom), the skill choice screen and the
## pause menu. Cooldown states (set_state, cooldown abilities only):
## - recharging: the shape dimmed and desaturated, a dark radial fill over the
##   part still recharging and a thin ring showing the progress;
## - ready: full colour with a glowing edge; the moment it becomes ready a short
##   bright flash ring grows out of it.

enum Shape { RINGS, HOURGLASS, BUBBLES, LURE, EYE, ARC, SHIELD, STAR, CHEVRONS, HEART, LINK, SHARD, REFILL }

@export var background_color: Color = Color(0.04, 0.06, 0.1, 0.9)
@export var border_color: Color = Color(0.35, 0.42, 0.55)
## Border while an active skill is in use (held / running).
@export var in_use_color: Color = Color(1.0, 0.85, 0.45)
@export var cooldown_color: Color = Color(0.0, 0.0, 0.0, 0.7)
@export var rank_color: Color = Color(1.0, 0.85, 0.45)
@export var empty_rank_color: Color = Color(0.3, 0.33, 0.4)
@export var line_width: float = 2.0

@export_group("Cooldown")
## While recharging: how much of the colour is kept (0 = grey) and how bright.
@export_range(0.0, 1.0) var cooling_saturation: float = 0.15
@export_range(0.0, 1.0) var cooling_brightness: float = 0.45
@export var progress_ring_width: float = 2.0
## Ready (cooldown abilities): glowing edge width and its soft halo.
@export var ready_edge_width: float = 2.5
@export_range(0.0, 1.0) var ready_halo_alpha: float = 0.3
## The flash when it becomes ready.
@export var flash_time: float = 0.4
@export var flash_color: Color = Color(1.0, 1.0, 1.0)

var definition: SkillDefinition
## Owned rank (0 = not owned yet, e.g. a card offering rank 1).
var rank: int = 0
## Rank shown highlighted on a card ("this pick gives rank 2").
var preview_rank: int = 0
## 0 = ready, 1 = just used (abilities with a cooldown).
var cooldown_ratio: float = 0.0
var in_use: bool = false
## True for abilities with a cooldown (the ready / recharging looks).
var has_cooldown: bool = false
## Times the ready flash started (tests).
var flashes: int = 0
var _shape: Shape = Shape.RINGS
var _color: Color = Color.WHITE
var _max_rank: int = 1
var _flash_left: float = 0.0
## Set by setup / setup_custom (nothing is drawn before).
var _configured: bool = false


func setup(skill: SkillDefinition, owned_rank: int, icon_size: float) -> void:
	definition = skill
	rank = owned_rank
	_shape = skill.icon_shape
	_color = skill.icon_color
	_max_rank = skill.max_rank
	_configured = true
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


## An icon without a SkillDefinition (the Echo's pulse).
func setup_custom(shape: Shape, color: Color, icon_size: float) -> void:
	definition = null
	_shape = shape
	_color = color
	_max_rank = 1
	_configured = true
	custom_minimum_size = Vector2(icon_size, icon_size)
	queue_redraw()


## ratio: 0 = ready, 1 = just used. Recharging -> ready starts the flash.
func set_state(ratio: float, using: bool) -> void:
	has_cooldown = true
	if cooldown_ratio > 0.0 and ratio <= 0.0:
		flashes += 1
		_flash_left = flash_time
		set_process(true)
	var changed: bool = not is_equal_approx(ratio, cooldown_ratio) or using != in_use or (ratio <= 0.0) != (cooldown_ratio <= 0.0)
	cooldown_ratio = ratio
	in_use = using
	if changed:
		queue_redraw()


func is_cooling() -> bool:
	return has_cooldown and cooldown_ratio > 0.0


func is_flashing() -> bool:
	return _flash_left > 0.0


## The colour the shape is drawn with right now.
func get_shape_color() -> Color:
	if not is_cooling():
		return _color
	var grey: float = _color.get_luminance()
	return Color(grey, grey, grey).lerp(_color, cooling_saturation) * Color(cooling_brightness, cooling_brightness, cooling_brightness, 1.0)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	queue_redraw()
	if _flash_left <= 0.0:
		set_process(false)


func _draw() -> void:
	if not _configured:
		return
	var center: Vector2 = size * 0.5
	# Room for the halo and the flash around the disc.
	var radius: float = minf(size.x, size.y) * 0.5 - 3.0
	draw_circle(center, radius, background_color)
	_draw_shape(_shape, center, radius * 0.6, get_shape_color())
	if is_cooling():
		_draw_sweep(center, radius, cooldown_ratio)
		draw_arc(center, radius, 0.0, TAU, 32, border_color.darkened(0.4), 1.0, true)
		# Progress ring: how much has recharged, clockwise from the top.
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cooldown_ratio), 32, _color, progress_ring_width, true)
	elif has_cooldown:
		draw_arc(center, radius + 1.5, 0.0, TAU, 32, Color(_color, ready_halo_alpha), 4.0, true)
		draw_arc(center, radius, 0.0, TAU, 32, in_use_color if in_use else _color, ready_edge_width, true)
	else:
		draw_arc(center, radius, 0.0, TAU, 32, in_use_color if in_use else border_color, 1.5, true)
	if _flash_left > 0.0:
		var t: float = 1.0 - _flash_left / flash_time
		draw_circle(center, radius, Color(flash_color, 0.35 * (1.0 - t)))
		draw_arc(center, radius + 2.0 * t, 0.0, TAU, 32, Color(flash_color, 1.0 - t), 2.0, true)
	if _max_rank > 1:
		_draw_ranks(center, radius)


## A dark radial fill over the part still recharging (clockwise from the top,
## the whole disc right after use).
func _draw_sweep(center: Vector2, radius: float, ratio: float) -> void:
	var points := PackedVector2Array([center])
	var steps: int = 32
	var start: float = -PI * 0.5 + TAU * (1.0 - ratio)
	for i: int in steps + 1:
		var angle: float = start + TAU * ratio * float(i) / steps
		points.append(center + Vector2.from_angle(angle) * radius)
	draw_colored_polygon(points, cooldown_color)


func _draw_ranks(center: Vector2, radius: float) -> void:
	var shown: int = maxi(rank, preview_rank)
	var spacing: float = radius * 0.4
	for i: int in _max_rank:
		var x: float = (float(i) - (_max_rank - 1) * 0.5) * spacing
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
