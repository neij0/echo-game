@tool
class_name LevelChunk
extends Node2D
## One hand-made room of a level's room grid. Contract so any room fits any
## cell (sizes in the WorldConfig "Rooms" group):
## - The room is a square from local (0, 0) to (room_size, room_size), with a
##   Floor Polygon2D covering it and RockWall polygons for the rock.
## - A rock band (room_wall_band) runs along its edges. On every side listed in
##   `openings` a doorway (room_door_width, centred on the side) is left open
##   through the band, and the open area behind it leads into the room.
## - The LevelBuilder can turn a room in quarter turns, connects two
##   neighbouring rooms when both have an opening on the shared side, and seals
##   every other opening with rock.
## - Spawn points are Marker2D children of "Spawns": Player1/Player2 (used in
##   the start room), Goal (the exit's ancient light; also the room's reference
##   point, e.g. for the lockdown), Boss (boss arena), Shard*, Creature*,
##   Coral*, Station*. Keep them away from the doorways.
## @tool only so the editor tool tools/propose_level.gd can call these methods
## (it has no callbacks, so nothing runs in the editor).

@export_flags("North", "East", "South", "West") var openings: int = 0
## The exit room of boss levels (has a Boss marker, usually one opening).
@export var is_boss_arena: bool = false
## 3/4 view (prototype): height of the rocks' front faces in this room
## (RockWall.height, also given to the seals in its cell). 0 = flat rocks.
@export var rock_height: float = 0.0

## Clockwise quarter turns applied by rotate_quarters.
var quarter_turns: int = 0


## Turns the room clockwise around its centre (polygons, markers, openings).
## Must be called before the room enters the tree, because RockWall builds its
## shapes in _ready.
func rotate_quarters(turns: int, room_size: float) -> void:
	var t: int = posmod(turns, 4)
	if t == 0:
		return
	quarter_turns = t
	var center := Vector2(room_size, room_size) * 0.5
	# Positive angles turn clockwise on screen (y points down).
	var turn := Transform2D(t * PI * 0.5, center) * Transform2D(0.0, -center)
	for node: Node in find_children("*", "", true, false):
		if node is RockWall:
			var wall := node as RockWall
			wall.polygon = turn * wall.polygon
		elif node is Polygon2D:
			var shape := node as Polygon2D
			shape.polygon = turn * shape.polygon
		elif node is Marker2D:
			var marker := node as Marker2D
			marker.position = turn * marker.position
	openings = RoomGrid.rotate_openings(openings, t)


func has_opening(side: int) -> bool:
	return openings & side != 0


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
