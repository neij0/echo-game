class_name SkillCard
extends PanelContainer
## One skill on the choice screen (SkillChoiceScreen): its icon, name, a kind
## line (New / Rank, Active / Passive, Shared) and a text (the description, or
## the co-op tip in the summary). States, from the theme's "Card" type tinted
## with the side's colour (Echo cyan, Guardian gold):
## - normal: dim navy, a faint edge;
## - focused (the player's cursor): a glowing edge in the side's colour, a
##   sonar ripple out of the icon when the cursor arrives, a wavy glowing line
##   under the name;
## - picked: warm gold with a check mark.
## Mirrors in Arabic (the icon on the right).

@export var ripple_time: float = 0.8
@export var ripple_reach: float = 70.0
@export var underline_grow_time: float = 0.2
@export var wave_length: float = 24.0
@export var wave_amplitude: float = 1.5
@export var wave_speed: float = 1.1
@export var underline_width: float = 1.4
@export var check_color: Color = Color(1.0, 0.85, 0.45)
@export var check_radius: float = 10.0

var definition: SkillDefinition
var is_focused: bool = false
var is_picked: bool = false
var _accent: Color = Color.WHITE
var _icon: SkillIcon
var _title: Label
var _fx: Control
var _ripple_age: float = INF
var _focus_amount: float = 0.0
var _time: float = 0.0


func _init() -> void:
	theme_type_variation = &"Card"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Builds the card. owned: the rank the player has now (the icon previews the
## next one); body: the description or the tip.
func setup(skill: SkillDefinition, owned: int, title_text: String, kind_text: String, body_text: String, accent: Color,
		width: float, icon_size: float, name_font_size: int, text_font_size: int, spacing: int) -> void:
	definition = skill
	_accent = accent
	custom_minimum_size.x = width
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", spacing + 4)
	add_child(row)
	_icon = SkillIcon.new()
	_icon.setup(skill, owned, icon_size)
	_icon.preview_rank = owned + 1
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	_title = _label(texts, name_font_size)
	_title.text = title_text
	var kind := _label(texts, text_font_size - 2)
	kind.add_theme_color_override("font_color", skill.icon_color)
	kind.text = kind_text
	kind.visible = kind_text != ""
	var body := _label(texts, text_font_size)
	body.theme_type_variation = &"DimLabel"
	body.add_theme_font_size_override("font_size", text_font_size)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = width - icon_size - spacing * 4
	body.text = body_text
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	set_state(false, false)
	set_process(false)


func set_state(focused: bool, picked: bool) -> void:
	if focused and not is_focused:
		_ripple_age = 0.0
	is_focused = focused
	is_picked = picked
	var style: StyleBox
	if picked:
		style = get_theme_stylebox("picked", &"Card").duplicate()
		if focused and style is StyleBoxFlat:
			(style as StyleBoxFlat).border_color = Color(_accent, 1.0)
			(style as StyleBoxFlat).set_border_width_all(2)
	elif focused:
		style = get_theme_stylebox("focus", &"Card").duplicate()
		if style is StyleBoxFlat:
			var flat := style as StyleBoxFlat
			flat.border_color = Color(_accent, flat.border_color.a)
			flat.shadow_color = Color(_accent, flat.shadow_color.a)
	else:
		style = get_theme_stylebox("panel", &"Card")
	add_theme_stylebox_override("panel", style)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_ripple_age += delta
	_focus_amount = move_toward(_focus_amount, 1.0 if is_focused else 0.0, delta / underline_grow_time)
	_fx.queue_redraw()
	if not is_focused and _focus_amount <= 0.0 and _ripple_age > ripple_time * 2.0:
		set_process(false)


func _draw_fx() -> void:
	# The overlay sits inside the card's margins; work in card coordinates.
	var shift: Vector2 = -_fx.position
	var icon_center: Vector2 = _icon.get_global_rect().get_center() - global_position + shift
	if _ripple_age < ripple_time * 2.0:
		GlowFx.ripple(_fx, icon_center, _ripple_age, ripple_time, ripple_reach, Color(_accent, 0.8))
	if _focus_amount > 0.0 and _title.text != "":
		var font: Font = _title.get_theme_font("font")
		var font_size: int = _title.get_theme_font_size("font_size")
		var width: float = font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var title_rect: Rect2 = _title.get_global_rect()
		var rtl: bool = is_layout_rtl()
		var start_x: float = (title_rect.end.x if rtl else title_rect.position.x) - global_position.x + shift.x
		var line_y: float = title_rect.get_center().y - global_position.y + shift.y + font.get_ascent(font_size) * 0.55
		var length: float = width * ease(_focus_amount, 0.5) * (-1.0 if rtl else 1.0)
		var points: PackedVector2Array = GlowFx.wave_points(Vector2(start_x, line_y), Vector2(start_x + length, line_y),
			_time * wave_speed, wave_length, wave_amplitude)
		GlowFx.glow_line(_fx, points, Color(_accent, _focus_amount), underline_width)
	if is_picked:
		var corner := Vector2(size.x - check_radius - 10.0 if not is_layout_rtl() else check_radius + 10.0, check_radius + 10.0) + shift
		GlowFx.dot(_fx, corner, check_radius, Color(check_color, 0.25))
		_fx.draw_arc(corner, check_radius, 0.0, TAU, 32, check_color, 1.5, true)
		_fx.draw_polyline(PackedVector2Array([corner + Vector2(-4.5, 0.0), corner + Vector2(-1.0, 3.5), corner + Vector2(5.0, -3.5)]),
			check_color, 2.0, true)


func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
