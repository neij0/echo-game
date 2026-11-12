class_name LevelBuilder
extends Node3D
## Builds one level from its LevelDefinition: a grid of hand-made rooms, each
## turned as the definition says. Neighbouring rooms connect where both have an
## opening on the shared side; every other opening is sealed with rock. The
## layout is always the same; creatures, corals, stations and shard spots are
## put on random room markers with a NEW seed on every build (retries
## included), so a retry never plays exactly the same. Shards go to different
## rooms, spread as far apart as possible. Every planned level is checked with
## the LayoutValidator (BFS) before it is built; if the spawns fail the check,
## the next spawn seed is tried.
##
## 3D: the planning (rooms, turns, seals, markers, the validator) works on the
## rooms' 2D floor plans, in pixels ("plan space"). Building turns plan space
## into the 3D floor: a plan point (x, y) is at (x, 0, y) * units_per_pixel
## (WorldConfig). Plan-space values below are in pixels, 3D values in units.
## Every rock outline is pulled up into rock (RockMesher): its height rises and
## falls along it (rock_middle_*, rock_height_spread, height_wave) and drops
## near every connected doorway (doorway_clear_*), so no rock top hides a way
## through. One mesh and one collider per room. Around the level, flat outer
## rock (no collision, no sonar) hides the void. The navigation mesh is baked
## from the plans (NavigationBaker) for normal creatures and, on a second map,
## for large ones (navigation_map_for).
## Built so far in 3D: rooms, seals, outer rock, the landmarks' solid footprints
## (plain rock until the landmark models, Phase C), creatures, Sentinels,
## corals, stations, Echo Shards and the ancient light. Boss levels put the
## ancient light on the arena's Boss marker until the boss, the arena door and
## the vents are ported (Phase B, next step); the lockdown, harmless life and
## floor scatter come later too (their plan is kept).

signal level_built(level_index: int)

const ROCK_SHADER: Shader = preload("res://shaders/rock_surface.gdshader")
const FLOOR_SHADER: Shader = preload("res://shaders/floor_surface.gdshader")

@export var world: WorldConfig
## -1 = a random spawn seed on every attempt. Any other value makes the attempts
## reproducible (each attempt still gets a different seed derived from it).
@export var forced_seed: int = -1
## Spawn seeds tried per build before giving up.
@export var max_attempts: int = 25
## Seed step between two tries of the same build.
@export var attempt_seed_step: int = 7919

## Flat rock around the whole level, this many pixels beyond the grid, so the
## space outside looks like rock fading into darkness. Not a wall: no
## collision, no sonar.
@export var outer_rock_margin: float = 3000.0
## Height of the outer rock's top (units).
@export var outer_rock_height: float = 1.1

@export_group("Look")
@export var floor_color: Color = Color(0.15, 0.19, 0.25)
@export var rock_color: Color = Color(0.24, 0.29, 0.36)
## The outer rock: the rock colour darkened by this share (it is never lit by
## the sonar, only by lights near the level's edge).
@export_range(0.0, 1.0) var outer_rock_darken: float = 0.25
@export var sonar_color: Color = Color(0.25, 0.85, 1.0)
## How strongly the pulse lights flat ground and rock.
@export var floor_fill_energy: float = 0.07
@export var rock_fill_energy: float = 0.24
## Corners sharper than this get a hard edge (and a sonar line).
@export var rock_smooth_degrees: float = 40.0
## Rock outlines are split into pieces this long (pixels), so the height can
## rise and fall along them.
@export var rock_piece_length: float = 20.0
## Height of a landmark's solid footprint until the landmark models (pixels).
@export var landmark_rock_height: float = 40.0

@export_group("Navigation")
## Creature clearance of the normal navigation mesh (units; a whole number of
## cells: the bake rounds it up).
@export var navigation_agent_radius: float = 0.5
## Clearance a creature needs beyond its body radius. A creature whose
## body_radius + this is bigger than navigation_agent_radius uses the large mesh.
@export var navigation_margin: float = 0.12
## Agent radius of the large mesh (the boss; units, whole cells).
@export var large_navigation_agent_radius: float = 1.0
@export var navigation_cell_size: float = 0.125
@export var navigation_cell_height: float = 0.125

@export_group("Sentinels")
## A Sentinel's post is this far from its shard, towards the room's centre
## (falls back to the shard spot if that point cannot be reached; pixels).
@export var sentinel_post_offset: float = 80.0

@export_group("Floor Detail")
## (Plan only for now: the floor scatter comes back with the models.)
## The same room type looks different in every level: its rock heights scale
## by up to this share (+ or -), ...
@export_range(0.0, 0.5) var room_height_jitter: float = 0.2
## ... and small things lie on its floor (this many per room).
@export var scatter_min: int = 14
@export var scatter_max: int = 30
## Open floor needed around a scattered thing (pixels).
@export var scatter_free_radius: float = 12.0

@export_group("Seals")
## Soft bumps on a seal's edge facing the room (pixels, + or -), one point
## every seal_bump_spacing pixels.
@export var seal_bump: float = 10.0
@export var seal_bump_spacing: float = 30.0

