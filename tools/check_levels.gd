extends SceneTree
## Headless level check: loads every LevelDefinition of a world and confirms it
## is completable (LevelBuilder + LayoutValidator, the same check the game runs
## before building a level) with many different spawn seeds, since spawns are
## reshuffled on every attempt. Also checks the structure (3 stages x 3 levels,
## a boss only and always on each stage's last level) and that the level
## generator (tools/propose_level.gd) still proposes valid levels.
##
## Run from the project folder:
##   godot --headless --path . -s res://tools/check_levels.gd
## Optional arguments after "--": world path and spawn seeds per level, e.g.
##   godot --headless --path . -s res://tools/check_levels.gd -- res://worlds/ocean.tres 20

const DEFAULT_WORLD: String = "res://worlds/ocean.tres"
const DEFAULT_SEEDS_PER_LEVEL: int = 20
const EXPECTED_STAGES: int = 3
const EXPECTED_LEVELS_PER_STAGE: int = 3
## Generator proposals checked (normal and boss levels each).
const GENERATOR_PROPOSALS: int = 3
const GENERATOR_TRIES: int = 50


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var world_path: String = args[0] if args.size() > 0 else DEFAULT_WORLD
	var seeds_per_level: int = int(args[1]) if args.size() > 1 else DEFAULT_SEEDS_PER_LEVEL
	var world := load(world_path) as WorldConfig
	var builder := LevelBuilder.new()
	builder.world = world
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var all_ok: bool = true

	print("World %s: %d stages, %d spawn seeds per level" % [world.world_name, world.get_stage_count(), seeds_per_level])
	if world.get_stage_count() != EXPECTED_STAGES:
		all_ok = _fail("expected %d stages, found %d" % [EXPECTED_STAGES, world.get_stage_count()])
	for stage_index: int in world.get_stage_count():
		var stage: StageDefinition = world.stages[stage_index]
		if stage.get_level_count() != EXPECTED_LEVELS_PER_STAGE:
			all_ok = _fail("stage %d: expected %d levels, found %d" % [stage_index + 1, EXPECTED_LEVELS_PER_STAGE, stage.get_level_count()])
		for level_index: int in stage.get_level_count():
			var definition: LevelDefinition = stage.levels[level_index]
			var label: String = "Stage %d level %d" % [stage_index + 1, level_index + 1]
			if definition == null:
				all_ok = _fail("%s: missing LevelDefinition" % label)
				continue
			var is_last: bool = level_index == stage.get_level_count() - 1
			if definition.is_boss_level() != is_last:
				all_ok = _fail("%s: %s" % [label, "the last level must have a boss" if is_last else "only the last level may have a boss"])
			if not _check_level(builder, definition, label, seeds_per_level, rng):
				all_ok = false

	if not _check_generator(builder, world, rng):
		all_ok = false
	builder.free()
	print("RESULT: %s" % ("ALL LEVELS VALID" if all_ok else "SOME CHECKS FAILED"))
	quit(0 if all_ok else 1)


## Validates one level with seeds_per_level different spawn seeds.
func _check_level(builder: LevelBuilder, definition: LevelDefinition, label: String, seeds_per_level: int, rng: RandomNumberGenerator) -> bool:
	var completable: int = 0
	var first_try: int = 0
	var total_attempts: int = 0
	var problems: Dictionary = {}
	var height: float = 0.0
	var pockets: int = 0
	for i: int in seeds_per_level:
		var base_seed: int = rng.randi() % 1000000
		# Record why first attempts fail (useful when designing levels).
		var first: LevelBuilder.Layout = builder.plan_layout(definition, base_seed)
		if first.valid:
			first_try += 1
		else:
			problems[first.problem] = int(problems.get(first.problem, 0)) + 1
		height = first.height
		pockets = first.chunks.size() - definition.chunks.size()
		first.free_chunks()
		var layout: LevelBuilder.Layout = builder.find_valid_layout(definition, base_seed)
		if layout:
			completable += 1
			total_attempts += builder.attempts_used
			layout.free_chunks()
	var creature_count: int = 0
	for spawn: CreatureSpawn in definition.creatures:
		creature_count += spawn.count
	print("%s: %d/%d completable, %d valid on the first seed, %.1f seeds tried on average | %d chunks, %d pockets, %d px tall, %d creatures, %d corals, %d stations%s" % [
		label, completable, seeds_per_level, first_try, float(total_attempts) / maxi(completable, 1),
		definition.chunks.size(), pockets, roundi(height), creature_count, definition.corals, definition.stations,
		", BOSS (%d hp)" % definition.boss_max_health if definition.is_boss_level() else "",
	])
	for problem: String in problems:
		print("  first-seed problem x%d: %s" % [problems[problem], problem])
	if completable < seeds_per_level:
		return _fail("%s: %d spawn seeds have no valid layout" % [label, seeds_per_level - completable])
	return true


func _check_generator(builder: LevelBuilder, world: WorldConfig, rng: RandomNumberGenerator) -> bool:
	var ok: bool = true
	var generator := LevelGenerator.new()
	generator.template = world.get_level(1, 0)
	for boss: bool in [false, true]:
		generator.boss_scene = world.get_level(0, 2).boss if boss else null
		var valid: int = 0
		for i: int in GENERATOR_PROPOSALS:
			if generator.propose_valid(world, rng.randi() % 1000000, GENERATOR_TRIES, builder):
				valid += 1
		print("Generator (%s levels): %d/%d proposals valid" % ["boss" if boss else "normal", valid, GENERATOR_PROPOSALS])
		if valid < GENERATOR_PROPOSALS:
			ok = _fail("the generator could not propose a valid %s level" % ("boss" if boss else "normal"))
	return ok


func _fail(message: String) -> bool:
	print("  FAILED: " + message)
	return false
