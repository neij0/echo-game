class_name SkillOffer
extends RefCounted
## Builds the skills offered to one player after a level (no UI, so the rules
## can be tested headless):
## - from the character's own pool + the shared pool, only skills available in
##   this world (available_from_world) and not at max rank yet (higher ranks of
##   owned skills can come back);
## - one active slot: once an active skill is owned, no other one is offered,
##   and an offer never holds two new active skills;
## - weighted random (offer_weight) without repeats;
## - empty places are filled with fallbacks (e.g. a full refill).
## How many cards and picks: StageDefinition (normal level / after a boss);
## nothing after the world's very last level (the skills reset next world).


## Every skill this character could get right now.
static func get_candidates(catalog: SkillCatalog, loadout: SkillLoadout, character: String, world_index: int) -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	var has_active: bool = loadout.has_active(character, catalog)
	for definition: SkillDefinition in catalog.skills:
		if definition == null or definition.is_fallback or not definition.is_for(character):
			continue
		if definition.available_from_world > world_index:
			continue
		var rank: int = loadout.get_rank(character, definition.id)
		if rank >= definition.max_rank:
			continue
		if definition.is_active() and rank == 0 and has_active:
			continue
		result.append(definition)
	return result


## `count` different skills (fewer only if not even the fallbacks fill it).
static func build(catalog: SkillCatalog, loadout: SkillLoadout, character: String, world_index: int, count: int, rng: RandomNumberGenerator) -> Array[SkillDefinition]:
	var pool: Array[SkillDefinition] = get_candidates(catalog, loadout, character, world_index)
	var result: Array[SkillDefinition] = []
	while result.size() < count and not pool.is_empty():
		var picked: SkillDefinition = _weighted_pick(pool, rng)
		result.append(picked)
		pool.erase(picked)
		if picked.is_active():
			# One slot: never two new actives in the same offer.
			pool.assign(pool.filter(func(other: SkillDefinition) -> bool: return not other.is_active() or loadout.get_rank(character, other.id) > 0))
	for fallback: SkillDefinition in catalog.fallbacks:
		if result.size() >= count:
			break
		if fallback:
			result.append(fallback)
	return result


## [cards, picks] after this level: Vector2i(0, 0) = no choice.
static func get_offer_size(world: WorldConfig, stage_index: int, level_index: int) -> Vector2i:
	if world == null:
		return Vector2i.ZERO
	var is_last_stage: bool = stage_index >= world.get_stage_count() - 1
	var is_last_level: bool = level_index >= world.get_level_count(stage_index) - 1
	if is_last_stage and is_last_level:
		return Vector2i.ZERO
	var stage: StageDefinition = world.get_stage(stage_index)
	if world.get_level(stage_index, level_index).is_boss_level():
		return Vector2i(stage.boss_skill_offer_count, stage.boss_skill_pick_count)
	return Vector2i(stage.skill_offer_count, stage.skill_pick_count)


static func _weighted_pick(pool: Array[SkillDefinition], rng: RandomNumberGenerator) -> SkillDefinition:
	var total: float = 0.0
	for definition: SkillDefinition in pool:
		total += maxf(definition.offer_weight, 0.0)
	if total <= 0.0:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var roll: float = rng.randf() * total
	for definition: SkillDefinition in pool:
		roll -= maxf(definition.offer_weight, 0.0)
		if roll <= 0.0:
			return definition
	return pool[pool.size() - 1]
