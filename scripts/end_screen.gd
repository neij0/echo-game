class_name EndScreen
extends CanvasLayer
## The in-game screens: the defeat screen (cause per player; retries on its own
## after death_restart_delay), the short "Level cleared" screen between levels,
## and the stage summary after the boss (its Continue button moves on).
## Works while the game is paused. Builds its UI in code (grey-box). Text comes
## from Game.text, in the language picked in the main menu.

signal restart_requested
signal continue_requested

## Seconds the defeat screen stays before the retry starts on its own.
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
var _button_emits_continue: bool = false
## Counts defeat screens, so an old auto-retry timer never fires on a newer one.
var _defeat_count: int = 0


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
	_button.add_theme_font_size_override("font_size", text_font_size)
	_button.pressed.connect(_on_button_pressed)
	column.add_child(_button)

	_root.visible = false


## Both players are down: show what took each of them, then retry (the level
## in Calm, the stage from level 1 in Challenge).
func show_defeat(players: Array[Player], stage_number: int, level_number: int, level_count: int, mode: SaveData.Mode) -> void:
	_title.text = Game.text("defeat_title")
	_title.add_theme_color_override("font_color", death_title_color)
	var lines: PackedStringArray = PackedStringArray()
	for player: Player in players:
		var reason: String = Game.text("cause_creature")
		if player.health.last_cause == PlayerHealth.Cause.PRESSURE:
			reason = Game.text("cause_pressure") % _pressure_name(player)
		lines.append("%s: %s" % [player.display_name, reason])
	lines.append(Game.text("reached") % [stage_number, level_number, level_count])
	lines.append("")
	if mode == SaveData.Mode.CALM:
		lines.append(Game.text("restart_level") % level_number)
	else:
		lines.append(Game.text("restart_stage"))
	_body.text = "\n".join(lines)
	_show_button(Game.text("retry"), false)
	_open()
	_defeat_count += 1
	var this_defeat: int = _defeat_count
	await get_tree().create_timer(death_restart_delay, true).timeout
	if _root.visible and not _button_emits_continue and this_defeat == _defeat_count:
		_root.visible = false
		restart_requested.emit()


## Short screen between two levels (no button; the StageManager hides it).
func show_level_cleared(level_number: int, level_count: int) -> void:
	_title.text = Game.text("level_cleared") % level_number
	_title.add_theme_color_override("font_color", victory_title_color)
	_body.text = Game.text("going_deeper") % [level_number + 1, level_count]
	_button.visible = false
	Game.apply_direction(_root)
	_root.visible = true


func hide_screen() -> void:
	_root.visible = false


## The stage is complete (the boss fell): stats, then Continue.
func show_stage_cleared(stage_number: int, beat_boss: bool, saved: bool, stage_time: float, pulses: int, hits: int, kills: int, players: Array[Player]) -> void:
	_title.text = Game.text("stage_cleared") % stage_number
	_title.add_theme_color_override("font_color", victory_title_color)
	var minutes: int = floori(stage_time / 60.0)
	var seconds: int = floori(stage_time) % 60
	var pressure_parts: PackedStringArray = PackedStringArray()
	for player: Player in players:
		pressure_parts.append("%s %d%%" % [player.display_name, roundi(player.pressure.get_ratio() * 100.0)])
	var pressure_name: String = _pressure_name(players[0]) if not players.is_empty() else ""
	var lines: PackedStringArray = PackedStringArray()
	if beat_boss:
		lines.append(Game.text("boss_down"))
	lines.append(Game.text("stat_time") % [minutes, seconds])
	lines.append(Game.text("stat_pulses") % pulses)
	lines.append(Game.text("stat_hits") % hits)
	lines.append(Game.text("stat_kills") % kills)
	lines.append(Game.text("stat_pressure") % [pressure_name.capitalize(), " / ".join(pressure_parts)])
	if saved:
		lines.append("")
		lines.append(Game.text("progress_saved"))
	_body.text = "\n".join(lines)
	_show_button(Game.text("continue"), true)
	_open()


func _pressure_name(player: Player) -> String:
	var key: String = "pressure_" + player.pressure.pressure_name
	var translated: String = Game.text(key)
	return player.pressure.pressure_name.to_lower() if translated == key else translated


func _show_button(label: String, emits_continue: bool) -> void:
	_button.text = label
	_button_emits_continue = emits_continue
	_button.visible = true


func _open() -> void:
	Game.apply_direction(_root)
	_root.visible = true
	_button.grab_focus()


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_button_pressed() -> void:
	_root.visible = false
	if _button_emits_continue:
		continue_requested.emit()
	else:
		restart_requested.emit()
