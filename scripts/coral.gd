class_name Coral
extends Node2D
## A bioluminescent coral. When the pulse reaches it, it lights up for a while
## and creates a small safe zone that creatures avoid.

@export var lit_duration: float = 6.0
@export var fade_time: float = 1.0
@export var light_radius: float = 170.0
## Creatures are pushed out of this radius while the coral is lit.
@export var safe_radius: float = 130.0
@export var lit_energy: float = 1.1
@export var light_color: Color = Color(0.3, 1.0, 0.75)
@export var dim_color: Color = Color(0.15, 0.3, 0.28)
@export var glow_color: Color = Color(0.5, 1.0, 0.85)

var lit_time_left: float = 0.0
var _light: PointLight2D


func _ready() -> void:
	add_to_group("corals")
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(256, 0.4)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, light_radius)
	_light.color = light_color
	_light.energy = 0.0
	add_child(_light)


func _process(delta: float) -> void:
	if lit_time_left <= 0.0:
		return
	lit_time_left = maxf(lit_time_left - delta, 0.0)
	# Full brightness, then fade out during the last fade_time seconds.
	_light.energy = lit_energy * clampf(lit_time_left / fade_time, 0.0, 1.0)
	queue_redraw()


func wake() -> void:
	lit_time_left = lit_duration
	_light.energy = lit_energy
	queue_redraw()


func is_lit() -> bool:
	return lit_time_left > 0.0


func is_in_safe_zone(point: Vector2) -> bool:
	return is_lit() and global_position.distance_to(point) <= safe_radius


func _draw() -> void:
	var color: Color = glow_color if is_lit() else dim_color
	draw_circle(Vector2(0, 0), 10.0, color)
	draw_circle(Vector2(-12, 6), 7.0, color)
	draw_circle(Vector2(11, 8), 6.0, color)
	draw_circle(Vector2(3, -12), 6.0, color)
