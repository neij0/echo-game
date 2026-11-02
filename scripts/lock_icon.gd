class_name LockIcon
extends Control
## A small padlock drawn in code (a shackle and a body with a keyhole), for
## locked things in the menus.

@export var color: Color = Color(0.5, 0.56, 0.66)
@export var line_width: float = 1.6


func _init() -> void:
	custom_minimum_size = Vector2(14.0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var body := Rect2(Vector2(0.0, h * 0.45), Vector2(w, h * 0.55))
	draw_arc(Vector2(w * 0.5, h * 0.45), w * 0.3, PI, TAU, 12, color, line_width, true)
	draw_line(Vector2(w * 0.2, h * 0.45), Vector2(w * 0.2, h * 0.5), color, line_width)
	draw_line(Vector2(w * 0.8, h * 0.45), Vector2(w * 0.8, h * 0.5), color, line_width)
	draw_rect(body, color)
	draw_circle(body.get_center() + Vector2(0.0, -1.0), w * 0.1, Color(0.0, 0.0, 0.0, 0.7))