@export_group("Rock Height")
## A rock's middle height is picked in this share of its room's height range
## (0 = rock_height_min, 1 = rock_height_max), by the rock's position.
@export var rock_middle_low: float = 0.25
@export var rock_middle_high: float = 0.75
## How far the height rises and falls along a rock, as a share of the range...
@export var rock_height_spread: float = 0.4
## ...and over what distance (pixels).
@export var height_wave: float = 200.0
## Near a connected doorway the rocks drop to this height (pixels), rising
## back to their own over doorway_clear_distance (so no top hides the way through).
@export var doorway_rock_height: float = 10.0
@export var doorway_clear_distance: float = 150.0
## Depth of the doorway corridor on each side of the shared room edge (pixels).
@export var doorway_clear_depth: float = 200.0

@export_group("Ambient Life")
## Random spots tried per creature of ambient life before giving up on it.
@export var life_spot_tries: int = 24
## Ambient life of one room keeps at least this far apart (pixels).
@export var life_spacing: float = 110.0
## near_rock life: rock must be within this many pixels of the spot.
@export var life_rock_distance: float = 50.0

@export_group("Validation")
@export var validator_cell_size: float = 20.0
## Free space a player needs (player radius + margin, pixels).
@export var validator_clearance: float = 16.0


## A planned level: chunk instances (not in the tree yet) and spawn positions,
## all in this node's local space.
class Layout:
	var layout_seed: int = 0
	var valid: bool = false
	var height: float = 0.0
	var chunks: Array[LevelChunk] = []
	## Room per grid cell (Vector2i -> LevelChunk).
	var rooms: Dictionary = {}
	## Connected neighbour cells per cell (Vector2i -> Array[Vector2i]).
	var links: Dictionary = {}
	## Rock polygons that close unused openings (this node's space).
	var seals: Array[PackedVector2Array] = []
	## The cell of each seal (same order as seals).
	var seal_cells: Array[Vector2i] = []
	var player_spawns: Array[Vector2] = []
	## The ancient light (normal level) or the boss (boss level).
	var goal: Vector2
	var has_boss: bool = false
	var creature_scenes: Array[PackedScene] = []
	var creature_positions: Array[Vector2] = []
	var corals: Array[Vector2] = []
	var stations: Array[Vector2] = []
	## Echo Shard spots (one per room) and the rooms they are in.
	var shards: Array[Vector2] = []
	var shard_cells: Array[Vector2i] = []
	## Landmarks (not in the tree yet), the cell of each, and their solid
	## footprints (this node's space).
	var landmarks: Array[Landmark] = []
	var landmark_cells: Array[Vector2i] = []
	var landmark_polygons: Array[PackedVector2Array] = []
	## Floor scatter spots per room (Vector2i -> PackedVector2Array).
	var scatter: Dictionary = {}
	## Harmless life: scene and spot of each.
	var life_scenes: Array[PackedScene] = []
	var life_positions: Array[Vector2] = []
	## Boss levels: the rock that seals the arena's doorway until all shards
	## are collected (this node's space).
	var door_polygon: PackedVector2Array = PackedVector2Array()
	## Boss levels: the arena's oxygen vents ("Vent*" markers).
	var vents: Array[Vector2] = []
	## Reference point of the lockdown room (its Goal marker), if any.
	var lockdown_point: Vector2
	var has_lockdown: bool = false
	## The lockdown room's square, the rock for each of its connected doorways
	## and its Creature markers (where the wave wakes).
	var lockdown_rect := Rect2()
	var lockdown_barriers: Array[PackedVector2Array] = []
	var lockdown_spawns: Array[Vector2] = []
	## Sentinel posts (next to some shards).
	var sentinel_posts: Array[Vector2] = []
	## The flood of the last check (can measure walking distances).
	var validator: LayoutValidator
	var problem: String = ""

	func free_chunks() -> void:
		for chunk: LevelChunk in chunks:
			if is_instance_valid(chunk) and not chunk.is_inside_tree():
				chunk.free()
		chunks.clear()
		rooms.clear()
		for landmark: Landmark in landmarks:
			if is_instance_valid(landmark) and not landmark.is_inside_tree():
				landmark.free()
		landmarks.clear()



## Level inside the current stage (0-based) and how many the stage has.
var level_index: int = 0
var level_count: int = 1
## Level counted from the world's first level (for the depth readout).
var global_level_index: int = 0
var spawn_seed: int = 0
var attempts_used: int = 0
## Height of the level's grid (pixels, plan space).
var level_height: float = 1.0
## Seconds the last build and its navigation bakes took (benchmark).
var build_seconds: float = 0.0
var bake_seconds: float = 0.0
var _builds: int = 0
var _definition: LevelDefinition
var _level: Node3D
var _goal: AncientLight
var _player_spawns: Array[Vector2] = []
## Planned Echo Shard spots of the current level (plan space).
var shard_spots: Array[Vector2] = []
var _creatures: Array[Creature] = []
## Where this level's creatures were spawned (3D).
var creature_spots: Array[Vector3] = []
var _shards: Array[EchoShard] = []
var _layout: Layout
var _navigation: NavigationRegion3D
var _navigation_large: NavigationRegion3D
var _large_map: RID
var _floor_material: ShaderMaterial
var _rock_material: ShaderMaterial
var _outer_material: ShaderMaterial
var _materials_registered: bool = false


