class_name LevelGenerator
extends RefCounted
## Proposes a new LevelDefinition from a world's chunk pools (WorldConfig
## "Chunk Pools"): a random start chunk, a random number of middle chunks (never
## the same one twice in a row), a goal chunk or a boss arena, and a random
## pocket for every side opening. The game never calls this: it is used by the
## editor tool tools/propose_level.gd, which saves the proposal as a .tres you
## can then edit by hand.

## How many middle chunks a proposal gets (random in this range).
var middle_min: int = 5
var middle_max: int = 7
## Set = propose a boss level (ends in a boss arena chunk with this boss).
var boss_scene: PackedScene
## Spawn settings (creatures, corals, stations...) are copied from this level
## if set; otherwise the LevelDefinition defaults are used.
var template: LevelDefinition


func propose(world: WorldConfig, proposal_seed: int) -> LevelDefinition:
	var rng := RandomNumberGenerator.new()
	rng.seed = proposal_seed
	var definition := LevelDefinition.new()
	definition.chunks.append(_pick(world.start_chunks, rng, null))
	var previous: PackedScene = null
	for i: int in rng.randi_range(middle_min, middle_max):
		previous = _pick(world.middle_chunks, rng, previous)
		definition.chunks.append(previous)
	var end_pool: Array[PackedScene] = world.boss_arena_chunks if boss_scene else world.goal_chunks
	definition.chunks.append(_pick(end_pool, rng, null))

	# One pocket per side opening of the main path.
	for scene: PackedScene in definition.chunks:
		var chunk := scene.instantiate() as LevelChunk
		for _opening: Marker2D in chunk.get_side_openings():
			definition.pockets.append(_pick(world.pocket_chunks, rng, null))
		chunk.free()

	if template:
		for spawn: CreatureSpawn in template.creatures:
			definition.creatures.append(spawn.duplicate() as CreatureSpawn)
		definition.corals = template.corals
		definition.stations = template.stations
		definition.station_distance_bias = template.station_distance_bias
		definition.boss_max_health = template.boss_max_health
	definition.boss = boss_scene
	return definition


## Proposes levels from base_seed, base_seed + 1, ... until one passes the
## LevelBuilder's check (BFS) with at least one spawn seed. Returns null if
## none did within tries.
func propose_valid(world: WorldConfig, base_seed: int, tries: int, builder: LevelBuilder) -> LevelDefinition:
	for i: int in tries:
		var definition: LevelDefinition = propose(world, base_seed + i)
		var layout: LevelBuilder.Layout = builder.find_valid_layout(definition, base_seed + i)
		if layout:
			layout.free_chunks()
			return definition
	return null


func _pick(scenes: Array[PackedScene], rng: RandomNumberGenerator, avoid: PackedScene) -> PackedScene:
	if scenes.size() > 1 and avoid != null:
		var options: Array[PackedScene] = scenes.filter(func(s: PackedScene) -> bool: return s != avoid)
		return options[rng.randi_range(0, options.size() - 1)]
	return scenes[rng.randi_range(0, scenes.size() - 1)]
