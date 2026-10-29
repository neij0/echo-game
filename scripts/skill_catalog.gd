class_name SkillCatalog
extends Resource
## Every skill of the game (skills/skill_catalog.tres, set on the Game
## autoload). Which ones are offered depends on the world
## (SkillDefinition.available_from_world), the character and what is owned
## already (SkillOffer).

@export var skills: Array[SkillDefinition] = []
## Offered when a player has nothing left to pick (e.g. a full refill).
@export var fallbacks: Array[SkillDefinition] = []


## The skill or fallback with this id (null if unknown, e.g. an old save).
func find(skill_id: String) -> SkillDefinition:
	for definition: SkillDefinition in skills + fallbacks:
		if definition and definition.id == skill_id:
			return definition
	return null