func _ready() -> void:
	add_to_group("level")
	_large_map = NavigationServer3D.map_create()
	NavigationBaker.apply_to_map(_large_map, navigation_cell_size, navigation_cell_height)
	NavigationServer3D.map_set_active(_large_map, true)
	# A new level's mesh must be used from the next physics frame on: with the
	# (default) asynchronous map updates, paths came from the previous level's
	# mesh for up to ~5 frames after a build.
	NavigationServer3D.map_set_use_async_iterations(_large_map, false)
	NavigationServer3D.map_set_use_async_iterations(get_world_3d().navigation_map, false)
	_floor_material = _surface_material(FLOOR_SHADER, floor_color, floor_fill_energy)
	_rock_material = _surface_material(ROCK_SHADER, rock_color, rock_fill_energy)
	_rock_material.set_shader_parameter("cut_enabled", true)
	_outer_material = _surface_material(ROCK_SHADER, rock_color.darkened(outer_rock_darken), 0.0)
	_outer_material.set_shader_parameter("cut_enabled", true)
	_outer_material.set_shader_parameter("sonar_color", Color.BLACK)


func _exit_tree() -> void:
	if _large_map.is_valid():
		NavigationServer3D.free_rid(_large_map)
		_large_map = RID()


## The navigation map a creature of this body radius (units) paths on.
func navigation_map_for(body_radius: float) -> RID:
	if body_radius + navigation_margin > navigation_agent_radius and _large_map.is_valid():
		return _large_map
	return get_world_3d().navigation_map


## A fresh spawn seed for the next build (random, or derived from forced_seed).
func next_spawn_seed() -> int:
	_builds += 1
	if forced_seed >= 0:
		return absi(hash([forced_seed, global_level_index, _builds]))
	return randi() % 1000000


## Plans the level with a new spawn seed until the plan passes validation,
## then builds it. Returns false if no seed worked within max_attempts.
func build_level(definition: LevelDefinition, index: int, count: int, global_index: int) -> bool:
	var started: int = Time.get_ticks_usec()
	level_index = index
	level_count = count
	global_level_index = global_index
	_definition = definition
	var layout: Layout = find_valid_layout(definition, next_spawn_seed())
	if layout == null:
		push_error("LevelBuilder: no valid layout for level %d" % (index + 1))
		return false
	_clear()
	_instantiate(layout)
	build_seconds = float(Time.get_ticks_usec() - started) / 1000000.0
	level_built.emit(index)
	return true


## Tries spawn seeds base_seed, base_seed + step, ... Returns the first valid
## layout (chunks not yet in the tree) or null. Sets attempts_used and spawn_seed.
func find_valid_layout(definition: LevelDefinition, base_seed: int) -> Layout:
	for attempt: int in max_attempts:
		var layout: Layout = plan_layout(definition, base_seed + attempt * attempt_seed_step)
		if layout.valid:
			attempts_used = attempt + 1
			spawn_seed = layout.layout_seed
			return layout
		layout.free_chunks()
	return null


func plan_layout(definition: LevelDefinition, layout_seed: int) -> Layout:
	var layout := Layout.new()
	layout.layout_seed = layout_seed
	if definition == null or definition.rooms.is_empty():
		layout.problem = "a level needs rooms"
		return layout
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var size: float = world.room_size

	# Rooms on the grid, turned as placed.
	var rows: int = 0
	for placement: RoomPlacement in definition.rooms:
		if placement.room == null or layout.rooms.has(placement.cell):
			layout.problem = "empty or doubled room at %s" % placement.cell
			return layout
		var room := placement.room.instantiate() as LevelChunk
		room.rotate_quarters(placement.quarter_turns, size)
		room.position = Vector2(placement.cell) * size
		layout.rooms[placement.cell] = room
		layout.chunks.append(room)
		rows = maxi(rows, placement.cell.y + 1)
	layout.height = rows * size

	# Connect matching openings, seal all the others.
	for cell: Vector2i in layout.rooms:
		var room: LevelChunk = layout.rooms[cell]
		var neighbours: Array[Vector2i] = []
		for side: int in RoomGrid.SIDES:
			if not room.has_opening(side):
				continue
			var other := layout.rooms.get(cell + RoomGrid.direction(side)) as LevelChunk
			if other and other.has_opening(RoomGrid.opposite(side)):
				neighbours.append(cell + RoomGrid.direction(side))
			else:
				layout.seals.append(seal_polygon(cell, side, true))
				layout.seal_cells.append(cell)
		layout.links[cell] = neighbours

	# Landmarks: the same spot on every attempt.
	for placement: LandmarkPlacement in definition.landmarks:
		if placement.scene == null or not layout.rooms.has(placement.cell):
			layout.problem = "landmark outside the grid at %s" % placement.cell
			return layout
		var landmark := placement.scene.instantiate() as Landmark
		landmark.position = Vector2(placement.cell) * size + placement.offset
		landmark.configure(placement)
		layout.landmarks.append(landmark)
		layout.landmark_cells.append(placement.cell)
		layout.landmark_polygons.append_array(landmark.get_placed_footprints())

	# Start, exit (ancient light or boss) and lockdown room.
	var start := layout.rooms.get(definition.start_cell) as LevelChunk
	var exit_room := layout.rooms.get(definition.exit_cell) as LevelChunk
	if start == null or exit_room == null or definition.start_cell == definition.exit_cell:
		layout.problem = "start and exit must be two different rooms of the grid"
		return layout
	for marker: Marker2D in _sorted_by_name(start.get_spawn_markers("Player")):
		layout.player_spawns.append(start.position + marker.position)
	layout.has_boss = definition.is_boss_level()
	var goal_markers: Array[Marker2D] = exit_room.get_spawn_markers("Boss" if layout.has_boss else "Goal")
	if layout.player_spawns.is_empty() or goal_markers.is_empty():
		layout.problem = "start room needs Player markers, exit room a %s marker" % ("Boss" if layout.has_boss else "Goal")
		return layout
	layout.goal = exit_room.position + goal_markers[0].position
	if layout.has_boss:
		layout.vents = _marker_positions(exit_room, "Vent")
		# The arena's doorway gets a door (the same shape as a seal).
		for side: int in RoomGrid.SIDES:
			if layout.links[definition.exit_cell].has(definition.exit_cell + RoomGrid.direction(side)):
				layout.door_polygon = seal_polygon(definition.exit_cell, side)
				break
	var lockdown := layout.rooms.get(definition.lockdown_cell) as LevelChunk
	if lockdown:
		var markers: Array[Marker2D] = lockdown.get_spawn_markers("Goal")
		if not markers.is_empty():
			layout.has_lockdown = true
			layout.lockdown_point = lockdown.position + markers[0].position
			layout.lockdown_rect = Rect2(lockdown.position, Vector2.ONE * size)
			for side: int in RoomGrid.SIDES:
				if layout.links[definition.lockdown_cell].has(definition.lockdown_cell + RoomGrid.direction(side)):
					layout.lockdown_barriers.append(seal_polygon(definition.lockdown_cell, side))
			layout.lockdown_spawns = _marker_positions(lockdown, "Creature")

	# Shuffled spawn points (different on every attempt).
	var creature_spots: Array[Vector2] = []
	var coral_spots: Array[Vector2] = []
	var station_spots: Array[Vector2] = []
	for cell: Vector2i in layout.rooms:
		var room: LevelChunk = layout.rooms[cell]
		coral_spots.append_array(_marker_positions(room, "Coral"))
		if cell != definition.start_cell:
			creature_spots.append_array(_marker_positions(room, "Creature"))
			station_spots.append_array(_marker_positions(room, "Station"))
	_shuffle(creature_spots, rng)
	for spawn: CreatureSpawn in definition.creatures:
		for i: int in spawn.count:
			if creature_spots.is_empty():
				layout.problem = "not enough creature markers"
				return layout
			layout.creature_scenes.append(spawn.scene)
			layout.creature_positions.append(creature_spots.pop_back())
	_shuffle(coral_spots, rng)
	for i: int in mini(definition.corals, coral_spots.size()):
		layout.corals.append(coral_spots[i])
	if station_spots.size() < definition.stations:
		layout.problem = "not enough station markers for %d stations" % definition.stations
		return layout
	_shuffle(station_spots, rng)
	for i: int in definition.stations:
		layout.stations.append(station_spots[i])
	if not _pick_shards(layout, definition, rng):
		return layout
	_pick_sentinels(layout, definition, rng)

	_validate(layout)
	if layout.valid:
		_pick_life(layout, rng)
	return layout


