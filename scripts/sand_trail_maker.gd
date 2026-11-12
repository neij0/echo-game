class_name SandTrailMaker
extends Node3D
## Put under anything that leaves a trail in the sand (players, creatures,
## later fish): SandTrails stamps a furrow where it moves and throws a puff
## of sand when it moves fast. It follows its parent's interpolated position.

## Half width of the furrow (units).
@export var radius: float = 0.22
## How deep the furrow gets (0-1) when it passes once.
@export_range(0.0, 1.0) var depth: float = 0.6
## Stirred sand left with the furrow, as a share of its depth.
@export_range(0.0, 2.0) var stir: float = 0.6
## Faster than this (units per second) = a puff of sand; 0 = never.
@export var puff_speed: float = 8.0
## Minimum seconds between two puffs of this maker.
@export var puff_interval: float = 0.15
## Size of its puffs.
@export var puff_scale: float = 1.0
## A move longer than this in one frame is a teleport: no furrow.
@export var max_step: float = 2.0

var last_floor_position: Vector3
var has_last: bool = false
var puff_cooldown_left: float = 0.0


func _ready() -> void:
	add_to_group("sand_trail_makers")


## Where it touches the floor now (its parent's interpolated position, y = 0).
func get_floor_position() -> Vector3:
	var parent := get_parent() as Node3D
	var at: Vector3 = parent.get_global_transform_interpolated().origin if parent else global_position
	return Vector3(at.x, 0.0, at.z)


## False while it should leave no trail (a dying creature, a downed player
## lying still is fine: it does not move).
func is_touching() -> bool:
	var creature := get_parent() as Creature
	return creature == null or not creature.is_dying()
