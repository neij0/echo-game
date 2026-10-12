@tool
class_name RockWall
extends StaticBody2D
## A grey-box rock wall: one polygon used for the visual, the collision and the
## light occluder. Its outline is drawn by SonarOverlay when a pulse hits it.
## @tool only so the editor tool tools/propose_level.gd can read the walls;
## _ready does nothing in the editor.

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.45, 0.42, 0.40)
## Blocks shadow-casting lights (the pulse glow), creating hidden areas behind the rock.
@export var casts_shadow: bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("rock_walls")

	var visual := Polygon2D.new()
	visual.polygon = polygon
	visual.color = color
	add_child(visual)

	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	add_child(shape)

	if casts_shadow:
		var occluder_shape := OccluderPolygon2D.new()
		occluder_shape.polygon = polygon
		var occluder := LightOccluder2D.new()
		occluder.occluder = occluder_shape
		add_child(occluder)


## The outline points in global coordinates (used by SonarOverlay).
func get_global_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(to_global(point))
	return result
