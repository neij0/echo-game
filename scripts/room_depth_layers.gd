class_name RoomDepthLayers
extends Node2D
## 3/4 view prototype: depth layers of one room (a child of its LevelChunk).
## - Background: dim silhouettes of distant rock ridges on the room's floor,
##   drawn in the world (so only lit floor shows them, the darkness stays) and
##   moving slower than the floor when the camera moves (parallax), as if far
##   below. Clipped to the room's Floor. The z_index (set in the scene) puts
##   them between the floor and the drop shadows.
## - Foreground: kelp strands and coral tips at the Marker2D children of this
##   node (name starting with "Kelp" or "Coral"), close to the camera: drawn
##   dark and unlit on an own CanvasLayer above the world, bigger and moving
##   faster than the world, swaying. They partly cover the view.

@export_group("Background")
@export var background_count: int = 9
## Seed of the ridge shapes (the same room always looks the same).
@export var background_seed: int = 7
## Share of the camera's movement the ridges move along with (0 = glued to
## the floor, 1 = glued to the screen). Higher = they look farther away.
@export_range(0.0, 1.0) var background_drift: float = 0.35
## Half width and half height range of one ridge.
@export var ridge_radius_min: Vector2 = Vector2(140.0, 50.0)
@export var ridge_radius_max: Vector2 = Vector2(320.0, 120.0)
## How ragged a ridge outline is (share of its radius).
@export_range(0.0, 1.0) var ridge_roughness: float = 0.35
@export var ridge_points: int = 16
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.18)

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

var _ridges: Array[PackedVector2Array] = []
var _floor := PackedVector2Array()
var _room_center := Vector2.ZERO
var _foreground: Node2D
var _spots: Array[Marker2D] = []
var _time: float = 0.0
var _last_camera := Vector2.INF


func _ready() -> void:
	var floor_shape := get_parent().get_node_or_null("Floor") as Polygon2D
	if floor_shape:
		_floor = floor_shape.polygon
		var bounds := Rect2(_floor[0], Vector2.ZERO)
		for point: Vector2 in _floor:
			bounds = bounds.expand(point)
		_room_center = bounds.get_center()
		_make_ridges(bounds)
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
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera:
		var center: Vector2 = camera.get_screen_center_position()
		if center != _last_camera:
			_last_camera = center
			queue_redraw()
	_foreground.queue_redraw()


func _make_ridges(bounds: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = background_seed
	for i: int in background_count:
		var center := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
		var radius := Vector2(rng.randf_range(ridge_radius_min.x, ridge_radius_max.x), rng.randf_range(ridge_radius_min.y, ridge_radius_max.y))
		var points := PackedVector2Array()
		for k: int in ridge_points:
			var angle: float = TAU * k / ridge_points
			var ragged: float = 1.0 + rng.randf_range(-ridge_roughness, ridge_roughness)
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * ragged)
		_ridges.append(points)


func _draw() -> void:
	if _floor.is_empty() or _last_camera == Vector2.INF:
		return
	# Far away = moves along with the camera a little (parallax).
	var offset: Vector2 = (to_local(_last_camera) - _room_center) * background_drift
	for ridge: PackedVector2Array in _ridges:
		var moved := PackedVector2Array()
		for point: Vector2 in ridge:
			moved.append(point + offset)
		# The floor is a square, so the parts never have holes; a ridge that
		# only grazes its edge can leave a degenerate sliver (skipped).
		for part: PackedVector2Array in Geometry2D.intersect_polygons(moved, _floor):
			if not Geometry2D.triangulate_polygon(part).is_empty():
				draw_colored_polygon(part, background_color)


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
