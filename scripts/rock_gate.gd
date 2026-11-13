class_name RockGate
extends Node3D
## A slab of rock across a doorway that can rise out of the floor and sink
## back into it (the base of the lockdown barriers and the boss arena's door).
## Built from an outline on the floor plane (world units; the shape of a
## seal) with the level's rock material, so it lights, takes the pulse and is
## cut away like any rock. While solid it has the rock's upright colliders
## (it stops bodies, the pulse and lines of sight); sunk, it has none and is
## hidden. The owner sets outline, height and material before it enters the
## tree, and tells the LevelBuilder when to rebake the navigation.

## Outline on the floor plane (x, z) in world units.
var outline: PackedVector2Array = PackedVector2Array()
## Height of the rock when fully risen (units).
var height: float = 1.0
var material: Material
## Seconds to rise / to sink.
var rise_time: float = 0.35
var sink_time: float = 1.0

var is_solid: bool = false
## 0 = sunk into the floor, 1 = fully risen.
var raised: float = 0.0
## Middle of the gate on the floor, the direction along it (its long side)
## and half its length.
var center: Vector3 = Vector3.ZERO
var along: Vector3 = Vector3.RIGHT
var half_length: float = 0.0
var _body: StaticBody3D
var _mesh: MeshInstance3D


func _ready() -> void:
	var bounds := Rect2(outline[0], Vector2.ZERO) if not outline.is_empty() else Rect2()
	for point: Vector2 in outline:
		bounds = bounds.expand(point)
	var middle: Vector2 = bounds.get_center()
	center = Vector3(middle.x, 0.0, middle.y)
	along = Vector3.RIGHT if bounds.size.x >= bounds.size.y else Vector3.BACK
	half_length = maxf(bounds.size.x, bounds.size.y) * 0.5
	_body = StaticBody3D.new()
	_body.name = "Rock"
	_body.collision_layer = 0
	_body.collision_mask = 0
	add_child(_body)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = RockMesher.rock_mesh(outline, height, 40.0)
	_mesh.material_override = material
	_body.add_child(_mesh)
	RockMesher.add_colliders(_body, outline)
	_apply_raised()


## Solid = it blocks at once (layer 1, like every rock); the look follows.
func set_solid(solid: bool) -> void:
	is_solid = solid
	if _body:
		_body.collision_layer = 1 if solid else 0


## Rises or sinks towards its state; returns true while it still moves.
func animate(delta: float) -> bool:
	var target: float = 1.0 if is_solid else 0.0
	if is_equal_approx(raised, target):
		return false
	raised = move_toward(raised, target, delta / maxf(rise_time if is_solid else sink_time, 0.01))
	_apply_raised()
	return true


## Jumps to its state (a level built with the gate already closed).
func snap() -> void:
	raised = 1.0 if is_solid else 0.0
	_apply_raised()


func _apply_raised() -> void:
	if _mesh == null:
		return
	_mesh.visible = raised > 0.001
	# Eased: it slows as it reaches its full height / the floor.
	var eased: float = raised * raised * (3.0 - 2.0 * raised)
	_mesh.scale = Vector3(1.0, maxf(eased, 0.001), 1.0)
