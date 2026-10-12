class_name MarineSnow
extends Node2D
## Environment light: tiny glowing particles ("marine snow") slowly drifting
## down and swaying. They live in a box around the camera and wrap around it,
## so they cover the whole level at a fixed cost. All values come from the
## WorldConfig ("Marine Snow" group).
## Must live on a CanvasLayer with follow_viewport_enabled, so the world's
## CanvasModulate darkness does not dim them.

## Extra space around the visible area where particles live, so none pop in at
## the screen edge.
@export var margin: float = 120.0

var count: int = 140
var color: Color = Color(0.7, 0.9, 1.0)
var alpha_min: float = 0.08
var alpha_max: float = 0.35
var size_min: float = 0.8
var size_max: float = 2.2
var fall_speed: float = 9.0
var sway_amount: float = 12.0
var sway_speed: float = 0.12
var twinkle_speed: float = 0.25

var _positions: PackedVector2Array = PackedVector2Array()
var _sizes: PackedFloat32Array = PackedFloat32Array()
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _phases: PackedFloat32Array = PackedFloat32Array()
var _time: float = 0.0
var _needs_spawn: bool = true


func _ready() -> void:
	add_to_group("world_listeners")


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	count = world.snow_count
	color = world.snow_color
	alpha_min = world.snow_alpha_min
	alpha_max = world.snow_alpha_max
	size_min = world.snow_size_min
	size_max = world.snow_size_max
	fall_speed = world.snow_fall_speed
	sway_amount = world.snow_sway_amount
	sway_speed = world.snow_sway_speed
	twinkle_speed = world.snow_twinkle_speed
	_needs_spawn = true


func _process(delta: float) -> void:
	var box: Rect2 = _view_box()
	if box.size == Vector2.ZERO:
		return
	if _needs_spawn:
		_spawn(box)
	_time += delta
	for i: int in _positions.size():
		var p: Vector2 = _positions[i] + Vector2(0.0, _speeds[i] * delta)
		# Wrap around the box so particles that leave one side come back on the other.
		p.x = box.position.x + fposmod(p.x - box.position.x, box.size.x)
		p.y = box.position.y + fposmod(p.y - box.position.y, box.size.y)
		_positions[i] = p
	queue_redraw()


func _spawn(box: Rect2) -> void:
	_needs_spawn = false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_positions.resize(count)
	_sizes.resize(count)
	_speeds.resize(count)
	_phases.resize(count)
	for i: int in count:
		_positions[i] = box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)
		_sizes[i] = rng.randf_range(size_min, size_max)
		_speeds[i] = rng.randf_range(0.3, 1.0) * fall_speed
		_phases[i] = rng.randf() * TAU


## The visible world area (plus margin), from the active camera.
func _view_box() -> Rect2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return Rect2()
	var view_size: Vector2 = get_viewport_rect().size / camera.zoom + Vector2.ONE * margin * 2.0
	return Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size)


func _draw() -> void:
	for i: int in _positions.size():
		var phase: float = _phases[i]
		var sway: float = sin(_time * TAU * sway_speed + phase) * sway_amount
		var twinkle: float = 0.5 + 0.5 * sin(_time * TAU * twinkle_speed + phase * 2.0)
		var alpha: float = lerpf(alpha_min, alpha_max, twinkle)
		draw_circle(_positions[i] + Vector2(sway, 0.0), _sizes[i], Color(color, alpha))
