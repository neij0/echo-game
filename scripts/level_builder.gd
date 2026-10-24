class_name LevelBuilder
extends Node2D
## Builds one level from its LevelDefinition: a grid of hand-made rooms, each
## turned as the definition says. Neighbouring rooms connect where both have an
## opening on the shared side; every other opening is sealed with rock. The
## layout is always the same; creatures, corals, stations and shard spots are
## put on random room markers with a NEW seed on every build (retries
## included), so a retry never plays exactly the same. Shards go to different
## rooms, spread as far apart as possible. Every planned level is checked with
## the LayoutValidator (BFS) before it is built; if the spawns fail the check,
## the next spawn seed is tried.
## Built levels get: the Echo Shards on the planned spots, Sentinels next to
## some of them, the LockdownRoom in the lockdown cell, a ShardDoor on the boss
## arena's doorway (boss levels), and a navigation mesh baked from every rock,
## so creatures can path through doorways and around corners. When a door or a
## lockdown barrier changes, the mesh is rebaked one frame later, while the
## camera shake started by that event hides the short hitch. Large creatures
## (the boss) get their own mesh, baked with a bigger agent radius on a second
## navigation map (navigation_map_for), so their paths never lead through gaps
## their body cannot fit through. Known: Godot 4.7 logs "edge error(s)"
## warnings for that second map on some levels (the same mesh on the default
## map is silent); the paths themselves test fine.

signal level_built(level_index: int)

@export var world: WorldConfig
## -1 = a random spawn seed on every attempt. Any other value makes the attempts
## reproducible (each attempt still gets a different seed derived from it).
@export var forced_seed: int = -1
## Spawn seeds tried per build before giving up.
@export var max_attempts: int = 25
## Seed step between two tries of the same build.
@export var attempt_seed_step: int = 7919

## Solid rock drawn around the whole level (this many pixels beyond its walls),
## so outside the playable area looks like rock fading into darkness instead
## of a hard black edge. Not a wall: no collision, no shadow, no sonar edge.
@export var outer_rock_margin: float = 3000.0

@export_group("Navigation")
## Creature clearance used when baking the navigation mesh (about the radius
## of a normal creature plus a small margin).
@export var navigation_agent_radius: float = 26.0
## Clearance a creature needs beyond its body radius. A creature whose
## body_radius + this is bigger than navigation_agent_radius uses the large mesh.
@export var navigation_margin: float = 6.0
## Agent radius of the large mesh (the biggest creature, the boss: 46 + margin).
@export var large_navigation_agent_radius: float = 52.0

@export_group("Sentinels")
## A Sentinel's post is this far from its shard, towards the room's centre
## (falls back to the shard spot if that point cannot be reached).
@export var sentinel_post_offset: float = 80.0

@export_group("Arena Door")
## Camera shake when the boss arena door opens (also hides the navigation rebake).
@export var door_shake_strength: float = 6.0
@export var door_shake_time: float = 0.5

@export_group("Validation")
@export var validator_cell_size: float = 20.0
## Free space a player needs (player radius + margin).
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
	## Boss levels: the rock that seals the arena's doorway until all shards
	## are collected (this node's space).
	var door_polygon: PackedVector2Array = PackedVector2Array()
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


## Level inside the current stage (0-based) and how many the stage has.
var level_index: int = 0
var level_count: int = 1
## Level counted from the world's first level (for the depth readout).
var global_level_index: int = 0
var spawn_seed: int = 0
var attempts_used: int = 0
var level_height: float = 1.0
var _builds: int = 0
var _definition: LevelDefinition
var _level: Node2D
var _goal: AncientLight
var _boss: Creature
var _player_spawns: Array[Vector2] = []
## Planned Echo Shard spots of the current level (spawned in a later step).
var shard_spots: Array[Vector2] = []
var _creatures: Array[Creature] = []
## Where this level's creatures were spawned (global positions).
var creature_spots: Array[Vector2] = []
var _shards: Array[EchoShard] = []
var _door: ShardDoor
var _lockdown: LockdownRoom
var _navigation: NavigationRegion2D
var _navigation_large: NavigationRegion2D
var _large_map: RID
var _rebake_pending: bool = false
## Rock outlines of the current level (navigation obstructions, door excluded).
var _nav_obstacles: Array[PackedVector2Array] = []
var _nav_bounds := Rect2()


