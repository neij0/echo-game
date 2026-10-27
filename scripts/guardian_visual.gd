class_name GuardianVisual
extends Node2D
## The Guardian's look ("silhouette + glow"), all procedural vector shapes:
## a tall dark cloaked figure seen top-down but slightly from the front, with
## large branching antlers (the clearest shape from above), a faint cold blue
## rim and two faint eyes. The cloak hem is a row of spring points, so it
## sways and trails when he moves. Each sword hit adds a small body lunge
## (read from SwordAbility). Downed: kneels and sinks, antlers lower, eyes dim.
## The dark silhouette is drawn in the world (lit by lights); rim and eyes on
## an own CanvasLayer that the darkness does not dim. Visual only.

@export var sword: SwordAbility

@export_group("Body")
@export var body_color: Color = Color(0.04, 0.045, 0.06)
@export var hood_radius: float = 6.5
@export var hood_offset: Vector2 = Vector2(0.0, -19.0)
@export var shoulder_half_width: float = 10.0
@export var shoulder_y: float = -12.0
@export var neck_half_width: float = 4.0

@export_group("Cloak")
@export var hem_half_width: float = 15.0
@export var hem_y: float = 24.0
## Points along the hem (more = smoother sway).
@export var hem_points: int = 6
## The middle of the hem hangs this much lower than its corners.
@export var hem_curve: float = 3.0
@export var cloak_stiffness: float = 45.0
@export var cloak_damping: float = 7.0
## How far the hem trails behind per px/s of speed.
@export var cloak_drag: float = 0.05
## Largest trailing offset of a hem point (keeps the shape valid).
@export var cloak_max_trail: float = 9.0
@export var cloak_sway_amount: float = 1.5
@export var cloak_sway_speed: float = 0.4

@export_group("Antlers")
@export var antler_base: Vector2 = Vector2(3.5, -24.0)
## Angle of the main beam from straight up, outward (degrees).
@export var antler_angle_degrees: float = 32.0
@export var antler_segments: int = 4
@export var antler_segment_length: float = 6.5
## The beam bends outward this much per segment (degrees).
@export var antler_curve_degrees: float = 12.0
@export var antler_width: float = 2.4
## Tines branch off the beam at segments 1..tine_count.
@export var tine_count: int = 3
@export var tine_length: float = 6.0
## Tine angle towards straight up, relative to the beam (degrees).
@export var tine_angle_degrees: float = 45.0

@export_group("Rim And Eyes")
@export var rim_color: Color = Color(0.4, 0.65, 1.0)
@export var rim_energy: float = 1.3
@export_range(0.0, 1.0) var rim_alpha: float = 0.35
@export var rim_width: float = 1.1
@export var eye_color: Color = Color(0.6, 0.8, 1.0)
@export var eye_energy: float = 2.0
@export_range(0.0, 1.0) var eye_alpha: float = 0.6
@export var eye_offset: Vector2 = Vector2(2.4, -19.5)
@export var eye_radius: float = 1.1

@export_group("Motion")
## Lean at full sideways speed (degrees).
@export var lean_degrees: float = 7.0
@export var lean_full_speed: float = 230.0

@export_group("Downed")
@export var downed_scale: Vector2 = Vector2(1.1, 0.7)
@export var downed_sink: float = 8.0
## Antlers rotate outward/down this much while downed (degrees).
@export var antler_droop_degrees: float = 35.0
## Share of the eye brightness left while downed.
@export_range(0.0, 1.0) var downed_eye_share: float = 0.2

@export_group("Behind Rocks")
## Share of the glow hidden while he stands behind (north of) a tall rock (the
## glow is drawn above the world, so the rock cannot cover it by itself).
@export_range(0.0, 1.0) var behind_rock_hide: float = 0.85
## How fast the glow fades out / back in there (per second).
@export var behind_rock_fade_speed: float = 6.0

var _player: Player
var _time: float = 0.0
var _down_amount: float = 0.0
var _transform: Transform2D = Transform2D.IDENTITY
var _hem: Array[SpringPoint] = []
var _glow: Node2D
var _behind_rock: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	# Springs work relative to the player, so moving only bends them by the drag.
	for i: int in hem_points:
		_hem.append(SpringPoint.new(_hem_rest(i)))
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_glow = Node2D.new()
	layer.add_child(_glow)
	_glow.draw.connect(_draw_glow)


