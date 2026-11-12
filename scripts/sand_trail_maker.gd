class_name SandTrailMaker
extends Node3D
## Put under anything that leaves a trail in the sand (players, creatures,
## later fish): SandTrails stamps a furrow where it moves and throws a puff
## of sand when it moves fast. It follows its parent's interpolated position.
## Something that floats (the Echo) gets depth 0 (no furrow) and a stir_speed:
## it only stirs the sand lightly when it moves faster than that or comes
## within near_floor_height of the floor.

## Half width of the furrow (units).
@export var radius: float = 0.22
## How deep the furrow gets (0-1) when it passes once.
@export_range(0.0, 1.0) var depth: float = 0.6
## Stirred sand left behind (0-1): a lighter patch that settles quickly.
@export_range(0.0, 1.0) var stir: float = 0.36
## Faster than this (units per second) = a puff of sand; 0 = never.
@export var puff_speed: float = 8.0
## Minimum seconds between two puffs of this maker.
@export var puff_interval: float = 0.15
## Size of its puffs.
@export var puff_scale: float = 1.0
## How dense its puffs are (share of the particles: lower = fainter).
@export_range(0.0, 1.0) var puff_strength: float = 1.0
## A move longer than this in one frame is a teleport: no furrow.
@export var max_step: float = 2.0

@export_group("Floating")
## 0 = it always touches the floor. Above 0: it floats, and only disturbs the
## sand while faster than this (units per second) or low over the floor.
@export var stir_speed: float = 0.0
## Closer to the floor than this (units) = it disturbs the sand at any speed.
@export var near_floor_height: float = 0.0
## Its height above the floor (a parent with get_hover_height() wins: a body
## that bobs).
@export var hover_height: float = 0.0

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


## Height above the floor right now.
func get_hover_height() -> float:
	var parent: Node = get_parent()
	if parent and parent.has_method("get_hover_height"):
		return float(parent.call("get_hover_height"))
	return hover_height


## True when it disturbs the sand at this speed (always, unless it floats).
func disturbs_at(speed: float) -> bool:
	if stir_speed <= 0.0:
		return true
	return speed >= stir_speed or get_hover_height() <= near_floor_height


## False while it should leave no trail (a dying creature, a downed player
## lying still is fine: it does not move).
func is_touching() -> bool:
	var creature := get_parent() as Creature
	return creature == null or not creature.is_dying()
