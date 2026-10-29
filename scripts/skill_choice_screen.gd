class_name SkillChoiceScreen
extends CanvasLayer
## The skill choice between levels (StageManager._offer_skills): the screen is
## split, Echo on the left and Guardian on the right (where the players sit, so
## it is not mirrored in Arabic; the text inside each half is). Each player
## moves through their own cards with their own controls (move up / down,
## action = pick / unpick) and is ready once they picked enough. When both are
## ready, both choices are shown with their co-op tips for summary_time
## seconds, then choose() returns. Works while the game is paused. Builds its
## UI in code (functional styling only for now).

signal finished

@export var backdrop_color: Color = Color(0.0, 0.01, 0.03, 0.88)
@export var title_color: Color = Color(1.0, 0.9, 0.6)
@export var text_color: Color = Color(0.85, 0.9, 1.0)
@export var dim_text_color: Color = Color(0.6, 0.66, 0.78)
@export var echo_color: Color = Color(0.45, 0.95, 1.0)
@export var guardian_color: Color = Color(1.0, 0.8, 0.35)
@export var card_color: Color = Color(0.06, 0.08, 0.13, 0.95)
@export var card_border_color: Color = Color(0.2, 0.25, 0.35)
@export var picked_color: Color = Color(0.2, 0.17, 0.08, 0.95)
@export var picked_border_color: Color = Color(1.0, 0.85, 0.45)
@export var title_font_size: int = 36
@export var header_font_size: int = 28
@export var name_font_size: int = 22
@export var text_font_size: int = 17
@export var icon_size: float = 52.0
@export var card_width: float = 520.0
@export var spacing: int = 12
## Seconds after opening before any input counts (so a held button from the
## level does not pick right away).
@export var input_delay: float = 0.5
## Seconds both choices stay on screen with their tips.
@export var summary_time: float = 2.0


## One player's half of the screen.
class ChoiceSide:
	var player: Player
	var offer: Array[SkillDefinition] = []
	var need: int = 1
	var cursor: int = 0
	var picked: Array[int] = []
	var done: bool = false
	var color: Color
	var root: VBoxContainer
	var header: Label
	var subheader: Label
	var cards: Array[PanelContainer] = []
	var cards_box: VBoxContainer
	var hint: Label
	var status: Label


var is_open: bool = false
var _sides: Array[ChoiceSide] = []
var _root: ColorRect
var _title: Label
var _columns: HBoxContainer
var _world: WorldConfig
var _delay_left: float = 0.0
var _summary: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = ColorRect.new()
	_root.color = backdrop_color
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", spacing * 2)
	margin.add_child(column)
	_title = _label(title_font_size, title_color)
	column.add_child(_title)
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
	_build_sides(players, offers, pick_counts)
	_summary = false
	_delay_left = input_delay
	_title.text = Game.text("skill_choice_title")
	_root.visible = true
	is_open = true
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


func _build_sides(players: Array[Player], offers: Dictionary, pick_counts: Dictionary) -> void:
	for child: Node in _columns.get_children():
		child.queue_free()
	_sides.clear()
	for player: Player in players:
		var side := ChoiceSide.new()
		side.player = player
		side.offer.assign(offers.get(player, []))
		side.need = int(pick_counts.get(player, 1))
		side.done = side.need <= 0 or side.offer.is_empty()
		side.color = echo_color if player.skill_owner == SkillDefinition.Owner.ECHO else guardian_color
		side.root = VBoxContainer.new()
		side.root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.root.add_theme_constant_override("separation", spacing)
		Game.apply_direction(side.root)
		_columns.add_child(side.root)
		side.header = _label(header_font_size, side.color)
		side.root.add_child(side.header)
		side.subheader = _label(text_font_size, dim_text_color)
		side.root.add_child(side.subheader)
		side.cards_box = VBoxContainer.new()
		side.cards_box.add_theme_constant_override("separation", spacing)
		side.root.add_child(side.cards_box)
		for definition: SkillDefinition in side.offer:
			var card: PanelContainer = _make_card(definition, player)
			side.cards.append(card)
			side.cards_box.add_child(card)
		side.hint = _label(text_font_size, dim_text_color)
		side.root.add_child(side.hint)
		side.status = _label(name_font_size, title_color)
		side.root.add_child(side.status)
		_sides.append(side)
		_refresh_side(side)


func _make_card(definition: SkillDefinition, player: Player) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = card_width
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", spacing)
	card.add_child(row)
	var icon := SkillIcon.new()
	var owned: int = player.skills.get_rank(definition.id)
	icon.setup(definition, owned, icon_size)
	icon.preview_rank = owned + 1
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var title := _label(name_font_size, text_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text = definition.display_name(Game.language, _world)
	texts.add_child(title)
	var kind_label := _label(text_font_size - 2, definition.icon_color)
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	kind_label.text = _kind_text(definition, owned)
	texts.add_child(kind_label)
	var body := _label(text_font_size, dim_text_color)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = card_width - icon_size - spacing * 3
	body.text = definition.description(Game.language, _world)
	texts.add_child(body)
	return card


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
	side.hint.text = Game.text("skill_hint_echo" if is_echo else "skill_hint_guardian")
	side.hint.visible = not side.done
	side.status.text = Game.text("skill_waiting") if side.done else ""
	for i: int in side.cards.size():
		var style := StyleBoxFlat.new()
		var is_picked: bool = i in side.picked
		style.bg_color = picked_color if is_picked else card_color
		var focused: bool = i == side.cursor and not side.done
		style.border_color = side.color if focused else (picked_border_color if is_picked else card_border_color)
		style.set_border_width_all(3 if focused or is_picked else 1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		side.cards[i].add_theme_stylebox_override("panel", style)


## Both choices with their co-op tips, then a short wait.
func _show_summary() -> void:
	_summary = true
	_title.text = Game.text("skill_summary_title")
	for side: ChoiceSide in _sides:
		for card: PanelContainer in side.cards:
			card.queue_free()
		side.cards.clear()
		side.hint.visible = false
		side.status.text = ""
		side.subheader.text = ""
		for index: int in side.picked:
			var definition: SkillDefinition = side.offer[index]
			var name_label := _label(name_font_size, definition.icon_color)
			var rank: int = side.player.skills.get_rank(definition.id) + 1
			name_label.text = definition.display_name(Game.language, _world)
			if definition.max_rank > 1:
				name_label.text += "  " + Game.text("skill_rank") % [rank, definition.max_rank]
			side.cards_box.add_child(name_label)
			var tip_label := _label(text_font_size, text_color)
			tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip_label.custom_minimum_size.x = card_width
			tip_label.text = definition.tip(Game.language, _world)
			side.cards_box.add_child(tip_label)
	await get_tree().create_timer(summary_time, true).timeout
	_summary = false


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
