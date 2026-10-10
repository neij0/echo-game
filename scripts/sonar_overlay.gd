class_name SonarOverlay
extends Node2D
## Draws what the sonar "sees": the travelling wave front, rock outlines that
## light up when the front reaches them (only parts in line of sight of the pulse)
## and small sparks at the hit points. Also tells every node in the
## "sonar_targets" group (corals, creatures) when the front reaches it in line
## of sight, by calling its on_sonar_hit(origin) method.
## Must live on a CanvasLayer with follow_viewport_enabled, so the world's
## CanvasModulate darkness does not dim it. Colours are multiplied by *_energy
## values above 1.0 so they bloom with the 2D HDR glow (GlowEnvironment).

## Emitted once per outline sample when the front reaches it.
## distance_ratio: 0 = at the pulse origin, 1 = at the pulse's max radius.
signal edge_hit(point: Vector2, distance_ratio: float)

@export_group("Wave Front")
@export var ring_color: Color = Color(0.4, 0.9, 1.0, 0.9)
## HDR brightness multiplier of the front (above 1.0 = glows).
@export var ring_energy: float = 3.0
## Width right at the start of the pulse.
@export var ring_start_width: float = 7.0
## Width when the front reaches max radius.
@export var ring_end_width: float = 1.5
## Opacity of the front when it reaches max radius (it starts at 1.0).
@export_range(0.0, 1.0) var ring_end_alpha: float = 0.15
## Higher = the front thins and fades earlier in its expansion.
@export var ring_fade_power: float = 0.7
## Rays cast per pulse so the front stops at rocks instead of passing through.
@export var ring_ray_count: int = 180

@export_group("Afterglow Trail")
## A single soft band right behind the front that fades towards the origin.
@export var trail_enabled: bool = true
## Length of the band in pixels behind the front.
@export var trail_length: float = 45.0
## Opacity of the band where it touches the front, compared to the front.
@export_range(0.0, 1.0) var trail_alpha: float = 0.1
## Brightness multiplier of the band. Kept at 1.0 (no bloom) so it stays soft;
## in HDR even low alpha with a high energy looks very bright.
@export var trail_energy: float = 1.0

@export_group("Edges")
## Distance between outline sample points in pixels. Lower = smoother reveal, more raycasts.
@export var sample_spacing: float = 10.0
@export var edge_width: float = 2.5
@export var edge_color: Color = Color(0.45, 0.95, 1.0)
## HDR brightness multiplier of revealed edges.
@export var edge_energy: float = 1.6
## Colour of an edge at the moment the front hits it, before it settles to edge_color.
@export var flash_color: Color = Color(1.0, 1.0, 1.0)
@export var flash_energy: float = 3.0
## Higher = the white flash disappears faster.
@export var flash_power: float = 4.0
@export var edge_fade_time: float = 2.0
## 0 = far edges as bright as near ones, 1 = edges at max radius are invisible.
@export_range(0.0, 1.0) var distance_falloff: float = 0.35

@export_group("Sparks")
@export var sparks_enabled: bool = true
## Chance (0-1) that a hit outline sample emits a spark.
@export_range(0.0, 1.0) var spark_chance: float = 0.25
@export var spark_color: Color = Color(0.85, 1.0, 1.0)
@export var spark_energy: float = 4.0
@export var spark_size: float = 3.0
@export var spark_time: float = 0.25
## Pixels a spark drifts away from the pulse origin during its life.
@export var spark_drift: float = 6.0

@export_group("Line Of Sight")
## Pulls each line-of-sight ray back from the target so the rock itself does not block it.
@export var los_tolerance: float = 2.0
@export_flags_2d_physics var wall_mask: int = 1


class Wave:
	var origin: Vector2
	var start_time: float
	var max_radius: float
	var expand_time: float
	var hit_distances: PackedFloat32Array = PackedFloat32Array()
	var scanned: bool = false
	## Sonar targets this wave has already reached (hit or blocked).
	var reached: Array[Node2D] = []

	func progress_at(time: float) -> float:
		return clampf((time - start_time) / expand_time, 0.0, 1.0)

	func radius_at(time: float) -> float:
		return max_radius * progress_at(time)

	func is_expanding(time: float) -> bool:
		return time - start_time <= expand_time


class Spark:
	var position: Vector2
	var direction: Vector2
	var born: float
	var strength: float


var _time: float = 0.0
var _waves: Array[Wave] = []
var _sparks: Array[Spark] = []

# One entry per outline sample point (all rocks flattened into one list).
var _points: PackedVector2Array = PackedVector2Array()
## Index of the next point on the same rock outline (closes the loop).
var _next: PackedInt32Array = PackedInt32Array()
var _lit_at: PackedFloat32Array = PackedFloat32Array()
var _strength: PackedFloat32Array = PackedFloat32Array()
var _pending_at: PackedFloat32Array = PackedFloat32Array()
var _pending_strength: PackedFloat32Array = PackedFloat32Array()
var _pending_ratio: PackedFloat32Array = PackedFloat32Array()
var _pending_dir: PackedVector2Array = PackedVector2Array()


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
		_check_targets(space, wave)


func _process(delta: float) -> void:
	_time += delta
	# Light up every sample the wave front has reached.
	for i: int in _points.size():
		if _time >= _pending_at[i]:
			_lit_at[i] = _pending_at[i]
			_strength[i] = _pending_strength[i]
			_pending_at[i] = INF
			_on_sample_hit(i)
	_waves = _waves.filter(func(wave: Wave) -> bool: return not wave.scanned or wave.is_expanding(_time))
	_sparks = _sparks.filter(func(spark: Spark) -> bool: return _time - spark.born < spark_time)
	queue_redraw()


