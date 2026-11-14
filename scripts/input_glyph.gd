class_name InputGlyph
extends Control
## One button prompt drawn in code (no textures, "silhouette + glow"): a
## keyboard key cap with its label or an arrow, or a gamepad part (a face
## button with its letter on an Xbox pad or its symbol on a PlayStation pad,
## a D-pad or a stick with the directions that count, a named button).
## spec_for(action, device, style) reads the InputMap, so a rebound key shows
## up by itself. Colours and font: the theme's "GlyphPrompt" type.

enum Device { KEYBOARD, GAMEPAD }
enum Shape { KEY, ARROW_KEY, FACE_BUTTON, DPAD, STICK }
## The PlayStation face buttons' symbols.
enum Symbol { NONE, CROSS, CIRCLE, SQUARE, TRIANGLE }

const THEME_TYPE: StringName = &"GlyphPrompt"
const FACE_LABELS: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
}
const FACE_SYMBOLS: Dictionary = {
	JOY_BUTTON_A: Symbol.CROSS, JOY_BUTTON_B: Symbol.CIRCLE, JOY_BUTTON_X: Symbol.SQUARE, JOY_BUTTON_Y: Symbol.TRIANGLE,
}
const BUTTON_LABELS: Dictionary = {
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
}
const PLAYSTATION_LABELS: Dictionary = {
	JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options", JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
}
const DPAD_DIRECTIONS: Dictionary = {
	JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
	JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
}
const ARROW_KEYS: Dictionary = {
	KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT,
}
## Shorter names for some keys.
const KEY_NAMES: Dictionary = {KEY_ESCAPE: "Esc", KEY_KP_ENTER: "Enter"}

@export var glyph_height: float = 26.0
## Space between a key's label and its edges.
@export var key_padding: float = 7.0
@export var corner_radius: float = 5.0
@export var line_width: float = 1.4

var shape: Shape = Shape.KEY
var label: String = ""
var symbol: Symbol = Symbol.NONE
## Arrow / D-pad arms / stick directions shown.
var directions: Array[Vector2] = []


## Shows one spec (from spec_of / specs_for).
func setup(spec: Dictionary) -> void:
	shape = spec.get("shape", Shape.KEY)
	label = spec.get("label", "")
	symbol = spec.get("symbol", Symbol.NONE)
	directions.assign(spec.get("directions", []))
	custom_minimum_size = Vector2(_glyph_width(), glyph_height)
	queue_redraw()


## The glyph for action on that device: the first key (keyboard), or the first
## gamepad button, else the first stick axis (gamepad; style = Xbox letters or
## PlayStation symbols). Empty if none is bound.
static func spec_for(action: StringName, device: Device, style: int = 0, newer_playstation: bool = true) -> Dictionary:
	if not InputMap.has_action(action):
		return {}
	var fallback: Dictionary = {}
	for event: InputEvent in InputMap.action_get_events(action):
		if device == Device.KEYBOARD and event is InputEventKey:
			return spec_of(event)
		if device == Device.GAMEPAD and event is InputEventJoypadButton:
			return spec_of(event, style, newer_playstation)
		if device == Device.GAMEPAD and event is InputEventJoypadMotion and fallback.is_empty():
			fallback = spec_of(event, style, newer_playstation)
	return fallback


## {shape, label, symbol, directions} for one input event (style:
## InputDevices.PadStyle; a PS5 pad calls Back "Create").
static func spec_of(event: InputEvent, style: int = 0, newer_playstation: bool = true) -> Dictionary:
	var playstation: bool = style == InputDevices.PadStyle.PLAYSTATION
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if ARROW_KEYS.has(code):
			return {"shape": Shape.ARROW_KEY, "directions": [ARROW_KEYS[code]]}
		if KEY_NAMES.has(code):
			return {"shape": Shape.KEY, "label": KEY_NAMES[code]}
		var shown: Key = code
		# The key's name in the user's layout (the headless server cannot tell).
		if key.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(code)
		return {"shape": Shape.KEY, "label": OS.get_keycode_string(shown)}
	if event is InputEventJoypadButton:
		var index: JoyButton = (event as InputEventJoypadButton).button_index
		if FACE_LABELS.has(index):
			if playstation:
				return {"shape": Shape.FACE_BUTTON, "label": "", "symbol": FACE_SYMBOLS[index]}
			return {"shape": Shape.FACE_BUTTON, "label": FACE_LABELS[index]}
		if DPAD_DIRECTIONS.has(index):
			return {"shape": Shape.DPAD, "directions": [DPAD_DIRECTIONS[index]]}
		if playstation:
			if index == JOY_BUTTON_BACK and newer_playstation:
				return {"shape": Shape.KEY, "label": "Create"}
			return {"shape": Shape.KEY, "label": PLAYSTATION_LABELS.get(index, "?")}
		return {"shape": Shape.KEY, "label": BUTTON_LABELS.get(index, "?")}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var sign_value: float = signf(motion.axis_value)
		match motion.axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X:
				return {"shape": Shape.STICK, "label": "L" if motion.axis == JOY_AXIS_LEFT_X else "R", "directions": [Vector2(sign_value, 0.0)]}
			JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_Y:
				return {"shape": Shape.STICK, "label": "L" if motion.axis == JOY_AXIS_LEFT_Y else "R", "directions": [Vector2(0.0, sign_value)]}
			JOY_AXIS_TRIGGER_LEFT:
				return {"shape": Shape.KEY, "label": "L2" if playstation else "LT"}
			JOY_AXIS_TRIGGER_RIGHT:
				return {"shape": Shape.KEY, "label": "R2" if playstation else "RT"}
	return {}


