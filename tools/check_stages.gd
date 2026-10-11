extends SceneTree
## Headless layout check: plans many random stages for a world and confirms
## every one is completable (StageBuilder + LayoutValidator, the same check the
## game runs before building a stage).
##
## Run from the project folder:
##   godot --headless --path . -s res://tools/check_stages.gd
## Optional arguments after "--": world path and seeds per stage, e.g.
##   godot --headless --path . -s res://tools/check_stages.gd -- res://worlds/ocean.tres 20

const DEFAULT_WORLD: String = "res://worlds/ocean.tres"
const DEFAULT_SEEDS_PER_STAGE: int = 20


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var world_path: String = args[0] if args.size() > 0 else DEFAULT_WORLD
	var seeds_per_stage: int = int(args[1]) if args.size() > 1 else DEFAULT_SEEDS_PER_STAGE
	var world := load(world_path) as WorldConfig
	var builder := StageBuilder.new()
	builder.world = world
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var all_ok: bool = true
	print("World %s: %d stages, %d seeds per stage" % [world.world_name, world.get_stage_count(), seeds_per_stage])
	for stage_index: int in world.get_stage_count():
		var completable: int = 0
		var first_try: int = 0
		var total_attempts: int = 0
		var problems: Dictionary = {}
		var started: int = Time.get_ticks_msec()
		for i: int in seeds_per_stage:
			var base_seed: int = rng.randi() % 1000000
			# Record why first attempts fail (useful when designing chunks).
			var first: StageBuilder.Layout = builder.plan_layout(stage_index, base_seed)
			if first.valid:
				first_try += 1
			else:
				problems[first.problem] = int(problems.get(first.problem, 0)) + 1
			first.free_chunks()
			var layout: StageBuilder.Layout = builder.find_valid_layout(stage_index, base_seed)
			if layout:
				completable += 1
				total_attempts += builder.attempts_used
				layout.free_chunks()
			else:
				all_ok = false
				print("  FAILED: stage %d base seed %d has no valid layout" % [stage_index + 1, base_seed])
		print("Stage %d: %d/%d completable, %d valid on the first seed, %.1f seeds tried on average, %.2f s per layout" % [
			stage_index + 1, completable, seeds_per_stage, first_try,
			float(total_attempts) / maxi(completable, 1), (Time.get_ticks_msec() - started) / 1000.0 / (seeds_per_stage * 2)])
		for problem: String in problems:
			print("  first-seed problem x%d: %s" % [problems[problem], problem])
	builder.free()
	print("RESULT: %s" % ("ALL COMPLETABLE" if all_ok else "SOME STAGES FAILED"))
	quit(0 if all_ok else 1)
