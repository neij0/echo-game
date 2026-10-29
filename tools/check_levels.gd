extends SceneTree
## Headless level check for a world's room grids:
## - every room on its own: all markers reachable with every door sealed, and
##   every declared doorway really opens (an unsealed door leaks out);
## - the structure: 3 stages x 3 levels, a boss only and always on each stage's
##   last level, lighting darker per stage, light shafts only in stage 1;
## - every level's room graph: one connected group with branches, at least one
##   loop and dead ends; where the lockdown room is;
## - every level is completable (LevelBuilder + LayoutValidator, the same check
##   the game runs) with many spawn seeds, since spawns and shards are
##   reshuffled on every attempt;
## - the walking path start -> all shards (best order) -> exit, in pixels and
##   in seconds at full swimming speed (a careful pair takes several times longer);
## - balance per level: Sentinels, the lockdown wave per mode (and that the
##   lockdown room has Creature markers for it), and for collapse-escape levels
##   the timer per mode against the longest walk from any shard to the exit at
##   the slower player's full speed (must be at least ESCAPE_MIN_RATIO times it);
## - landmarks: 1-3 per level, every level its own mix, no kind twice in a
##   stage, and two placements of a kind never in the same room type with the
##   same turn close to the same spot (so they never look alike); each one
##   clear of the room's rock, its markers and the doorway corridors (the
##   level checks above already include their footprints as rock);
## - ambient life: every creature is placed on open floor and none of it is a
##   creature (a node in the "creatures" group);
## - the level generator (tools/propose_level.gd) still proposes valid levels.
##
## Run from the project folder:
##   godot --headless --path . -s res://tools/check_levels.gd
## Optional arguments after "--": world path and spawn seeds per level, e.g.
##   godot --headless --path . -s res://tools/check_levels.gd -- res://worlds/ocean.tres 20

const DEFAULT_WORLD: String = "res://worlds/ocean.tres"
const DEFAULT_SEEDS_PER_LEVEL: int = 12
const EXPECTED_STAGES: int = 3
const EXPECTED_LEVELS_PER_STAGE: int = 3
## Swimming speed used for the time estimate (px/s, about the players' top speed).
const SWIM_SPEED: float = 240.0
## The slower player's top speed (the Guardian), for the escape timer check.
const ESCAPE_SPEED: float = 230.0
## Escape timer >= this times the longest shard -> exit walk at ESCAPE_SPEED.
const ESCAPE_MIN_RATIO: float = 1.6
## Generator proposals checked (normal and boss levels each).
const GENERATOR_PROPOSALS: int = 3
const GENERATOR_TRIES: int = 60
const MARKER_PREFIXES: Array[String] = ["Player", "Goal", "Boss", "Shard", "Creature", "Coral", "Station"]
## Landmarks per level, free space from the room's rock (beyond the footprint),
## from every spawn marker, and from the doorway corridors.
const LANDMARKS_MIN: int = 1
const LANDMARKS_MAX: int = 3
const LANDMARK_ROCK_MARGIN: float = 40.0
const LANDMARK_MARKER_DISTANCE: float = 60.0
const LANDMARK_DOORWAY_MARGIN: float = 40.0
## Two placements of a kind in the same room type and turn must be this far apart.
const LANDMARK_REPEAT_DISTANCE: float = 400.0


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
	## Landmark mix of every level (each one must differ).
	var mixes: Dictionary = {}

	print("World %s: %d room types, %d stages, %d spawn seeds per level" % [
		world.world_name, world.room_chunks.size() + world.boss_arena_rooms.size(), world.get_stage_count(), seeds_per_level])
	var rooms: Array[PackedScene] = world.room_chunks.duplicate()
	rooms.append_array(world.boss_arena_rooms)
	for room: PackedScene in rooms:
		if not _check_room(builder, room):
			all_ok = false

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
			if not _check_graph(definition, label):
				all_ok = false
			if not _check_level(builder, definition, label, seeds_per_level, rng):
				all_ok = false
			if not _check_landmarks(builder, definition, label, mixes, stage_index):
				all_ok = false

	if not _check_lighting(world):
		all_ok = false
	if not _check_generator(builder, world, rng):
		all_ok = false
	builder.free()
	print("RESULT: %s" % ("ALL LEVELS VALID" if all_ok else "SOME CHECKS FAILED"))
	quit(0 if all_ok else 1)