func _ready() -> void:
	add_to_group("level")
	_large_map = NavigationServer2D.map_create()
	var default_map: RID = get_world_2d().navigation_map
	NavigationServer2D.map_set_cell_size(_large_map, NavigationServer2D.map_get_cell_size(default_map))
	NavigationServer2D.map_set_edge_connection_margin(_large_map, NavigationServer2D.map_get_edge_connection_margin(default_map))
	NavigationServer2D.map_set_merge_rasterizer_cell_scale(_large_map, NavigationServer2D.map_get_merge_rasterizer_cell_scale(default_map))
	NavigationServer2D.map_set_use_edge_connections(_large_map, NavigationServer2D.map_get_use_edge_connections(default_map))
	NavigationServer2D.map_set_link_connection_radius(_large_map, NavigationServer2D.map_get_link_connection_radius(default_map))
	NavigationServer2D.map_set_active(_large_map, true)


func _exit_tree() -> void:
	if _large_map.is_valid():
		NavigationServer2D.free_rid(_large_map)
		_large_map = RID()


## The navigation map a creature of this body radius paths on.
func navigation_map_for(body_radius: float) -> RID:
	if body_radius + navigation_margin > navigation_agent_radius and _large_map.is_valid():
		return _large_map
	return get_world_2d().navigation_map


## A fresh spawn seed for the next build (random, or derived from forced_seed).
func next_spawn_seed() -> int:
	_builds += 1
	if forced_seed >= 0:
		return absi(hash([forced_seed, global_level_index, _builds]))
	return randi() % 1000000


## Plans the level with a new spawn seed until the plan passes validation,
## then builds it. Returns false if no seed worked within max_attempts.
func build_level(definition: LevelDefinition, index: int, count: int, global_index: int) -> bool:
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


## Plans (but does not build) the level with one spawn seed and validates it.
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
				layout.seals.append(seal_polygon(cell, side))
		layout.links[cell] = neighbours

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
	return layout


## Rock that closes an unused opening of a room (this node's space).
func seal_polygon(cell: Vector2i, side: int) -> PackedVector2Array:
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
	return PackedVector2Array([local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)])


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


static func _nearest(points: Array[Vector2], to: Vector2) -> Vector2:
	var best: Vector2 = to
	var best_distance: float = INF
	for point: Vector2 in points:
		if point.distance_squared_to(to) < best_distance:
			best_distance = point.distance_squared_to(to)
			best = point
	return best


func _instantiate(layout: Layout) -> void:
	_level = Node2D.new()
	_level.name = "Level"
	add_child(_level)
	level_height = layout.height
	var progress: float = (level_index + 0.5) / maxf(level_count, 1.0)
	var floor_color: Color = world.floor_color_shallow.lerp(world.floor_color_deep, progress)
	for chunk: LevelChunk in layout.chunks:
		_apply_palette(chunk, floor_color)
	_add_outer_rock(layout, floor_color.lightened(world.rock_fill_lift))
	# Floors first (all chunks), so pocket floors never cover a neighbour's walls.
	for chunk: LevelChunk in layout.chunks:
		_level.add_child(chunk)
	for polygon: PackedVector2Array in layout.seals:
		var seal := RockWall.new()
		seal.name = "Seal"
		seal.polygon = polygon
		seal.color = floor_color.lightened(world.rock_fill_lift)
		_level.add_child(seal)
	_player_spawns = layout.player_spawns
	shard_spots = layout.shards

	_shards.clear()
	for position_value: Vector2 in layout.shards:
		var shard := _spawn(world.shard_scene, position_value) as EchoShard
		if shard:
			_shards.append(shard)
	for position_value: Vector2 in layout.corals:
		_spawn(world.coral_scene, position_value)
	for position_value: Vector2 in layout.stations:
		_spawn(world.station_scene, position_value)
	_creatures.clear()
	creature_spots.clear()
	for i: int in layout.creature_scenes.size():
		creature_spots.append(to_global(layout.creature_positions[i]))
		var creature := _spawn(layout.creature_scenes[i], layout.creature_positions[i]) as Creature
		if creature:
			_creatures.append(creature)
	for post: Vector2 in layout.sentinel_posts:
		creature_spots.append(to_global(post))
		var sentinel := _spawn(world.sentinel_scene, post) as Creature
		if sentinel:
			_creatures.append(sentinel)
	_goal = null
	_boss = null
	_door = null
	if layout.has_boss:
		_boss = _spawn_boss(layout.goal)
		_add_door(layout.door_polygon, floor_color.lightened(world.rock_fill_lift))
	else:
		_goal = _spawn(world.goal_scene, layout.goal) as AncientLight
	_add_lockdown(layout, floor_color.lightened(world.rock_fill_lift))
	_add_navigation(layout)
	# The sonar overlay samples the new rock outlines.
	get_tree().call_group("sonar_overlay", "rebuild_samples")


