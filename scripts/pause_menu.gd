class_name PauseMenu
extends CanvasLayer
## The pause menu: either player presses Start / Esc ("pause" action) while a
## level is played (StageManager.can_pause). The whole game tree pauses
## (players, creatures, oxygen, the escape timer...). Pages: the main list
## (Resume, Options, Restart level (Challenge: Restart stage, from level 1),
## Quit to world map, Quit to main menu), the
## Options (OptionsPanel) and a confirmation for the three that lose the
## level's progress (stage saves are kept). Beside the list: the current mode
## and both players' skills with their ranks (read-only). Navigated with the
## ui_* actions (keyboard and every gamepad); pause / ui_cancel goes back or
## resumes. Builds its UI in code (functional styling only for now).

signal opened
signal closed

@export var stage_manager: StageManager
@export var backdrop_color: Color = Color(0.0, 0.01, 0.03, 0.82)
@export var title_color: Color = Color(0.45, 0.95, 1.0)
@export var text_color: Color = Color(0.75, 0.82, 0.92)
@export var warning_color: Color = Color(1.0, 0.75, 0.45)
@export var title_font_size: int = 48
@export var button_font_size: int = 24
@export var info_font_size: int = 18
@export var button_width: float = 340.0
@export var spacing: int = 12
@export var skill_icon_size: float = 30.0

enum Confirm { NONE, RESTART, WORLD_MAP, MAIN_MENU }

var is_open: bool = false
var _root: ColorRect
var _title: Label
var _main_page: VBoxContainer
var _resume_button: Button
var _options_button: Button
var _restart_button: Button
var _world_map_button: Button
var _main_menu_button: Button
var _options: OptionsPanel
var _confirm_page: VBoxContainer
var _confirm_label: Label
var _confirm_warning: Label
var _yes_button: Button
var _no_button: Button
var _info: VBoxContainer
var _confirm_action: Confirm = Confirm.NONE
## Focused when going back to the main page.
var _return_focus: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = ColorRect.new()
	_root.color = backdrop_color
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", spacing * 5)
	center.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", spacing)
	row.add_child(left)
	_title = _make_label(title_font_size, title_color)
	left.add_child(_title)
	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", spacing)
	left.add_child(_main_page)
	_resume_button = _make_button(_main_page, close)
	_options_button = _make_button(_main_page, _show_page.bind("options"))
	_restart_button = _make_button(_main_page, _ask.bind(Confirm.RESTART))
	_world_map_button = _make_button(_main_page, _ask.bind(Confirm.WORLD_MAP))
	_main_menu_button = _make_button(_main_page, _ask.bind(Confirm.MAIN_MENU))

	_options = OptionsPanel.new()
	_options.text_color = text_color
	_options.button_font_size = button_font_size
	_options.info_font_size = info_font_size
	_options.width = button_width
	_options.spacing = spacing
	_options.back_pressed.connect(_show_page.bind("main"))
	left.add_child(_options)

	_confirm_page = VBoxContainer.new()
	_confirm_page.add_theme_constant_override("separation", spacing)
	left.add_child(_confirm_page)
	_confirm_label = _make_label(button_font_size, text_color)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.custom_minimum_size.x = button_width
	_confirm_page.add_child(_confirm_label)
	_confirm_warning = _make_label(info_font_size, warning_color)
	_confirm_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_warning.custom_minimum_size.x = button_width
	_confirm_page.add_child(_confirm_warning)
	_yes_button = _make_button(_confirm_page, _on_confirmed)
	_no_button = _make_button(_confirm_page, _show_page.bind("main"))

	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", spacing)
	_info.custom_minimum_size.x = button_width
	row.add_child(_info)
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_open:
			_back()
		else:
			open()
	elif is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func open() -> void:
	if is_open or (stage_manager and not stage_manager.can_pause()):
		return
	is_open = true
	get_tree().paused = true
	# In case a hit-stop (SwordAbility) was running.
	Engine.time_scale = 1.0
	_refresh_text()
	_refresh_info()
	_root.visible = true
	_show_page("main")
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	closed.emit()


## Esc / Start / ui_cancel: back to the main page, or resume from there.
func _back() -> void:
	if _main_page.visible:
		close()
	else:
		_show_page("main")


