class_name MainMenu
extends Control
## The main menu: Continue (only if a save exists), New Game, Mode
## (Calm / Challenge), Language (English / Arabic), Quit. Builds its UI in code
## (grey-box) and rebuilds the text when the language changes. Arabic lays the
## menu out right-to-left.

@export var background_color: Color = Color(0.01, 0.02, 0.05)
@export var title_color: Color = Color(0.45, 0.95, 1.0)
@export var text_color: Color = Color(0.75, 0.82, 0.92)
@export var title_font_size: int = 72
@export var button_font_size: int = 26
@export var info_font_size: int = 18
@export var button_width: float = 340.0
@export var spacing: int = 14

var _column: VBoxContainer
var _title: Label
var _info: Label
var _continue_button: Button
var _new_game_button: Button
var _mode_button: Button
var _mode_info: Label
var _language_button: Button
var _quit_button: Button
var _confirm: ConfirmationDialog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = background_color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", spacing)
	center.add_child(_column)

	_title = _make_label(title_font_size, title_color)
	_column.add_child(_title)
	_info = _make_label(info_font_size, text_color)
	_column.add_child(_info)
	_continue_button = _make_button(Game.continue_game)
	_new_game_button = _make_button(_on_new_game_pressed)
	_mode_button = _make_button(_on_mode_pressed)
	_mode_info = _make_label(info_font_size, text_color)
	_mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.custom_minimum_size.x = button_width
	_column.add_child(_mode_info)
	_language_button = _make_button(Game.toggle_language)
	_quit_button = _make_button(get_tree().quit)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(Game.new_game)
	add_child(_confirm)

	Game.language_changed.connect(_refresh)
	_refresh()
	if _continue_button.visible:
		_continue_button.grab_focus()
	else:
		_new_game_button.grab_focus()


func _refresh() -> void:
	Game.apply_direction(self)
	_title.text = Game.text("game_title")
	var has_save: bool = Game.has_save()
	_continue_button.visible = has_save
	_info.visible = has_save
	if has_save:
		_info.text = Game.text("saved_at") % [Game.world_display_name(Game.save.world_id), Game.save.stage_index + 1]
	_continue_button.text = Game.text("continue")
	_new_game_button.text = Game.text("new_game")
	_mode_button.text = Game.text("mode") % Game.mode_name(Game.get_mode())
	_mode_info.text = Game.text("mode_challenge_desc" if Game.get_mode() == SaveData.Mode.CHALLENGE else "mode_calm_desc")
	_language_button.text = Game.text("language")
	_quit_button.text = Game.text("quit")
	_confirm.dialog_text = Game.text("confirm_new_game")
	_confirm.ok_button_text = Game.text("yes")
	_confirm.cancel_button_text = Game.text("no")


func _on_new_game_pressed() -> void:
	if Game.has_save():
		_confirm.popup_centered()
	else:
		Game.new_game()


func _on_mode_pressed() -> void:
	Game.toggle_mode()
	_refresh()


func _make_button(on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size.x = button_width
	button.add_theme_font_size_override("font_size", button_font_size)
	button.pressed.connect(on_pressed)
	_column.add_child(button)
	return button


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
