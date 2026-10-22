class_name LockdownBarrier
extends RockWall
## The rock that seals one doorway of the lockdown room. It starts open (no
## collision, no shadow, no sonar edge, invisible). close() makes it solid at
## once and lets the rock rise into view; open() fades it away again with a
## warm glow along the doorway (the "you made it" light cue). The LockdownRoom
## creates one per connected doorway (the polygon of a seal).

@export var close_time: float = 0.35
@export var open_time: float = 1.0

@export_group("Open Light")
@export var light_color: Color = Color(1.0, 0.85, 0.5)
@export var light_energy: float = 1.6
@export var light_radius: float = 320.0
## Glowing seam along the doorway while it opens.
@export var seam_energy: float = 3.0
@export var seam_width: float = 4.0

var is_closed: bool = false
var _fade: float = 0.0
var _open_glow_left: float = 0.0
var _rock_visual: Polygon2D
var _collision: CollisionPolygon2D
var _occluder: LightOccluder2D
var _light: PointLight2D
var _seam: Node2D
var _center: Vector2
var _along: Vector2 = Vector2.RIGHT
var _half_length: float = 0.0


func _ready() -> void:
	super()
	for child: Node in get_children():
		if child is Polygon2D:
			_rock_visual = child as Polygon2D
		elif child is CollisionPolygon2D:
			_collision = child as CollisionPolygon2D
		elif child is LightOccluder2D:
			_occluder = child as LightOccluder2D
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	_center = bounds.get_center()
	_along = Vector2.RIGHT if bounds.size.x >= bounds.size.y else Vector2.DOWN
	_half_length = maxf(bounds.size.x, bounds.size.y) * 0.5

	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(128, 0.0)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, light_radius)
	_light.color = light_color
	_light.energy = 0.0
	_light.position = _center
	add_child(_light)

	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_seam = Node2D.new()
	layer.add_child(_seam)
	_seam.draw.connect(_draw_seam)
	_set_solid(false)
	_apply_fade()


func close() -> void:
	if is_closed:
		return
	is_closed = true
	_set_solid(true)


func open() -> void:
	if not is_closed:
		return
	is_closed = false
	_set_solid(false)
	_open_glow_left = open_time


func _set_solid(solid: bool) -> void:
	if _collision:
		_collision.set_deferred("disabled", not solid)
	if _occluder:
		_occluder.visible = solid
	if solid:
		add_to_group("rock_walls")
	else:
		remove_from_group("rock_walls")


func _process(delta: float) -> void:
	var target: float = 1.0 if is_closed else 0.0
	var time: float = close_time if is_closed else open_time
	_fade = move_toward(_fade, target, delta / maxf(time, 0.01))
	_open_glow_left = maxf(_open_glow_left - delta, 0.0)
	_apply_fade()
	_seam.global_position = to_global(_center)
	_seam.queue_redraw()


func _apply_fade() -> void:
	if _rock_visual:
		_rock_visual.modulate.a = _fade
	var glow: float = _open_glow_left / maxf(open_time, 0.01)
	_light.energy = light_energy * glow


func _draw_seam() -> void:
	var glow: float = _open_glow_left / maxf(open_time, 0.01)
	if glow <= 0.0:
		return
	var color := Color(light_color.r * seam_energy, light_color.g * seam_energy, light_color.b * seam_energy, glow)
	_seam.draw_line(-_along * _half_length, _along * _half_length, color, seam_width, true)