## One room alone: sealed, every marker is reachable; each doorway really opens.
func _check_room(builder: LevelBuilder, scene: PackedScene) -> bool:
	var room := scene.instantiate() as LevelChunk
	var label: String = scene.resource_path.get_file().get_basename()
	var ok: bool = true
	var walls: Array[PackedVector2Array] = room.get_wall_polygons()
	var sealed: Array[PackedVector2Array] = walls.duplicate()
	for side: int in RoomGrid.SIDES:
		if room.has_opening(side):
			sealed.append(builder.seal_polygon(Vector2i.ZERO, side))
	var players: Array[Marker2D] = room.get_spawn_markers("Player")
	if players.is_empty() or room.get_spawn_markers("Goal").is_empty():
		room.free()
		return _fail("room %s needs Player and Goal markers" % label)
	var validator: LayoutValidator = _validator(builder)
	if not validator.flood(sealed, players[0].position):
		ok = _fail("room %s: %s with every door sealed" % [label, "leaks" if validator.leaked else "start is blocked"])
	var markers: int = 0
	for prefix: String in MARKER_PREFIXES:
		for marker: Marker2D in room.get_spawn_markers(prefix):
			markers += 1
			if not validator.is_reachable(marker.position):
				ok = _fail("room %s: marker %s cannot be reached" % [label, marker.name])
	# Each doorway alone unsealed: the flood must get out through it.
	for side: int in RoomGrid.SIDES:
		if not room.has_opening(side):
			continue
		var one_open: Array[PackedVector2Array] = walls.duplicate()
		for other: int in RoomGrid.SIDES:
			if other != side and room.has_opening(other):
				one_open.append(builder.seal_polygon(Vector2i.ZERO, other))
		var door_check: LayoutValidator = _validator(builder)
		door_check.flood(one_open, players[0].position)
		if not door_check.leaked:
			ok = _fail("room %s: the %s doorway is blocked" % [label, RoomGrid.side_names(side)])
	print("Room %-26s openings %-4s %2d markers %s" % [label, RoomGrid.side_names(room.openings), markers, "ok" if ok else "PROBLEM"])
	room.free()
	return ok


## The level's room graph: connected, with branches, loops and dead ends.
func _check_graph(definition: LevelDefinition, label: String) -> bool:
	var links: Dictionary = RoomGrid.connections(definition.rooms)
	var link_count: int = 0
	var branches: int = 0
	var dead_ends: int = 0
	var size := Vector2i.ZERO
	for cell: Vector2i in links:
		var degree: int = (links[cell] as Array).size()
		link_count += degree
		branches += 1 if degree >= 3 else 0
		dead_ends += 1 if degree == 1 else 0
		size = Vector2i(maxi(size.x, cell.x + 1), maxi(size.y, cell.y + 1))
	link_count /= 2
	var reached: int = 0
	for cell: Vector2i in links:
		if RoomGrid.steps_between(links, definition.start_cell, cell) >= 0:
			reached += 1
	var loops: int = link_count - links.size() + 1
	var ok: bool = true
	if reached != links.size():
		ok = _fail("%s: %d rooms cannot be reached from the start" % [label, links.size() - reached])
	if not LevelGenerator.has_required_shape(links):
		ok = _fail("%s: needs branches, a loop and dead ends" % label)
	var exit_steps: int = RoomGrid.steps_between(links, definition.start_cell, definition.exit_cell)
	var lockdown_note: String = "none"
	if definition.has_lockdown():
		var via: int = RoomGrid.steps_between(links, definition.start_cell, definition.lockdown_cell) \
			+ RoomGrid.steps_between(links, definition.lockdown_cell, definition.exit_cell)
		lockdown_note = "on the shortest way" if via == exit_steps else "%d rooms off the shortest way" % (via - exit_steps)
	print("%s: %dx%d grid, %d rooms, %d links, %d branches, %d loop(s), %d dead ends, exit %d rooms from start, lockdown %s" % [
		label, size.x, size.y, links.size(), link_count, branches, loops, dead_ends, exit_steps, lockdown_note])
	return ok


