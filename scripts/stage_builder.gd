class_name StageBuilder
extends Node2D
## Builds each stage of the run from the world's hand-made chunks: one start
## chunk, a random number of middle chunks, one goal chunk, and a pocket chunk
## on every side opening. Creatures, corals, stations and the goal are spawned
## on random chunk markers, with counts from the world's StageSpawns. Every
## layout is checked with the LayoutValidator (BFS) before it is built; if it
## fails, the next seed is tried. Everything is decided by the seed.

signal stage_built(stage_index: int)

@export var world: WorldConfig
## -1 = a random run seed. Any other value forces this run seed (for testing).
@export var forced_seed: int = -1
## Seeds tried per stage before giving up.
@export var max_attempts: int = 25
## Seed step between attempts.
@export var attempt_seed_step: int = 7919

@export_group("Validation")
@export var validator_cell_size: float = 20.0
## Free space a player needs (player radius + margin).
@export var validator_clearance: float = 16.0


## A planned stage: chunk instances (not in the tree yet) and spawn positions,
## all in this node's local space.
class Layout:
	var layout_seed: int = 0
	var valid: bool = false
	var height: float = 0.0
	var chunks: Array[LevelChunk] = []
	var player_spawns: Array[Vector2] = []
	var goal: Vector2
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


var run_seed: int = 0
var stage_index: int = 0
var stage_seed: int = 0
var attempts_used: int = 0
var stage_height: float = 1.0
var _level: Node2D
var _goal: AncientLight
var _player_spawns: Array[Vector2] = []
var _creatures: Array[Creature] = []


func _ready() -> void:
	add_to_group("level")
	run_seed = forced_seed if forced_seed >= 0 else randi() % 1000000


func get_stage_count() -> int:
	return world.get_stage_count()


func seed_for_stage(index: int) -> int:
	return absi(hash([run_seed, index]))


## Plans layouts from the stage's seed until one passes validation, then
## builds it. Returns false if no seed worked within max_attempts.
func build_stage(index: int) -> bool:
	stage_index = index
	var layout: Layout = find_valid_layout(index, seed_for_stage(index))
	if layout == null:
		push_error("StageBuilder: no valid layout for stage %d" % (index + 1))
		return false
	_clear()
	_instantiate(layout)
	stage_built.emit(index)
	return true


## Tries seeds base_seed, base_seed + step, ... Returns the first valid layout
## (chunks not yet in the tree) or null. Sets attempts_used and stage_seed.
func find_valid_layout(index: int, base_seed: int) -> Layout:
	for attempt: int in max_attempts:
		var layout: Layout = plan_layout(index, base_seed + attempt * attempt_seed_step)
		if layout.valid:
			attempts_used = attempt + 1
			stage_seed = layout.layout_seed
			return layout
		layout.free_chunks()
	return null


