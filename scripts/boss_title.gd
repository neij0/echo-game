class_name BossTitle
extends CanvasLayer
## The boss's name on screen when it is revealed: a large name and a short
## line under it, fading in, holding and fading out (AR / EN from UiText,
## laid out right-to-left in Arabic). Works while the game is paused.

@export var name_color: Color = Color(0.85, 1.0, 0.95)
@export var subtitle_color: Color = Color(0.6, 0.75, 0.8)
@export var name_font_size: int = 54
@export var subtitle_font_size: int = 22
## Distance from the top of the screen (pixels).
@export var top: float = 150.0
@export var fade_in_time: float = 0.4
@export var hold_time: float = 2.4
@export var fade_out_time: float = 0.8

var _box: VBoxContainer
var _name: Label
var _subtitle: Label
var _age: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_top = top
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_box)
	_name = _make_label(name_font_size, name_color)
	_subtitle = _make_label(subtitle_font_size, subtitle_color)
	_box.add_child(_name)
	_box.add_child(_subtitle)
	_box.modulate.a = 0.0


## name_key / subtitle_key: UiText keys.
func show_title(name_key: String, subtitle_key: String) -> void:
	Game.apply_direction(_box)
	_name.text = Game.text(name_key)
	_subtitle.text = Game.text(subtitle_key)
	_age = 0.0


func is_showing() -> bool:
	return _age >= 0.0


func _process(delta: float) -> void:
	if _age < 0.0:
		return
	_age += delta
	var alpha: float = 1.0
	if _age < fade_in_time:
		alpha = _age / fade_in_time
	elif _age > fade_in_time + hold_time:
		alpha = 1.0 - (_age - fade_in_time - hold_time) / fade_out_time
	_box.modulate.a = clampf(alpha, 0.0, 1.0)
	if _age >= fade_in_time + hold_time + fade_out_time:
		_age = -1.0
		_box.modulate.a = 0.0


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label
