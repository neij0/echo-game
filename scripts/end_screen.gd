class_name EndScreen
extends CanvasLayer
## The in-game screens in the "silhouette + glow" style (Game.ui_theme): the
## defeat screen (what took each player, in their colour; retries on its own
## after death_restart_delay, a glowing line counting it down), the short
## "Level cleared" card between levels, and the stage summary after the boss
## (its stats in two columns, Continue moves on). Each is uncovered by a pulse
## wipe (PulseReveal) over a dark veil; buttons are GlowButtons with drawn
## prompts. Works while the game is paused. Arabic is laid out right-to-left.
## The StageManager hides it (hide_screen) once the screen has faded to black.

signal restart_requested
signal continue_requested

## Seconds the defeat screen stays before the retry starts on its own.
@export var death_restart_delay: float = 3.0
@export var cleared_backdrop: Color = Color(0.0, 0.008, 0.02, 0.74)
@export var defeat_backdrop: Color = Color(0.02, 0.0, 0.01, 0.82)
@export var summary_backdrop: Color = Color(0.0, 0.008, 0.02, 0.94)
@export var title_font_size: int = 50
@export var subtitle_font_size: int = 22
@export var spacing: int = 10
@export var column_width: float = 560.0
@export var victory_rule_color: Color = Color(1.25, 1.0, 0.55, 0.75)
@export var defeat_rule_color: Color = Color(1.3, 0.35, 0.3, 0.7)
@export var countdown_color: Color = Color(1.2, 0.4, 0.34, 0.85)
@export var rule_size: Vector2 = Vector2(220.0, 26.0)

var _root: Control
var _backdrop: ColorRect
var _reveal: PulseReveal
var _title: Label
var _subtitle: Label
var _rule: WaveRule
var _body: VBoxContainer
var _countdown: Control
var _button: GlowButton
var _prompt: InputPrompt
var _button_emits_continue: bool = false
## Counts defeat screens, so an old auto-retry timer never fires on a newer one.
var _defeat_count: int = 0
## Seconds left before the automatic retry (the countdown line).
var _countdown_left: float = 0.0
var _answered: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = Game.ui_theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_reveal = PulseReveal.new()
	_reveal.custom_minimum_size.x = column_width
	center.add_child(_reveal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", spacing)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal.add_child(column)

	_title = _make_label(column, &"HeaderLabel", title_font_size)
	_subtitle = _make_label(column, &"DimLabel", subtitle_font_size)
	_rule = WaveRule.new()
	_rule.custom_minimum_size = rule_size
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_rule)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	_countdown = Control.new()
	_countdown.custom_minimum_size = Vector2(rule_size.x, 10.0)
	_countdown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_countdown.draw.connect(_draw_countdown)
	column.add_child(_countdown)
	_button = GlowButton.new()
	_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_on_button_pressed)
	column.add_child(_button)
	_prompt = InputPrompt.new()
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_prompt)
	_root.visible = false


func _process(delta: float) -> void:
	if _countdown_left > 0.0 and _root.visible:
		_countdown_left = maxf(_countdown_left - delta, 0.0)
		_countdown.queue_redraw()


## Both players are down: show what took each of them, then retry (the level
## in Calm, the stage from level 1 in Challenge).
func show_defeat(players: Array[Player], stage_number: int, level_number: int, level_count: int, mode: SaveData.Mode) -> void:
	_start(defeat_backdrop, &"DangerLabel", defeat_rule_color)
	_title.text = Game.text("defeat_title")
	_subtitle.text = Game.text("reached") % [stage_number, level_number, level_count]
	for player: Player in players:
		var reason: String = Game.text("cause_creature")
		if player.health.last_cause == PlayerHealth.Cause.PRESSURE:
			reason = Game.text("cause_pressure") % _pressure_name(player)
		elif player.health.last_cause == PlayerHealth.Cause.COLLAPSE:
			reason = Game.text("cause_collapse")
		_add_pair(_character_name(player), reason, _character_variation(player), &"Label")
	var restart: Label = _make_label(_body, &"DimLabel", 18)
	restart.text = Game.text("restart_level") % level_number if mode == SaveData.Mode.CALM else Game.text("restart_stage")
	_countdown_left = death_restart_delay
	_countdown.visible = true
	_show_button(Game.text("retry"), false)
	_open()
	_defeat_count += 1
	var this_defeat: int = _defeat_count
	await get_tree().create_timer(death_restart_delay, true).timeout
	if _root.visible and not _button_emits_continue and this_defeat == _defeat_count and not _answered:
		_answered = true
		restart_requested.emit()


## Short card between two levels (no button; the StageManager hides it).
func show_level_cleared(level_number: int, level_count: int) -> void:
	_start(cleared_backdrop, &"HeaderLabel", victory_rule_color)
	_title.text = Game.text("level_cleared") % level_number
	_subtitle.text = Game.text("going_deeper") % [level_number + 1, level_count]
	_button.visible = false
	_prompt.visible = false
	_open(false)


func hide_screen() -> void:
	_root.visible = false
	_countdown_left = 0.0


