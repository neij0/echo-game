class_name PauseMenu
extends CanvasLayer
## The pause menu: either player presses Start / Esc ("pause" action) while a
## level is played (StageManager.can_pause). The whole game tree pauses
## (players, creatures, oxygen, the escape timer...). In the "silhouette +
## glow" style (Game.ui_theme): the frozen level stays dimly visible behind a
## dark veil (darkest on the menu's side); the column (title, a glowing wave
## line, GlowButtons) is uncovered by a pulse wipe (PulseReveal). Pages, all in
## the column's place: the main list (Resume, Options, Restart level
## (Challenge: Restart stage, from level 1), Quit to the Journey, Quit to main
## menu), the Options (OptionsPanel) and a confirmation (ConfirmPanel) for the
## three that lose the level's progress (stage saves are kept). Beside it: the
## current mode and both players' skills with their ranks (read-only). Drawn
## button prompts at the bottom. Navigated with the ui_* actions (keyboard and
## every gamepad); pause / ui_cancel goes back or resumes. Arabic: the layout
## mirrors (the column on the right).

signal opened
signal closed

@export var stage_manager: StageManager
@export var backdrop_color: Color = Color(0.0, 0.008, 0.022, 0.8)
## The veil on the column's side (it fades to backdrop_color across the screen).
@export var backdrop_side_color: Color = Color(0.0, 0.006, 0.016, 0.96)
@export var screen_margin: Vector2 = Vector2(90.0, 56.0)
@export var column_width: float = 420.0
@export var info_width: float = 380.0
@export var title_font_size: int = 64
@export var button_font_size: int = 28
@export var info_font_size: int = 19
@export var spacing: int = 4
@export var skill_icon_size: float = 30.0
@export var title_rule_size: Vector2 = Vector2(180.0, 30.0)
## Room before the texts (the buttons' text margin).
@export var text_indent: int = 34

enum Confirm { NONE, RESTART, WORLD_MAP, MAIN_MENU }

var is_open: bool = false
var _root: Control
var _veil: TextureRect
var _reveal: PulseReveal
var _info_reveal: PulseReveal
var _title: Label
var _main_page: VBoxContainer
var _resume_button: GlowButton
var _options_button: GlowButton
var _restart_button: GlowButton
var _world_map_button: GlowButton
var _main_menu_button: GlowButton
var _options: OptionsPanel
var _confirm: ConfirmPanel
## The confirmation's texts (tests read them).
var _confirm_label: Label
var _confirm_warning: Label
var _info: VBoxContainer
var _prompt: InputPrompt
var _indented: Array[MarginContainer] = []
var _confirm_action: Confirm = Confirm.NONE
## Focused when going back to the main page.
var _return_focus: GlowButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(FocusKeeper.GROUP)
	_root = Control.new()
	_root.theme = Game.ui_theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_veil = TextureRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_veil)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(screen_margin.x))
	margin.add_theme_constant_override("margin_right", int(screen_margin.x))
	margin.add_theme_constant_override("margin_top", int(screen_margin.y))
	margin.add_theme_constant_override("margin_bottom", int(screen_margin.y))
	_root.add_child(margin)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	var layout := HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 60)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(layout)
	_prompt = InputPrompt.new()
	rows.add_child(_prompt)

	_reveal = PulseReveal.new()
	_reveal.custom_minimum_size.x = column_width
	layout.add_child(_reveal)
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", spacing)
	_reveal.add_child(page)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", title_font_size)
	_indent(page, _title)
	var rule := WaveRule.new()
	rule.custom_minimum_size = title_rule_size
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_indent(page, rule)

	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", spacing)
	page.add_child(_main_page)
	_resume_button = _make_button(_main_page, close)
	_options_button = _make_button(_main_page, _show_page.bind("options"))
	_restart_button = _make_button(_main_page, _ask.bind(Confirm.RESTART))
	_world_map_button = _make_button(_main_page, _ask.bind(Confirm.WORLD_MAP))
	_main_menu_button = _make_button(_main_page, _ask.bind(Confirm.MAIN_MENU))

	_options = OptionsPanel.new()
	_options.button_font_size = button_font_size
	_options.width = column_width - text_indent
	_options.back_pressed.connect(_show_page.bind("main"))
	page.add_child(_options)

	_confirm = ConfirmPanel.new()
	_confirm.width = column_width
	_confirm.confirmed.connect(_on_confirmed)
	_confirm.cancelled.connect(_show_page.bind("main"))
	page.add_child(_confirm)
	_confirm_label = _confirm.question_label
	_confirm_warning = _confirm.warning_label

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)
	_info_reveal = PulseReveal.new()
	_info_reveal.custom_minimum_size.x = info_width
	layout.add_child(_info_reveal)
	_info = VBoxContainer.new()
	_info.alignment = BoxContainer.ALIGNMENT_CENTER
	_info.add_theme_constant_override("separation", 8)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_reveal.add_child(_info)
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
	_info_reveal.reveal(Vector2(1.0 if Game.is_rtl() else 0.0, 0.5))
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	closed.emit()


