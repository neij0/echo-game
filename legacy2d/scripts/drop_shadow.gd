class_name DropShadow
extends Node2D
## A soft dark ellipse a little below a character or creature (3/4 view: it
## floats above the floor), drawn in the world so only lit floor shows it.
## Its z_index (set in the scene) puts it on the floor, under rocks and bodies.
## Follows the body's visibility when the parent has get_body_visibility()
## (a hidden creature casts no visible shadow).

@export var enabled: bool = true
## Half width and half height of the ellipse.
@export var radius: Vector2 = Vector2(12.0, 5.0)
## > 0: the half width is the parent's body_radius times this (creatures; the
## half height keeps the ratio of radius).
@export var body_radius_scale: float = 0.0
## Where the shadow falls, from the parent's origin (down = farther from the light).
@export var offset: Vector2 = Vector2(0.0, 14.0)
@export_range(0.0, 1.0) var opacity: float = 0.45
## Stacked ellipses from the edge inward: more = a softer edge.
@export var softness_steps: int = 4
@export var segments: int = 24

var _shown_alpha: float = -1.0


func _ready() -> void:
	position = offset
	if body_radius_scale > 0.0 and "body_radius" in get_parent():
		var body_radius: float = get_parent().get("body_radius")
		radius = Vector2(body_radius * body_radius_scale, body_radius * body_radius_scale * radius.y / radius.x)


func _process(_delta: float) -> void:
	var alpha: float = opacity if enabled else 0.0
	if get_parent().has_method("get_body_visibility"):
		alpha *= get_parent().call("get_body_visibility")
	if not is_equal_approx(alpha, _shown_alpha):
		_shown_alpha = alpha
		queue_redraw()


func _draw() -> void:
	if _shown_alpha <= 0.0:
		return
	# Each step adds a smaller ellipse on top, so the centre is darkest.
	var step_alpha: float = _shown_alpha / softness_steps
	for step: int in softness_steps:
		var size: float = 1.0 - float(step) / softness_steps * 0.6
		var points := PackedVector2Array()
		for i: int in segments:
			var angle: float = TAU * i / segments
			points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * size)
		draw_colored_polygon(points, Color(0.0, 0.0, 0.0, step_alpha))
