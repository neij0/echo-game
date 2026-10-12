class_name LevelBuilder
extends Node2D
## Builds one level from its LevelDefinition. The chunks are fixed (always the
## same layout); a pocket chunk is attached to every side opening in the order
## the definition lists them. Creatures, corals and stations are put on random
## chunk markers, with a NEW seed on every build (retries included), so a retry
## never plays exactly the same. Every planned level is checked with the
## LayoutValidator (BFS) before it is built; if the spawns fail the check, the
## next spawn seed is tried.

signal level_built(level_index: int)

@export var world: WorldConfig
## -1 = a random spawn seed on every attempt. Any other value makes the attempts
## reproducible (each attempt still gets a different seed derived from it).
@export var forced_seed: int = -1
## Spawn seeds tried per build before giving up.
@export var max_attempts: int = 25
## Seed step between two tries of the same build.
@export var attempt_seed_step: int = 7919

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
	var player_spawns: Array[Vector2] = []
	## The ancient light (normal level) or the boss (boss level).
	var goal: Vector2
	var has_boss: bool = false
	var creature_scenes: Array[PackedScene] = []
	var creature_positions: Array[Vector2] = []
	var corals: Array[Vector2] = []
	var stations: Array[Vector2] = []
	var problem: String = ""

	func free_chunks() -> void:
		for chunk: LevelChunk in chunks:
			if is_instance_valid(chunk) and not chunk.is_inside_tree():
				chunk.free()
		chunks.clear()


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
var _creatures: Array[Creature] = []


func _ready() -> void:
	add_to_group("level")


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
	if definition == null or definition.chunks.size() < 2:
		layout.problem = "a level needs at least a start chunk and an end chunk"
		return layout
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed

	# Main path: the definition's chunks, stacked top to bottom.
	var main_chunks: Array[LevelChunk] = []
	var y: float = 0.0
	for scene: PackedScene in definition.chunks:
		var chunk: LevelChunk = _place_chunk(scene, y)
		main_chunks.append(chunk)
		y += chunk.height
	layout.height = y
	layout.chunks.append_array(main_chunks)
	var start: LevelChunk = main_chunks[0]
	var end_chunk: LevelChunk = main_chunks[main_chunks.size() - 1]

	# A pocket on every side opening, in the definition's order (mirrored for
	# the right side).
	var pockets: Array[LevelChunk] = []
	for chunk: LevelChunk in main_chunks:
		for opening: Marker2D in chunk.get_side_openings():
			if definition.pockets.is_empty():
				layout.problem = "side opening without a pocket (the pockets list is empty)"
				return layout
			var pocket_scene: PackedScene = definition.pockets[pockets.size() % definition.pockets.size()]
			var pocket := pocket_scene.instantiate() as LevelChunk
			if opening.name == "SideRight":
				pocket.mirror()
			pocket.position = chunk.position + opening.position
			pockets.append(pocket)
			layout.chunks.append(pocket)

	# Fixed spawn points: players, and the ancient light or the boss.
	for marker: Marker2D in _sorted_by_name(start.get_spawn_markers("Player")):
		layout.player_spawns.append(start.position + marker.position)
	layout.has_boss = definition.is_boss_level()
	var goal_markers: Array[Marker2D] = end_chunk.get_spawn_markers("Boss" if layout.has_boss else "Goal")
	if layout.player_spawns.is_empty() or goal_markers.is_empty():
		layout.problem = "start chunk needs Player markers, end chunk a %s marker" % ("Boss" if layout.has_boss else "Goal")
		return layout
	layout.goal = end_chunk.position + goal_markers[0].position

	# Shuffled spawn points (different on every attempt).
	var creature_spots: Array[Vector2] = []
	for chunk: LevelChunk in main_chunks:
		if chunk != start:
			creature_spots.append_array(_marker_positions(chunk, "Creature"))
	_shuffle(creature_spots, rng)
	for spawn: CreatureSpawn in definition.creatures:
		for i: int in spawn.count:
			if creature_spots.is_empty():
				layout.problem = "not enough creature markers"
				return layout
			layout.creature_scenes.append(spawn.scene)
			layout.creature_positions.append(creature_spots.pop_back())

	var coral_spots: Array[Vector2] = []
	for chunk: LevelChunk in layout.chunks:
		coral_spots.append_array(_marker_positions(chunk, "Coral"))
	_shuffle(coral_spots, rng)
	for i: int in mini(definition.corals, coral_spots.size()):
		layout.corals.append(coral_spots[i])

	if pockets.size() < definition.stations:
		layout.problem = "not enough side pockets for %d stations" % definition.stations
		return layout
	var station_pockets: Array[LevelChunk] = pockets.duplicate()
	_shuffle_chunks(station_pockets, rng)
	for i: int in definition.stations:
		var pocket: LevelChunk = station_pockets[i]
		var markers: Array[Marker2D] = pocket.get_spawn_markers("Station")
		if markers.is_empty():
			continue
		# Closest to the pocket opening first; the bias picks how deep inside.
		markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool: return a.position.length() < b.position.length())
		var pick: int = roundi(definition.station_distance_bias * (markers.size() - 1))
		layout.stations.append(pocket.position + markers[pick].position)

	_validate(layout)
	return layout


