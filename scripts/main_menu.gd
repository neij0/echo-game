class_name MainMenu
extends Control
## The main menu in the "silhouette + glow" style (Game.ui_theme). Behind it,
## dark and dim: the night sky and the Journey tower far away (JourneyTower,
## lit by the save), drifting slowly, with the small Echo and Guardian on a
## ledge at the bottom looking up at it (MenuSilhouettes). The menu is the
## clearest thing on screen: the title "ECHO" / "صدى" and a column of glowing
## buttons (GlowButton, one lit at a time): Continue (only with a save: the
## Journey), New Game (the intro story, then stage 1; a confirmation if a save
## exists: a ConfirmPanel in the column's place), Mode (Calm / Challenge),
## Language, Options (OptionsPanel, same place), Quit. The help line at the bottom explains the focused button (the
## save for Continue, the mode for Mode); drawn button prompts under it follow
## the device in use. The column is uncovered by a pulse wipe (PulseReveal).
## Arabic lays it out right-to-left: the column moves right, the tower left.
## Music: music_path (Music bus), fading in and out with the screen.

@export_group("Layout")
## Space round the screen edge (pixels).
@export var screen_margin: Vector2 = Vector2(80.0, 52.0)
@export var column_width: float = 470.0
@export var spacing: int = 4
## Room before the buttons' text (their glowing dot); labels line up with it.
@export var text_indent: int = 34
## Height of the glowing wave line between the title and the buttons, and its width.
@export var title_gap: int = 34
@export var title_rule_width: float = 200.0

@export_group("Background")
## Where the tower stands (share of the screen; mirrored in Arabic) and its size.
@export var tower_anchor: Vector2 = Vector2(0.7, 0.43)
@export var tower_scale: float = 0.25
## The tower is far away: its brightness (0-1).
@export var tower_dim: float = 0.42
## It drifts slowly round its spot: pixels and cycles per second.
@export var tower_drift: Vector2 = Vector2(10.0, 7.0)
@export var tower_drift_speed: float = 0.035
## The ledge with the Echo and the Guardian (share of the screen, mirrored) and their size.
@export var silhouettes_anchor: Vector2 = Vector2(0.7, 0.955)
@export var silhouettes_scale: float = 1.5

@export_group("Reveal")
## Seconds after opening before the pulse uncovers the column.
@export var reveal_delay: float = 0.35

@export_group("Music")
@export var music_path: String = "res://assets/audio/music/music_menu.wav"
@export var music_volume_db: float = -4.0
@export var music_fade_time: float = 3.0

var _sky: NightSky
var _tower_holder: Node2D
var _tower: JourneyTower
var _silhouettes: MenuSilhouettes
var _ui: Control
var _reveal: PulseReveal
var _column: VBoxContainer
var _title: Label
var _title_other: Label
var _continue_button: GlowButton
var _new_game_button: GlowButton
var _mode_button: GlowButton
var _language_button: GlowButton
var _options_button: GlowButton
var _quit_button: GlowButton
var _indented: Array[MarginContainer] = []
var _help: Label
var _prompt: InputPrompt
var _options: OptionsPanel
var _confirm: ConfirmPanel
var _music: AudioStreamPlayer
var _music_time: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Game.ui_theme
	_build_background()
	_build_ui()
	_add_music()
	Game.language_changed.connect(_refresh)
	_refresh()
	if _continue_button.visible:
		_continue_button.focus_quietly()
	else:
		_new_game_button.focus_quietly()
	_reveal.cover()
	get_tree().create_timer(reveal_delay).timeout.connect(_reveal_column)