func _show_page(page: String) -> void:
	_main_page.visible = page == "main"
	_options.visible = page == "options"
	_confirm_page.visible = page == "confirm"
	match page:
		"main":
			# Back on the button that opened the page (Resume when just opened).
			var focus: Button = _return_focus if _return_focus else _resume_button
			_return_focus = null
			_confirm_action = Confirm.NONE
			focus.grab_focus()
		"options":
			_return_focus = _options_button
			_options.refresh()
			_options.focus_first()
		"confirm":
			# "No" first: a stray press never loses progress.
			_no_button.grab_focus()


func _ask(action: Confirm) -> void:
	_confirm_action = action
	match action:
		Confirm.RESTART:
			_confirm_label.text = Game.text("pause_confirm_restart_stage" if _is_challenge() else "pause_confirm_restart")
			_return_focus = _restart_button
		Confirm.WORLD_MAP:
			_confirm_label.text = Game.text("pause_confirm_world_map")
			_return_focus = _world_map_button
		Confirm.MAIN_MENU:
			_confirm_label.text = Game.text("pause_confirm_main_menu")
			_return_focus = _main_menu_button
	var warning: String = "pause_quit_warning"
	if action == Confirm.RESTART:
		warning = "pause_restart_stage_warning" if _is_challenge() else "pause_restart_warning"
	_confirm_warning.text = Game.text(warning)
	_show_page("confirm")


func _on_confirmed() -> void:
	var action: Confirm = _confirm_action
	_confirm_action = Confirm.NONE
	is_open = false
	_root.visible = false
	match action:
		Confirm.RESTART:
			if stage_manager:
				stage_manager.restart_level()
			else:
				get_tree().paused = false
		Confirm.WORLD_MAP:
			Game.go_to_world_map()
		Confirm.MAIN_MENU:
			Game.go_to_main_menu()
	closed.emit()


func _refresh_text() -> void:
	Game.apply_direction(_root)
	_title.text = Game.text("pause_title")
	_resume_button.text = Game.text("pause_resume")
	_options_button.text = Game.text("options")
	_restart_button.text = Game.text("pause_restart_stage" if _is_challenge() else "pause_restart")
	_world_map_button.text = Game.text("pause_world_map")
	_main_menu_button.text = Game.text("pause_main_menu")
	_yes_button.text = Game.text("yes")
	_no_button.text = Game.text("no")


## Challenge: "Restart level" restarts the whole stage (StageManager.restart_level).
func _is_challenge() -> bool:
	return stage_manager != null and stage_manager.mode == SaveData.Mode.CHALLENGE


## The mode and both players' skills (read-only).
func _refresh_info() -> void:
	for child: Node in _info.get_children():
		child.queue_free()
	var mode: SaveData.Mode = stage_manager.mode if stage_manager else Game.get_mode()
	var mode_label := _make_label(button_font_size, text_color)
	mode_label.text = Game.text("mode") % Game.mode_name(mode)
	_info.add_child(mode_label)
	var world: WorldConfig = stage_manager.world if stage_manager else null
	var players: Array[Player] = stage_manager.players if stage_manager else Players.all(get_tree())
	for player: Player in players:
		var is_echo: bool = player.skill_owner == SkillDefinition.Owner.ECHO
		var header := _make_label(button_font_size, title_color)
		header.text = Game.text("char_echo" if is_echo else "char_guardian")
		_info.add_child(header)
		var owned: Array[SkillDefinition] = player.skills.get_owned()
		if owned.is_empty():
			var none := _make_label(info_font_size, text_color)
			none.text = Game.text("pause_no_skills")
			_info.add_child(none)
		for definition: SkillDefinition in owned:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", spacing)
			var icon := SkillIcon.new()
			icon.setup(definition, player.skills.get_rank(definition.id), skill_icon_size)
			line.add_child(icon)
			var label := _make_label(info_font_size, text_color)
			label.text = definition.display_name(Game.language, world)
			if definition.max_rank > 1:
				label.text += "  " + Game.text("skill_rank") % [player.skills.get_rank(definition.id), definition.max_rank]
			line.add_child(label)
			_info.add_child(line)


func _make_button(parent: Control, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size.x = button_width
	button.add_theme_font_size_override("font_size", button_font_size)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
