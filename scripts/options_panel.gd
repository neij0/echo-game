class_name OptionsPanel
extends VBoxContainer
## The Options page (main menu and pause menu): the Brightness slider and one
## volume slider per audio bus (Game.volume_buses), plus a Back button. Every
## change is applied and saved right away by the Game autoload. Builds its UI
## in code; call refresh() after a language change.

signal back_pressed

@export var text_color: Color = Color(0.75, 0.82, 0.92)
@export var button_font_size: int = 26
@export var info_font_size: int = 18
@export var width: float = 340.0
@export var spacing: int = 14
## Step of the Brightness slider (the range comes from the Game autoload).
@export var brightness_step: float = 0.05
## Step of the volume sliders (0-1).
@export var volume_step: float = 0.05

var _brightness_label: Label
var _brightness_slider: HSlider
var _brightness_info: Label
var _back_button: Button
## Bus name -> its volume Label.
var _volume_labels: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", spacing)
	_brightness_label = _make_label(button_font_size)
	add_child(_brightness_label)
	_brightness_slider = _make_slider(Game.min_brightness, Game.max_brightness, brightness_step, Game.brightness)
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	_brightness_info = _make_label(info_font_size)
	_brightness_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brightness_info.custom_minimum_size.x = width
	add_child(_brightness_info)
	for bus: String in Game.volume_buses:
		var label: Label = _make_label(info_font_size + 4)
		add_child(label)
		_volume_labels[bus] = label
		var slider: HSlider = _make_slider(0.0, 1.0, volume_step, Game.get_volume(bus))
		slider.value_changed.connect(_on_volume_changed.bind(bus))
	_back_button = Button.new()
	_back_button.custom_minimum_size.x = width
	_back_button.add_theme_font_size_override("font_size", button_font_size)
	_back_button.pressed.connect(back_pressed.emit)
	add_child(_back_button)
	refresh()


func refresh() -> void:
	_brightness_label.text = Game.text("brightness") % roundi(Game.brightness * 100.0)
	_brightness_info.text = Game.text("brightness_desc")
	for bus: String in _volume_labels:
		_update_volume_label(bus)
	_back_button.text = Game.text("back")


func focus_first() -> void:
	_brightness_slider.grab_focus()


func _make_slider(min_value: float, max_value: float, step: float, start: float) -> HSlider:
	var slider := HSlider.new()
	slider.custom_minimum_size.x = width
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = start
	add_child(slider)
	return slider


func _on_brightness_changed(value: float) -> void:
	Game.set_brightness(value)
	_brightness_label.text = Game.text("brightness") % roundi(Game.brightness * 100.0)


func _on_volume_changed(value: float, bus: String) -> void:
	Game.set_volume(bus, value)
	_update_volume_label(bus)


func _update_volume_label(bus: String) -> void:
	(_volume_labels[bus] as Label).text = Game.text("volume_" + bus) % roundi(Game.get_volume(bus) * 100.0)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	return label
