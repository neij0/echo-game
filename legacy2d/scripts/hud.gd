class_name Hud
extends CanvasLayer
## The in-game HUD in the "silhouette + glow" style (Game.ui_theme), readable
## and minimal: one PlayerStatus per registered player on its own screen edge
## (the Echo top left, the Guardian top right: where the players sit, so it is
## not mirrored in Arabic; the texts are), and between them, centred at the
## top, the shared parts: Depth Awareness (a thin glowing meter from calm blue
## to danger red) and the Echo Shards (ShardPips; its line of text, the exit /
## arena door open, fades after done_text_time), then the collapse escape timer.
## Never holds a single fixed player. The debug lines (stage, level, mode,
## seed, abilities, creatures, chase speeds) sit at the bottom left behind
## debug_toggle_key (F1): hidden in normal play, shown when running from the
## editor. A dark gradient along the top edge sits behind the blocks (top_shade:
## nearly opaque behind the texts, fading out below them), so no world or sonar
## line crosses a HUD text. Other screen parts (the boss health bar) ask
## get_occupied_rects() to stay clear of it.

@export var stage_manager: StageManager
@export var awareness: DepthAwareness
@export var level_builder: LevelBuilder
@export var escape_event: EscapeEvent

@export_group("Layout")
## Space between the HUD and the screen edges (pixels).
@export var screen_margin: Vector2 = Vector2(26.0, 20.0)

@export_group("Top Shade")
## The dark gradient behind the HUD at the top edge: its colour at the top
## (alpha; opaque: the sonar lines are over-bright, any see-through shows them),
## the share of its height it stays that dark, and how far it reaches
## below the lowest HUD block (pixels) while fading out.
@export var top_shade_color: Color = Color(0.0, 0.004, 0.012, 1.0)
@export_range(0.0, 1.0) var top_shade_hold: float = 0.55
@export var top_shade_fade: float = 110.0

@export_group("Debug")
@export var debug_toggle_key: Key = KEY_F1
@export var debug_font_size: int = 13

@export_group("Awareness")
@export var calm_color: Color = Color(0.35, 0.6, 1.0)
@export var warning_color: Color = Color(1.0, 0.22, 0.18)
@export var awareness_size: Vector2 = Vector2(220.0, 8.0)
## Above this share the meter breathes.
@export var awareness_alarm: float = 0.75

@export_group("Shard Counter")
@export var shard_counter_color: Color = Color(0.55, 0.95, 1.0)
## Colour of the text once every shard is collected.
@export var shard_done_color: Color = Color(1.0, 0.82, 0.35)
## Seconds the "exit open" line stays before it fades (the gold pips stay).
@export var done_text_time: float = 6.0
@export var done_text_fade: float = 1.5

@export_group("Escape Timer")
@export var escape_font_size: int = 30
@export var escape_color: Color = Color(1.0, 0.8, 0.45)
## Below this many seconds the timer turns red and blinks.
@export var escape_warning_time: float = 10.0
@export var escape_warning_color: Color = Color(1.0, 0.25, 0.2)
@export var escape_blink_speed: float = 2.0

@onready var _debug_label: Label = $DebugLabel
@onready var _statuses: Control = $PlayerStatuses

var _center: VBoxContainer
var _top_shade: TextureRect
var _awareness_caption: Label
var _awareness_meter: HudMeter
var _shard_pips: ShardPips
var _shard_label: Label
var _escape_label: Label
var _time: float = 0.0
## Seconds since every shard was collected (< 0: not yet).
var _done_age: float = -1.0