## Rock that closes an unused opening of a room (this node's space).
## natural: its edge facing the room gets soft bumps (seal_bump), so it does
## not look like a cut block; its ends stay where they are.
func seal_polygon(cell: Vector2i, side: int, natural: bool = false) -> PackedVector2Array:
	var size: float = world.room_size
	var half_door: float = world.room_door_width * 0.5 + world.room_wall_band * 0.2
	var depth: float = world.room_seal_depth
	var local := Rect2()
	match side:
		RoomGrid.Side.NORTH:
			local = Rect2(size * 0.5 - half_door, 0.0, half_door * 2.0, depth)
		RoomGrid.Side.SOUTH:
			local = Rect2(size * 0.5 - half_door, size - depth, half_door * 2.0, depth)
		RoomGrid.Side.WEST:
			local = Rect2(0.0, size * 0.5 - half_door, depth, half_door * 2.0)
		_:
			local = Rect2(size - depth, size * 0.5 - half_door, depth, half_door * 2.0)
	local.position += Vector2(cell) * size
	var corners := PackedVector2Array([local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)])
	if not natural:
		return corners
	# The edge facing the room: [corner from, corner to, direction into the room].
	var inner: Array = [3, 0, Vector2.LEFT]
	match side:
		RoomGrid.Side.NORTH:
			inner = [2, 3, Vector2.DOWN]
		RoomGrid.Side.SOUTH:
			inner = [0, 1, Vector2.UP]
		RoomGrid.Side.WEST:
			inner = [1, 2, Vector2.RIGHT]
	var result := PackedVector2Array()
	var phase: float = fposmod(sin(cell.x * 12.9898 + cell.y * 78.233 + side * 37.719) * 43758.5453, 1.0) * TAU
	for i: int in 4:
		result.append(corners[i])
		if i != int(inner[0]):
			continue
		var a: Vector2 = corners[inner[0]]
		var b: Vector2 = corners[inner[1]]
		var steps: int = maxi(2, ceili(a.distance_to(b) / seal_bump_spacing))
		for k: int in range(1, steps):
			var t: float = float(k) / steps
			var bump: float = seal_bump * sin(PI * t) * (0.6 * sin(TAU * 1.5 * t + phase) + 0.4 * sin(TAU * 3.3 * t + phase * 1.7))
			result.append(a.lerp(b, t) + (inner[2] as Vector2) * bump)
	return result


