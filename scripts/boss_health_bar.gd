class_name BossHealthBar
extends CanvasLayer
## The boss's name and health at the top of the screen while it fights (AR /
## EN from UiText, right-to-left in Arabic), in the "silhouette + glow" style
## (the UI theme): the name in the spaced title font, a thin glowing bar (a
## soft halo under a bright core, a brighter tip) over a faint track, a small
## diamond at every phase threshold (lit while that phase is still ahead), a
## pale "recent damage" trail that catches up, and a fade in / out. Driven by
## its Boss (show_bar, set_ratio, hide_bar).
## It never covers the HUD (Hud.get_occupied_rects, "hud" group): centred at
## the top when that is free, else just below the HUD parts in the way (down
## to max_top), else beside them (at least min_width wide), else below them.

const THEME: Theme = preload("res://assets/ui/echo_theme.tres")

@export var bar_size: Vector2 = Vector2(520.0, 12.0)
## The fill's core thickness (the halo is wider).
@export var line_thickness: float = 4.0
## Distance from the top of the screen (pixels).
@export var top: float = 26.0
@export var name_font_size: int = 20
@export var name_color: Color = Color(0.85, 1.05, 1.0)
@export var back_color: Color = Color(0.45, 0.65, 0.75, 0.18)
@export var fill_color: Color = Color(0.35, 1.0, 0.88)
@export var trail_color: Color = Color(1.0, 0.92, 0.75, 0.55)
@export var tick_color: Color = Color(0.9, 0.95, 1.0, 0.8)
## A threshold already passed (its phase has begun).
@export var tick_passed_color: Color = Color(0.5, 0.6, 0.7, 0.35)
## The trail waits this long after a hit, then catches up at trail_speed (share / s).
@export var trail_delay: float = 0.45
@export var trail_speed: float = 0.6
@export var fade_time: float = 0.5
## Free space kept round the HUD parts (pixels).
@export var hud_margin: float = 10.0
## Lowest top it moves down to before it goes beside the HUD instead.
@export var max_top: float = 120.0
@export var min_width: float = 260.0
## Non-zero: lay out for this screen size instead of the window (tests).
@export var screen_size_override: Vector2 = Vector2.ZERO

var ratio: float = 1.0
var _trail: float = 1.0
var _trail_wait: float = 0.0
var _thresholds: PackedFloat32Array = PackedFloat32Array()
var _shown: bool = false
var _alpha: float = 0.0
var _box: VBoxContainer
var _label: Label
var _bar: Control
var _width: float = 0.0


func _ready() -> void:
	layer = 4
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.theme = THEME
	add_child(_box)
	_label = Label.new()
	_label.theme_type_variation = &"SubtitleLatinLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", name_font_size)
	_label.add_theme_color_override("font_color", name_color)
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_box.add_child(_label)
	_bar = Control.new()
	_bar.custom_minimum_size = bar_size
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_box.add_child(_bar)
	_box.modulate.a = 0.0
	_width = bar_size.x


func show_bar(name_key: String, start_ratio: float, thresholds: PackedFloat32Array) -> void:
	# Through the node, not the autoload name (-s tools load the boss scene).
	var game: Node = get_node_or_null("/root/Game")
	_label.text = String(game.call("text", name_key)) if game and name_key != "" else name_key
	if game:
		game.call("apply_direction", _box)
	# No letter spacing in Arabic (it would break the joined letters).
	var rtl: bool = game != null and bool(game.call("is_rtl"))
	_label.theme_type_variation = &"SubtitleLabel" if rtl else &"SubtitleLatinLabel"
	_label.add_theme_font_size_override("font_size", name_font_size)
	_label.add_theme_color_override("font_color", name_color)
	_thresholds = thresholds
	ratio = start_ratio
	_trail = start_ratio
	_shown = true


func set_ratio(new_ratio: float) -> void:
	ratio = clampf(new_ratio, 0.0, 1.0)
	_trail_wait = trail_delay


func hide_bar() -> void:
	_shown = false


func is_shown() -> bool:
	return _shown


func _process(delta: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if _shown else 0.0, delta / maxf(fade_time, 0.01))
	_box.modulate.a = _alpha
	if _trail_wait > 0.0:
		_trail_wait -= delta
	else:
		_trail = move_toward(_trail, ratio, trail_speed * delta)
	_trail = maxf(_trail, ratio)
	if _alpha > 0.0:
		_place()
		_bar.queue_redraw()


