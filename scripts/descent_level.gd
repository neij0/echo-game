class_name DescentLevel
extends Node2D
## A hand-built vertical descent. Converts world height to depth in metres and
## provides the player spawn points (child Marker2D nodes of $Spawns, one per
## player, in order).

## Depth in metres at world y = 0 (the top of the level).
@export var surface_depth_m: float = 200.0
@export var meters_per_pixel: float = 0.1
## World y of the bottom of the level (used for the 0-1 depth ratio).
@export var bottom_y: float = 9000.0

@onready var _spawns: Node2D = $Spawns


func _ready() -> void:
	add_to_group("level")


func depth_at(world_y: float) -> float:
	return surface_depth_m + maxf(world_y, 0.0) * meters_per_pixel


## 0 at the top of the level, 1 at the bottom.
func depth_ratio_at(world_y: float) -> float:
	return clampf(world_y / bottom_y, 0.0, 1.0)


## Spawn position for player_number (1-based). Falls back to the first spawn.
func get_spawn_position(player_number: int) -> Vector2:
	var count: int = _spawns.get_child_count()
	if count == 0:
		return global_position
	var index: int = clampi(player_number - 1, 0, count - 1)
	return (_spawns.get_child(index) as Node2D).global_position
