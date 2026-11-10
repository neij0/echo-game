class_name BossTitle
extends CanvasLayer
## The boss's name on screen when it is revealed, in the "silhouette + glow"
## style (the UI theme): a large spaced title, a glowing wave line and a short
## line under it, fading in (the name settling from wide letter spacing),
## holding and fading out (AR / EN from UiText, right-to-left in Arabic, no
## letter spacing there: it would break the joined letters). Works while the
## game is paused.

const THEME: Theme = preload("res://assets/ui/echo_theme.tres")

@export var name_color: Color = Color(0.85, 1.1, 1.05)
@export var subtitle_color: Color = Color(0.6, 0.75, 0.85)
@export var rule_size: Vector2 = Vector2(240.0, 26.0)
@export var name_font_size: int = 54
@export var subtitle_font_size: int = 22
## Distance from the top of the screen (pixels).
@export var top: float = 215.0
@export var fade_in_time: float = 0.4
@export var hold_time: float = 2.4
@export var fade_out_time: float = 0.8

var _box: VBoxContainer
var _name: Label
var _subtitle: Label
var _rule: WaveRule
var _age: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_top = top
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.theme = THEME
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_name = _make_label(name_font_size, name_color)
	_name.theme_type_variation = &"SubtitleLatinLabel"
	_box.add_child(_name)
	_rule = WaveRule.new()
	_rule.custom_minimum_size = rule_size
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_rule)
	_subtitle = _make_label(subtitle_font_size, subtitle_color)
	_box.add_child(_subtitle)
	_box.modulate.a = 0.0


## name_key / subtitle_key: UiText keys.
func show_title(name_key: String, subtitle_key: String) -> void:
	# Through the node, not the autoload name: the boss scene is also loaded by
	# the -s tools (check_levels), which run without autoloads.
	var game: Node = get_node_or_null("/root/Game")
	var rtl: bool = game != null and bool(game.call("is_rtl"))
	if game:
		game.call("apply_direction", _box)
	_name.theme_type_variation = &"SubtitleLabel" if rtl else &"SubtitleLatinLabel"
	_name.add_theme_font_size_override("font_size", name_font_size)
	_name.text = String(game.call("text", name_key)) if game else name_key
	_subtitle.text = String(game.call("text", subtitle_key)) if game else subtitle_key
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