## Shard spots: one per room (never the start or exit room). Each next shard
## goes to the room farthest (in rooms) from the start and the shards already
## placed; ties are broken by the seed.
func _pick_shards(layout: Layout, definition: LevelDefinition, rng: RandomNumberGenerator) -> bool:
	var candidates: Dictionary = {}
	for cell: Vector2i in layout.rooms:
		if cell == definition.start_cell or cell == definition.exit_cell:
			continue
		var spots: Array[Vector2] = _marker_positions(layout.rooms[cell] as LevelChunk, "Shard")
		if not spots.is_empty():
			candidates[cell] = spots
	if candidates.size() < definition.shard_count:
		layout.problem = "not enough rooms with Shard markers for %d shards" % definition.shard_count
		return false
	var cells: Array = candidates.keys()
	_shuffle_any(cells, rng)
	var placed: Array[Vector2i] = [definition.start_cell]
	for i: int in definition.shard_count:
		var best: Vector2i = cells[0]
		var best_score: int = -1
		for cell: Vector2i in cells:
			if cell in placed:
				continue
			var score: int = 1000000
			for other: Vector2i in placed:
				var steps: int = RoomGrid.steps_between(layout.links, cell, other)
				score = mini(score, steps if steps >= 0 else 1000)
			if score > best_score:
				best_score = score
				best = cell
		placed.append(best)
		var spots: Array[Vector2] = candidates[best]
		layout.shard_cells.append(best)
		layout.shards.append(spots[rng.randi_range(0, spots.size() - 1)])
	return true


## Sentinel posts: next to `sentinels` of the shards (picked by the seed),
## a little towards the centre of the shard's room.
func _pick_sentinels(layout: Layout, definition: LevelDefinition, rng: RandomNumberGenerator) -> void:
	var order: Array = range(layout.shards.size())
	_shuffle_any(order, rng)
	for i: int in mini(definition.sentinels, order.size()):
		var index: int = order[i]
		var spot: Vector2 = layout.shards[index]
		var room_center: Vector2 = (Vector2(layout.shard_cells[index]) + Vector2(0.5, 0.5)) * world.room_size
		layout.sentinel_posts.append(spot + spot.direction_to(room_center) * sentinel_post_offset)


func _validate(layout: Layout) -> void:
	var polygons: Array[PackedVector2Array] = []
	for chunk: LevelChunk in layout.chunks:
		polygons.append_array(chunk.get_wall_polygons())
	polygons.append_array(layout.seals)
	polygons.append_array(layout.landmark_polygons)
	var validator := LayoutValidator.new()
	validator.cell_size = validator_cell_size
	validator.clearance = validator_clearance
	layout.validator = validator
	if not validator.flood(polygons, layout.player_spawns[0]):
		layout.problem = "leak into the void" if validator.leaked else "start is blocked"
		return
	var targets: Array[Vector2] = [layout.goal]
	targets.append_array(layout.player_spawns)
	targets.append_array(layout.stations)
	targets.append_array(layout.creature_positions)
	targets.append_array(layout.corals)
	targets.append_array(layout.shards)
	if layout.has_lockdown:
		targets.append(layout.lockdown_point)
		targets.append_array(layout.lockdown_spawns)
	for target: Vector2 in targets:
		if not validator.is_reachable(target):
			layout.problem = "unreachable point %s" % target
			return
	# A post inside rock falls back to its shard's spot (always reachable).
	for i: int in layout.sentinel_posts.size():
		if not validator.is_reachable(layout.sentinel_posts[i]):
			layout.sentinel_posts[i] = _nearest(layout.shards, layout.sentinel_posts[i])
	layout.valid = true


## Harmless life on open floor of every room (WorldConfig.ambient_life),
## from the validator's flood: never inside rock, a landmark or the void.
func _pick_life(layout: Layout, rng: RandomNumberGenerator) -> void:
	var size: float = world.room_size
	for cell: Vector2i in layout.rooms:
		var room := Rect2(Vector2(cell) * size, Vector2.ONE * size).grow(-world.room_wall_band * 0.5)
		layout.scatter[cell] = _scatter_spots(layout, cell, room)
		var taken: Array[Vector2] = []
		for spawn: AmbientLifeSpawn in world.ambient_life:
			if spawn.scene == null:
				continue
			for i: int in rng.randi_range(spawn.per_room_min, spawn.per_room_max):
				for attempt: int in life_spot_tries:
					var spot := Vector2(rng.randf_range(room.position.x, room.end.x), rng.randf_range(room.position.y, room.end.y))
					if not layout.validator.is_open(spot, spawn.free_radius):
						continue
					if spawn.near_rock and not layout.validator.is_near_blocked(spot, life_rock_distance):
						continue
					if taken.any(func(other: Vector2) -> bool: return other.distance_to(spot) < life_spacing):
						continue
					taken.append(spot)
					layout.life_scenes.append(spawn.scene)
					layout.life_positions.append(spot)
					break


## Open-floor spots for a room's FloorScatter, picked by the level and the
## cell (the same level always looks the same; another level differs).
func _scatter_spots(layout: Layout, cell: Vector2i, room: Rect2) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash([global_level_index, cell, "scatter"]))
	var spots := PackedVector2Array()
	var wanted: int = rng.randi_range(scatter_min, scatter_max)
	for attempt: int in wanted * 3:
		if spots.size() >= wanted:
			break
		var spot := Vector2(rng.randf_range(room.position.x, room.end.x), rng.randf_range(room.position.y, room.end.y))
		if layout.validator.is_open(spot, scatter_free_radius):
			spots.append(spot)
	return spots


## Same value for the same level and cell, in [0, 1).
func _room_pick(cell: Vector2i, key: String) -> float:
	return float(absi(hash([global_level_index, cell, key])) % 10007) / 10007.0