func _on_sample_hit(i: int) -> void:
	edge_hit.emit(_points[i], _pending_ratio[i])
	if sparks_enabled and randf() < spark_chance:
		var spark := Spark.new()
		spark.position = _points[i]
		spark.direction = _pending_dir[i]
		spark.born = _time
		spark.strength = _strength[i]
		_sparks.append(spark)


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
	_pending_ratio.resize(total)
	_pending_ratio.fill(0.0)
	_pending_dir.resize(total)
	_pending_dir.fill(Vector2.ZERO)


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
		var ratio: float = distance / wave.max_radius
		_pending_at[i] = wave.start_time + ratio * wave.expand_time
		_pending_strength[i] = 1.0 - distance_falloff * ratio
		_pending_ratio[i] = ratio
		_pending_dir[i] = wave.origin.direction_to(point)
	wave.scanned = true


## Calls on_sonar_hit(origin) on every sonar target the front has just reached,
## if it is in line of sight of the pulse origin (same check as the rock edges).
func _check_targets(space: PhysicsDirectSpaceState2D, wave: Wave) -> void:
	var radius: float = wave.radius_at(_time)
	for node: Node in get_tree().get_nodes_in_group("sonar_targets"):
		var target := node as Node2D
		if target == null or target in wave.reached:
			continue
		if wave.origin.distance_to(target.global_position) > radius:
			continue
		wave.reached.append(target)
		if _in_line_of_sight(space, wave.origin, target.global_position):
			target.call("on_sonar_hit", wave.origin)


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


## Multiplies a colour's RGB (not alpha) so it goes above 1.0 and blooms.
static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


## 1.0 right when the front hits the sample, 0.0 after edge_fade_time.
func _fade(i: int) -> float:
	var age: float = _time - _lit_at[i]
	if age < 0.0 or age > edge_fade_time:
		return 0.0
	return 1.0 - age / edge_fade_time


func _draw() -> void:
	_draw_edges()
	_draw_wave_fronts()
	_draw_sparks()


func _draw_edges() -> void:
	var settled: Color = _hdr(edge_color, edge_energy, 1.0)
	var flash: Color = _hdr(flash_color, flash_energy, 1.0)
	for i: int in _points.size():
		var j: int = _next[i]
		# A segment shows only once the front has reached both of its ends.
		var fade: float = minf(_fade(i), _fade(j))
		if fade <= 0.0:
			continue
		var color: Color = settled.lerp(flash, pow(fade, flash_power))
		color.a = fade * (_strength[i] + _strength[j]) * 0.5
		draw_line(_points[i], _points[j], color, edge_width, true)


func _draw_wave_fronts() -> void:
	for wave: Wave in _waves:
		if not wave.scanned:
			continue
		var radius: float = wave.radius_at(_time)
		# Bright and thick at the start, thinner and fainter as it expands.
		var t: float = pow(wave.progress_at(_time), ring_fade_power)
		var width: float = lerpf(ring_start_width, ring_end_width, t)
		var alpha: float = lerpf(1.0, ring_end_alpha, t) * ring_color.a
		if trail_enabled:
			_draw_trail(wave, radius, _hdr(ring_color, trail_energy, alpha * trail_alpha))
		_draw_ring(wave, radius, _hdr(ring_color, ring_energy, alpha), width)


func _draw_ring(wave: Wave, radius: float, color: Color, width: float) -> void:
	if radius <= width:
		return
	var count: int = wave.hit_distances.size()
	for i: int in count:
		var j: int = (i + 1) % count
		# Stop drawing the front where a rock has already blocked it.
		if radius > wave.hit_distances[i] or radius > wave.hit_distances[j]:
			continue
		var a: Vector2 = wave.origin + Vector2.from_angle(TAU * i / count) * radius
		var b: Vector2 = wave.origin + Vector2.from_angle(TAU * j / count) * radius
		draw_line(a, b, color, width, true)


## A soft band from the front back towards the origin: opaque at the front,
## fully transparent trail_length pixels behind it.
func _draw_trail(wave: Wave, radius: float, color: Color) -> void:
	var inner: float = maxf(radius - trail_length, 0.0)
	if radius <= inner:
		return
	var clear := Color(color, 0.0)
	var colors := PackedColorArray([color, color, clear, clear])
	var count: int = wave.hit_distances.size()
	for i: int in count:
		var j: int = (i + 1) % count
		# Same as the front: no trail where a rock has already blocked the wave.
		if radius > wave.hit_distances[i] or radius > wave.hit_distances[j]:
			continue
		var dir_a: Vector2 = Vector2.from_angle(TAU * i / count)
		var dir_b: Vector2 = Vector2.from_angle(TAU * j / count)
		var quad := PackedVector2Array([
			wave.origin + dir_a * radius,
			wave.origin + dir_b * radius,
			wave.origin + dir_b * inner,
			wave.origin + dir_a * inner,
		])
		draw_polygon(quad, colors)


func _draw_sparks() -> void:
	for spark: Spark in _sparks:
		var t: float = (_time - spark.born) / spark_time
		var size: float = spark_size * (1.0 - t)
		var color: Color = _hdr(spark_color, spark_energy, (1.0 - t) * spark.strength)
		# Drift back towards the pulse, like a tiny reflection off the rock.
		var center: Vector2 = spark.position - spark.direction * spark_drift * t
		draw_circle(center, size * 0.5, color)
		draw_line(center - Vector2(size, 0.0), center + Vector2(size, 0.0), color, 1.0, true)
		draw_line(center - Vector2(0.0, size), center + Vector2(0.0, size), color, 1.0, true)