func _ready() -> void:
	add_to_group("hud")
	_debug_label.visible = OS.has_feature("editor")
	_debug_label.theme = Game.ui_theme
	_debug_label.theme_type_variation = &"DimLabel"
	_debug_label.add_theme_font_size_override("font_size", debug_font_size)
	_debug_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_statuses.theme = Game.ui_theme
	_statuses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_shade = TextureRect.new()
	_top_shade.name = "TopShade"
	_top_shade.texture = _top_shade_texture()
	_top_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_shade)
	# Behind every HUD part (the hurt vignette stays first, it is a screen edge effect).
	move_child(_top_shade, 1)

	_center = VBoxContainer.new()
	_center.name = "SharedStatus"
	_center.theme = Game.ui_theme
	_center.alignment = BoxContainer.ALIGNMENT_BEGIN
	_center.add_theme_constant_override("separation", 3)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_awareness_caption = _label(&"DimLabel", 13)
	_awareness_meter = HudMeter.new()
	_awareness_meter.custom_minimum_size = awareness_size
	_awareness_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_center.add_child(_awareness_meter)
	_shard_pips = ShardPips.new()
	_shard_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_center.add_child(_shard_pips)
	_shard_label = _label(&"Label", 15)
	_shard_label.name = "ShardCounter"
	_escape_label = _label(&"Label", escape_font_size)
	_escape_label.name = "EscapeTimer"
	_escape_label.visible = false

	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)
		stage_manager.shards_changed.connect(_on_shards_changed)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == debug_toggle_key:
		set_debug_visible(not _debug_label.visible)
		get_viewport().set_input_as_handled()


func set_debug_visible(shown: bool) -> void:
	_debug_label.visible = shown


func is_debug_visible() -> bool:
	return _debug_label.visible


## Screen rects of the HUD parts showing right now (labels by their text).
func get_occupied_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var parts: Array[Control] = [_debug_label, _awareness_caption, _awareness_meter, _shard_pips, _shard_label, _escape_label]
	for child: Node in _statuses.get_children():
		if child is Control:
			parts.append(child as Control)
	for control: Control in parts:
		if control == null or not control.is_visible_in_tree() or control.modulate.a <= 0.01:
			continue
		var label := control as Label
		if label and label.text.is_empty():
			continue
		rects.append(control.get_global_rect())
	return rects


func _on_shards_changed(collected: int, total: int) -> void:
	_shard_pips.set_progress(collected, total)
	_shard_label.modulate.a = 1.0
	if total > 0 and collected >= total:
		_shard_label.text = Game.text("arena_open" if stage_manager.is_boss_level() else "exit_open")
		_shard_label.add_theme_color_override("font_color", shard_done_color)
		_done_age = 0.0
	else:
		_shard_label.text = Game.text("shards") % [collected, total]
		_shard_label.add_theme_color_override("font_color", shard_counter_color)
		_done_age = -1.0


func _on_player_registered(player: Player) -> void:
	var status := PlayerStatus.new()
	status.setup(player, level_builder, stage_manager.world if stage_manager else null)
	_statuses.add_child(status)


func _process(delta: float) -> void:
	_time += delta
	_layout()
	_update_escape_timer()
	var share: float = awareness.get_ratio()
	_awareness_caption.text = Game.text("hud_awareness")
	_awareness_meter.ratio = share
	_awareness_meter.color = calm_color.lerp(warning_color, share)
	_awareness_meter.pulsing = share >= awareness_alarm
	if _done_age >= 0.0:
		_done_age += delta
		_shard_label.modulate.a = clampf(1.0 - (_done_age - done_text_time) / done_text_fade, 0.0, 1.0)
	if _debug_label.visible:
		_debug_label.text = _debug_text()


## The players' blocks on their screen edges, the shared parts centred at the
## top, the debug lines at the bottom left.
func _layout() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	for child: Node in _statuses.get_children():
		var status := child as PlayerStatus
		if status == null:
			continue
		status.size = status.get_combined_minimum_size()
		if status.side == PlayerStatus.ScreenSide.LEFT:
			status.position = screen_margin
		else:
			status.position = Vector2(screen.x - screen_margin.x - status.size.x, screen_margin.y)
	_center.size = Vector2(maxf(_center.get_combined_minimum_size().x, 360.0), 0.0)
	_center.position = Vector2((screen.x - _center.size.x) * 0.5, screen_margin.y - 4.0)
	var lowest: float = _center.position.y + _center.get_combined_minimum_size().y
	for child: Node in _statuses.get_children():
		var block := child as Control
		if block:
			lowest = maxf(lowest, block.position.y + block.size.y)
	var height: float = lowest + top_shade_fade
	_top_shade.position = Vector2.ZERO
	_top_shade.size = Vector2(screen.x, height)
	_debug_label.size = _debug_label.get_combined_minimum_size()
	_debug_label.position = Vector2(screen_margin.x, screen.y - screen_margin.y - _debug_label.size.y)