func _add_outer_rock(layout: Layout, rock_color: Color) -> void:
	var bounds := Rect2()
	var first: bool = true
	for chunk: LevelChunk in layout.chunks:
		for polygon: PackedVector2Array in chunk.get_wall_polygons():
			for point: Vector2 in polygon:
				bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
				first = false
	bounds = bounds.grow(outer_rock_margin)
	var rock := Polygon2D.new()
	rock.name = "OuterRock"
	rock.color = rock_color
	rock.polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	# First child = drawn under every chunk.
	_level.add_child(rock)


func _add_lockdown(layout: Layout, rock_color: Color) -> void:
	_lockdown = null
	if not layout.has_lockdown or world.lockdown_room_scene == null:
		return
	_lockdown = world.lockdown_room_scene.instantiate() as LockdownRoom
	_lockdown.room_rect = layout.lockdown_rect
	_lockdown.barrier_polygons = layout.lockdown_barriers
	_lockdown.barrier_color = rock_color
	_lockdown.spawn_points = layout.lockdown_spawns
	_lockdown.creature_scene = world.lockdown_creature_scene
	_lockdown.wave_calm = _definition.lockdown_wave_calm if _definition else 0
	_lockdown.wave_challenge = _definition.lockdown_wave_challenge if _definition else 0
	_lockdown.navigation_changed.connect(_rebake_navigation_soon)
	_level.add_child(_lockdown)


func _add_door(door_polygon: PackedVector2Array, rock_color: Color) -> void:
	if door_polygon.is_empty() or world.shard_door_scene == null:
		return
	_door = world.shard_door_scene.instantiate() as ShardDoor
	# Before _ready: RockWall builds its shapes from these.
	_door.polygon = door_polygon
	_door.color = rock_color
	_level.add_child(_door)


## Bakes the creatures' navigation mesh: the whole grid is walkable except the
## rock (room walls, seals and the closed arena door), shrunk by the agent radius.
func _add_navigation(layout: Layout) -> void:
	_nav_obstacles.clear()
	for chunk: LevelChunk in layout.chunks:
		_nav_obstacles.append_array(chunk.get_wall_polygons())
	_nav_obstacles.append_array(layout.seals)
	_nav_bounds = Rect2()
	for chunk: LevelChunk in layout.chunks:
		var room := Rect2(chunk.position, Vector2.ONE * world.room_size)
		_nav_bounds = room if not _nav_bounds.has_area() else _nav_bounds.merge(room)
	_navigation = NavigationRegion2D.new()
	_navigation.name = "Navigation"
	_navigation.navigation_polygon = bake_navigation(_nav_obstacles, _nav_bounds, _changing_obstacles())
	_level.add_child(_navigation)
	_navigation_large = NavigationRegion2D.new()
	_navigation_large.name = "NavigationLarge"
	_navigation_large.navigation_polygon = bake_navigation(_nav_obstacles, _nav_bounds, _changing_obstacles(), large_navigation_agent_radius)
	# Before it enters the tree, so it never sits on the default map.
	_navigation_large.set_navigation_map(_large_map)
	_level.add_child(_navigation_large)


## Rock that can open or close: the closed arena door, closed lockdown barriers.
func _changing_obstacles() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if _door and not _door.is_open:
		result.append(_door.polygon)
	if is_instance_valid(_lockdown):
		result.append_array(_lockdown.get_obstacles())
	return result