func _glyph_width() -> float:
	if shape == Shape.KEY:
		var font: Font = get_theme_font("font", THEME_TYPE)
		var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size", THEME_TYPE)).x
		return maxf(glyph_height, text_width + key_padding * 2.0)
	return glyph_height


func _draw() -> void:
	var line: Color = get_theme_color("glyph_color", THEME_TYPE)
	var fill: Color = get_theme_color("glyph_fill", THEME_TYPE)
	var rect := Rect2(Vector2.ZERO, Vector2(_glyph_width(), glyph_height))
	var center: Vector2 = rect.get_center()
	var radius: float = glyph_height * 0.5 - line_width
	match shape:
		Shape.KEY, Shape.ARROW_KEY:
			_draw_key_cap(rect, line, fill)
			if shape == Shape.KEY:
				_draw_label(center, label)
			else:
				for direction: Vector2 in directions:
					_draw_arrow(center, direction, glyph_height * 0.2, get_theme_color("glyph_text", THEME_TYPE))
		Shape.FACE_BUTTON:
			draw_circle(center, radius, fill)
			draw_arc(center, radius, 0.0, TAU, 32, line, line_width, true)
			if symbol == Symbol.NONE:
				_draw_label(center, label)
			else:
				_draw_symbol(center, radius * 0.48, get_theme_color("glyph_text", THEME_TYPE))
		Shape.DPAD:
			_draw_dpad(center, radius, line, fill)
		Shape.STICK:
			draw_circle(center, radius, fill)
			draw_arc(center, radius, 0.0, TAU, 32, line, line_width, true)
			draw_circle(center, radius * 0.42, Color(line, 0.55))
			for direction: Vector2 in directions:
				_draw_arrow(center + direction * radius * 0.7, direction, radius * 0.22, get_theme_color("glyph_text", THEME_TYPE))


func _draw_key_cap(rect: Rect2, line: Color, fill: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(int(ceilf(line_width)))
	style.border_width_bottom = int(ceilf(line_width)) + 1
	style.set_corner_radius_all(int(corner_radius))
	style.anti_aliasing = true
	draw_style_box(style, rect)


func _draw_label(center: Vector2, text: String) -> void:
	var font: Font = get_theme_font("font", THEME_TYPE)
	var font_size: int = get_theme_font_size("font_size", THEME_TYPE)
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline: float = center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - text_size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		get_theme_color("glyph_text", THEME_TYPE))


## A PlayStation face symbol (Cross, Circle, Square, Triangle) as thin lines.
func _draw_symbol(center: Vector2, half: float, color: Color) -> void:
	var width: float = line_width * 1.3
	match symbol:
		Symbol.CROSS:
			draw_line(center + Vector2(-half, -half), center + Vector2(half, half), color, width, true)
			draw_line(center + Vector2(-half, half), center + Vector2(half, -half), color, width, true)
		Symbol.CIRCLE:
			draw_arc(center, half, 0.0, TAU, 24, color, width, true)
		Symbol.SQUARE:
			var corners := PackedVector2Array([center + Vector2(-half, -half), center + Vector2(half, -half),
				center + Vector2(half, half), center + Vector2(-half, half), center + Vector2(-half, -half)])
			draw_polyline(corners, color, width, true)
		Symbol.TRIANGLE:
			var top: Vector2 = center + Vector2(0.0, -half * 1.05)
			var points := PackedVector2Array([top, center + Vector2(half * 1.1, half * 0.8), center + Vector2(-half * 1.1, half * 0.8), top])
			draw_polyline(points, color, width, true)


## A small filled triangle pointing along direction.
func _draw_arrow(center: Vector2, direction: Vector2, half: float, color: Color) -> void:
	var side: Vector2 = direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([center + direction * half, center - direction * half * 0.7 + side * half,
		center - direction * half * 0.7 - side * half]), color)


## A plus-shaped pad; the arms that count are filled.
func _draw_dpad(center: Vector2, radius: float, line: Color, fill: Color) -> void:
	var arm: float = radius * 0.36
	var outline := PackedVector2Array()
	for corner: Vector2 in [Vector2(-arm, -radius), Vector2(arm, -radius), Vector2(arm, -arm), Vector2(radius, -arm),
			Vector2(radius, arm), Vector2(arm, arm), Vector2(arm, radius), Vector2(-arm, radius), Vector2(-arm, arm),
			Vector2(-radius, arm), Vector2(-radius, -arm), Vector2(-arm, -arm)]:
		outline.append(center + corner)
	draw_colored_polygon(outline, fill)
	for direction: Vector2 in directions:
		var side: Vector2 = direction.orthogonal() * arm * 0.7
		var near: Vector2 = center + direction * arm
		var far: Vector2 = center + direction * (radius - line_width)
		draw_colored_polygon(PackedVector2Array([near + side, far + side, far - side, near - side]), Color(line, 0.85))
	outline.append(outline[0])
	draw_polyline(outline, line, line_width, true)