func _validate(layout: Layout) -> void:
	var polygons: Array[PackedVector2Array] = []
	for chunk: LevelChunk in layout.chunks:
		polygons.append_array(chunk.get_wall_polygons())
	var validator := LayoutValidator.new()
	validator.cell_size = validator_cell_size
	validator.clearance = validator_clearance
	if not validator.flood(polygons, layout.player_spawns[0]):
		layout.problem = "leak into the void" if validator.leaked else "start is blocked"
		return
	var targets: Array[Vector2] = [layout.goal]
	targets.append_array(layout.player_spawns)
	targets.append_array(layout.stations)
	targets.append_array(layout.creature_positions)
	targets.append_array(layout.corals)
	for target: Vector2 in targets:
		if not validator.is_reachable(target):
			layout.problem = "unreachable point %s" % target
			return
	layout.valid = true


func _instantiate(layout: Layout) -> void:
	_level = Node2D.new()
	_level.name = "Level"
	add_child(_level)
	level_height = layout.height
	var progress: float = (level_index + 0.5) / maxf(level_count, 1.0)
	var floor_color: Color = world.floor_color_shallow.lerp(world.floor_color_deep, progress)
	for chunk: LevelChunk in layout.chunks:
		_apply_palette(chunk, floor_color)
	# Floors first (all chunks), so pocket floors never cover a neighbour's walls.
	for chunk: LevelChunk in layout.chunks:
		_level.add_child(chunk)
	_player_spawns = layout.player_spawns

	for position_value: Vector2 in layout.corals:
		_spawn(world.coral_scene, position_value)
	for position_value: Vector2 in layout.stations:
		_spawn(world.station_scene, position_value)
	_creatures.clear()
	for i: int in layout.creature_scenes.size():
		var creature := _spawn(layout.creature_scenes[i], layout.creature_positions[i]) as Creature
		if creature:
			_creatures.append(creature)
	_goal = null
	_boss = null
	if layout.has_boss:
		_boss = _spawn_boss(layout.goal)
	else:
		_goal = _spawn(world.goal_scene, layout.goal) as AncientLight
	# The sonar overlay samples the new rock outlines.
	get_tree().call_group("sonar_overlay", "rebuild_samples")


func _spawn_boss(at: Vector2) -> Creature:
	var boss := _definition.boss.instantiate() as Creature
	if boss == null:
		push_error("LevelBuilder: the boss scene must be a Creature")
		return null
	# Before _ready, so the creature starts with the overridden health.
	if _definition.boss_max_health > 0:
		boss.max_health = _definition.boss_max_health
	boss.position = at
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
			(node as RockWall).color = world.rock_color
		elif node is Polygon2D:
			(node as Polygon2D).color = floor_color


func _place_chunk(scene: PackedScene, y: float) -> LevelChunk:
	var chunk := scene.instantiate() as LevelChunk
	chunk.position = Vector2(0.0, y)
	return chunk


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


static func _shuffle_chunks(values: Array[LevelChunk], rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: LevelChunk = values[i]
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


func get_creatures() -> Array[Creature]:
	return _creatures