## Completable with many spawn seeds; walking path through all shards to the exit.
func _check_level(builder: LevelBuilder, definition: LevelDefinition, label: String, seeds_per_level: int, rng: RandomNumberGenerator) -> bool:
	var completable: int = 0
	var problems: Dictionary = {}
	var shortest_tour: float = INF
	var longest_tour: float = 0.0
	## Longest walk from any shard to the exit over every layout (escape check).
	var escape_walk: float = 0.0
	var lockdown_spawns: int = -1
	var started: int = Time.get_ticks_msec()
	for i: int in seeds_per_level:
		var base_seed: int = rng.randi() % 1000000
		var first: LevelBuilder.Layout = builder.plan_layout(definition, base_seed)
		if not first.valid:
			problems[first.problem] = int(problems.get(first.problem, 0)) + 1
		first.free_chunks()
		var layout: LevelBuilder.Layout = builder.find_valid_layout(definition, base_seed)
		if layout == null:
			continue
		completable += 1
		if layout.has_lockdown:
			lockdown_spawns = layout.lockdown_spawns.size()
		if definition.escape_event:
			escape_walk = maxf(escape_walk, _longest_shard_to_exit(layout))
		# The path is measured on a few layouts (it is the slow part).
		if i < 3:
			var tour: float = _tour_length(layout)
			shortest_tour = minf(shortest_tour, tour)
			longest_tour = maxf(longest_tour, tour)
		layout.free_chunks()
	var creature_count: int = 0
	for spawn: CreatureSpawn in definition.creatures:
		creature_count += spawn.count
	print("  %d/%d completable | %d shards, %d creatures, %d corals, %d stations%s | start -> shards -> exit: %d-%d px = %d-%d s at full speed | %.1f s checked" % [
		completable, seeds_per_level, definition.shard_count, creature_count, definition.corals, definition.stations,
		", BOSS (%d hp)" % definition.boss_max_health if definition.is_boss_level() else "",
		roundi(shortest_tour), roundi(longest_tour), roundi(shortest_tour / SWIM_SPEED), roundi(longest_tour / SWIM_SPEED),
		(Time.get_ticks_msec() - started) / 1000.0])
	for problem: String in problems:
		print("  first-seed problem x%d: %s" % [problems[problem], problem])
	var ok: bool = _check_balance(definition, label, lockdown_spawns, escape_walk)
	if completable < seeds_per_level:
		return _fail("%s: %d spawn seeds have no valid layout" % [label, seeds_per_level - completable])
	return ok