## Vertical: top_shade_color down to top_shade_hold of the height, then clear.
func _top_shade_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, top_shade_color)
	gradient.set_color(1, Color(top_shade_color, 0.0))
	gradient.add_point(top_shade_hold, top_shade_color)
	gradient.add_point(lerpf(top_shade_hold, 1.0, 0.5), Color(top_shade_color, top_shade_color.a * 0.35))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = 128
	return texture


func _update_escape_timer() -> void:
	var active: bool = escape_event != null and escape_event.is_active
	_escape_label.visible = active
	if not active:
		return
	var seconds: int = ceili(escape_event.time_left)
	_escape_label.text = Game.text("escape_timer") % seconds
	var warning: bool = escape_event.time_left <= escape_warning_time
	_escape_label.add_theme_color_override("font_color", escape_warning_color if warning else escape_color)
	_escape_label.modulate.a = 1.0 if not warning or fmod(_time * escape_blink_speed, 1.0) < 0.7 else 0.25


func _label(variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(label)
	return label


func _debug_text() -> String:
	# How many creatures are in each state (WANDER / INVESTIGATE / CHASE).
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(Creature.State.size())
	counts.fill(0)
	var creatures: Array[Node] = get_tree().get_nodes_in_group("creatures")
	for node: Node in creatures:
		var creature := node as Creature
		if creature:
			counts[creature.state] += 1
	var state_counts: PackedStringArray = PackedStringArray()
	for state_index: int in Creature.State.size():
		state_counts.append("%s %d" % [Creature.State.keys()[state_index], counts[state_index]])

	var lines: PackedStringArray = PackedStringArray()
	if stage_manager and level_builder:
		lines.append("Stage %d   Level %d / %d%s   Mode: %s   Spawn seed %d (try %d)" % [
			stage_manager.stage_index + 1, stage_manager.level_index + 1, stage_manager.get_level_count(),
			" (boss)" if stage_manager.is_boss_level() else "",
			SaveData.Mode.keys()[stage_manager.mode].capitalize(),
			level_builder.spawn_seed, level_builder.attempts_used,
		])
	lines.append("Awareness: %.1f / %.0f" % [awareness.value, awareness.max_value])
	if stage_manager:
		lines.append("Shards: %d / %d" % [stage_manager.shards_collected, stage_manager.shards_total])
		for player: Player in stage_manager.players:
			lines.append("P%d %s: %s" % [player.player_number, player.display_name, _ability_text(player)])
			var nearest: Creature = _nearest_creature(creatures, player.global_position)
			if nearest:
				lines.append("P%d nearest creature: %s (%d px), chase %d px/s vs player %d px/s" % [
					player.player_number,
					nearest.get_state_name(),
					roundi(nearest.global_position.distance_to(player.global_position)),
					roundi(player.max_speed * nearest.get_chase_ratio()),
					roundi(player.max_speed),
				])
	lines.append("Creatures: " + " / ".join(state_counts))
	return "\n".join(lines)


func _ability_text(player: Player) -> String:
	if player.health.is_downed:
		return "DOWNED"
	if player.is_reviving():
		return "reviving (hold action)"
	var pulse := player.get_node_or_null("Pulse") as PulseAbility
	if pulse:
		return "pulse READY" if pulse.is_ready() else "pulse %.1fs" % pulse.cooldown_left
	var sword := player.get_node_or_null("UnlitLayer/Sword") as SwordAbility
	if sword:
		var light: String = "in light" if sword.is_in_echo_light() else "in dark"
		return "combo hit %d (%s)" % [sword.hit_index + 1, light] if sword.is_attacking() else "sword ready (%s)" % light
	return ""


func _nearest_creature(creatures: Array[Node], from: Vector2) -> Creature:
	var best: Creature = null
	var best_distance: float = INF
	for node: Node in creatures:
		var creature := node as Creature
		if creature == null:
			continue
		var distance: float = from.distance_squared_to(creature.global_position)
		if distance < best_distance:
			best_distance = distance
			best = creature
	return best
