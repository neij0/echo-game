class_name PlayerSkills
extends Node
## The skills one player owns right now (set by the StageManager from the
## SkillLoadout at every level start, retry and pick). Passive skills are read
## as stats by the game systems:
##   get_multiplier("pulse_radius_mult")  product of every owned value (1 = none)
##   get_bonus("close_sense_add")         sum of every owned value (0 = none)
##   team_bonus / team_multiplier         the same over both players (creatures)
## The owned active skill's node (SkillDefinition.active_scene, an ActiveSkill)
## is added to the player's UnlitLayer while owned.
## Stats used so far: pulse_radius_mult, pulse_cost_mult, pressure_drain_mult,
## exposed_time_add, mark_time_add, sword_arc_mult, close_sense_add,
## revive_time_mult, mend_rate_mult, mend_distance_mult, shard_heal_add.

signal changed

@export var player: Player

## Skill id -> rank.
var _ranks: Dictionary = {}
## Skill id -> SkillDefinition (owned ones only).
var _definitions: Dictionary = {}
## Stat -> cached total (rebuilt on every change).
var _multipliers: Dictionary = {}
var _bonuses: Dictionary = {}
var active: ActiveSkill


static func of(target: Player) -> PlayerSkills:
	return target.get_node_or_null("Skills") as PlayerSkills if target else null


## Sum of a stat over every player (Echo Mark, Longer Exposure: read by creatures).
static func team_bonus(tree: SceneTree, stat: String) -> float:
	var total: float = 0.0
	for each: Player in Players.all(tree):
		var skills: PlayerSkills = of(each)
		if skills:
			total += skills.get_bonus(stat)
	return total


## {skill id: rank} from the SkillLoadout; unknown ids (old saves) are skipped.
func set_skills(entries: Dictionary, catalog: SkillCatalog) -> void:
	_ranks = {}
	_definitions = {}
	for skill_id: Variant in entries:
		var definition: SkillDefinition = catalog.find(str(skill_id)) if catalog else null
		if definition == null or definition.is_fallback:
			continue
		_definitions[definition.id] = definition
		_ranks[definition.id] = clampi(int(entries[skill_id]), 1, definition.max_rank)
	_rebuild_stats()
	_rebuild_active()
	changed.emit()


func get_rank(skill_id: String) -> int:
	return int(_ranks.get(skill_id, 0))


func get_multiplier(stat: String) -> float:
	return float(_multipliers.get(stat, 1.0))


func get_bonus(stat: String) -> float:
	return float(_bonuses.get(stat, 0.0))


## Owned skills: the active one first, then the passives by id.
func get_owned() -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	for skill_id: String in _definitions:
		result.append(_definitions[skill_id] as SkillDefinition)
	result.sort_custom(func(a: SkillDefinition, b: SkillDefinition) -> bool:
		if a.is_active() != b.is_active():
			return a.is_active()
		return a.id < b.id)
	return result


func get_active_definition() -> SkillDefinition:
	return active.definition if active else null


func _rebuild_stats() -> void:
	_multipliers = {}
	_bonuses = {}
	for skill_id: String in _definitions:
		var definition: SkillDefinition = _definitions[skill_id]
		if definition.is_active():
			continue
		var rank: int = get_rank(skill_id)
		for stat: String in definition.values:
			var value: float = definition.get_value(stat, rank)
			if stat.ends_with("_mult"):
				_multipliers[stat] = float(_multipliers.get(stat, 1.0)) * value
			else:
				_bonuses[stat] = float(_bonuses.get(stat, 0.0)) + value


func _rebuild_active() -> void:
	var wanted: SkillDefinition = null
	for skill_id: String in _definitions:
		var definition: SkillDefinition = _definitions[skill_id]
		if definition.is_active() and definition.active_scene:
			wanted = definition
			break
	if active and is_instance_valid(active):
		if wanted and active.definition == wanted:
			active.rank = get_rank(wanted.id)
			return
		active.queue_free()
	active = null
	if wanted == null or player == null:
		return
	active = wanted.active_scene.instantiate() as ActiveSkill
	if active == null:
		push_warning("PlayerSkills: %s's active_scene is not an ActiveSkill" % wanted.id)
		return
	active.setup(player, wanted, get_rank(wanted.id))
	var layer: Node = player.get_node_or_null("UnlitLayer")
	(layer if layer else player).add_child(active)