## The level's landmarks: how many, a mix no other level has, each one clear
## of the room's rock, markers and doorway corridors; and the ambient life of
## one layout on open floor, never a creature.
func _check_landmarks(builder: LevelBuilder, definition: LevelDefinition, label: String, mixes: Dictionary, stage_index: int) -> bool:
	var ok: bool = true
	var count: int = definition.landmarks.size()
	if count < LANDMARKS_MIN or count > LANDMARKS_MAX:
		ok = _fail("%s: %d landmarks (expected %d-%d)" % [label, count, LANDMARKS_MIN, LANDMARKS_MAX])
	var names: Array[String] = []
	for placement: LandmarkPlacement in definition.landmarks:
		names.append(placement.scene.resource_path.get_file().get_basename().trim_prefix("landmark_") if placement.scene else "?")
	var sorted_names: Array[String] = names.duplicate()
	sorted_names.sort()
	var mix: String = ", ".join(sorted_names)
	if mixes.has(mix):
		ok = _fail("%s: same landmarks as %s (%s)" % [label, mixes[mix], mix])
	mixes[mix] = label
	for i: int in definition.landmarks.size():
		var placement: LandmarkPlacement = definition.landmarks[i]
		var stage_key: String = "stage %d %s" % [stage_index, names[i]]
		if mixes.has(stage_key):
			ok = _fail("%s: a %s again in the same stage (%s)" % [label, names[i], mixes[stage_key]])
		mixes[stage_key] = label
		var room_placement: RoomPlacement = definition.get_placement(placement.cell)
		var spot: Array = [room_placement.room.resource_path if room_placement else "", room_placement.quarter_turns if room_placement else 0, placement.offset, label]
		for earlier: Array in mixes.get("spots " + names[i], []):
			if earlier[0] == spot[0] and earlier[1] == spot[1] and (earlier[2] as Vector2).distance_to(placement.offset) < LANDMARK_REPEAT_DISTANCE:
				ok = _fail("%s: the %s stands where it stands in %s (same room type and spot)" % [label, names[i], earlier[3]])
		if not mixes.has("spots " + names[i]):
			mixes["spots " + names[i]] = []
		(mixes["spots " + names[i]] as Array).append(spot)
	var layout: LevelBuilder.Layout = builder.find_valid_layout(definition, 1)
	if layout == null:
		return _fail("%s: no valid layout for the landmark check" % label)
	var rock: Array[PackedVector2Array] = []
	for chunk: LevelChunk in layout.chunks:
		rock.append_array(chunk.get_wall_polygons())
	rock.append_array(layout.seals)
	var markers: Array[Vector2] = []
	for chunk: LevelChunk in layout.chunks:
		for prefix: String in MARKER_PREFIXES:
			for marker: Marker2D in chunk.get_spawn_markers(prefix):
				markers.append(chunk.position + marker.position)
	var doorways: Array[Rect2] = builder.call("_doorway_corridors", layout)
	var notes: Array[String] = []
	for i: int in layout.landmarks.size():
		var landmark: Landmark = layout.landmarks[i]
		notes.append("%s %s" % [names[i], layout.landmark_cells[i]])
		for footprint: PackedVector2Array in landmark.get_placed_footprints():
			for grown: PackedVector2Array in Geometry2D.offset_polygon(footprint, LANDMARK_ROCK_MARGIN):
				for polygon: PackedVector2Array in rock:
					if not Geometry2D.intersect_polygons(grown, polygon).is_empty():
						ok = _fail("%s: landmark %s is closer than %d px to rock" % [label, names[i], LANDMARK_ROCK_MARGIN])
						break
			for marker: Vector2 in markers:
				if Geometry2D.is_point_in_polygon(marker, footprint) or _distance_to_outline(marker, footprint) < LANDMARK_MARKER_DISTANCE:
					ok = _fail("%s: landmark %s is closer than %d px to a marker at %s" % [label, names[i], LANDMARK_MARKER_DISTANCE, marker])
			for doorway: Rect2 in doorways:
				var box := Rect2(footprint[0], Vector2.ZERO)
				for point: Vector2 in footprint:
					box = box.expand(point)
				if box.grow(LANDMARK_DOORWAY_MARGIN).intersects(doorway):
					ok = _fail("%s: landmark %s blocks a doorway" % [label, names[i]])
	var life_ok: bool = true
	for spot: Vector2 in layout.life_positions:
		if not layout.validator.is_reachable(spot):
			life_ok = _fail("%s: ambient life outside the open floor at %s" % [label, spot])
	for scene: PackedScene in layout.life_scenes:
		var probe: Node = scene.instantiate()
		if not probe is AmbientLife or probe.is_in_group("creatures") or probe is CollisionObject2D:
			life_ok = _fail("%s: ambient life %s is not harmless" % [label, scene.resource_path])
		probe.free()
	print("  landmarks: %s | ambient life: %d on open floor%s" % [", ".join(notes), layout.life_positions.size(), "" if life_ok else " PROBLEM"])
	layout.free_chunks()
	return ok and life_ok


static func _distance_to_outline(point: Vector2, outline: PackedVector2Array) -> float:
	var best: float = INF
	for k: int in outline.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, outline[k], outline[(k + 1) % outline.size()])
		best = minf(best, closest.distance_to(point))
	return best


## Sentinels, lockdown wave per mode, and the collapse escape timer per mode.
func _check_balance(definition: LevelDefinition, label: String, lockdown_spawns: int, escape_walk: float) -> bool:
	var ok: bool = true
	var sentinels: int = mini(definition.sentinels, definition.shard_count)
	var wave: String = "no lockdown"
	if definition.has_lockdown():
		wave = "lockdown wave Calm %d / Challenge %d (%d spawn markers)" % [
			definition.lockdown_wave_calm, definition.lockdown_wave_challenge, lockdown_spawns]
		if lockdown_spawns <= 0 and maxi(definition.lockdown_wave_calm, definition.lockdown_wave_challenge) > 0:
			ok = _fail("%s: the lockdown room has no Creature markers for its wave" % label)
		if definition.lockdown_wave_calm > definition.lockdown_wave_challenge:
			ok = _fail("%s: the Calm lockdown wave is bigger than the Challenge one" % label)
	var escape: String = ""
	if definition.escape_event:
		var walk_time: float = escape_walk / ESCAPE_SPEED
		var calm_ratio: float = definition.escape_time_calm / maxf(walk_time, 0.01)
		var challenge_ratio: float = definition.escape_time_challenge / maxf(walk_time, 0.01)
		escape = " | ESCAPE: longest shard -> exit %d px = %.1f s at %d px/s; timer Calm %.0f s (%.2fx), Challenge %.0f s (%.2fx)" % [
			roundi(escape_walk), walk_time, roundi(ESCAPE_SPEED), definition.escape_time_calm, calm_ratio,
			definition.escape_time_challenge, challenge_ratio]
		if challenge_ratio < ESCAPE_MIN_RATIO or calm_ratio < ESCAPE_MIN_RATIO:
			ok = _fail("%s: the escape timer is below %.1fx the longest shard -> exit walk" % [label, ESCAPE_MIN_RATIO])
		if definition.escape_time_calm < definition.escape_time_challenge:
			ok = _fail("%s: the Calm escape timer is shorter than the Challenge one" % label)
	print("  balance: %d sentinel(s) | %s%s" % [sentinels, wave, escape])
	return ok


