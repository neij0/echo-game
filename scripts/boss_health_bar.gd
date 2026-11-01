class_name BossHealthBar
extends CanvasLayer
## The boss's name and health at the top of the screen while it fights (AR /
## EN from UiText, right-to-left in Arabic): a thin bar with a tick at every
## phase threshold, a pale "recent damage" trail that catches up, and a fade
## in / out. Driven by its Boss (show_bar, set_ratio, hide_bar).

@export var bar_size: Vector2 = Vector2(520.0, 10.0)
## Distance from the top of the screen (pixels).
@export var top: float = 26.0
@export var name_font_size: int = 22
@export var name_color: Color = Color(0.85, 1.0, 0.95)
@export var back_color: Color = Color(0.02, 0.04, 0.06, 0.75)
@export var fill_color: Color = Color(0.3, 0.95, 0.85)
@export var trail_color: Color = Color(1.0, 0.95, 0.8, 0.8)
@export var tick_color: Color = Color(0.9, 0.95, 1.0, 0.7)
@export var frame_color: Color = Color(0.5, 0.8, 0.8, 0.5)
## The trail waits this long after a hit, then catches up at trail_speed (share / s).
@export var trail_delay: float = 0.45
@export var trail_speed: float = 0.6
@export var fade_time: float = 0.5

var ratio: float = 1.0
var _trail: float = 1.0
var _trail_wait: float = 0.0
var _thresholds: PackedFloat32Array = PackedFloat32Array()
var _shown: bool = false
var _alpha: float = 0.0
var _box: VBoxContainer
var _label: Label
var _bar: Control


func _ready() -> void:
	layer = 4
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_top = top
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_label = Label.new()
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


func show_bar(name_key: String, start_ratio: float, thresholds: PackedFloat32Array) -> void:
	# Through the node, not the autoload name (-s tools load the boss scene).
	var game: Node = get_node_or_null("/root/Game")
	_label.text = String(game.call("text", name_key)) if game and name_key != "" else name_key
	if game:
		game.call("apply_direction", _box)
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
		_bar.queue_redraw()


func _draw_bar() -> void:
	var rect := Rect2(Vector2.ZERO, bar_size)
	_bar.draw_rect(rect.grow(2.0), back_color)
	# Right-to-left in Arabic: the bar empties towards the start of the line.
	var rtl: bool = _box.layout_direction == Control.LAYOUT_DIRECTION_RTL
	_bar.draw_rect(_part(_trail, rtl), trail_color)
	_bar.draw_rect(_part(ratio, rtl), fill_color)
	for threshold: float in _thresholds:
		var x: float = bar_size.x * (1.0 - threshold if rtl else threshold)
		_bar.draw_line(Vector2(x, -3.0), Vector2(x, bar_size.y + 3.0), tick_color, 2.0)
	_bar.draw_rect(rect.grow(2.0), frame_color, false, 1.0)


func _part(share: float, rtl: bool) -> Rect2:
	var width: float = bar_size.x * share
	return Rect2(Vector2(bar_size.x - width if rtl else 0.0, 0.0), Vector2(width, bar_size.y))