## The screen rect of the name + bar right now.
func get_screen_rect() -> Rect2:
	return Rect2(_box.global_position, _box.size)


func _place() -> void:
	var screen: Vector2 = screen_size_override if screen_size_override != Vector2.ZERO else get_viewport().get_visible_rect().size
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var rects: Array[Rect2] = []
	if hud:
		rects.assign(hud.call("get_occupied_rects"))
	var height: float = _label.get_minimum_size().y + _box.get_theme_constant("separation") + bar_size.y + 4.0
	var block: Rect2 = _fit(screen, rects, height)
	_width = block.size.x - 4.0
	_bar.custom_minimum_size = Vector2(_width, bar_size.y)
	_box.position = block.position
	_box.size = Vector2(block.size.x, 0.0)


func _fit(screen: Vector2, rects: Array[Rect2], height: float) -> Rect2:
	var width: float = bar_size.x + 4.0
	# 1. Centred at the top.
	var centred := Rect2((screen.x - width) * 0.5, top, width, height)
	var blocking: Array[Rect2] = _overlapping(centred, rects)
	if blocking.is_empty():
		return centred
	# 2. Centred, just below what is in the way.
	var below: float = top
	for rect: Rect2 in blocking:
		below = maxf(below, rect.end.y + hud_margin)
	var lowered := Rect2(centred.position.x, below, width, height)
	if below <= max_top and _overlapping(lowered, rects).is_empty():
		return lowered
	# 3. At the top, in the free space beside the HUD.
	var band := Rect2(0.0, top, screen.x, height)
	var left: float = hud_margin
	var right: float = screen.x - hud_margin
	for rect: Rect2 in _overlapping(band, rects):
		if rect.get_center().x < screen.x * 0.5:
			left = maxf(left, rect.end.x + hud_margin)
		else:
			right = minf(right, rect.position.x - hud_margin)
	var free: float = right - left
	if free >= min_width:
		var side_width: float = minf(width, free)
		return Rect2(left + (free - side_width) * 0.5, top, side_width, height)
	# 4. Below everything at the top.
	var lowest: float = top
	for rect: Rect2 in rects:
		if rect.position.y < screen.y * 0.5:
			lowest = maxf(lowest, rect.end.y + hud_margin)
	return Rect2(centred.position.x, lowest, width, height)


static func _overlapping(area: Rect2, rects: Array[Rect2]) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect: Rect2 in rects:
		if rect.intersects(area):
			result.append(rect)
	return result


func _draw_bar() -> void:
	var y: float = bar_size.y * 0.5
	# Right-to-left in Arabic: the bar empties towards the start of the line.
	var rtl: bool = _box.layout_direction == Control.LAYOUT_DIRECTION_RTL
	_bar.draw_line(Vector2(0.0, y), Vector2(_width, y), back_color, line_thickness)
	var trail: Rect2 = _part(_trail, rtl)
	if trail.size.x > 0.5:
		_bar.draw_line(Vector2(trail.position.x, y), Vector2(trail.end.x, y), trail_color, line_thickness)
	var fill: Rect2 = _part(ratio, rtl)
	if fill.size.x > 0.5:
		var from := Vector2(fill.position.x, y)
		var to := Vector2(fill.end.x, y)
		_bar.draw_line(from, to, Color(fill_color, 0.2), line_thickness * 3.2)
		_bar.draw_line(from, to, fill_color, line_thickness)
		_bar.draw_circle(from if rtl else to, line_thickness * 0.9, fill_color.lightened(0.4))
	for threshold: float in _thresholds:
		var x: float = _width * (1.0 - threshold if rtl else threshold)
		var half := Vector2(3.5, 5.5)
		var diamond := PackedVector2Array([Vector2(x, y - half.y), Vector2(x + half.x, y), Vector2(x, y + half.y), Vector2(x - half.x, y)])
		_bar.draw_colored_polygon(diamond, tick_color if ratio > threshold else tick_passed_color)


func _part(share: float, rtl: bool) -> Rect2:
	var width: float = _width * share
	return Rect2(Vector2(_width - width if rtl else 0.0, 0.0), Vector2(width, bar_size.y))
