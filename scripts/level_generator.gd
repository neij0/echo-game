class_name LevelGenerator
extends RefCounted
## Proposes a new room-grid LevelDefinition from a world's room pool
## (WorldConfig "Rooms"): grows a random group of cells on the grid, links them
## with a random tree, adds extra links for loops, then picks for every cell a
## room and a quarter turn whose openings match exactly the links it needs.
## The exit is a room a few steps from the start (a dead end with a boss arena
## for boss levels); the lockdown room is on the way between them. The game
## never calls this: it is used by the editor tool tools/propose_level.gd, which
## saves the proposal as a .tres you can then edit by hand.

var grid_size: Vector2i = Vector2i(4, 4)
## How many cells get a room (random in this range).
var room_count_min: int = 8
var room_count_max: int = 11
## Extra links on top of the tree (each one makes a loop).
var extra_links: int = 1
## The exit is at least this many rooms away from the start.
var min_exit_steps: int = 3
## Set = propose a boss level (the exit room is a boss arena with this boss).
var boss_scene: PackedScene
## Spawn settings (creatures, corals, stations, shards, boss health) are copied
## from this level if set; otherwise the LevelDefinition defaults are used.
var template: LevelDefinition


## A proposal, or null if this seed did not work out (try another one).
func propose(world: WorldConfig, proposal_seed: int) -> LevelDefinition:
	var rng := RandomNumberGenerator.new()
	rng.seed = proposal_seed
	var cells: Array[Vector2i] = _grow_cells(rng)
	var links: Dictionary = _link_cells(cells, rng)
	if not has_required_shape(links):
		return null
	var start: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
	var exit_cell: Vector2i = _pick_exit(cells, links, start, rng)
	if exit_cell == start:
		return null

	var definition := LevelDefinition.new()
	for cell: Vector2i in cells:
		var needed: int = 0
		for other: Vector2i in links[cell]:
			needed |= _side_towards(cell, other)
		var pool: Array[PackedScene] = world.boss_arena_rooms if boss_scene and cell == exit_cell else world.room_chunks
		var placement: RoomPlacement = _matching_room(cell, needed, pool, rng)
		if placement == null:
			return null
		definition.rooms.append(placement)
	definition.start_cell = start
	definition.exit_cell = exit_cell
	definition.lockdown_cell = _pick_lockdown(links, start, exit_cell)
	if template:
		for spawn: CreatureSpawn in template.creatures:
			definition.creatures.append(spawn.duplicate() as CreatureSpawn)
		definition.corals = template.corals
		definition.stations = template.stations
		definition.shard_count = template.shard_count
		definition.boss_max_health = template.boss_max_health
	definition.boss = boss_scene
	return definition


## Proposes levels from base_seed, base_seed + 1, ... until one passes the
## LevelBuilder's check (BFS) with at least one spawn seed. Returns null if
## none did within tries.
func propose_valid(world: WorldConfig, base_seed: int, tries: int, builder: LevelBuilder) -> LevelDefinition:
	for i: int in tries:
		var definition: LevelDefinition = propose(world, base_seed + i)
		if definition == null:
			continue
		var layout: LevelBuilder.Layout = builder.find_valid_layout(definition, base_seed + i)
		if layout:
			layout.free_chunks()
			return definition
	return null


## Every level needs at least one branch (a room with 3+ links), one loop and
## one dead end.
static func has_required_shape(links: Dictionary) -> bool:
	var link_count: int = 0
	var branches: int = 0
	var dead_ends: int = 0
	for cell: Vector2i in links:
		var degree: int = (links[cell] as Array).size()
		link_count += degree
		branches += 1 if degree >= 3 else 0
		dead_ends += 1 if degree == 1 else 0
	var loops: int = link_count / 2 - links.size() + 1
	return branches >= 1 and loops >= 1 and dead_ends >= 1


## A random connected group of cells inside the grid.
func _grow_cells(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var target: int = mini(rng.randi_range(room_count_min, room_count_max), grid_size.x * grid_size.y)
	var cells: Array[Vector2i] = [Vector2i(rng.randi_range(0, grid_size.x - 1), rng.randi_range(0, grid_size.y - 1))]
	while cells.size() < target:
		var from: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var next: Vector2i = from + RoomGrid.direction(RoomGrid.SIDES[rng.randi_range(0, 3)])
		if _inside(next) and not next in cells:
			cells.append(next)
	return cells


## A random spanning tree over neighbouring cells, plus extra_links loops.
func _link_cells(cells: Array[Vector2i], rng: RandomNumberGenerator) -> Dictionary:
	var links: Dictionary = {}
	for cell: Vector2i in cells:
		links[cell] = [] as Array[Vector2i]
	var visited: Array[Vector2i] = [cells[0]]
	var stack: Array[Vector2i] = [cells[0]]
	while not stack.is_empty():
		var cell: Vector2i = stack[stack.size() - 1]
		var options: Array[Vector2i] = []
		for side: int in RoomGrid.SIDES:
			var next: Vector2i = cell + RoomGrid.direction(side)
			if next in cells and not next in visited:
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		(links[cell] as Array[Vector2i]).append(chosen)
		(links[chosen] as Array[Vector2i]).append(cell)
		visited.append(chosen)
		stack.append(chosen)
	var extra: Array = []
	for cell: Vector2i in cells:
		for side: int in [RoomGrid.Side.EAST, RoomGrid.Side.SOUTH]:
			var next: Vector2i = cell + RoomGrid.direction(side)
			if next in cells and not next in links[cell]:
				extra.append([cell, next])
	for i: int in mini(extra_links, extra.size()):
		var pair: Array = extra.pop_at(rng.randi_range(0, extra.size() - 1))
		(links[pair[0]] as Array[Vector2i]).append(pair[1])
		(links[pair[1]] as Array[Vector2i]).append(pair[0])
	return links


func _pick_exit(cells: Array[Vector2i], links: Dictionary, start: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var options: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if cell == start or RoomGrid.steps_between(links, start, cell) < min_exit_steps:
			continue
		# Boss arenas have a single opening: the exit must be a dead end.
		if boss_scene and (links[cell] as Array).size() != 1:
			continue
		options.append(cell)
	return options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else start


## The room with the most links on the way from start to exit (not either end).
func _pick_lockdown(links: Dictionary, start: Vector2i, exit_cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_links: int = -1
	for cell: Vector2i in links:
		if cell == start or cell == exit_cell:
			continue
		var via: int = RoomGrid.steps_between(links, start, cell) + RoomGrid.steps_between(links, cell, exit_cell)
		if via != RoomGrid.steps_between(links, start, exit_cell):
			continue
		if (links[cell] as Array).size() > best_links:
			best_links = (links[cell] as Array).size()
			best = cell
	return best


## A room and quarter turn whose openings are exactly the needed sides.
func _matching_room(cell: Vector2i, needed: int, pool: Array[PackedScene], rng: RandomNumberGenerator) -> RoomPlacement:
	var options: Array[RoomPlacement] = []
	for scene: PackedScene in pool:
		for turns: int in 4:
			if RoomGrid.rotate_openings(RoomGrid.base_openings(scene), turns) == needed:
				var placement := RoomPlacement.new()
				placement.cell = cell
				placement.room = scene
				placement.quarter_turns = turns
				options.append(placement)
	return options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else null


func _side_towards(cell: Vector2i, other: Vector2i) -> int:
	for side: int in RoomGrid.SIDES:
		if cell + RoomGrid.direction(side) == other:
			return side
	return 0


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y
