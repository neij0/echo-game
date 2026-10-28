class_name RoomDepthLayers
extends Node2D
## 3/4 view: the foreground depth layer of one room (a child of its
## LevelChunk): kelp strands and coral tips at the Marker2D children of this
## node (name starting with "Kelp" or "Coral"), close to the camera: drawn
## dark and unlit on an own CanvasLayer above the world, bigger and moving
## faster than the world, swaying. They partly cover the view.
## (There is no background layer: dim ridges on the floor read as fake rocks.)

@export_group("Foreground")
## Above the world and the glow layers, under the HUD.
@export var foreground_layer: int = 1
## Size and movement of the foreground compared to the world (> 1 = closer
## to the camera: bigger, and it slides past faster).
@export var foreground_scale: float = 1.45
@export var foreground_color: Color = Color(0.008, 0.012, 0.02, 0.92)
@export var kelp_length: float = 230.0
@export var kelp_width: float = 24.0
@export var kelp_segments: int = 14
@export var kelp_sway_amount: float = 26.0
## Sway cycles per second.
@export var kelp_sway_speed: float = 0.22
@export var coral_branch_length: float = 70.0
@export var coral_branch_width: float = 7.0
@export var coral_branches: int = 5
@export var coral_sway_amount: float = 6.0

var _foreground: Node2D
var _spots: Array[Marker2D] = []
var _time: float = 0.0


func _ready() -> void:
	for child: Node in get_children():
		if child is Marker2D:
			_spots.append(child as Marker2D)
	var layer := CanvasLayer.new()
	layer.layer = foreground_layer
	add_child(layer)
	_foreground = Node2D.new()
	layer.add_child(_foreground)
	_foreground.draw.connect(_draw_foreground)


func _process(delta: float) -> void:
	_time += delta
	_foreground.queue_redraw()


func _draw_foreground() -> void:
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var screen_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var size: float = canvas.get_scale().x * foreground_scale
	var screen := Rect2(Vector2.ZERO, screen_center * 2.0)
	for i: int in _spots.size():
		var spot: Marker2D = _spots[i]
		# Closer than the world: scaled away from the screen centre.
		var base: Vector2 = screen_center + (canvas * spot.global_position - screen_center) * foreground_scale
		if not screen.grow(kelp_length * size).has_point(base):
			continue
		if spot.name.begins_with("Kelp"):
			_draw_kelp(base, size, i)
		elif spot.name.begins_with("Coral"):
			_draw_coral(base, size, i)


## A strand rising from base, swaying more towards its tip, tapering.
func _draw_kelp(base: Vector2, size: float, phase: int) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k: int in kelp_segments + 1:
		var t: float = float(k) / kelp_segments
		var sway: float = sin(_time * TAU * kelp_sway_speed + phase * 1.7 + t * 2.2) * kelp_sway_amount * pow(t, 1.5)
		var point: Vector2 = base + Vector2(sway, -kelp_length * t) * size
		var half: float = kelp_width * 0.5 * (1.0 - t * 0.8) * size
		left.append(point - Vector2(half, 0.0))
		right.append(point + Vector2(half, 0.0))
	right.reverse()
	left.append_array(right)
	_foreground.draw_colored_polygon(left, foreground_color)


## A small fan of branches with rounded tips, swaying a little.
func _draw_coral(base: Vector2, size: float, phase: int) -> void:
	for b: int in coral_branches:
		var spread: float = (float(b) / maxf(coral_branches - 1, 1) - 0.5) * 1.6
		var sway: float = sin(_time * TAU * kelp_sway_speed * 1.3 + phase + b) * coral_sway_amount
		var length: float = coral_branch_length * (0.7 + 0.3 * cos(spread))
		var tip: Vector2 = base + (Vector2.UP.rotated(spread) * length + Vector2(sway, 0.0)) * size
		var width: float = coral_branch_width * size
		_foreground.draw_line(base, tip, foreground_color, width)
		_foreground.draw_circle(tip, width * 0.6, foreground_color)