## Plans (but does not build) the layout for one seed and validates it.
func plan_layout(index: int, layout_seed: int) -> Layout:
	var layout := Layout.new()
	layout.layout_seed = layout_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var stage: StageSpawns = world.get_stage(index)

	# Main path: start, middles (no chunk twice in a row), goal.
	var main_chunks: Array[LevelChunk] = []
	var y: float = 0.0
	var start: LevelChunk = _place_chunk(_pick(world.start_chunks, rng, null), y)
	main_chunks.append(start)
	y += start.height
	var middle_count: int = rng.randi_range(stage.middle_chunks_min, stage.middle_chunks_max)
	var previous: PackedScene = null
	for i: int in middle_count:
		var scene: PackedScene = _pick(world.middle_chunks, rng, previous)
		previous = scene
		var middle: LevelChunk = _place_chunk(scene, y)
		main_chunks.append(middle)
		y += middle.height
	var goal_chunk: LevelChunk = _place_chunk(_pick(world.goal_chunks, rng, null), y)
	main_chunks.append(goal_chunk)
	y += goal_chunk.height
	layout.height = y
	layout.chunks.append_array(main_chunks)

	# A pocket on every side opening (mirrored for the right side).
	var pockets: Array[LevelChunk] = []
	for chunk: LevelChunk in main_chunks:
		for opening: Marker2D in chunk.get_side_openings():
			var pocket := _pick(world.pocket_chunks, rng, null).instantiate() as LevelChunk
			if opening.name == "SideRight":
				pocket.mirror()
			pocket.position = chunk.position + opening.position
			pockets.append(pocket)
	layout.chunks.append_array(pockets)

	# Spawn points.
	for marker: Marker2D in _sorted_by_name(start.get_spawn_markers("Player")):
		layout.player_spawns.append(start.position + marker.position)
	var goal_markers: Array[Marker2D] = goal_chunk.get_spawn_markers("Goal")
	if layout.player_spawns.is_empty() or goal_markers.is_empty():
		layout.problem = "start chunk needs Player markers, goal chunk a Goal marker"
		return layout
	layout.goal = goal_chunk.position + goal_markers[0].position

	var creature_spots: Array[Vector2] = []
	for chunk: LevelChunk in main_chunks:
		if chunk != start:
			creature_spots.append_array(_marker_positions(chunk, "Creature"))
	_shuffle(creature_spots, rng)
	for spawn: CreatureSpawn in stage.creatures:
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
	for i: int in mini(stage.corals, coral_spots.size()):
		layout.corals.append(coral_spots[i])

	if pockets.size() < stage.stations:
		layout.problem = "not enough side pockets for %d stations" % stage.stations
		return layout
	var station_pockets: Array[LevelChunk] = pockets.duplicate()
	_shuffle_chunks(station_pockets, rng)
	for i: int in stage.stations:
		var pocket: LevelChunk = station_pockets[i]
		var markers: Array[Marker2D] = pocket.get_spawn_markers("Station")
		if markers.is_empty():
			continue
		# Closest to the pocket opening first; the bias picks how deep inside.
		markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool: return a.position.length() < b.position.length())
		var pick: int = roundi(stage.station_distance_bias * (markers.size() - 1))
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
	stage_height = layout.height
	var progress: float = (stage_index + 0.5) / maxf(get_stage_count(), 1.0)
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
	_goal = _spawn(world.goal_scene, layout.goal) as AncientLight
	# The sonar overlay samples the new rock outlines.
	get_tree().call_group("sonar_overlay", "rebuild_samples")


func _clear() -> void:
	if _level:
		# Out of the tree right away, so groups (rock_walls, creatures...) only
		# contain the new stage from now on.
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


func _pick(scenes: Array[PackedScene], rng: RandomNumberGenerator, avoid: PackedScene) -> PackedScene:
	if scenes.size() > 1 and avoid != null:
		var options: Array[PackedScene] = scenes.filter(func(s: PackedScene) -> bool: return s != avoid)
		return options[rng.randi_range(0, options.size() - 1)]
	return scenes[rng.randi_range(0, scenes.size() - 1)]


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


# --- Queries used by the HUD, Darkness, RunManager --------------------------

func depth_at(world_y: float) -> float:
	return world.surface_depth_m + stage_index * world.stage_depth_step_m + maxf(world_y, 0.0) * world.meters_per_pixel


## 0 at the top of the current stage, 1 at its bottom.
func depth_ratio_at(world_y: float) -> float:
	return clampf(world_y / stage_height, 0.0, 1.0)


## 0 at the top of stage 1, 1 at the bottom of the last stage.
func run_progress_at(world_y: float) -> float:
	return (stage_index + depth_ratio_at(world_y)) / maxf(get_stage_count(), 1.0)


func get_spawn_position(player_number: int) -> Vector2:
	if _player_spawns.is_empty():
		return global_position
	return to_global(_player_spawns[clampi(player_number - 1, 0, _player_spawns.size() - 1)])


func get_goal() -> AncientLight:
	return _goal


func get_creatures() -> Array[Creature]:
	return _creatures
