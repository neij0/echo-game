class_name EndScreen
extends CanvasLayer
## The end-of-run screens: a short death screen with the cause (restarts on its
## own after death_restart_delay), and the summary after activating the ancient
## light. Works while the game is paused. Builds its UI in code (grey-box).

signal restart_requested

## Seconds the death screen stays before the run restarts from the top.
@export var death_restart_delay: float = 3.0
@export var backdrop_color: Color = Color(0.0, 0.0, 0.0, 0.75)
@export var death_title_color: Color = Color(1.0, 0.3, 0.25)
@export var victory_title_color: Color = Color(1.0, 0.9, 0.6)
@export var text_color: Color = Color(0.85, 0.9, 1.0)
@export var title_font_size: int = 44
@export var text_font_size: int = 22
@export var spacing: int = 14

var _title: Label
var _body: Label
var _button: Button
var _root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = ColorRect.new()
	(_root as ColorRect).color = backdrop_color
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", spacing)
	center.add_child(column)

	_title = _make_label(title_font_size)
	column.add_child(_title)
	_body = _make_label(text_font_size)
	_body.add_theme_color_override("font_color", text_color)
	column.add_child(_body)

	_button = Button.new()
	_button.text = "Restart"
	_button.add_theme_font_size_override("font_size", text_font_size)
	_button.pressed.connect(_on_restart_pressed)
	column.add_child(_button)

	_root.visible = false


func show_death(cause: PlayerHealth.Cause) -> void:
	_title.text = "You died"
	_title.add_theme_color_override("font_color", death_title_color)
	var reason: String = "Out of oxygen." if cause == PlayerHealth.Cause.OXYGEN else "Caught by a creature."
	_body.text = "%s\n\nRestarting from the top..." % reason
	_open()
	await get_tree().create_timer(death_restart_delay, true).timeout
	if _root.visible:
		restart_requested.emit()


func show_victory(run_time: float, pulses: int, hits: int, oxygen_ratio: float) -> void:
	_title.text = "The ancient light is awake"
	_title.add_theme_color_override("font_color", victory_title_color)
	var minutes: int = floori(run_time / 60.0)
	var seconds: int = floori(run_time) % 60
	_body.text = "Time: %d:%02d\nPulses used: %d\nHits taken: %d\nOxygen left: %d%%" % [
		minutes, seconds, pulses, hits, roundi(oxygen_ratio * 100.0),
	]
	_open()


func _open() -> void:
	_root.visible = true
	_button.grab_focus()


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_restart_pressed() -> void:
	_root.visible = false
	restart_requested.emit()
