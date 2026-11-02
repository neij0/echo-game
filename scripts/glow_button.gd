class_name GlowButton
extends Button

## Emitted on focus with help_text (empty = nothing to explain).
signal help_shown(text: String)
## A menu button in the "silhouette + glow" style (assets/ui/echo_theme.tres):
## glowing text, no box. Keyboard, gamepad and mouse share one focus (hovering
## focuses it; the theme's hover colour is the normal one, so a button under a
## resting mouse never looks focused), and only the focused button is lit: a glowing dot before the text, a sonar ripple
## out of the dot, a wavy glowing underline that grows from the dot, the
## brighter focus text colour and a soft ping (UiAudio "ui_focus"). Pressing it
## flashes it brighter (a second ripple, "ui_press"). Mirrors in Arabic (the dot
## sits before the text on the right). Colours: the theme's "GlowButton" type.

@export_group("Focus")
## Seconds one ripple ring takes to grow and fade.
@export var ripple_time: float = 0.7
## How far the ripple grows (pixels).
@export var ripple_reach: float = 58.0
## Seconds the underline takes to grow / shrink.
@export var underline_grow_time: float = 0.22
@export var underline_width: float = 1.6
@export var wave_length: float = 26.0
@export var wave_amplitude: float = 1.8
## Cycles per second the wave travels along the underline.
@export var wave_speed: float = 1.2
@export var dot_radius: float = 3.2

@export_group("Press")
@export var flash_time: float = 0.28
## Brightness at the peak of the flash (self_modulate).
@export var flash_energy: float = 1.9

## Shown in the screen's help line while this button has the focus (help_shown).
@export_multiline var help_text: String = ""

@export_group("Sound")
@export var focus_sound: StringName = &"ui_focus"
@export var press_sound: StringName = &"ui_press"

## 0-1: how far the underline has grown (follows the focus).
var focus_amount: float = 0.0
## Losing the focus clears the underline and dot at once (never two lit buttons).
var _ripple_age: float = INF
var _flash: float = 0.0
var _time: float = 0.0
var _quiet: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_wake)
	mouse_entered.connect(_on_mouse_entered)
	pressed.connect(_on_pressed)
	set_process(false)


## Takes the focus without the ping (a screen opening on this button).
func focus_quietly() -> void:
	_quiet = true
	grab_focus()
	_quiet = false


func is_flashing() -> bool:
	return _flash > 0.0


func _on_mouse_entered() -> void:
	if not disabled and focus_mode != Control.FOCUS_NONE and is_visible_in_tree() and not has_focus():
		grab_focus()


func _on_focus_entered() -> void:
	_ripple_age = 0.0
	help_shown.emit(help_text)
	if not _quiet:
		UiAudio.play_in(get_tree(), focus_sound)
	_wake()


func _on_pressed() -> void:
	_flash = 1.0
	_ripple_age = 0.0
	UiAudio.play_in(get_tree(), press_sound)
	_wake()


func _wake() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_ripple_age += delta
	focus_amount = move_toward(focus_amount, 1.0, delta / underline_grow_time) if has_focus() else 0.0
	_flash = maxf(_flash - delta / flash_time, 0.0)
	var energy: float = lerpf(1.0, flash_energy, _flash)
	self_modulate = Color(energy, energy, energy)
	queue_redraw()
	if focus_amount <= 0.0 and _flash <= 0.0 and _ripple_age > ripple_time * 2.0:
		set_process(false)


func _draw() -> void:
	if text == "":
		return
	var span: Vector2 = get_text_span()
	var rtl: bool = is_layout_rtl()
	var start_x: float = span.y if rtl else span.x
	var direction: float = -1.0 if rtl else 1.0
	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")
	var middle_y: float = size.y * 0.5
	var origin := Vector2(start_x - direction * float(_constant("dot_gap", 18)), middle_y)
	var glow: Color = _color("glow_color", Color(0.5, 1.15, 1.35))
	if _ripple_age < ripple_time * 2.0:
		GlowFx.ripple(self, origin, _ripple_age, ripple_time, ripple_reach, _color("ripple_color", Color(0.45, 0.95, 1.0, 0.75)))
	if focus_amount <= 0.0:
		return
	GlowFx.dot(self, origin, dot_radius * focus_amount, glow)
	var line_y: float = middle_y + font.get_ascent(font_size) * 0.5 + float(_constant("underline_gap", 2))
	var length: float = (span.y - span.x) * ease(focus_amount, 0.5)
	var from_point := Vector2(start_x, line_y)
	var points: PackedVector2Array = GlowFx.wave_points(from_point, from_point + Vector2(direction * length, 0.0),
		_time * wave_speed, wave_length, wave_amplitude)
	GlowFx.glow_line(self, points, Color(glow, focus_amount), underline_width)


## Where the text is drawn: x from / to in local pixels (follows the
## alignment, mirrored in a right-to-left layout).
func get_text_span() -> Vector2:
	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var style: StyleBox = get_theme_stylebox("normal")
	var left: float = style.get_margin(SIDE_LEFT) if style else 0.0
	var right: float = style.get_margin(SIDE_RIGHT) if style else 0.0
	var align: HorizontalAlignment = alignment
	if is_layout_rtl() and align != HORIZONTAL_ALIGNMENT_CENTER:
		align = HORIZONTAL_ALIGNMENT_RIGHT if align == HORIZONTAL_ALIGNMENT_LEFT else HORIZONTAL_ALIGNMENT_LEFT
	var x: float
	match align:
		HORIZONTAL_ALIGNMENT_LEFT:
			x = left
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = size.x - right - width
		_:
			x = left + (size.x - left - right - width) * 0.5
	return Vector2(x, x + width)


func _color(item: StringName, fallback: Color) -> Color:
	return get_theme_color(item, &"GlowButton") if has_theme_color(item, &"GlowButton") else fallback


func _constant(item: StringName, fallback: int) -> int:
	return get_theme_constant(item, &"GlowButton") if has_theme_constant(item, &"GlowButton") else fallback
