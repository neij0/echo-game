class_name StoryScreen
extends Control
## The story between parts of the game (Game.story_id): "intro" after New Game
## (Continue starts the first stage), "<world id>_end" after a world's last
## stage (Continue opens the Journey). In the "silhouette + glow" style
## (Game.ui_theme): the menus' night sky, dimmer; short lines of text fade in
## one by one, each rising a little into place and glowing softly as it comes
## (over-bright, it blooms under the GlowEnvironment), then settling to the
## text colour. A glowing wave line and the Continue button (GlowButton)
## follow; drawn prompts at the bottom ("skip" while the lines come, then
## "continue"). The text comes from story/<story id>_<language>.txt (one line
## of story per line; empty lines are skipped). Arabic is laid out
## right-to-left. Pressing confirm while lines are still appearing shows them
## all at once.

@export var text_color: Color = Color(0.82, 0.88, 0.98)
## A line's colour while it fades in (over-bright: a soft bloom).
@export var arriving_color: Color = Color(1.0, 1.25, 1.45)
@export var font_size: int = 28
@export var button_font_size: int = 28
@export var line_spacing: int = 18
## Pixels a line rises while it fades in.
@export var line_rise: float = 10.0
## Width of the text column in pixels (longer lines wrap).
@export var text_width: float = 900.0
## Seconds before the first line appears.
@export var first_line_delay: float = 1.0
## Seconds each line takes to fade in...
@export var line_fade_time: float = 1.5
## ...and seconds between the start of two lines.
@export var line_interval: float = 2.2
## Seconds after the last line before the Continue button appears.
@export var button_delay: float = 1.0
## The sky behind the text (0-1 of the menus' brightness).
@export var sky_brightness: float = 0.6
@export var rule_size: Vector2 = Vector2(220.0, 30.0)
@export var screen_margin: float = 46.0
## Used when no story was asked for (e.g. the scene is run on its own).
@export var fallback_story_id: String = "intro"

## Each line: {label, start (s)}.
var _lines: Array[Dictionary] = []
var _rule: WaveRule
var _button: GlowButton
var _prompt: InputPrompt
var _time: float = 0.0
var _button_start: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Game.ui_theme
	Game.apply_direction(self)
	var sky := NightSky.new()
	sky.modulate = Color(sky_brightness, sky_brightness, sky_brightness)
	add_child(sky)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", line_spacing)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var story: String = Game.story_id if Game.story_id != "" else fallback_story_id
	var lines: PackedStringArray = _read_lines(Game.get_story_path_for(story))
	for i: int in lines.size():
		# Each line rises into place: its box trades bottom room for top room,
		# so the column never moves.
		var box := MarginContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(box)
		var label := Label.new()
		label.text = lines[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = text_width
		label.add_theme_font_size_override("font_size", font_size)
		label.modulate.a = 0.0
		box.add_child(label)
		_lines.append({"label": label, "box": box, "start": first_line_delay + float(i) * line_interval})

	_rule = WaveRule.new()
	_rule.custom_minimum_size = rule_size
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.modulate.a = 0.0
	column.add_child(_rule)
	_button = GlowButton.new()
	_button.text = Game.text("continue")
	_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button.add_theme_font_size_override("font_size", button_font_size)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.modulate.a = 0.0
	# Disabled (and unfocused) until it shows, so an early press only skips.
	_button.disabled = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(Game.after_story)
	column.add_child(_button)
	_button_start = first_line_delay + float(maxi(_lines.size() - 1, 0)) * line_interval + line_fade_time + button_delay

	_prompt = InputPrompt.new()
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	add_child(_prompt)
	_set_prompt("prompt_skip")
	add_child(GlowEnvironment.new())


func _process(delta: float) -> void:
	_time += delta
	for line: Dictionary in _lines:
		var label: Label = line.label
		var t: float = clampf((_time - float(line.start)) / line_fade_time, 0.0, 1.0)
		label.modulate.a = t
		var rise: int = roundi(line_rise * (1.0 - ease(t, 0.4)))
		var box: MarginContainer = line.box
		box.add_theme_constant_override("margin_top", rise)
		box.add_theme_constant_override("margin_bottom", roundi(line_rise) - rise)
		# Bright while it arrives, then it settles.
		var glow: float = clampf(1.0 - (_time - float(line.start) - line_fade_time * 0.5) / (line_fade_time * 1.5), 0.0, 1.0)
		label.add_theme_color_override("font_color", text_color.lerp(arriving_color, glow * t))
	var button_t: float = clampf((_time - _button_start) / line_fade_time, 0.0, 1.0)
	_rule.modulate.a = button_t
	_button.modulate.a = button_t
	if button_t > 0.0 and _button.disabled:
		_enable_button()
	_prompt.position = Vector2((size.x - _prompt.size.x) * 0.5, size.y - screen_margin - _prompt.size.y)


## Any confirm press before the end shows everything at once (the next press
## continues).
func _unhandled_input(event: InputEvent) -> void:
	if not _button.disabled or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ui_accept") or event.is_action("p1_action") or event.is_action("p2_action"):
		_show_all()
		get_viewport().set_input_as_handled()


func _show_all() -> void:
	_time = maxf(_time, _button_start + line_fade_time)
	_enable_button()


func _enable_button() -> void:
	if not _button.disabled:
		return
	_button.disabled = false
	_button.focus_mode = Control.FOCUS_ALL
	_button.focus_quietly()
	_set_prompt("continue")


func _set_prompt(key: String) -> void:
	_prompt.setup([{"actions": [&"ui_accept"], "text": Game.text(key)}], InputPrompt.menu_device, true)


func _read_lines(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not FileAccess.file_exists(path):
		push_warning("StoryScreen: no story file at %s" % path)
		return result
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var clean: String = line.strip_edges()
		if clean != "":
			result.append(clean)
	return result
