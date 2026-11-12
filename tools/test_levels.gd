extends Node
## Headless checks of Phase B so far, on the real level test stage:
## every Ocean level builds in 3D (rooms, rock with colliders, navigation on
## both maps, every shard and the exit reachable from the start, the spawns
## the definition asks for), the level flow (shards unlock the ancient light,
## waking it starts the next level, both players down = the level again), the
## oxygen stations, corals (wake on a pulse, safe zone), the Sentinel's leash,
## the light hunter sensing the Echo through rock, and the sand trails
## (stamps while moving near the camera, none for a teleport or far away,
## puffs when fast). Also prints the "quiet spaces" report per level (rooms
## without creatures, alert chains) for tuning.
## godot --headless --path . --fixed-fps 60 res://tools/test_levels.tscn
## Exits with 1 when a check fails.

const LEVEL_TEST_SCENE: PackedScene = preload("res://tools/level_test.tscn")

var _failures: int = 0
var _checks: int = 0
var test: LevelTest


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("TEST LEVELS (3D)")
	test = LEVEL_TEST_SCENE.instantiate() as LevelTest
	add_child(test)
	await _frames(3)
	await _test_every_level_builds()
	await _test_level_flow()
	await _test_station_and_coral()
	await _test_sentinel_and_hunter()
	await _test_sand_trails()
	print("")
	print("%d checks, %d failed" % [_checks, _failures])
	print("RESULT: ", "LEVELS OK" if _failures == 0 else "LEVELS FAIL")
	get_tree().quit(0 if _failures == 0 else 1)


# --- Checks -----------------------------------------------------------------------

func _test_every_level_builds() -> void:
	print("- every level builds in 3D")
	var world: WorldConfig = test.world
	var number: int = 0
	var report := PackedStringArray()
	for stage: int in world.get_stage_count():
		for level: int in world.get_level_count(stage):
			number += 1
			var definition: LevelDefinition = world.get_level(stage, level)
			var built: bool = test.start_level(stage, level)
			await _frames(3)
			var label: String = "level %d (%d-%d)" % [number, stage + 1, level + 1]
			_check(built, "%s builds (seed %d, %d attempt(s), %.2f s, navigation %.2f s)" % [
				label, test.builder.spawn_seed, test.builder.attempts_used, test.builder.build_seconds, test.builder.bake_seconds])
			if not built:
				continue
			var rooms: int = 0
			var colliders: int = 0
			for node: Node in test.builder.find_children("Room_*", "", true, false):
				rooms += 1
				var rock := node.get_node_or_null("Rock") as StaticBody3D
				if rock and rock.get_child_count() >= 2:
					colliders += 1
			_check(rooms == definition.rooms.size() and colliders == rooms,
				"%s: %d rooms, each with rock and a collider" % [label, rooms])
			var expected_creatures: int = 0
			for spawn: CreatureSpawn in definition.creatures:
				expected_creatures += spawn.count
			expected_creatures += mini(definition.sentinels, definition.shard_count)
			_check(test.builder.get_creatures().size() == expected_creatures and test.shards_total == definition.shard_count,
				"%s: %d creatures (incl. Sentinels), %d shards as defined" % [label, test.builder.get_creatures().size(), test.shards_total])
			# Reachable on the navigation mesh (players' clearance is smaller, so
			# a creature path is the stricter test).
			var start: Vector3 = test.builder.get_spawn_position(1)
			var targets: Array[Vector3] = []
			for shard: EchoShard in test.builder.get_shards():
				targets.append(shard.global_position)
			targets.append(test.builder.get_goal().global_position)
			var unreachable: int = 0
			for target: Vector3 in targets:
				if not _reachable(start, target):
					unreachable += 1
			_check(unreachable == 0, "%s: every shard and the exit can be reached from the start on the navigation mesh (%d unreachable)" % [label, unreachable])
			var large_map: RID = test.builder.navigation_map_for(1.0)
			_check(large_map != test.get_world_3d().navigation_map and NavigationServer3D.map_get_regions(large_map).size() == 1,
				"%s: the large creatures' map has its own mesh" % label)
			report.append(_quiet_report(label))
	print("  quiet spaces (rooms without a creature at the start; alert chains: creatures that wake each other, alert radius %.0f units):" % Creature.new().alert_radius)
	for line: String in report:
		print("    " + line)


