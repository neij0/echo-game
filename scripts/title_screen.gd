class_name TitleScreen
extends Control
## "Press any button": the big title (ECHO with صدى under it, swapped in Arabic)
## over the night sky, a slow sonar ring growing from behind it, the prompt
## breathing under it. The first press (a key, a gamepad button or a click)
## makes that device Player 1's (the Echo: Game.assign_player_one), sends a
## brighter ring out and opens the main menu.

@export var input_delay: float = 0.6
@export var ring_interval: float = 4.0
@export var ring_time: float = 3.4
@export var ring_reach: float = 560.0
@export var ring_color: Color = Color(0.45, 0.95, 1.0, 0.45)
@export var burst_color: Color = Color(0.7, 1.2, 1.4, 0.9)
## Breaths per second of the prompt.
@export var prompt_breath_speed: float = 0.45
@export var title_font_size: int = 132
@export var press_sound: StringName = &"ui_press"

var _rings: Control
var _title: Label
var _title_other: Label
var _prompt: Label
var _time: float = 0.0
## Start times of the rings (seconds of _time).
var _ring_starts: Array[float] = []
var _burst_start: float = -INF
var _accepted: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Game.ui_theme
	Game.apply_direction(self)
	add_child(NightSky.new())
	add_child(GlowEnvironment.new())
	_rings = Control.new()
	_rings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rings.draw.connect(_draw_rings)
	add_child(_rings)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)
	var rtl: bool = Game.is_rtl()
	_title = _label(column, &"TitleArabicLabel" if rtl else &"TitleLabel", Game.text("game_title"))
	_title.add_theme_font_size_override("font_size", title_font_size)
	_title_other = _label(column, &"SubtitleLatinLabel" if rtl else &"SubtitleLabel", Game.text("game_title_other"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 70.0
	column.add_child(gap)
	_prompt = _label(column, &"PromptLabel", Game.text("press_any_button"))
	_prompt.add_theme_font_size_override("font_size", 24)
	_ring_starts.append(0.4)


func _process(delta: float) -> void:
	_time += delta
	if _time - _ring_starts[_ring_starts.size() - 1] >= ring_interval:
		_ring_starts.append(_time)
	while _ring_starts.size() > 3:
		_ring_starts.remove_at(0)
	var breath: float = 0.5 + 0.5 * sin(_time * TAU * prompt_breath_speed)
	_prompt.modulate.a = 0.0 if _accepted else lerpf(0.35, 1.0, breath)
	_rings.queue_redraw()


func _input(event: InputEvent) -> void:
	if _accepted or _time < input_delay:
		return
	var device: int = -2
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		device = -1
	elif event is InputEventMouseButton and event.is_pressed():
		device = -1
	elif event is InputEventJoypadButton and event.is_pressed():
		device = event.device
	if device == -2:
		return
	get_viewport().set_input_as_handled()
	accept(device)


## Player 1 takes this device (-1 = the keyboard), then the main menu opens.
func accept(device: int) -> void:
	_accepted = true
	_burst_start = _time
	UiAudio.play_in(get_tree(), press_sound)
	# The menus' prompts already follow the device that pressed (InputDevices).
	Game.assign_player_one(device)
	Game.go_to_main_menu()


func _draw_rings() -> void:
	var center: Vector2 = _title.get_global_rect().get_center() - _rings.global_position
	for start: float in _ring_starts:
		GlowFx.ripple(_rings, center, _time - start, ring_time, ring_reach, ring_color, 1, 0.0, 1.4)
	if _accepted:
		GlowFx.ripple(_rings, center, _time - _burst_start, 0.9, ring_reach * 1.4, burst_color, 3, 0.1, 2.0)


func _label(parent: Control, variation: StringName, text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	parent.add_child(label)
	return label