## The control focused while the menu is open (FocusKeeper).
func get_default_focus() -> Control:
	if not is_open or not _root.visible:
		return null
	if _confirm.visible:
		return _confirm.no_button
	if _options.visible:
		return _options.get_first_focus()
	return _resume_button


## Esc / Start / ui_cancel: back to the main page, or resume from there.
func _back() -> void:
	if _main_page.visible:
		close()
	else:
		_show_page("main")


func _show_page(page: String) -> void:
	_main_page.visible = page == "main"
	_options.visible = page == "options"
	_confirm.visible = page == "confirm"
	_reveal.reveal(Vector2(1.0 if Game.is_rtl() else 0.0, 0.5))
	match page:
		"main":
			# Back on the button that opened the page (Resume when just opened).
			var focus: GlowButton = _return_focus if _return_focus else _resume_button
			_return_focus = null
			_confirm_action = Confirm.NONE
			focus.focus_quietly()
		"options":
			_return_focus = _options_button
			_options.refresh()
			_options.focus_first()
		"confirm":
			# "No" first: a stray press never loses progress (ConfirmPanel.ask).
			pass
	_refresh_prompt(page)


func _ask(action: Confirm) -> void:
	_confirm_action = action
	var question: String = ""
	match action:
		Confirm.RESTART:
			question = Game.text("pause_confirm_restart_stage" if _is_challenge() else "pause_confirm_restart")
			_return_focus = _restart_button
		Confirm.WORLD_MAP:
			question = Game.text("pause_confirm_journey")
			_return_focus = _world_map_button
		Confirm.MAIN_MENU:
			question = Game.text("pause_confirm_main_menu")
			_return_focus = _main_menu_button
	var warning: String = "pause_quit_warning"
	if action == Confirm.RESTART:
		warning = "pause_restart_stage_warning" if _is_challenge() else "pause_restart_warning"
	_show_page("confirm")
	_confirm.ask(question, Game.text(warning))


func _on_confirmed() -> void:
	var action: Confirm = _confirm_action
	_confirm_action = Confirm.NONE
	is_open = false
	match action:
		Confirm.RESTART:
			if stage_manager:
				# The menu stays until the screen is black (the level rebuilds behind it).
				stage_manager.restart_level_faded(_hide)
			else:
				_hide()
				get_tree().paused = false
		Confirm.WORLD_MAP:
			Game.go_to_journey()
		Confirm.MAIN_MENU:
			Game.go_to_main_menu()
		_:
			_hide()
	closed.emit()


func _hide() -> void:
	_root.visible = false