func _test_level_flow() -> void:
	print("- level flow: shards unlock the light, the light starts the next level")
	test.start_level(0, 0)
	test.set_creatures_frozen(true)
	await _frames(3)
	var goal: AncientLight = test.builder.get_goal()
	_check(goal.is_locked(), "the ancient light starts locked (%d sockets)" % goal.shards_needed)
	test.echo.health.set_segments(2.0)
	var shards: Array[EchoShard] = test.builder.get_shards().duplicate()
	for shard: EchoShard in shards:
		shard.collect()
	await _frames(2)
	_check(not goal.is_locked() and test.shards_collected == shards.size(), "collecting every shard unlocks it")
	_check(test.echo.health.value > 2.0, "a shard heals one segment (got %.1f)" % test.echo.health.value)
	_place(test.echo, goal.global_position + Vector3(1.0, 0.0, 0.0))
	_place(test.guardian, goal.global_position + Vector3(-1.0, 0.0, 0.0))
	var woke: Array[bool] = [false]
	goal.activated.connect(func() -> void: woke[0] = true)
	await _seconds(goal.activation_time + 0.4)
	_check(woke[0], "standing next to it for %.0f s wakes it" % goal.activation_time)
	await _seconds(test.next_level_delay + 0.3)
	_check(test.level_index == 1, "then the next level starts (level %d)" % (test.level_index + 1))
	var seed_before: int = test.builder.spawn_seed
	test.echo.health.down(PlayerHealth.Cause.CREATURE)
	test.guardian.health.down(PlayerHealth.Cause.CREATURE)
	await _seconds(test.retry_delay + 0.4)
	_check(test.level_index == 1 and not test.echo.health.is_downed and test.builder.spawn_seed != seed_before,
		"both down: the same level again, with a new seed")
	test.set_creatures_frozen(false)


func _test_station_and_coral() -> void:
	print("- oxygen station and coral")
	test.start_level(0, 0)
	test.set_creatures_frozen(true)
	await _frames(3)
	var station := get_tree().get_first_node_in_group("pressure_stations") as PressureStation
	_check(station != null, "the level has an oxygen station")
	if station:
		test.echo.pressure.value = test.echo.pressure.max_value * 0.3
		_place(test.echo, station.global_position)
		# The leash: the partner comes along.
		_place(test.guardian, station.global_position + Vector3(0.0, 0.0, 2.0))
		await _seconds(0.3)
		_check(station.is_used and test.echo.pressure.get_ratio() > 0.95, "touching it refills the oxygen, then it is used up")
	var coral := get_tree().get_first_node_in_group("corals") as Coral
	_check(coral != null, "the level has corals")
	if coral:
		coral.on_sonar_hit(coral.global_position)
		_check(coral.is_lit() and coral.is_in_safe_zone(coral.global_position + Vector3(1.0, 0.0, 0.0))
			and not coral.is_in_safe_zone(coral.global_position + Vector3(coral.safe_radius + 0.5, 0.0, 0.0)),
			"a pulse wakes it: lit, with a safe zone of %.1f units" % coral.safe_radius)
	test.set_creatures_frozen(false)


func _test_sentinel_and_hunter() -> void:
	print("- Sentinel and light hunter")
	test.start_level(0, 0)
	await _frames(3)
	var sentinel: Sentinel = null
	var hunter: LightHunter = null
	for creature: Creature in test.builder.get_creatures():
		if creature is Sentinel and sentinel == null:
			sentinel = creature as Sentinel
		elif creature is LightHunter and hunter == null:
			hunter = creature as LightHunter
	_check(sentinel != null, "the level has a Sentinel")
	if sentinel:
		_check(sentinel.max_health == sentinel.calm_max_health, "it has its Calm health (%d)" % sentinel.max_health)
		var near: Vector3 = sentinel.post + Vector3(sentinel.get_leash_radius() * 0.5, 0.0, 0.0)
		var far: Vector3 = sentinel.post + Vector3(sentinel.get_leash_radius() + 3.0, 0.0, 0.0)
		_place(test.echo, near)
		_place(test.guardian, near)
		_check(sentinel._can_chase(test.echo), "it chases a player inside its leash")
		_place(test.echo, far)
		_check(not sentinel._can_chase(test.echo), "and not beyond it")
	var any_hunter: bool = hunter != null
	if hunter == null:
		# Not every level has one: test it on its own.
		hunter = (load("res://scenes/light_hunter.tscn") as PackedScene).instantiate() as LightHunter
		test.builder.add_child(hunter)
		hunter.global_position = test.builder.get_spawn_position(1) + Vector3(6.0, 0.0, 0.0)
	_check(true, "light hunter: %s" % ("one in the level" if any_hunter else "added for the test"))
	_place(test.echo, hunter.global_position + Vector3(hunter.sense_range * 0.5, 0.0, 0.0))
	_place(test.guardian, test.echo.global_position + Vector3(1.0, 0.0, 0.0))
	await _seconds(0.3)
	_check(hunter.state == Creature.State.CHASE and hunter.get_chased_player() == test.echo,
		"it senses the Echo within %.0f units (through rock too) and hunts her" % hunter.sense_range)


