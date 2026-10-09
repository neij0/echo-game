class_name RockWall
extends StaticBody2D
## A grey-box rock wall: one polygon used for both the visual and the collision.

@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.45, 0.42, 0.40)


func _ready() -> void:
	var visual := Polygon2D.new()
	visual.polygon = polygon
	visual.color = color
	add_child(visual)

	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	add_child(shape)