static func _nearest(points: Array[Vector2], to: Vector2) -> Vector2:
	var best: Vector2 = to
	var best_distance: float = INF
	for point: Vector2 in points:
		if point.distance_squared_to(to) < best_distance:
			best_distance = point.distance_squared_to(to)
			best = point
	return best


func _instantiate(layout: Layout) -> void:
	_register_materials()
	_layout = layout
	_level = Node3D.new()
	_level.name = "Level"
	add_child(_level)
	level_height = layout.height
	var doorways: Array[Rect2] = _doorway_corridors(layout)

	# Floors and rock, one mesh and one collider per room.
	var size: float = world.room_size
	for cell: Vector2i in layout.rooms:
		var chunk: LevelChunk = layout.rooms[cell]
		var room := Node3D.new()
		room.name = "Room_%d_%d" % [cell.x, cell.y]
		_level.add_child(room)
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2.ONE * size * _units()
		var floor_instance := MeshInstance3D.new()
		floor_instance.name = "Floor"
		floor_instance.mesh = floor_mesh
		floor_instance.material_override = _floor_material
		floor_instance.position = to_world((Vector2(cell) + Vector2(0.5, 0.5)) * size)
		room.add_child(floor_instance)
		var rocks: Array[Dictionary] = []
		var room_scale: float = 1.0 + (_room_pick(cell, "height") - 0.5) * 2.0 * room_height_jitter
		var height_range: float = chunk.rock_height_max - chunk.rock_height_min
		for polygon: PackedVector2Array in chunk.get_wall_polygons():
			var pick: float = _position_pick(_middle_of(polygon))
			var middle: float = lerpf(chunk.rock_height_min, chunk.rock_height_max, lerpf(rock_middle_low, rock_middle_high, pick)) * room_scale
			rocks.append({"outline": polygon, "height": middle, "spread": height_range * rock_height_spread * room_scale})
		for i: int in layout.seals.size():
			if layout.seal_cells[i] == cell:
				rocks.append({"outline": layout.seals[i], "height": lerpf(chunk.rock_height_min, chunk.rock_height_max, 0.5),
					"spread": height_range * rock_height_spread})
		for i: int in layout.landmarks.size():
			if layout.landmark_cells[i] != cell:
				continue
			for polygon: PackedVector2Array in layout.landmarks[i].get_placed_footprints():
				rocks.append({"outline": polygon, "height": landmark_rock_height, "spread": 0.0})
		room.add_child(_room_rock(rocks, doorways))
	_add_outer_rock(layout)

	_player_spawns = layout.player_spawns
	shard_spots = layout.shards
	_shards.clear()
	for spot: Vector2 in layout.shards:
		var shard := _spawn(world.shard_scene, spot) as EchoShard
		if shard:
			_shards.append(shard)
	for spot: Vector2 in layout.corals:
		_spawn(world.coral_scene, spot)
	for spot: Vector2 in layout.stations:
		_spawn(world.station_scene, spot)
	_creatures.clear()
	creature_spots.clear()
	for i: int in layout.creature_scenes.size():
		var creature := _spawn(layout.creature_scenes[i], layout.creature_positions[i]) as Creature
		if creature:
			creature_spots.append(creature.position)
			_creatures.append(creature)
	for post: Vector2 in layout.sentinel_posts:
		var sentinel := _spawn(world.sentinel_scene, post) as Creature
		if sentinel:
			creature_spots.append(sentinel.position)
			_creatures.append(sentinel)
	# Until the boss is ported, a boss level ends at an ancient light on the
	# arena's Boss marker.
	_goal = _spawn(world.goal_scene, layout.goal) as AncientLight
	_add_navigation(layout)


## The materials of this level's surfaces join the sonar, the cut-away and the
## sand trails (once: the materials are shared by every level).
func _register_materials() -> void:
	if _materials_registered:
		return
	var sonar: Sonar = Sonar.find(get_tree())
	var cutaway: ViewCutaway = ViewCutaway.find(get_tree())
	var trails: SandTrails = SandTrails.find(get_tree())
	if sonar == null:
		return
	_materials_registered = true
	for material: ShaderMaterial in [_floor_material, _rock_material, _outer_material]:
		sonar.register_material(material)
	if cutaway:
		cutaway.register_material(_rock_material)
		cutaway.register_material(_outer_material)
	if trails:
		trails.register_material(_floor_material)