func _process(delta: float) -> void:
	_time += delta
	var phase: float = _time * TAU * tower_drift_speed
	var drift := Vector2(sin(phase), sin(phase * 1.37 + 0.8)) * tower_drift
	_tower_holder.position = size * _mirrored(tower_anchor) + drift
	_silhouettes.position = size * _mirrored(silhouettes_anchor)
	if _music and _music.playing:
		# Fades in at the start and with the screen (in and out).
		_music_time += delta
		var level: float = minf(_music_time / music_fade_time, 1.0) * (1.0 - Game.fader.get_cover())
		_music.volume_db = music_volume_db + linear_to_db(maxf(level, 0.001))


func _mirrored(share: Vector2) -> Vector2:
	return Vector2(1.0 - share.x, share.y) if Game.is_rtl() else share


func _build_background() -> void:
	_sky = NightSky.new()
	add_child(_sky)
	_tower_holder = Node2D.new()
	_tower_holder.scale = Vector2(tower_scale, tower_scale)
	_tower_holder.modulate = Color(tower_dim, tower_dim, tower_dim)
	add_child(_tower_holder)
	_tower = JourneyTower.new()
	_tower.position = Vector2(0.0, _tower.island_spacing * 2.0)
	_tower_holder.add_child(_tower)
	if Game.has_save():
		_tower.set_progress(Game.get_world_index(Game.save.world_id), Game.save.stage_index)
	else:
		_tower.set_progress(0, 0)
	_silhouettes = MenuSilhouettes.new()
	_silhouettes.scale = Vector2(silhouettes_scale, silhouettes_scale)
	add_child(_silhouettes)
	add_child(GlowEnvironment.new())


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(screen_margin.x))
	margin.add_theme_constant_override("margin_right", int(screen_margin.x))
	margin.add_theme_constant_override("margin_top", int(screen_margin.y))
	margin.add_theme_constant_override("margin_bottom", int(screen_margin.y))
	_ui.add_child(margin)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	var layout := HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(layout)
	_reveal = PulseReveal.new()
	_reveal.custom_minimum_size.x = column_width
	layout.add_child(_reveal)
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal.add_child(page)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)
	_help = Label.new()
	_help.theme_type_variation = &"DimLabel"
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(column_width + 160.0, 26.0)
	_help.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rows.add_child(_help)
	_prompt = InputPrompt.new()
	rows.add_child(_prompt)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", spacing)
	page.add_child(_column)
	_title = _add_label(&"TitleLabel")
	_title_other = _add_label(&"SubtitleLabel")
	var rule := WaveRule.new()
	rule.custom_minimum_size = Vector2(title_rule_width, title_gap)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_indent(rule)
	_continue_button = _make_button(Game.continue_game)
	_new_game_button = _make_button(_on_new_game_pressed)
	_mode_button = _make_button(_on_mode_pressed)
	_language_button = _make_button(Game.toggle_language)
	_options_button = _make_button(_show_options.bind(true))
	_quit_button = _make_button(get_tree().quit)
	_build_options(page)
	_build_confirm(page)


func _refresh() -> void:
	var rtl: bool = Game.is_rtl()
	Game.apply_direction(self)
	_title.text = Game.text("game_title")
	_title.theme_type_variation = &"TitleArabicLabel" if rtl else &"TitleLabel"
	_title_other.text = Game.text("game_title_other")
	_title_other.theme_type_variation = &"SubtitleLatinLabel" if rtl else &"SubtitleLabel"
	for container: MarginContainer in _indented:
		container.add_theme_constant_override("margin_left", 0 if rtl else text_indent)
		container.add_theme_constant_override("margin_right", text_indent if rtl else 0)
	var has_save: bool = Game.has_save()
	_continue_button.visible = has_save
	_continue_button.help_text = Game.text("saved_at") % [Game.world_display_name(Game.save.world_id), Game.save.stage_index + 1] \
		if has_save else ""
	_continue_button.text = Game.text("continue")
	_new_game_button.text = Game.text("new_game")
	_mode_button.text = Game.text("mode") % Game.mode_name(Game.get_mode())
	_mode_button.help_text = Game.text("mode_challenge_desc" if Game.get_mode() == SaveData.Mode.CHALLENGE else "mode_calm_desc")
	_language_button.text = Game.text("language")
	_options_button.text = Game.text("options")
	_quit_button.text = Game.text("quit")
	_options.refresh()
	_confirm.refresh()
	if _confirm.visible:
		_confirm.question_label.text = Game.text("confirm_new_game")
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_show_help_of_focus()
	_refresh_prompt()


