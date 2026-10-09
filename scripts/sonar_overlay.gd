class_name SonarOverlay
extends Node2D
## Draws what the sonar "sees": the travelling wave front, and rock outlines that
## light up when the front reaches them (only parts in line of sight of the pulse).
## Must live on a CanvasLayer with follow_viewport_enabled, so the world's
## CanvasModulate darkness does not dim it.

@export_group("Wave Front")
@export var ring_width: float = 3.0
@export var ring_color: Color = Color(0.4, 0.9, 1.0, 0.8)
## Rays cast per pulse so the front stops at rocks instead of passing through.
@export var ring_ray_count: int = 180

@export_group("Edges")
## Distance between outline sample points in pixels. Lower = smoother reveal, more raycasts.
@export var sample_spacing: float = 10.0
@export var edge_width: float = 2.5
@export var edge_color: Color = Color(0.45, 0.95, 1.0)
## Colour of an edge at the moment the front hits it, before it settles to edge_color.
@export var flash_color: Color = Color(1.0, 1.0, 1.0)
## Higher = the white flash disappears faster.
@export var flash_power: float = 4.0
@export var edge_fade_time: float = 2.0
## 0 = far edges as bright as near ones, 1 = edges at max radius are invisible.
@export_range(0.0, 1.0) var distance_falloff: float = 0.35

@export_group("Line Of Sight")
## Pulls each line-of-sight ray back from the outline so the rock itself does not block it.
@export var los_tolerance: float = 2.0
@export_flags_2d_physics var wall_mask: int = 1


class Wave:
	var origin: Vector2
	var start_time: float
	var max_radius: float
	var expand_time: float
	var hit_distances: PackedFloat32Array = PackedFloat32Array()
	var scanned: bool = false

	func radius_at(time: float) -> float:
		return max_radius * clampf((time - start_time) / expand_time, 0.0, 1.0)

	func is_expanding(time: float) -> bool:
		return time - start_time <= expand_time


var _time: float = 0.0
var _waves: Array[Wave] = []

# One entry per outline sample point (all rocks flattened into one list).
var _points: PackedVector2Array = PackedVector2Array()
## Index of the next point on the same rock outline (closes the loop).
var _next: PackedInt32Array = PackedInt32Array()
var _lit_at: PackedFloat32Array = PackedFloat32Array()
var _strength: PackedFloat32Array = PackedFloat32Array()
var _pending_at: PackedFloat32Array = PackedFloat32Array()
var _pending_strength: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	add_to_group("sonar_overlay")
	# Deferred so every RockWall has run _ready and joined its group.
	_build_samples.call_deferred()


## Called (via group) by PulseRing when a pulse starts.
func add_pulse(origin: Vector2, max_radius: float, expand_time: float) -> void:
	var wave := Wave.new()
	wave.origin = origin
	wave.start_time = _time
	wave.max_radius = max_radius
	wave.expand_time = expand_time
	_waves.append(wave)


func _physics_process(_delta: float) -> void:
	# Raycasts happen here, where the physics space is safe to query.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for wave: Wave in _waves:
		if not wave.scanned:
			_scan_wave(space, wave)


func _process(delta: float) -> void:
	_time += delta
	# Light up every sample the wave front has reached.
	for i: int in _points.size():
		if _time >= _pending_at[i]:
			_lit_at[i] = _pending_at[i]
			_strength[i] = _pending_strength[i]
			_pending_at[i] = INF
	_waves = _waves.filter(func(wave: Wave) -> bool: return not wave.scanned or wave.is_expanding(_time))
	queue_redraw()


func _build_samples() -> void:
	for node: Node in get_tree().get_nodes_in_group("rock_walls"):
		var wall := node as RockWall
		if wall == null:
			continue
		var outline: PackedVector2Array = wall.get_global_outline()
		var first: int = _points.size()
		for e: int in outline.size():
			var a: Vector2 = outline[e]
			var b: Vector2 = outline[(e + 1) % outline.size()]
			var steps: int = maxi(1, ceili(a.distance_to(b) / sample_spacing))
			for k: int in steps:
				_points.append(a.lerp(b, float(k) / steps))
		var count: int = _points.size() - first
		for k: int in count:
			_next.append(first + (k + 1) % count)

	var total: int = _points.size()
	_lit_at.resize(total)
	_lit_at.fill(-INF)
	_strength.resize(total)
	_strength.fill(0.0)
	_pending_at.resize(total)
	_pending_at.fill(INF)
	_pending_strength.resize(total)
	_pending_strength.fill(0.0)


func _scan_wave(space: PhysicsDirectSpaceState2D, wave: Wave) -> void:
	# How far the front can travel in each direction before a rock stops it.
	wave.hit_distances.resize(ring_ray_count)
	for i: int in ring_ray_count:
		var direction: Vector2 = Vector2.from_angle(TAU * i / ring_ray_count)
		wave.hit_distances[i] = _ray_distance(space, wave.origin, wave.origin + direction * wave.max_radius)

	# Schedule every visible outline sample to light up when the front reaches it.
	for i: int in _points.size():
		var point: Vector2 = _points[i]
		var distance: float = wave.origin.distance_to(point)
		if distance > wave.max_radius or not _in_line_of_sight(space, wave.origin, point):
			continue
		_pending_at[i] = wave.start_time + distance / wave.max_radius * wave.expand_time
		_pending_strength[i] = 1.0 - distance_falloff * distance / wave.max_radius
	wave.scanned = true


func _ray_distance(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> float:
	var query := PhysicsRayQueryParameters2D.create(from, to, wall_mask)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return from.distance_to(to)
	return from.distance_to(hit["position"])


func _in_line_of_sight(space: PhysicsDirectSpaceState2D, from: Vector2, point: Vector2) -> bool:
	var target: Vector2 = point - from.direction_to(point) * los_tolerance
	var query := PhysicsRayQueryParameters2D.create(from, target, wall_mask)
	return space.intersect_ray(query).is_empty()


## 1.0 right when the front hits the sample, 0.0 after edge_fade_time.
func _fade(i: int) -> float:
	var age: float = _time - _lit_at[i]
	if age < 0.0 or age > edge_fade_time:
		return 0.0
	return 1.0 - age / edge_fade_time


func _draw() -> void:
	_draw_edges()
	_draw_wave_fronts()


func _draw_edges() -> void:
	for i: int in _points.size():
		var j: int = _next[i]
		# A segment shows only once the front has reached both of its ends.
		var fade: float = minf(_fade(i), _fade(j))
		if fade <= 0.0:
			continue
		var color: Color = edge_color.lerp(flash_color, pow(fade, flash_power))
		color.a = fade * (_strength[i] + _strength[j]) * 0.5
		draw_line(_points[i], _points[j], color, edge_width, true)


func _draw_wave_fronts() -> void:
	for wave: Wave in _waves:
		if not wave.scanned:
			continue
		var radius: float = wave.radius_at(_time)
		if radius <= ring_width:
			continue
		var count: int = wave.hit_distances.size()
		for i: int in count:
			var j: int = (i + 1) % count
			# Stop drawing the front where a rock has already blocked it.
			if radius > wave.hit_distances[i] or radius > wave.hit_distances[j]:
				continue
			var a: Vector2 = wave.origin + Vector2.from_angle(TAU * i / count) * radius
			var b: Vector2 = wave.origin + Vector2.from_angle(TAU * j / count) * radius
			draw_line(a, b, ring_color, ring_width, true)
