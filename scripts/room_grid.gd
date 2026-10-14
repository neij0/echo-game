class_name RoomGrid
extends RefCounted
## Helpers for a level's room grid: sides, rotating openings, and which rooms
## connect. Two neighbouring rooms connect when both have an opening on the
## shared side; every other opening is sealed with rock by the LevelBuilder.

enum Side { NORTH = 1, EAST = 2, SOUTH = 4, WEST = 8 }

const SIDES: Array[int] = [Side.NORTH, Side.EAST, Side.SOUTH, Side.WEST]

## Base openings per room scene path (read once from the scene).
static var _openings_cache: Dictionary = {}


static func direction(side: int) -> Vector2i:
	match side:
		Side.NORTH:
			return Vector2i(0, -1)
		Side.EAST:
			return Vector2i(1, 0)
		Side.SOUTH:
			return Vector2i(0, 1)
	return Vector2i(-1, 0)


static func opposite(side: int) -> int:
	return rotate_openings(side, 2)


## Openings after clockwise quarter turns (North -> East -> South -> West).
static func rotate_openings(flags: int, turns: int) -> int:
	var t: int = posmod(turns, 4)
	return ((flags << t) | (flags >> (4 - t))) & 15


static func side_names(flags: int) -> String:
	var names: String = ""
	for i: int in SIDES.size():
		if flags & SIDES[i]:
			names += "NESW"[i]
	return names


## The room scene's own openings (before rotation).
static func base_openings(room: PackedScene) -> int:
	if room == null:
		return 0
	if not _openings_cache.has(room.resource_path):
		var chunk := room.instantiate() as LevelChunk
		_openings_cache[room.resource_path] = chunk.openings if chunk else 0
		if chunk:
			chunk.free()
	return int(_openings_cache[room.resource_path])


static func openings_of(placement: RoomPlacement) -> int:
	return rotate_openings(base_openings(placement.room), placement.quarter_turns)


## Cell -> Array of connected neighbour cells (Vector2i), for a level's rooms.
static func connections(rooms: Array[RoomPlacement]) -> Dictionary:
	var by_cell: Dictionary = {}
	for placement: RoomPlacement in rooms:
		by_cell[placement.cell] = openings_of(placement)
	var result: Dictionary = {}
	for cell: Vector2i in by_cell:
		var neighbours: Array[Vector2i] = []
		for side: int in SIDES:
			var other: Vector2i = cell + direction(side)
			if int(by_cell[cell]) & side and by_cell.has(other) and int(by_cell[other]) & opposite(side):
				neighbours.append(other)
		result[cell] = neighbours
	return result


## Steps between two cells through connected rooms (-1 = not connected).
static func steps_between(links: Dictionary, from: Vector2i, to: Vector2i) -> int:
	if not links.has(from):
		return -1
	var distance: Dictionary = {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			return int(distance[cell])
		for next: Vector2i in links[cell]:
			if not distance.has(next):
				distance[next] = int(distance[cell]) + 1
				queue.append(next)
	return -1
