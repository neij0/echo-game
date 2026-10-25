extends Node
## Headless stuck test: creatures (a normal one and one of boss size) chase the
## players through every level while the players jump from spot to spot (the
## creature spots of the level: rooms, corners, doorways), so the creatures
## keep pathing around rock. A second pass plays "normally": three creatures
## with their own AI (no frenzy), the Echo pulses on every hop (corals wake and
## push creatures out of their safe zones) and the players stand next to lit
## corals and creature spots. Every CreatureStuckWatch report is counted;
## stuck for STUCK_FAIL_WINDOWS windows in a row (about 1.5 s) fails.
##   godot --headless --path . --fixed-fps 60 res://tools/test_stuck.tscn
## Optional: -- log        (print every stuck window)
##           -- norecover  (safety net off: shows the real causes)

const GAME_SCENE: String = "res://scenes/game.tscn"
const CREATURE_SCENES: Array[String] = ["res://scenes/creature.tscn", "res://scenes/boss_placeholder.tscn"]
const PHYSICS_FPS: float = 60.0
const RUNS_PER_LEVEL: int = 4
## Seconds the players stay on one spot, and spots per run.
const HOP_TIME: float = 2.5
const HOPS_PER_RUN: int = 4
## Stuck this many windows in a row = a real stuck (not a short bump).
const STUCK_FAIL_WINDOWS: int = 2
const MAX_PRINTED: int = 12

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player
var _printed: int = 0
var _recover: bool = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	CreatureStuckWatch.log_enabled = "log" in OS.get_cmdline_user_args()
	_recover = not "norecover" in OS.get_cmdline_user_args()
	print("Safety net %s" % ("on" if _recover else "OFF"))
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	_stage = _game.get_node("StageManager") as StageManager
	_stage.test_mode = SaveData.Mode.CHALLENGE
	add_child(_game)
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	_echo = _game.get_node("Echo") as Player
	_guardian = _game.get_node("Guardian") as Player
	(_game.get_node("DepthAwareness") as DepthAwareness).decay_per_second = 0.0
	await _frames(10)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var failures: int = 0
	var world: WorldConfig = _stage.world
	for scene_path: String in CREATURE_SCENES:
		var scene := load(scene_path) as PackedScene
		var windows: int = 0
		var stuck_runs: int = 0
		var runs: int = 0
		var seconds: float = 0.0
		for stage_index: int in world.get_stage_count():
			for level_index: int in world.get_level_count(stage_index):
				await _build(stage_index, level_index)
				var spots: Array[Vector2] = _builder.creature_spots.duplicate()
				if spots.size() < 2:
					continue
				for run: int in RUNS_PER_LEVEL:
					var result: Dictionary = await _chase_run(scene, spots, rng)
					runs += 1
					seconds += HOP_TIME * HOPS_PER_RUN
					windows += int(result.windows)
					if int(result.longest) >= STUCK_FAIL_WINDOWS:
						stuck_runs += 1
		var label: String = scene_path.get_file().get_basename()
		print("%-17s %d runs, %.0f s chasing: %d stuck windows (%.1f s), %d runs stuck >= %d windows in a row" % [
			label, runs, seconds, windows, windows * 0.75, stuck_runs, STUCK_FAIL_WINDOWS])
		failures += stuck_runs
	failures += await _normal_play_pass(rng)
	failures += await _safety_net_check()
	print("RESULT: %s" % ("NO STUCK CREATURES" if failures == 0 else "%d STUCK RUN(S)" % failures))
	# Free the game a moment before quitting (the audio server releases freed
	# players' playbacks on its own thread; still playing at exit = "leaked").
	_game.queue_free()
	for i: int in 10:
		await get_tree().process_frame
		OS.delay_msec(30)
	get_tree().quit(0 if failures == 0 else 1)


## One creature chases the players while they hop between spots.
func _chase_run(scene: PackedScene, spots: Array[Vector2], rng: RandomNumberGenerator) -> Dictionary:
	var creature := scene.instantiate() as Creature
	var start: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
	creature.position = _builder.to_local(start)
	_builder._level.add_child(creature)
	creature.challenge_mode = true
	creature.safe_zone_push = 0.0
	(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)
	var watch: CreatureStuckWatch = creature.get_node("StuckWatch") as CreatureStuckWatch
	watch.recover_enabled = _recover
	var longest: Array[int] = [0]
	watch.stuck.connect(func(info: Dictionary) -> void:
		longest[0] = maxi(longest[0], int(info.windows_in_a_row))
		if int(info.windows_in_a_row) >= STUCK_FAIL_WINDOWS and _printed < MAX_PRINTED:
			_printed += 1
			print("  stuck: %s" % info))
	await _frames(2)
	creature.set_frenzy(true)
	for hop: int in HOPS_PER_RUN:
		var spot: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		_echo.global_position = spot
		_guardian.global_position = spot + Vector2(12.0, 0.0)
		for i: int in int(HOP_TIME * PHYSICS_FPS):
			await get_tree().physics_frame
			_protect_players()
	var result: Dictionary = {"windows": watch.total_stuck_windows, "longest": longest[0]}
	creature.queue_free()
	await _frames(1)
	return result


