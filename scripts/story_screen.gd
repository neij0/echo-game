class_name StoryScreen
extends Control
## Shown after a world's last stage: a black screen where short lines of text
## fade in one by one, then a Continue button to the World Map. The text comes
## from story/<world id>_end_<language>.txt (one line of story per line; empty
## lines are skipped). Arabic is laid out right-to-left. Pressing Continue
## while lines are still appearing shows them all at once.

@export var background_color: Color = Color(0.0, 0.0, 0.0)
@export var text_color: Color = Color(0.85, 0.9, 1.0)
@export var font_size: int = 28
@export var button_font_size: int = 24
@export var button_width: float = 220.0
@export var line_spacing: int = 18
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
## Used when no world was just finished (e.g. the scene is run on its own).
@export var fallback_world_id: String = "ocean"

var _lines: Array[Label] = []
var _button: Button
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.apply_direction(self)
	var background := ColorRect.new()
	background.color = background_color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", line_spacing)
	center.add_child(column)

	var world_id: String = Game.finished_world_id if Game.finished_world_id != "" else fallback_world_id
	for line: String in _read_lines(Game.get_story_path(world_id)):
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = text_width
		label.text_direction = Control.TEXT_DIRECTION_RTL if Game.is_rtl() else Control.TEXT_DIRECTION_LTR
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", text_color)
		label.modulate.a = 0.0
		column.add_child(label)
		_lines.append(label)

	_button = Button.new()
	_button.text = Game.text("continue")
	_button.add_theme_font_size_override("font_size", button_font_size)
	_button.custom_minimum_size.x = button_width
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.modulate.a = 0.0
	# Disabled (and unfocused) until it shows, so an early press only skips.
	_button.disabled = true
	_button.pressed.connect(Game.go_to_world_map)
	column.add_child(_button)

	_tween = create_tween().set_parallel(true)
	for i: int in _lines.size():
		var start: float = first_line_delay + i * line_interval
		_tween.tween_property(_lines[i], "modulate:a", 1.0, line_fade_time).set_delay(start)
	var button_start: float = first_line_delay + maxi(_lines.size() - 1, 0) * line_interval + line_fade_time + button_delay
	_tween.tween_property(_button, "modulate:a", 1.0, line_fade_time).set_delay(button_start)
	_tween.chain().tween_callback(_enable_button)


## Any confirm press before the end shows everything at once (the next press
## continues).
func _unhandled_input(event: InputEvent) -> void:
	if not _button.disabled or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ui_accept") or event.is_action("p1_action") or event.is_action("p2_action"):
		_show_all()
		get_viewport().set_input_as_handled()


func _show_all() -> void:
	if _tween:
		_tween.kill()
	for label: Label in _lines:
		label.modulate.a = 1.0
	_button.modulate.a = 1.0
	_enable_button()


func _enable_button() -> void:
	_button.disabled = false
	_button.grab_focus()


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
