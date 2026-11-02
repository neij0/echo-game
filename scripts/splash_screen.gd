class_name SplashScreen
extends Control
## The developer's logo before the title (the first scene of the game): a sonar
## mark (a glowing point and three arcs going out of it) and the studio name (a
## placeholder for now: studio_name) fade in and out on black. Any press after
## skip_delay skips it. Then the title screen.

@export var studio_name: String = "STUDIO NAME"
@export var mark_color: Color = Color(0.45, 0.95, 1.0)
@export var name_color: Color = Color(0.75, 0.82, 0.92)
@export var mark_energy: float = 2.2
@export var fade_in_time: float = 0.9
@export var hold_time: float = 1.6
@export var fade_out_time: float = 0.8
@export var skip_delay: float = 0.3

var _mark: Control
var _name: Label
var _time: float = 0.0
var _done: bool = false
var _alpha: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Game.ui_theme
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	add_child(GlowEnvironment.new())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	_mark = Control.new()
	_mark.custom_minimum_size = Vector2(120.0, 90.0)
	_mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mark.draw.connect(_draw_mark)
	column.add_child(_mark)
	_name = Label.new()
	_name.theme_type_variation = &"SubtitleLatinLabel"
	_name.add_theme_color_override("font_color", name_color)
	_name.add_theme_font_size_override("font_size", 26)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text = studio_name
	column.add_child(_name)
	_apply_alpha()


func _process(delta: float) -> void:
	_time += delta
	if _time < fade_in_time:
		_alpha = _time / fade_in_time
	elif _time < fade_in_time + hold_time:
		_alpha = 1.0
	else:
		_alpha = 1.0 - (_time - fade_in_time - hold_time) / fade_out_time
		if _alpha <= 0.0:
			_finish()
	_apply_alpha()
	_mark.queue_redraw()


func _input(event: InputEvent) -> void:
	if _time < skip_delay:
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	Game.go_to_title()


func _apply_alpha() -> void:
	_name.modulate.a = clampf(_alpha, 0.0, 1.0)


func _draw_mark() -> void:
	var a: float = clampf(_alpha, 0.0, 1.0)
	var origin := Vector2(_mark.size.x * 0.3, _mark.size.y * 0.5)
	var hdr := Color(mark_color.r * mark_energy, mark_color.g * mark_energy, mark_color.b * mark_energy, a)
	GlowFx.dot(_mark, origin, 4.0, hdr)
	for k: int in 3:
		var radius: float = 16.0 + 14.0 * float(k)
		var wave: float = 0.6 + 0.4 * sin(_time * 2.0 - float(k) * 0.8)
		_mark.draw_arc(origin, radius, -0.7, 0.7, 20, Color(hdr, a * wave * (1.0 - 0.22 * float(k))), 2.2, true)