func _test_sand_trails() -> void:
	print("- sand trails")
	test.start_level(0, 0)
	test.set_creatures_frozen(true)
	await _frames(3)
	var trails: SandTrails = test.trails
	trails.enabled = true
	var before: int = trails.stamps_drawn
	await _frames(10)
	_check(trails.stamps_drawn == before, "nothing moves: no stamps")
	var start: Vector3 = test.guardian.global_position
	for i: int in 30:
		test.guardian.global_position = start + Vector3(0.05 * i, 0.0, 0.0)
		await get_tree().process_frame
	_check(trails.stamps_drawn > before, "a moving player stamps a furrow (%d stamps)" % (trails.stamps_drawn - before))
	var maker := test.guardian.get_node("SandTrail") as SandTrailMaker
	# A jump longer than max_step in one frame (a teleport, a respawn).
	maker.has_last = true
	maker.last_floor_position = maker.get_floor_position() - Vector3(maker.max_step + 1.0, 0.0, 0.0)
	trails._pending.clear()
	trails._update_maker(maker, maker.get_floor_position(), 1.0 / 60.0)
	_check(trails._pending.is_empty(), "a teleport leaves no furrow across the floor")
	var far: Vector3 = trails._focus() + Vector3(trails.active_radius + 5.0, 0.0, 0.0)
	maker.last_floor_position = far
	maker.has_last = true
	var stamps: int = trails.stamps_drawn
	trails._update_maker(maker, trails._focus(), 1.0 / 60.0)
	_check(trails.stamps_drawn == stamps and trails._pending.size() == 0 or Creature._flat_distance(maker.get_floor_position(), trails._focus()) <= trails.active_radius,
		"a maker far from the camera does not stamp (it would land on wrapped texels)")
	var puffs: int = trails.puffs_thrown
	maker.has_last = true
	maker.last_floor_position = maker.get_floor_position() - Vector3(0.3, 0.0, 0.0)
	maker.puff_cooldown_left = 0.0
	trails._update_maker(maker, maker.get_floor_position(), 1.0 / 60.0)
	_check(trails.puffs_thrown == puffs + 1, "moving fast (%.0f units/s) throws a puff of sand" % (0.3 * 60.0))
	trails.enabled = false
	before = trails.stamps_drawn
	for i: int in 10:
		test.guardian.global_position = start + Vector3(0.05 * i, 0.0, 1.0)
		await get_tree().process_frame
	_check(trails.stamps_drawn == before, "trails off: nothing is stamped")
	trails.enabled = true
	test.set_creatures_frozen(false)


# --- Quiet spaces -----------------------------------------------------------------

## Rooms without a creature at the start, and the biggest group of creatures
## that alert each other (each within the alert radius of the next).
func _quiet_report(label: String) -> String:
	var layout: LevelBuilder.Layout = test.builder.get_layout()
	var size: float = test.world.room_size
	var busy: Dictionary = {}
	var creatures: Array[Creature] = test.builder.get_creatures()
	for creature: Creature in creatures:
		var plan: Vector2 = test.builder.to_plan(creature.global_position)
		busy[Vector2i((plan / size).floor())] = true
	var quiet: int = 0
	for cell: Vector2i in layout.rooms:
		if not busy.has(cell):
			quiet += 1
	# Alert chains (connected groups within alert_radius, straight line).
	var seen: Dictionary = {}
	var biggest: int = 0
	for creature: Creature in creatures:
		if seen.has(creature):
			continue
		var group: int = 0
		var stack: Array[Creature] = [creature]
		seen[creature] = true
		while not stack.is_empty():
			var current: Creature = stack.pop_back()
			group += 1
			for other: Creature in creatures:
				if not seen.has(other) and Creature._flat_distance(current.global_position, other.global_position) <= current.alert_radius:
					seen[other] = true
					stack.append(other)
		biggest = maxi(biggest, group)
	return "%s: %d rooms, %d quiet (no creature), %d creatures, biggest alert chain %d" % [
		label, layout.rooms.size(), quiet, creatures.size(), biggest]


# --- Helpers ----------------------------------------------------------------------

func _reachable(from: Vector3, to: Vector3) -> bool:
	var map: RID = test.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty():
		return false
	var end: Vector3 = path[path.size() - 1]
	# The end of the path is the closest mesh point: the target sits within a
	# player's reach of it (shards in tight alcoves sit near rock).
	return Creature._flat_distance(end, to) <= 1.2


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = Vector3(at.x, 0.0, at.z)
	node.reset_physics_interpolation()
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["ok  " if ok else "FAIL", label])


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