func _surface_material(shader: Shader, color: Color, fill_energy: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("sonar_color", sonar_color)
	material.set_shader_parameter("fill_energy", fill_energy)
	return material


## The rocks of one room as one mesh and one collider. rocks: outline (plan
## space), middle height and spread (pixels).
func _room_rock(rocks: Array[Dictionary], doorways: Array[Rect2]) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Rock"
	body.collision_layer = 1
	body.collision_mask = 0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var units: float = _units()
	for rock: Dictionary in rocks:
		var outline: PackedVector2Array = RockMesher.subdivide(rock["outline"] as PackedVector2Array, rock_piece_length)
		var reach: Rect2 = _bounds_of(outline).grow(doorway_clear_distance)
		var zones: Array[Rect2] = []
		for doorway: Rect2 in doorways:
			if reach.intersects(doorway):
				zones.append(doorway)
		var middle: float = rock["height"]
		var spread: float = rock["spread"]
		var height_at: Callable = func(point: Vector2) -> float:
			return rock_height_at(point / units, middle, spread, zones) * units
		var mesh: ArrayMesh = RockMesher.rock_mesh(_to_units(outline), middle * units, rock_smooth_degrees, height_at)
		if mesh.get_surface_count() > 0:
			tool.append_from(mesh, 0, Transform3D.IDENTITY)
	var merged: ArrayMesh = tool.commit()
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = merged
	instance.material_override = _rock_material
	body.add_child(instance)
	if merged.get_surface_count() > 0:
		var shape: ConcavePolygonShape3D = merged.create_trimesh_shape()
		shape.backface_collision = true
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
	return body


## Height of a rock at plan point p (pixels): its middle height with a slow
## rise and fall along the rock, dropping to doorway_rock_height near a
## doorway corridor.
func rock_height_at(p: Vector2, middle: float, spread: float, zones: Array[Rect2]) -> float:
	var h: float = middle + spread * _noise2(p / maxf(height_wave, 1.0))
	if not zones.is_empty():
		var distance: float = INF
		for zone: Rect2 in zones:
			var dx: float = maxf(maxf(zone.position.x - p.x, p.x - zone.end.x), 0.0)
			var dy: float = maxf(maxf(zone.position.y - p.y, p.y - zone.end.y), 0.0)
			distance = minf(distance, Vector2(dx, dy).length())
		var f: float = clampf(distance / maxf(doorway_clear_distance, 1.0), 0.0, 1.0)
		h = lerpf(minf(doorway_rock_height, h), h, f * f * (3.0 - 2.0 * f))
	return maxf(h, 1.0)


## Flat rock tops round the level: every empty cell of the grid's bounds plus
## a frame outer_rock_margin wide. Lit only by lights near the level's edge.
func _add_outer_rock(layout: Layout) -> void:
	var size: float = world.room_size
	var cells := Rect2i()
	var first: bool = true
	for cell: Vector2i in layout.rooms:
		cells = Rect2i(cell, Vector2i.ONE) if first else cells.merge(Rect2i(cell, Vector2i.ONE))
		first = false
	var slabs: Array[Rect2] = []
	for x: int in range(cells.position.x, cells.end.x):
		for y: int in range(cells.position.y, cells.end.y):
			if not layout.rooms.has(Vector2i(x, y)):
				slabs.append(Rect2(Vector2(x, y) * size, Vector2.ONE * size))
	var grid := Rect2(Vector2(cells.position) * size, Vector2(cells.size) * size)
	var outer: Rect2 = grid.grow(outer_rock_margin)
	slabs.append(Rect2(outer.position, Vector2(outer.size.x, grid.position.y - outer.position.y)))
	slabs.append(Rect2(Vector2(outer.position.x, grid.end.y), Vector2(outer.size.x, outer.end.y - grid.end.y)))
	slabs.append(Rect2(Vector2(outer.position.x, grid.position.y), Vector2(grid.position.x - outer.position.x, grid.size.y)))
	slabs.append(Rect2(Vector2(grid.end.x, grid.position.y), Vector2(outer.end.x - grid.end.x, grid.size.y)))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for slab: Rect2 in slabs:
		var a: Vector3 = to_world(slab.position) + Vector3.UP * outer_rock_height
		var b: Vector3 = to_world(Vector2(slab.end.x, slab.position.y)) + Vector3.UP * outer_rock_height
		var c: Vector3 = to_world(slab.end) + Vector3.UP * outer_rock_height
		var d: Vector3 = to_world(Vector2(slab.position.x, slab.end.y)) + Vector3.UP * outer_rock_height
		# Clockwise seen from above: Godot's front face.
		for corner: Vector3 in [a, b, c, a, c, d]:
			tool.add_vertex(corner)
	var instance := MeshInstance3D.new()
	instance.name = "OuterRock"
	instance.mesh = tool.commit()
	instance.material_override = _outer_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_level.add_child(instance)


## Bakes the creatures' navigation meshes from the plans: every room's square
## is walkable except its rock (walls, seals, landmark footprints).
func _add_navigation(layout: Layout) -> void:
	var started: int = Time.get_ticks_usec()
	var floors: Array[PackedVector2Array] = []
	var rocks: Array[Dictionary] = []
	var size: float = world.room_size
	for cell: Vector2i in layout.rooms:
		var corner: Vector2 = Vector2(cell) * size
		floors.append(_to_units(PackedVector2Array([corner, corner + Vector2(size, 0.0),
			corner + Vector2(size, size), corner + Vector2(0.0, size)])))
	var obstacles: Array[PackedVector2Array] = []
	for chunk: LevelChunk in layout.chunks:
		obstacles.append_array(chunk.get_wall_polygons())
	obstacles.append_array(layout.seals)
	obstacles.append_array(layout.landmark_polygons)
	for polygon: PackedVector2Array in obstacles:
		rocks.append({"outline": _to_units(polygon), "height": 1.0})
	NavigationBaker.apply_to_map(get_world_3d().navigation_map, navigation_cell_size, navigation_cell_height)
	_navigation = NavigationRegion3D.new()
	_navigation.name = "Navigation"
	_navigation.navigation_mesh = NavigationBaker.bake(floors, rocks, navigation_agent_radius, navigation_cell_size, navigation_cell_height)
	_level.add_child(_navigation)
	_navigation_large = NavigationRegion3D.new()
	_navigation_large.name = "NavigationLarge"
	_navigation_large.navigation_mesh = NavigationBaker.bake(floors, rocks, large_navigation_agent_radius, navigation_cell_size, navigation_cell_height)
	# Before it enters the tree, so it never sits on the default map.
	_navigation_large.set_navigation_map(_large_map)
	_level.add_child(_navigation_large)
	bake_seconds = float(Time.get_ticks_usec() - started) / 1000000.0


## All shards collected: unlock the ancient light.
func open_exit() -> void:
	if _goal:
		_goal.set_shard_progress(_goal.shards_needed, _goal.shards_needed)


func _clear() -> void:
	if _level:
		# Out of the tree right away, so groups (creatures, corals...) only
		# contain the new level from now on.
		remove_child(_level)
		_level.queue_free()
		_level = null
	if _layout:
		_layout.free_chunks()
		_layout = null


## An instance of scene on a plan point (null if the scene is missing or not 3D).
func _spawn(scene: PackedScene, at: Vector2) -> Node3D:
	if scene == null:
		return null
	var instance: Node = scene.instantiate()
	var node := instance as Node3D
	if node == null:
		push_warning("LevelBuilder: %s is not a 3D scene yet; skipped" % scene.resource_path)
		instance.free()
		return null
	node.position = to_world(at)
	_level.add_child(node)
	return node


# --- Plan space and 3D ----------------------------------------------------------

func _units() -> float:
	return world.units_per_pixel if world else 0.02


## A plan point (pixels) on the 3D floor.
func to_world(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y) * _units()


## A 3D point back to plan space (pixels).
func to_plan(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / _units()


func _to_units(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	var units: float = _units()
	for point: Vector2 in points:
		result.append(point * units)
	return result


## Same value for the same rock position and level, in [0, 1).
func _position_pick(middle: Vector2) -> float:
	return fposmod(sin(middle.x * 0.0173 + middle.y * 0.0291 + global_level_index * 1.618) * 43758.5453, 1.0)


static func _middle_of(points: PackedVector2Array) -> Vector2:
	var middle := Vector2.ZERO
	for point: Vector2 in points:
		middle += point / points.size()
	return middle


static func _bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


## Smooth value noise in [-1, 1].
static func _noise2(p: Vector2) -> float:
	var cell := Vector2(floorf(p.x), floorf(p.y))
	var f: Vector2 = p - cell
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var top_row: float = lerpf(_hash(cell.x * 57.0 + cell.y * 113.0), _hash((cell.x + 1.0) * 57.0 + cell.y * 113.0), f.x)
	var bottom_row: float = lerpf(_hash(cell.x * 57.0 + (cell.y + 1.0) * 113.0), _hash((cell.x + 1.0) * 57.0 + (cell.y + 1.0) * 113.0), f.x)
	return lerpf(top_row, bottom_row, f.y) * 2.0 - 1.0


static func _hash(n: float) -> float:
	return fposmod(sin(n) * 43758.5453, 1.0)


func _doorway_corridors(layout: Layout) -> Array[Rect2]:
	var size: float = world.room_size
	var result: Array[Rect2] = []
	for cell: Vector2i in layout.links:
		for other: Vector2i in layout.links[cell]:
			# Each doorway once (from the cell with the smaller neighbour step).
			if other.x < cell.x or other.y < cell.y:
				continue
			var middle: Vector2 = (Vector2(cell) + Vector2(other) + Vector2.ONE) * 0.5 * size
			var across: float = world.room_door_width
			var along: float = doorway_clear_depth * 2.0
			var extent := Vector2(along, across) if other.x != cell.x else Vector2(across, along)
			result.append(Rect2(middle - extent * 0.5, extent))
	return result


func _marker_positions(chunk: LevelChunk, prefix: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for marker: Marker2D in chunk.get_spawn_markers(prefix):
		result.append(chunk.position + marker.position)
	return result


func _sorted_by_name(markers: Array[Marker2D]) -> Array[Marker2D]:
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool: return String(a.name) < String(b.name))
	return markers


static func _shuffle(values: Array[Vector2], rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Vector2 = values[i]
		values[i] = values[j]
		values[j] = swap


static func _shuffle_any(values: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap




# --- Queries used by the HUD, Darkness, the level flow ---------------------------

## Depth in metres at a 3D point's z (the HUD's depth readout).
func depth_at(world_z: float) -> float:
	return world.surface_depth_m + global_level_index * world.level_depth_step_m + maxf(world_z / _units(), 0.0) * world.meters_per_pixel


## 0 at the top of the current level, 1 at its bottom (3D z).
func depth_ratio_at(world_z: float) -> float:
	return clampf(world_z / _units() / level_height, 0.0, 1.0)


## 0 at the top of the stage's first level, 1 at the bottom of its last level.
func stage_progress_at(world_z: float) -> float:
	return (level_index + depth_ratio_at(world_z)) / maxf(level_count, 1.0)


func get_spawn_position(player_number: int) -> Vector3:
	if _player_spawns.is_empty():
		return global_position
	return to_world(_player_spawns[clampi(player_number - 1, 0, _player_spawns.size() - 1)])


## The ancient light (the exit; on a boss level, for now, in the arena).
func get_goal() -> AncientLight:
	return _goal


## The Echo Shards of the current level (collected ones are freed).
func get_shards() -> Array[EchoShard]:
	return _shards


func get_creatures() -> Array[Creature]:
	var alive: Array[Creature] = []
	for creature: Creature in _creatures:
		if is_instance_valid(creature):
			alive.append(creature)
	return alive


## The plan of the current level (rooms, links, spawns; plan space).
func get_layout() -> Layout:
	return _layout
