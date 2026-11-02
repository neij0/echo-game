class_name SkillChoiceScreen
extends CanvasLayer
## The skill choice between levels (StageManager._offer_skills), in the
## "silhouette + glow" style (Game.ui_theme). The screen is split, Echo on the
## left and Guardian on the right (where the players sit, so it is not
## mirrored in Arabic; the text inside each half is). Each half is uncovered
## by a pulse wipe (PulseReveal); each player moves through their own cards
## (SkillCard: a glowing edge in their colour, a sonar ripple and a soft ping
## when the cursor arrives) with their own controls (move up / down, action =
## pick / unpick; drawn prompts for the device they use, InputPrompt) and is
## ready once they picked enough. When both are ready, both choices are shown
## with their co-op tips for summary_time seconds, then choose() returns.
## Works while the game is paused. Builds its UI in code.

signal finished

@export var backdrop_color: Color = Color(0.0, 0.008, 0.02, 0.985)
@export var echo_color: Color = Color(0.45, 0.95, 1.0)
@export var guardian_color: Color = Color(0.95, 0.75, 0.4)
@export var name_font_size: int = 23
@export var text_font_size: int = 17
@export var icon_size: float = 52.0
@export var card_width: float = 520.0
@export var spacing: int = 12
@export var screen_margin: int = 36
## Seconds after opening before any input counts (so a held button from the
## level does not pick right away).
@export var input_delay: float = 0.5
## Seconds both choices stay on screen with their tips.
@export var summary_time: float = 2.0
@export var focus_sound: StringName = &"ui_focus"
@export var pick_sound: StringName = &"ui_press"


## One player's half of the screen.
class ChoiceSide:
	var player: Player
	var offer: Array[SkillDefinition] = []
	var need: int = 1
	var cursor: int = 0
	var picked: Array[int] = []
	var done: bool = false
	var color: Color
	var reveal: PulseReveal
	var root: VBoxContainer
	var header: Label
	var subheader: Label
	var cards: Array[SkillCard] = []
	var cards_box: VBoxContainer
	var prompt: InputPrompt
	var status: Label


var is_open: bool = false
var _sides: Array[ChoiceSide] = []
var _root: Control
var _title: Label
var _title_rule: WaveRule
var _columns: HBoxContainer
var _world: WorldConfig
var _delay_left: float = 0.0
var _summary: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = Game.ui_theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = backdrop_color
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, screen_margin)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", spacing)
	margin.add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_title_rule = WaveRule.new()
	_title_rule.custom_minimum_size = Vector2(260.0, 10.0)
	_title_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_title_rule)
	_columns = HBoxContainer.new()
	# Echo always left, Guardian always right (not mirrored in Arabic).
	_columns.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", spacing * 3)
	column.add_child(_columns)
	_root.visible = false


## Shows the offers and waits until both players picked. offers / pick_counts:
## Player -> Array[SkillDefinition] / int. Returns Player -> Array[SkillDefinition].
func choose(players: Array[Player], offers: Dictionary, pick_counts: Dictionary, world: WorldConfig) -> Dictionary:
	_world = world
	Game.apply_direction(_root)
	_build_sides(players, offers, pick_counts)
	_summary = false
	_delay_left = input_delay
	_title.text = Game.text("skill_choice_title")
	_root.visible = true
	is_open = true
	_reveal_sides()
	if _all_done():
		await get_tree().process_frame
	else:
		await finished
	var result: Dictionary = get_picks()
	await _show_summary()
	_root.visible = false
	is_open = false
	return result


## Player -> Array[SkillDefinition] picked so far.
func get_picks() -> Dictionary:
	var result: Dictionary = {}
	for side: ChoiceSide in _sides:
		var picks: Array[SkillDefinition] = []
		for index: int in side.picked:
			picks.append(side.offer[index])
		result[side.player] = picks
	return result


## For tests and the player's own input: move one side's cursor.
func move_cursor(player: Player, step: int) -> void:
	var side: ChoiceSide = _side_of(player)
	if side == null or side.done or side.offer.is_empty():
		return
	side.cursor = posmod(side.cursor + step, side.offer.size())
	UiAudio.play_in(get_tree(), focus_sound)
	_refresh_side(side)


## For tests and the player's own input: pick / unpick the card under the cursor.
func press_pick(player: Player) -> void:
	var side: ChoiceSide = _side_of(player)
	if side == null or side.done or side.offer.is_empty():
		return
	if side.cursor in side.picked:
		side.picked.erase(side.cursor)
	else:
		side.picked.append(side.cursor)
	if side.picked.size() >= side.need:
		side.done = true
	UiAudio.play_in(get_tree(), pick_sound)
	_refresh_side(side)
	if _all_done():
		finished.emit()


func _process(delta: float) -> void:
	if not is_open or _summary:
		return
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	for side: ChoiceSide in _sides:
		var prefix: String = side.player.input_prefix
		if Input.is_action_just_pressed(prefix + "move_up"):
			move_cursor(side.player, -1)
		elif Input.is_action_just_pressed(prefix + "move_down"):
			move_cursor(side.player, 1)
		if Input.is_action_just_pressed(prefix + "action"):
			press_pick(side.player)