## Normal AI, pulses and lit corals, several creatures at once.
func _normal_play_pass(rng: RandomNumberGenerator) -> int:
	var scene := load(CREATURE_SCENES[0]) as PackedScene
	var world: WorldConfig = _stage.world
	var windows: int = 0
	var stuck_runs: int = 0
	var runs: int = 0
	for stage_index: int in world.get_stage_count():
		for level_index: int in world.get_level_count(stage_index):
			await _build(stage_index, level_index)
			var spots: Array[Vector2] = _builder.creature_spots.duplicate()
			var corals: Array[Vector2] = []
			for node: Node in get_tree().get_nodes_in_group("corals"):
				corals.append((node as Node2D).global_position)
			for run: int in RUNS_PER_LEVEL:
				runs += 1
				var creatures: Array[Creature] = []
				var longest: Array[int] = [0]
				for i: int in 3:
					var creature := scene.instantiate() as Creature
					creature.position = _builder.to_local(spots[rng.randi_range(0, spots.size() - 1)])
					_builder._level.add_child(creature)
					creature.challenge_mode = true
					(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)
					(creature.get_node("StuckWatch") as CreatureStuckWatch).recover_enabled = _recover
					(creature.get_node("StuckWatch") as CreatureStuckWatch).stuck.connect(func(info: Dictionary) -> void:
						longest[0] = maxi(longest[0], int(info.windows_in_a_row))
						if int(info.windows_in_a_row) >= STUCK_FAIL_WINDOWS and _printed < MAX_PRINTED * 2:
							_printed += 1
							print("  stuck (normal play): %s" % info))
					creatures.append(creature)
				await _frames(2)
				for hop: int in HOPS_PER_RUN:
					# Next to a coral (just outside its safe zone) or a creature spot.
					var near_coral: bool = not corals.is_empty() and rng.randf() < 0.6
					var base: Vector2 = corals[rng.randi_range(0, corals.size() - 1)] if near_coral else spots[rng.randi_range(0, spots.size() - 1)]
					var spot: Vector2 = NavigationServer2D.map_get_closest_point(get_viewport().world_2d.navigation_map,
						base + Vector2.from_angle(rng.randf() * TAU) * (150.0 if near_coral else 0.0))
					_echo.global_position = spot
					_guardian.global_position = spot + Vector2(12.0, 0.0)
					(_echo.get_node("Pulse") as PulseAbility).emit_pulse()
					for i: int in int(HOP_TIME * PHYSICS_FPS):
						await get_tree().physics_frame
						_protect_players()
				for creature: Creature in creatures:
					windows += (creature.get_node("StuckWatch") as CreatureStuckWatch).total_stuck_windows
					creature.queue_free()
				if longest[0] >= STUCK_FAIL_WINDOWS:
					stuck_runs += 1
				await _frames(1)
	print("normal play       %d runs x 3 creatures: %d stuck windows (%.1f s), %d runs stuck >= %d windows in a row" % [
		runs, windows, windows * 0.75, stuck_runs, STUCK_FAIL_WINDOWS])
	return stuck_runs


## A creature that cannot move (chase speed 0) must get a fresh path after
## repath_after windows and a nudge after nudge_after windows.
func _safety_net_check() -> int:
	await _build(0, 0)
	var creature := (load(CREATURE_SCENES[0]) as PackedScene).instantiate() as Creature
	var spots: Array[Vector2] = _builder.creature_spots
	creature.position = _builder.to_local(spots[0])
	_builder._level.add_child(creature)
	(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)
	creature.calm_chase_ratio_min = 0.0
	creature.calm_chase_ratio_max = 0.0
	creature.challenge_chase_ratio_min = 0.0
	creature.challenge_chase_ratio_max = 0.0
	var watch: CreatureStuckWatch = creature.get_node("StuckWatch") as CreatureStuckWatch
	watch.recover_enabled = true
	_echo.global_position = spots[spots.size() - 1]
	_guardian.global_position = spots[spots.size() - 1] + Vector2(12.0, 0.0)
	await _frames(2)
	creature.set_frenzy(true)
	for i: int in int(watch.check_time * (watch.nudge_after + 0.5) * PHYSICS_FPS):
		await get_tree().physics_frame
		_protect_players()
	var ok: bool = watch.repaths_done >= 1 and watch.nudges_done >= 1
	print("safety net        frozen creature: %d repath(s), %d nudge(s) -> %s" % [watch.repaths_done, watch.nudges_done, "ok" if ok else "FAIL"])
	creature.queue_free()
	return 0 if ok else 1


func _build(stage_index: int, level_index: int) -> void:
	_stage.stage_index = stage_index
	_stage._start_level(level_index)
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		node.remove_from_group("creatures")
		node.queue_free()
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	await _frames(12)


func _protect_players() -> void:
	for player: Player in [_echo, _guardian]:
		if player.health.is_downed:
			player.health.revive()
		player.health._invulnerable_left = 999.0
		player.pressure.refill()
		player.velocity = Vector2.ZERO


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