func _process(delta: float) -> void:
	_time += delta
	var downed: bool = _player != null and _player.health.is_downed
	_down_amount = move_toward(_down_amount, 1.0 if downed else 0.0, delta * 3.0)
	var velocity: Vector2 = _player.velocity if _player else Vector2.ZERO
	var lunge: Vector2 = sword.get_lunge_offset() if sword else Vector2.ZERO
	var lean: float = deg_to_rad(lean_degrees) * clampf((velocity.x + lunge.x * 20.0) / lean_full_speed, -1.0, 1.0)
	var body_scale: Vector2 = Vector2.ONE.lerp(downed_scale, _down_amount)
	_transform = Transform2D(lean * (1.0 - _down_amount), body_scale, 0.0, lunge + Vector2(0.0, downed_sink * _down_amount))

	for i: int in _hem.size():
		var trail: Vector2 = (-velocity * cloak_drag).limit_length(cloak_max_trail)
		var sway := Vector2(sin(_time * TAU * cloak_sway_speed + i * 0.9) * cloak_sway_amount, 0.0)
		# Corners follow the body more closely than the middle of the hem.
		var weight: float = 0.5 + 0.5 * sin(PI * float(i) / maxf(hem_points - 1, 1))
		_hem[i].step(_hem_rest(i) + trail * weight + sway, cloak_stiffness, cloak_damping, delta)
	_glow.global_position = global_position
	_behind_rock = move_toward(_behind_rock, 1.0 if RockFace.is_covered(get_tree(), global_position, global_position.y) else 0.0, behind_rock_fade_speed * delta)
	_glow.modulate.a = 1.0 - _behind_rock * behind_rock_hide
	queue_redraw()
	_glow.queue_redraw()


func _hem_rest(index: int) -> Vector2:
	var t: float = float(index) / maxf(hem_points - 1, 1)
	var x: float = lerpf(-hem_half_width, hem_half_width, t)
	var y: float = hem_y + sin(PI * t) * hem_curve
	return _transform * Vector2(x, y)


## The cloak outline relative to the player (neck, shoulder, hem, shoulder, neck).
func _cloak_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(_transform * Vector2(-neck_half_width, shoulder_y - 3.0))
	points.append(_transform * Vector2(-shoulder_half_width, shoulder_y))
	for spring: SpringPoint in _hem:
		points.append(spring.position)
	points.append(_transform * Vector2(shoulder_half_width, shoulder_y))
	points.append(_transform * Vector2(neck_half_width, shoulder_y - 3.0))
	return points


## Antler polylines (beam + tines) for one side, relative to the player.
func _antler_lines(side: float) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var droop: float = deg_to_rad(antler_droop_degrees) * _down_amount
	var direction: Vector2 = Vector2.UP.rotated((deg_to_rad(antler_angle_degrees) + droop) * side)
	var point: Vector2 = Vector2(antler_base.x * side, antler_base.y)
	var beam := PackedVector2Array([_transform * point])
	for k: int in antler_segments:
		direction = direction.rotated(deg_to_rad(antler_curve_degrees) * side)
		point += direction * antler_segment_length
		beam.append(_transform * point)
		if k >= 1 and k <= tine_count and k < antler_segments - 1:
			var tine_direction: Vector2 = direction.rotated(-deg_to_rad(tine_angle_degrees) * side)
			var length: float = tine_length * (1.0 - 0.15 * k)
			lines.append(PackedVector2Array([_transform * point, _transform * (point + tine_direction * length)]))
	lines.append(beam)
	return lines


# --- Dark silhouette (world, lit by lights) ----------------------------------

func _draw() -> void:
	draw_colored_polygon(_cloak_points(), body_color)
	draw_circle(_transform * hood_offset, hood_radius * _transform.get_scale().x, body_color)
	for side: float in [-1.0, 1.0]:
		for line: PackedVector2Array in _antler_lines(side):
			draw_polyline(line, body_color, antler_width, true)


## His silhouette as polylines in this node's space (OccludedOutline): the
## cloak, the hood and the antlers.
func get_outline_lines() -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var cloak: PackedVector2Array = _cloak_points()
	cloak.append(cloak[0])
	lines.append(cloak)
	var hood := PackedVector2Array()
	var center: Vector2 = _transform * hood_offset
	var radius: float = hood_radius * _transform.get_scale().x
	for i: int in 17:
		hood.append(center + Vector2.from_angle(TAU * i / 16.0) * radius)
	lines.append(hood)
	for side: float in [-1.0, 1.0]:
		lines.append_array(_antler_lines(side))
	return lines


# --- Rim and eyes (unlit layer) ----------------------------------------------

static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw_glow() -> void:
	var rim: Color = _hdr(rim_color, rim_energy, rim_alpha)
	var outline: PackedVector2Array = _cloak_points()
	outline.append(outline[0])
	_glow.draw_polyline(outline, rim, rim_width, true)
	_glow.draw_arc(_transform * hood_offset, hood_radius * _transform.get_scale().x, 0.0, TAU, 24, rim, rim_width, true)
	for side: float in [-1.0, 1.0]:
		for line: PackedVector2Array in _antler_lines(side):
			_glow.draw_polyline(line, rim, rim_width, true)
	var eyes: Color = _hdr(eye_color, eye_energy, eye_alpha * lerpf(1.0, downed_eye_share, _down_amount))
	for side: float in [-1.0, 1.0]:
		_glow.draw_circle(_transform * Vector2(eye_offset.x * side, eye_offset.y), eye_radius, eyes)
