class_name Hud
extends CanvasLayer
## Awareness bar, the Echo Shard counter, a debug label (stage, level, mode,
## seed, abilities, creatures, chase speeds), and one PlayerStatus (depth +
## pressure meter) per registered player. Never holds a single fixed player.

@export var stage_manager: StageManager
@export var awareness: DepthAwareness
@export var level_builder: LevelBuilder

@export_group("Awareness Bar")
@export var calm_color: Color = Color(0.2, 0.55, 1.0)
@export var warning_color: Color = Color(1.0, 0.15, 0.15)
@export var background_color: Color = Color(0.1, 0.12, 0.18, 0.85)

@export_group("Shard Counter")
@export var shard_counter_position: Vector2 = Vector2(340.0, 18.0)
@export var shard_counter_color: Color = Color(0.55, 0.95, 1.0)
## Colour once every shard is collected.
@export var shard_done_color: Color = Color(1.0, 0.82, 0.35)

@onready var _bar: ProgressBar = $AwarenessBar
@onready var _debug_label: Label = $DebugLabel
@onready var _statuses: VBoxContainer = $PlayerStatuses

var _fill_style: StyleBoxFlat
var _shard_label: Label


func _ready() -> void:
	_bar.max_value = awareness.max_value

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = calm_color
	_bar.add_theme_stylebox_override("fill", _fill_style)

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = background_color
	_bar.add_theme_stylebox_override("background", background_style)

	_shard_label = Label.new()
	_shard_label.name = "ShardCounter"
	_shard_label.position = shard_counter_position
	add_child(_shard_label)

	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)
		stage_manager.shards_changed.connect(_on_shards_changed)


func _on_shards_changed(collected: int, total: int) -> void:
	if total > 0 and collected >= total:
		_shard_label.text = Game.text("arena_open" if stage_manager.is_boss_level() else "exit_open")
		_shard_label.add_theme_color_override("font_color", shard_done_color)
	else:
		_shard_label.text = Game.text("shards") % [collected, total]
		_shard_label.add_theme_color_override("font_color", shard_counter_color)


func _on_player_registered(player: Player) -> void:
	var status := PlayerStatus.new()
	status.setup(player, level_builder, stage_manager.world if stage_manager else null)
	_statuses.add_child(status)


func _process(_delta: float) -> void:
	_bar.value = awareness.value
	_fill_style.bg_color = calm_color.lerp(warning_color, awareness.get_ratio())

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
	if stage_manager:
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
	_debug_label.text = "\n".join(lines)


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
