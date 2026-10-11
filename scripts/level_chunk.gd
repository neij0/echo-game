class_name LevelChunk
extends Node2D
## One hand-made piece of a stage (a room, corridor, pocket...). Contract so any
## chunk connects to any other:
## - Main chunks (start, corridor, cave, narrow, goal) span x = -100..1700 and
##   y = 0..height. The walkable area at y = 0 and y = height always includes
##   x = 560..1040 (the connector). Their side walls fill everything else in
##   that band, so stacking chunks keeps the stage sealed.
## - A side opening is a 160 px tall gap through the side wall, marked by a
##   Marker2D named "SideLeft" (at x = -100) or "SideRight" (at x = 1700).
##   The StageBuilder attaches a pocket chunk to every side opening.
## - Pocket chunks have their opening at their local (0, 0) and extend to -x
##   (they are mirrored for right openings).
## - Spawn points are Marker2D children of "Spawns" named Player1/Player2,
##   Goal, Creature*, Coral* or Station*.

enum ChunkType { START, CORRIDOR, CAVE, NARROW, POCKET, GOAL }

@export var chunk_type: ChunkType = ChunkType.CORRIDOR
## Height of the chunk in pixels (the next chunk starts below it).
@export var height: float = 1200.0

var is_mirrored: bool = false


## Flips the chunk horizontally (for pockets on the right side). Must be called
## before the chunk enters the tree, because RockWall builds its shapes in _ready.
func mirror() -> void:
	is_mirrored = not is_mirrored
	for node: Node in find_children("*", "", true, false):
		if node is RockWall:
			var wall := node as RockWall
			wall.polygon = _flip_polygon(wall.polygon)
		elif node is Polygon2D:
			var shape := node as Polygon2D
			shape.polygon = _flip_polygon(shape.polygon)
		elif node is Marker2D:
			var marker := node as Marker2D
			marker.position.x = -marker.position.x


## Spawn markers whose name starts with prefix (e.g. "Creature"), in local space.
func get_spawn_markers(prefix: String) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var spawns: Node = get_node_or_null("Spawns")
	if spawns == null:
		return result
	for child: Node in spawns.get_children():
		if child is Marker2D and child.name.begins_with(prefix):
			result.append(child as Marker2D)
	return result


## Side opening markers ("SideLeft" / "SideRight").
func get_side_openings() -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	for marker_name: String in ["SideLeft", "SideRight"]:
		var marker := get_node_or_null(marker_name) as Marker2D
		if marker:
			result.append(marker)
	return result


## Wall outlines in the coordinate space of this chunk's parent (works before
## the chunk is in the tree, used by the LayoutValidator).
func get_wall_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for node: Node in find_children("*", "", true, false):
		var wall := node as RockWall
		if wall == null:
			continue
		var to_parent: Transform2D = transform * wall.transform
		var points := PackedVector2Array()
		for point: Vector2 in wall.polygon:
			points.append(to_parent * point)
		result.append(points)
	return result


static func _flip_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var flipped := PackedVector2Array()
	# Reverse the order too, so the winding stays the same after mirroring.
	for i: int in range(points.size() - 1, -1, -1):
		flipped.append(Vector2(-points[i].x, points[i].y))
	return flipped