## The help line shows the focused button's help (nothing for most).
func _show_help(text: String) -> void:
	_help.text = text


func _show_help_of_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner() as GlowButton
	_show_help(focused.help_text if focused else "")


func _refresh_prompt() -> void:
	var entries: Array[Dictionary] = [
		{"actions": [&"ui_up", &"ui_down"], "text": Game.text("prompt_navigate")},
		{"actions": [&"ui_accept"], "text": Game.text("prompt_select")},
	]
	if _options.visible or _confirm.visible:
		entries.append({"actions": [&"ui_cancel"], "text": Game.text("prompt_back")})
	_prompt.setup(entries, InputPrompt.menu_device, true)


## The pulse that uncovers the column starts from the side facing the tower.
func _reveal_column() -> void:
	_reveal.reveal(Vector2(0.0 if Game.is_rtl() else 1.0, 0.55))


func _unhandled_input(event: InputEvent) -> void:
	if _options.visible and event.is_action_pressed(&"ui_cancel"):
		_show_options(false)
		get_viewport().set_input_as_handled()


## The Options page replaces the main buttons (same place on screen).
func _build_options(parent: Control) -> void:
	_options = OptionsPanel.new()
	_options.text_color = Color(0.74, 0.81, 0.9)
	_options.width = column_width - text_indent * 2
	_options.visible = false
	_options.back_pressed.connect(_show_options.bind(false))
	parent.add_child(_options)


## The New Game question replaces the main buttons too (No focused first).
func _build_confirm(parent: Control) -> void:
	_confirm = ConfirmPanel.new()
	_confirm.width = column_width - text_indent * 2
	_confirm.visible = false
	_confirm.confirmed.connect(Game.new_game)
	_confirm.cancelled.connect(_show_confirm.bind(false))
	parent.add_child(_confirm)


func _show_confirm(open: bool) -> void:
	_column.visible = not open
	_confirm.visible = open
	_reveal.reveal(Vector2(0.0 if Game.is_rtl() else 1.0, 0.5))
	_refresh_prompt()
	if open:
		_show_help("")
		_confirm.ask(Game.text("confirm_new_game"))
	else:
		_new_game_button.focus_quietly()


func _show_options(open: bool) -> void:
	_column.visible = not open
	_confirm.visible = false
	_options.visible = open
	_reveal.reveal(Vector2(0.0 if Game.is_rtl() else 1.0, 0.5))
	_refresh_prompt()
	if open:
		_show_help("")
		_options.focus_first()
	else:
		_options_button.focus_quietly()


func _on_new_game_pressed() -> void:
	if Game.has_save():
		_show_confirm(true)
	else:
		Game.new_game()


func _on_mode_pressed() -> void:
	Game.toggle_mode()
	_refresh()


func _add_music() -> void:
	if not ResourceLoader.exists(music_path):
		return
	_music = AudioStreamPlayer.new()
	_music.stream = load(music_path) as AudioStream
	_music.bus = &"Music"
	_music.volume_db = -80.0
	add_child(_music)
	_music.play()


func _make_button(on_pressed: Callable) -> GlowButton:
	var button := GlowButton.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(on_pressed)
	button.help_shown.connect(_show_help)
	_column.add_child(button)
	return button


## A label lined up with the buttons' text (indented like them).
func _add_label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_indent(label)
	return label


## Adds control to the column, indented like the buttons' text.
func _indent(control: Control) -> void:
	var container := MarginContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(container)
	_indented.append(container)
	container.add_child(control)