## Rebakes the navigation on the next frame (the event that asked for it has
## just started a camera shake, which hides the short hitch).
func _rebake_navigation_soon() -> void:
	if _rebake_pending:
		return
	_rebake_pending = true
	await get_tree().process_frame
	_rebake_pending = false
	if is_instance_valid(_navigation):
		_navigation.navigation_polygon = bake_navigation(_nav_obstacles, _nav_bounds, _changing_obstacles())
	if is_instance_valid(_navigation_large):
		_navigation_large.navigation_polygon = bake_navigation(_nav_obstacles, _nav_bounds, _changing_obstacles(), large_navigation_agent_radius)


## A navigation mesh over bounds with every obstacle cut out (extras = rock
## that can open or close; may be empty). agent_radius < 0 = navigation_agent_radius.
func bake_navigation(obstacles: Array[PackedVector2Array], bounds: Rect2, extras: Array[PackedVector2Array], agent_radius: float = -1.0) -> NavigationPolygon:
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)]))
	for polygon: PackedVector2Array in obstacles:
		source.add_obstruction_outline(polygon)
	for polygon: PackedVector2Array in extras:
		source.add_obstruction_outline(polygon)
	var navigation := NavigationPolygon.new()
	navigation.agent_radius = agent_radius if agent_radius >= 0.0 else navigation_agent_radius
	NavigationServer2D.bake_from_source_geometry_data(navigation, source)
	return navigation


## All shards collected: unlock the ancient light, or open the arena door (and
## let the creatures path through it).
func open_exit() -> void:
	if _goal:
		_goal.set_shard_progress(_goal.shards_needed, _goal.shards_needed)
	if _door and not _door.is_open:
		_door.open()
		get_tree().call_group("shared_camera", "shake_with", door_shake_strength, door_shake_time)
		_rebake_navigation_soon()


func _spawn_boss(at: Vector2) -> Creature:
	var boss := _definition.boss.instantiate() as Creature
	if boss == null:
		push_error("LevelBuilder: the boss scene must be a Creature")
		return null
	# Before _ready, so the creature starts with the overridden health.
	if _definition.boss_max_health > 0:
		boss.max_health = _definition.boss_max_health
	boss.position = at
	# The Echo's echo points to it once the arena door is open.
	boss.add_to_group("level_exit")
	_level.add_child(boss)
	return boss


func _clear() -> void:
	if _level:
		# Out of the tree right away, so groups (rock_walls, creatures...) only
		# contain the new level from now on.
		remove_child(_level)
		_level.queue_free()
		_level = null


func _spawn(scene: PackedScene, at: Vector2) -> Node2D:
	if scene == null:
		return null
	var node := scene.instantiate() as Node2D
	node.position = at
	_level.add_child(node)
	return node


func _apply_palette(chunk: LevelChunk, floor_color: Color) -> void:
	for node: Node in chunk.find_children("*", "", true, false):
		if node is RockWall:
			(node as RockWall).color = floor_color.lightened(world.rock_fill_lift)
		elif node is Polygon2D:
			(node as Polygon2D).color = floor_color


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


# --- Queries used by the HUD, Darkness, StageManager ------------------------

func depth_at(world_y: float) -> float:
	return world.surface_depth_m + global_level_index * world.level_depth_step_m + maxf(world_y, 0.0) * world.meters_per_pixel


## 0 at the top of the current level, 1 at its bottom.
func depth_ratio_at(world_y: float) -> float:
	return clampf(world_y / level_height, 0.0, 1.0)


## 0 at the top of the stage's first level, 1 at the bottom of its last level.
func stage_progress_at(world_y: float) -> float:
	return (level_index + depth_ratio_at(world_y)) / maxf(level_count, 1.0)


func get_spawn_position(player_number: int) -> Vector2:
	if _player_spawns.is_empty():
		return global_position
	return to_global(_player_spawns[clampi(player_number - 1, 0, _player_spawns.size() - 1)])


## The ancient light (null in a boss level).
func get_goal() -> AncientLight:
	return _goal


## The boss (null in a normal level).
func get_boss() -> Creature:
	return _boss


## The lockdown event of the current level (null if it has none).
func get_lockdown() -> LockdownRoom:
	return _lockdown if is_instance_valid(_lockdown) else null


## The boss arena's door (null in a normal level).
func get_exit_door() -> ShardDoor:
	return _door


## The Echo Shards of the current level (collected ones are freed).
func get_shards() -> Array[EchoShard]:
	return _shards


func get_creatures() -> Array[Creature]:
	return _creatures