## The longest walk from any of the layout's shard spots to its exit (pixels).
func _longest_shard_to_exit(layout: LevelBuilder.Layout) -> float:
	var from_exit: PackedInt32Array = layout.validator.distances_from(layout.goal)
	var longest: float = 0.0
	for shard: Vector2 in layout.shards:
		longest = maxf(longest, layout.validator.distance_to(from_exit, shard))
	return longest


## Shortest walk start -> every shard (best order) -> exit, in pixels.
func _tour_length(layout: LevelBuilder.Layout) -> float:
	var validator: LayoutValidator = layout.validator
	var points: Array[Vector2] = [layout.player_spawns[0]]
	points.append_array(layout.shards)
	var maps: Array[PackedInt32Array] = []
	for point: Vector2 in points:
		maps.append(validator.distances_from(point))
	var best: float = INF
	for order: Array in _permutations(range(1, points.size())):
		var length: float = 0.0
		var at: int = 0
		for next: int in order:
			length += validator.distance_to(maps[at], points[next])
			at = next
		length += validator.distance_to(maps[at], layout.goal)
		best = minf(best, length)
	return best


func _permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items]
	var result: Array = []
	for i: int in items.size():
		var rest: Array = items.duplicate()
		var first: Variant = rest.pop_at(i)
		for tail: Array in _permutations(rest):
			result.append([first] + tail)
	return result


func _validator(builder: LevelBuilder) -> LayoutValidator:
	var validator := LayoutValidator.new()
	validator.cell_size = builder.validator_cell_size
	validator.clearance = builder.validator_clearance
	return validator


func _check_lighting(world: WorldConfig) -> bool:
	var ok: bool = true
	var previous: float = INF
	for stage_index: int in world.get_stage_count():
		var stage: StageDefinition = world.stages[stage_index]
		var brightness: float = stage.ambient_color.get_luminance()
		print("Stage %d lighting: ambient luminance %.3f (deep %.3f), light shafts %.2f" % [
			stage_index + 1, brightness, stage.deep_ambient_color.get_luminance(), stage.light_shaft_strength])
		if brightness >= previous:
			ok = _fail("stage %d is not darker than the stage before" % (stage_index + 1))
		if stage.deep_ambient_color.get_luminance() > brightness:
			ok = _fail("stage %d: the deep ambient colour is brighter than the ambient colour" % (stage_index + 1))
		if stage_index > 0 and stage.light_shaft_strength > 0.0:
			ok = _fail("stage %d has light shafts (only the first stage should)" % (stage_index + 1))
		previous = brightness
	return ok


func _check_generator(builder: LevelBuilder, world: WorldConfig, rng: RandomNumberGenerator) -> bool:
	var ok: bool = true
	var generator := LevelGenerator.new()
	generator.template = world.get_level(1, 0)
	for boss: bool in [false, true]:
		generator.boss_scene = world.get_level(0, 2).boss if boss else null
		var valid: int = 0
		for i: int in GENERATOR_PROPOSALS:
			var proposal: LevelDefinition = generator.propose_valid(world, rng.randi() % 1000000, GENERATOR_TRIES, builder)
			if proposal and _check_graph(proposal, "  generator proposal"):
				valid += 1
		print("Generator (%s levels): %d/%d proposals valid" % ["boss" if boss else "normal", valid, GENERATOR_PROPOSALS])
		if valid < GENERATOR_PROPOSALS:
			ok = _fail("the generator could not propose a valid %s level" % ("boss" if boss else "normal"))
	return ok


func _fail(message: String) -> bool:
	print("  FAILED: " + message)
	return false
