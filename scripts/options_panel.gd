class_name OptionsPanel
extends VBoxContainer
## The Options page (main menu and pause menu) in the "silhouette + glow" style:
## the Brightness slider and one volume slider per audio bus
## (Game.volume_buses), plus a Back button (GlowButton). Each setting is a row:
## its name and value over a thin glowing slider (the theme's HSlider); the
## focused row lights up (brighter name, a glowing dot before it, the soft
## "ui_focus" ping). Every change is applied and saved right away by the Game
## autoload. Lines up on the start side (right in Arabic). Builds its UI in
## code; call refresh() after a language change.

signal back_pressed

@export var text_color: Color = Color(0.75, 0.82, 0.92)
## The focused row's name (over-bright: it blooms where a GlowEnvironment covers it).
@export var focus_color: Color = Color(0.82, 1.28, 1.45)
@export var value_color: Color = Color(0.55, 0.63, 0.75)
@export var button_font_size: int = 26
@export var info_font_size: int = 18
@export var name_font_size: int = 21
@export var width: float = 340.0
@export var spacing: int = 14
## Room before the names for the focus dot (pixels).
@export var dot_room: float = 34.0
@export var dot_radius: float = 2.8
## Step of the Brightness slider (the range comes from the Game autoload).
@export var brightness_step: float = 0.05
## Step of the volume sliders (0-1).
@export var volume_step: float = 0.05


## One setting: name + value over its slider; lit while the slider has the focus.
class OptionRow:
	extends VBoxContainer
	var name_label: Label
	var value_label: Label
	var slider: HSlider
	var panel: OptionsPanel

	func _init(owner_panel: OptionsPanel) -> void:
		panel = owner_panel
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		var room := Control.new()
		room.custom_minimum_size.x = panel.dot_room
		line.add_child(room)
		name_label = Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", panel.name_font_size)
		line.add_child(name_label)
		value_label = Label.new()
		value_label.add_theme_font_size_override("font_size", panel.name_font_size - 2)
		value_label.add_theme_color_override("font_color", panel.value_color)
		line.add_child(value_label)
		slider = HSlider.new()
		slider.custom_minimum_size.x = panel.width
		slider.focus_entered.connect(_on_focus.bind(true))
		slider.focus_exited.connect(_on_focus.bind(false))
		slider.mouse_entered.connect(func() -> void: slider.grab_focus())
		add_child(slider)
		_on_focus(false)

	func _on_focus(focused: bool) -> void:
		name_label.add_theme_color_override("font_color", panel.focus_color if focused else panel.text_color)
		if focused and is_inside_tree():
			UiAudio.play_in(get_tree(), &"ui_focus")
		queue_redraw()

	func _draw() -> void:
		if slider == null or not slider.has_focus():
			return
		var rtl: bool = is_layout_rtl()
		var x: float = size.x - panel.dot_room * 0.5 if rtl else panel.dot_room * 0.5
		var y: float = name_label.position.y + name_label.size.y * 0.5
		GlowFx.dot(self, Vector2(x, y), panel.dot_radius, Color(0.5, 1.15, 1.35))


var _brightness: OptionRow
var _brightness_info: Label
var _back_button: GlowButton
## Bus name -> its row.
var _volume_rows: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", spacing)
	_brightness = _make_row(Game.min_brightness, Game.max_brightness, brightness_step, Game.brightness)
	_brightness.slider.value_changed.connect(_on_brightness_changed)
	_brightness_info = Label.new()
	_brightness_info.theme_type_variation = &"DimLabel"
	_brightness_info.add_theme_font_size_override("font_size", info_font_size - 2)
	_brightness_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brightness_info.custom_minimum_size.x = width - dot_room
	var info_box := MarginContainer.new()
	info_box.add_theme_constant_override("margin_left", int(dot_room))
	info_box.add_theme_constant_override("margin_right", int(dot_room))
	info_box.add_child(_brightness_info)
	add_child(info_box)
	for bus: String in Game.volume_buses:
		var row: OptionRow = _make_row(0.0, 1.0, volume_step, Game.get_volume(bus))
		row.slider.value_changed.connect(_on_volume_changed.bind(bus))
		_volume_rows[bus] = row
	_back_button = GlowButton.new()
	_back_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back_button.custom_minimum_size.x = width
	_back_button.add_theme_font_size_override("font_size", button_font_size)
	_back_button.pressed.connect(back_pressed.emit)
	add_child(_back_button)
	refresh()


func refresh() -> void:
	_brightness.name_label.text = _setting_name("brightness")
	_brightness.value_label.text = "%d%%" % roundi(Game.brightness * 100.0)
	_brightness_info.text = Game.text("brightness_desc")
	for bus: String in _volume_rows:
		_update_volume_row(bus)
	_back_button.text = Game.text("back")


func focus_first() -> void:
	_brightness.slider.grab_focus()


## The control focused when the page opens (FocusKeeper).
func get_first_focus() -> Control:
	return _brightness.slider


## The setting's name without its value (the texts are "Brightness: %d%%").
func _setting_name(key: String) -> String:
	var text: String = Game.text(key)
	var cut: int = text.find(":")
	return text.substr(0, cut).strip_edges() if cut >= 0 else text.replace("%d%%", "").replace("%d", "").strip_edges()


func _make_row(min_value: float, max_value: float, step: float, start: float) -> OptionRow:
	var row := OptionRow.new(self)
	add_child(row)
	row.slider.min_value = min_value
	row.slider.max_value = max_value
	row.slider.step = step
	row.slider.value = start
	return row


func _on_brightness_changed(value: float) -> void:
	Game.set_brightness(value)
	_brightness.value_label.text = "%d%%" % roundi(Game.brightness * 100.0)


func _on_volume_changed(value: float, bus: String) -> void:
	Game.set_volume(bus, value)
	_update_volume_row(bus)


func _update_volume_row(bus: String) -> void:
	var row: OptionRow = _volume_rows[bus]
	row.name_label.text = _setting_name("volume_" + bus)
	row.value_label.text = "%d%%" % roundi(Game.get_volume(bus) * 100.0)