func is_showing() -> bool:
	return _root.visible


## The stage is complete (the boss fell): stats, then Continue.
func show_stage_cleared(stage_number: int, beat_boss: bool, saved: bool, stage_time: float, pulses: int, hits: int, kills: int, players: Array[Player]) -> void:
	_start(summary_backdrop, &"HeaderLabel", victory_rule_color)
	_title.text = Game.text("stage_cleared") % stage_number
	_subtitle.text = Game.text("boss_down") if beat_boss else ""
	_subtitle.visible = beat_boss
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(grid)
	_add_stat(grid, Game.text("stat_time"), _value("%d:%02d" % [floori(stage_time / 60.0), floori(stage_time) % 60]))
	_add_stat(grid, Game.text("stat_pulses"), _value(str(pulses)))
	_add_stat(grid, Game.text("stat_hits"), _value(str(hits)))
	_add_stat(grid, Game.text("stat_kills"), _value(str(kills)))
	if not players.is_empty():
		var meters := HBoxContainer.new()
		meters.add_theme_constant_override("separation", 14)
		meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for player: Player in players:
			var value := Label.new()
			value.theme_type_variation = _character_variation(player)
			value.add_theme_font_size_override("font_size", 20)
			value.text = "%s %d%%" % [_character_name(player), roundi(player.pressure.get_ratio() * 100.0)]
			meters.add_child(value)
		_add_stat(grid, Game.text("stat_pressure") % _pressure_name(players[0]).capitalize(), meters)
	if saved:
		var saved_label: Label = _make_label(_body, &"EchoLabel", 18)
		saved_label.text = Game.text("progress_saved")
	_show_button(Game.text("continue"), true)
	_open()


## Clears the last screen's content and sets this one's look.
func _start(backdrop: Color, title_variation: StringName, rule_color: Color) -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_backdrop.color = backdrop
	_title.theme_type_variation = title_variation
	_title.add_theme_font_size_override("font_size", title_font_size)
	_subtitle.visible = true
	_rule.color = rule_color
	_countdown.visible = false
	_countdown_left = 0.0
	_answered = false


func _value(text: String) -> Label:
	var shown := Label.new()
	shown.theme_type_variation = &"StatValueLabel"
	shown.text = text
	return shown


func _add_stat(grid: GridContainer, key_text: String, value: Control) -> void:
	var key := Label.new()
	key.theme_type_variation = &"DimLabel"
	key.add_theme_font_size_override("font_size", 20)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.text = key_text
	grid.add_child(key)
	grid.add_child(value)


## "Echo — caught by a creature": the name in the character's colour.
func _add_pair(who_text: String, what_text: String, name_variation: StringName, text_variation: StringName) -> void:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var who := Label.new()
	who.theme_type_variation = name_variation
	who.add_theme_font_size_override("font_size", 22)
	who.text = who_text
	line.add_child(who)
	var what := Label.new()
	what.theme_type_variation = text_variation
	what.add_theme_font_size_override("font_size", 20)
	what.text = what_text
	line.add_child(what)
	_body.add_child(line)


func _character_name(player: Player) -> String:
	return Game.text("char_echo" if player.skill_owner == SkillDefinition.Owner.ECHO else "char_guardian")


func _character_variation(player: Player) -> StringName:
	return &"EchoLabel" if player.skill_owner == SkillDefinition.Owner.ECHO else &"GuardianLabel"


func _pressure_name(player: Player) -> String:
	var key: String = "pressure_" + player.pressure.pressure_name
	var translated: String = Game.text(key)
	return player.pressure.pressure_name.to_lower() if translated == key else translated


func _show_button(label: String, emits_continue: bool) -> void:
	_button.text = label
	_button_emits_continue = emits_continue
	_button.visible = true
	_button.disabled = false
	_prompt.visible = true
	_prompt.setup([{"actions": [&"ui_accept"], "text": label}], InputPrompt.menu_device, true)


func _open(take_focus: bool = true) -> void:
	Game.apply_direction(_root)
	_root.visible = true
	_reveal.reveal(Vector2(0.5, 0.45))
	if take_focus:
		_button.focus_quietly()


func _make_label(parent: Control, variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = column_width
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


## The automatic retry: a glowing line that shrinks to its middle.
func _draw_countdown() -> void:
	if death_restart_delay <= 0.0:
		return
	var share: float = _countdown_left / death_restart_delay
	var width: float = _countdown.size.x * share
	var y: float = _countdown.size.y * 0.5
	var start := Vector2((_countdown.size.x - width) * 0.5, y)
	if width > 1.0:
		GlowFx.glow_line(_countdown, PackedVector2Array([start, start + Vector2(width, 0.0)]), countdown_color, 1.4)


## The screen stays up (the StageManager hides it once the screen is black).
func _on_button_pressed() -> void:
	if _answered:
		return
	_answered = true
	_button.disabled = true
	_countdown_left = 0.0
	if _button_emits_continue:
		continue_requested.emit()
	else:
		restart_requested.emit()