func _all_done() -> bool:
	for side: ChoiceSide in _sides:
		if not side.done:
			return false
	return true


func _side_of(player: Player) -> ChoiceSide:
	for side: ChoiceSide in _sides:
		if side.player == player:
			return side
	return null


## Each half is uncovered by a pulse from the top of its column.
func _reveal_sides() -> void:
	for side: ChoiceSide in _sides:
		side.reveal.reveal(Vector2(0.5, 0.0))


func _build_sides(players: Array[Player], offers: Dictionary, pick_counts: Dictionary) -> void:
	for child: Node in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	_sides.clear()
	for player: Player in players:
		var side := ChoiceSide.new()
		side.player = player
		side.offer.assign(offers.get(player, []))
		side.need = int(pick_counts.get(player, 1))
		side.done = side.need <= 0 or side.offer.is_empty()
		var is_echo: bool = player.skill_owner == SkillDefinition.Owner.ECHO
		side.color = echo_color if is_echo else guardian_color
		side.reveal = PulseReveal.new()
		side.reveal.ring_color = Color(side.color * 1.3, 0.9)
		side.reveal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_columns.add_child(side.reveal)
		side.root = VBoxContainer.new()
		side.root.add_theme_constant_override("separation", spacing)
		Game.apply_direction(side.root)
		side.reveal.add_child(side.root)
		side.header = _label(side.root, &"EchoLabel" if is_echo else &"GuardianLabel")
		side.subheader = _label(side.root, &"DimLabel")
		side.cards_box = VBoxContainer.new()
		side.cards_box.add_theme_constant_override("separation", spacing)
		side.root.add_child(side.cards_box)
		for definition: SkillDefinition in side.offer:
			var owned: int = player.skills.get_rank(definition.id)
			var card := SkillCard.new()
			card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			side.cards_box.add_child(card)
			card.setup(definition, owned, definition.display_name(Game.language, _world), _kind_text(definition, owned),
				definition.description(Game.language, _world), side.color, card_width, icon_size, name_font_size, text_font_size, spacing)
			side.cards.append(card)
		side.prompt = InputPrompt.new()
		side.prompt.alignment = BoxContainer.ALIGNMENT_CENTER
		side.root.add_child(side.prompt)
		side.prompt.setup([
			{"actions": [StringName(player.input_prefix + "move_up"), StringName(player.input_prefix + "move_down")],
				"text": Game.text("prompt_choose")},
			{"actions": [StringName(player.input_prefix + "action")], "text": Game.text("prompt_pick")},
		], InputGlyph.Device.GAMEPAD if player.uses_gamepad else InputGlyph.Device.KEYBOARD)
		side.status = _label(side.root, &"EchoLabel" if is_echo else &"GuardianLabel")
		side.status.add_theme_font_size_override("font_size", name_font_size)
		_sides.append(side)
		_refresh_side(side)


## "New - Active (skill button) - Shared", "Rank 2"...
func _kind_text(definition: SkillDefinition, owned: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if definition.is_fallback:
		parts.append(Game.text("skill_fallback"))
	elif owned > 0:
		parts.append(Game.text("skill_rank") % [owned + 1, definition.max_rank])
	else:
		parts.append(Game.text("skill_new"))
	if not definition.is_fallback:
		parts.append(Game.text("skill_active" if definition.is_active() else "skill_passive"))
	if definition.owner == SkillDefinition.Owner.SHARED and not definition.is_fallback:
		parts.append(Game.text("skill_shared"))
	return "  ·  ".join(parts)


func _refresh_side(side: ChoiceSide) -> void:
	var is_echo: bool = side.player.skill_owner == SkillDefinition.Owner.ECHO
	side.header.text = Game.text("char_echo" if is_echo else "char_guardian")
	side.subheader.text = Game.text("skill_pick") % [side.need, side.offer.size()]
	side.prompt.visible = not side.done
	side.status.text = Game.text("skill_waiting") if side.done else ""
	for i: int in side.cards.size():
		side.cards[i].set_state(i == side.cursor and not side.done, i in side.picked)


## Both choices with their co-op tips, then a short wait.
func _show_summary() -> void:
	_summary = true
	_title.text = Game.text("skill_summary_title")
	for side: ChoiceSide in _sides:
		for card: SkillCard in side.cards:
			card.queue_free()
		side.cards.clear()
		side.prompt.visible = false
		side.status.text = ""
		side.subheader.text = ""
		for index: int in side.picked:
			var definition: SkillDefinition = side.offer[index]
			var rank: int = side.player.skills.get_rank(definition.id) + 1
			var card := SkillCard.new()
			card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			side.cards_box.add_child(card)
			var rank_text: String = Game.text("skill_rank") % [rank, definition.max_rank] if definition.max_rank > 1 else ""
			card.setup(definition, rank - 1, definition.display_name(Game.language, _world), rank_text,
				definition.tip(Game.language, _world), side.color, card_width, icon_size, name_font_size, text_font_size, spacing)
			card.set_state(false, true)
			side.cards.append(card)
		side.reveal.reveal(Vector2(0.5, 0.0))
	await get_tree().create_timer(summary_time, true).timeout
	_summary = false


func _label(parent: Control, variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label
