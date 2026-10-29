class_name SkillDefinition
extends Resource
## One skill the players can pick between levels (skills/<owner>/<id>.tres,
## listed in skills/skill_catalog.tres). Skills last for the whole world and
## reset when the next world starts (SkillLoadout).
## - Passive skills change stats: every key in `values` is a stat that the game
##   systems read through PlayerSkills ("*_mult" keys multiply, 1 = no change;
##   "*_add" keys add, 0 = no change). A new skill that only changes existing
##   stats needs no code: just a new .tres in the catalog.
## - Active skills put their active_scene (an ActiveSkill) under the player
##   while owned; their `values` are that node's parameters (cooldown, range...).
##   Each character has one active slot.
## - Fallbacks (SkillCatalog.fallbacks) are offered when nothing else is left;
##   they are not kept, StageManager applies them once (e.g. a full refill).
## Text: English + Arabic here; a world can rename a skill (e.g. the pressure
## skills: oxygen in the Ocean, cold in the Snow) with
## WorldConfig.skill_text_overrides.

enum Owner { ECHO, GUARDIAN, SHARED }
## CORE = every world, PRESSURE = about the world's survival meter (renamed per
## world), WORLD = only makes sense in one world.
enum Category { CORE, PRESSURE, WORLD }
enum Kind { PASSIVE, ACTIVE }

## Unique id, used in the save file (never change it once released).
@export var id: String = ""
@export var owner: Owner = Owner.ECHO
@export var category: Category = Category.CORE
@export var kind: Kind = Kind.PASSIVE
@export_range(1, 2) var max_rank: int = 1
## Index in Game.world_ids from which on the skill is offered (0 = Ocean).
@export var available_from_world: int = 0
## Relative chance of being offered (2 = twice as often).
@export var offer_weight: float = 1.0
## One value per rank for every key (index 0 = rank 1). See the class notes.
@export var values: Dictionary[String, PackedFloat32Array] = {}
## Active skills only: the ability node added under the player (ActiveSkill).
@export var active_scene: PackedScene
## Not kept: applied once when picked (SkillCatalog.fallbacks only).
@export var is_fallback: bool = false

@export_group("Text")
@export var name_en: String = ""
@export var name_ar: String = ""
@export_multiline var description_en: String = ""
@export_multiline var description_ar: String = ""
## Short co-op tip shown after both players picked.
@export_multiline var tip_en: String = ""
@export_multiline var tip_ar: String = ""

@export_group("Icon")
@export var icon_shape: SkillIcon.Shape = SkillIcon.Shape.RINGS
@export var icon_color: Color = Color(0.55, 0.95, 1.0)


## The value of a key at a rank (1-based). Ranks above the list use its last entry.
func get_value(key: String, rank: int, default_value: float = 0.0) -> float:
	if not values.has(key):
		return default_value
	var per_rank: PackedFloat32Array = values[key]
	if per_rank.is_empty():
		return default_value
	return per_rank[clampi(rank - 1, 0, per_rank.size() - 1)]


func is_active() -> bool:
	return kind == Kind.ACTIVE


## True when a character ("echo" / "guardian") can own this skill.
func is_for(character: String) -> bool:
	return owner == Owner.SHARED or owner_key(owner) == character


func display_name(language: String, world: WorldConfig = null) -> String:
	return _text("name", language, world)


func description(language: String, world: WorldConfig = null) -> String:
	return _text("description", language, world)


func tip(language: String, world: WorldConfig = null) -> String:
	return _text("tip", language, world)


## "echo" or "guardian" (SHARED has no key of its own).
static func owner_key(value: Owner) -> String:
	match value:
		Owner.ECHO:
			return "echo"
		Owner.GUARDIAN:
			return "guardian"
	return "shared"


## A world's override wins; Arabic falls back to English when empty.
func _text(field: String, language: String, world: WorldConfig) -> String:
	if world:
		var override: SkillTextOverride = world.get_skill_text_override(id)
		if override:
			var replaced: String = override.get_text(field, language)
			if replaced != "":
				return replaced
	var text: String = str(get(field + "_" + language)) if language in UiText.LANGUAGES else ""
	return text if text != "" else str(get(field + "_en"))