func _refresh_text() -> void:
	var rtl: bool = Game.is_rtl()
	Game.apply_direction(_root)
	_veil.texture = _veil_texture(rtl)
	_title.text = Game.text("pause_title")
	_title.theme_type_variation = &"TitleArabicLabel" if rtl else &"TitleLabel"
	_title.add_theme_font_size_override("font_size", title_font_size)
	for container: MarginContainer in _indented:
		container.add_theme_constant_override("margin_left", 0 if rtl else text_indent)
		container.add_theme_constant_override("margin_right", text_indent if rtl else 0)
	_resume_button.text = Game.text("pause_resume")
	_options_button.text = Game.text("options")
	_restart_button.text = Game.text("pause_restart_stage" if _is_challenge() else "pause_restart")
	_world_map_button.text = Game.text("pause_journey")
	_main_menu_button.text = Game.text("pause_main_menu")
	_confirm.refresh()


func _refresh_prompt(page: String) -> void:
	var entries: Array[Dictionary] = [
		{"actions": [&"ui_up", &"ui_down"], "text": Game.text("prompt_navigate")},
		{"actions": [&"ui_accept"], "text": Game.text("prompt_select")},
		{"actions": [&"ui_cancel"], "text": Game.text("pause_resume") if page == "main" else Game.text("prompt_back")},
	]
	_prompt.setup(entries, InputDevices.menu_device, true)


## The veil: darkest on the column's side, so the frozen level shows a little
## on the other.
func _veil_texture(rtl: bool) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, backdrop_side_color)
	gradient.set_color(1, backdrop_color)
	gradient.add_point(0.45, backdrop_side_color.lerp(backdrop_color, 0.35))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	texture.fill_from = Vector2(1.0 if rtl else 0.0, 0.0)
	texture.fill_to = Vector2(0.0 if rtl else 1.0, 0.0)
	return texture


## Challenge: "Restart level" restarts the whole stage (StageManager.restart_level).
func _is_challenge() -> bool:
	return stage_manager != null and stage_manager.mode == SaveData.Mode.CHALLENGE


## The mode and both players' skills (read-only).
func _refresh_info() -> void:
	for child: Node in _info.get_children():
		child.queue_free()
	var mode: SaveData.Mode = stage_manager.mode if stage_manager else Game.get_mode()
	var mode_label := _make_label(&"DimLabel", info_font_size)
	mode_label.text = Game.text("mode") % Game.mode_name(mode)
	_info.add_child(mode_label)
	var world: WorldConfig = stage_manager.world if stage_manager else null
	var players: Array[Player] = stage_manager.players if stage_manager else Players.all(get_tree())
	for player: Player in players:
		var is_echo: bool = player.skill_owner == SkillDefinition.Owner.ECHO
		var header := _make_label(&"EchoLabel" if is_echo else &"GuardianLabel", 24)
		header.text = Game.text("char_echo" if is_echo else "char_guardian")
		_info.add_child(header)
		var owned: Array[SkillDefinition] = player.skills.get_owned()
		if owned.is_empty():
			var none := _make_label(&"DimLabel", info_font_size)
			none.text = Game.text("pause_no_skills")
			_info.add_child(none)
		for definition: SkillDefinition in owned:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon := SkillIcon.new()
			icon.setup(definition, player.skills.get_rank(definition.id), skill_icon_size)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(icon)
			var label := _make_label(&"Label", info_font_size)
			label.text = definition.display_name(Game.language, world)
			if definition.max_rank > 1:
				label.text += "  " + Game.text("skill_rank") % [player.skills.get_rank(definition.id), definition.max_rank]
			line.add_child(label)
			_info.add_child(line)


func _make_button(parent: Control, on_pressed: Callable) -> GlowButton:
	var button := GlowButton.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = column_width
	button.add_theme_font_size_override("font_size", button_font_size)
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button


func _make_label(variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _indent(parent: Control, control: Control) -> void:
	var container := MarginContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)
	container.add_child(control)
	_indented.append(container)
