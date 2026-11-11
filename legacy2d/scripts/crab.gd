class_name Crab
extends AmbientLife
## A small crab at the foot of a rock: a dark flat shell with little legs
## and claws (no eyes), lit only by the real lights. It steps sideways now
## and then; a player coming close (or a pulse) sends it scuttling sideways
## away, never far from its spot.

@export var shell_radii: Vector2 = Vector2(8.0, 5.5)
@export var leg_length: float = 7.0
@export var claw_size: float = 3.2
@export var shell_color: Color = Color(0.32, 0.3, 0.34)
## A player this close scares it; it scuttles this fast for scuttle_time.
@export var scare_radius: float = 130.0
@export var scuttle_speed: float = 170.0
@export var scuttle_time: float = 0.45
## Never farther than this from its spot.
@export var home_leash: float = 70.0
## A small side step every few seconds (random in this range).
@export var step_interval_min: float = 2.0
@export var step_interval_max: float = 5.0
@export var step_distance: float = 10.0
@export var step_speed: float = 40.0

var _home := Vector2.ZERO
var _velocity := Vector2.ZERO
var _move_left: float = 0.0
var _next_step: float = 0.0
var _gait: float = 0.0
var _was_moving: bool = true


func _ready() -> void:
	super._ready()
	add_to_group("sonar_targets")
	_home = position
	_next_step = randf_range(step_interval_min, step_interval_max)


## Called by SonarOverlay when a pulse reaches it.
func on_sonar_hit(origin: Vector2) -> void:
	_scuttle_from(origin)


func is_scuttling() -> bool:
	return _move_left > 0.0 and _velocity.length() > step_speed


func _scuttle_from(point: Vector2) -> void:
	var away: Vector2 = point.direction_to(global_position)
	# Crabs go sideways: mostly left or right.
	var side: float = signf(away.x) if absf(away.x) > 0.01 else 1.0
	var direction := Vector2(side, away.y * 0.4).normalized()
	# Back towards the spot if the leash is used up on that side.
	if (position + direction * scuttle_speed * scuttle_time).distance_to(_home) > home_leash:
		direction = Vector2(-direction.x, direction.y)
	_velocity = direction * scuttle_speed
	_move_left = scuttle_time


func _update(delta: float) -> void:
	if _move_left <= 0.0:
		var player: Player = nearest_player_within(scare_radius)
		if player:
			_scuttle_from(player.global_position)
	if _move_left <= 0.0:
		_next_step -= delta
		if _next_step <= 0.0:
			_next_step = randf_range(step_interval_min, step_interval_max)
			_velocity = Vector2(1.0 if randf() < 0.5 else -1.0, 0.0) * step_speed
			_move_left = step_distance / step_speed
	if _move_left > 0.0:
		_move_left -= delta
		var next: Vector2 = position + _velocity * delta
		if next.distance_to(_home) <= home_leash:
			position = next
		_gait += delta * _velocity.length() * 0.25
	else:
		_velocity = Vector2.ZERO
		_was_moving = false


func _is_moving() -> bool:
	# One more redraw after it stops, to put the legs down.
	if _move_left > 0.0:
		_was_moving = true
		return true
	return _was_moving


func _draw() -> void:
	var moving: bool = _move_left > 0.0
	var leg_color: Color = shell_color.darkened(0.25)
	# Four legs a side, moving in turns while it walks.
	for side: float in [-1.0, 1.0]:
		for k: int in 4:
			var root := Vector2(side * shell_radii.x * 0.6, lerpf(-shell_radii.y * 0.5, shell_radii.y * 0.6, k / 3.0))
			var swing: float = sin(_gait + k * 1.6 + side) * 2.0 if moving else 0.0
			var knee: Vector2 = root + Vector2(side * leg_length * 0.6, -2.0 + swing * 0.5)
			var foot: Vector2 = knee + Vector2(side * leg_length * 0.5, 3.0 + swing)
			_batch.add_polyline(PackedVector2Array([root, knee, foot]), leg_color, 1.2)
	# Two small claws in front.
	for side: float in [-1.0, 1.0]:
		var claw := Vector2(side * shell_radii.x * 0.55, -shell_radii.y - claw_size * 0.6)
		_batch.add_dot(claw, claw_size, shell_color.darkened(0.1), 7)
	_batch.add_convex(Landmark.ellipse(Vector2.ZERO, shell_radii, 12), shell_color)
	_batch.add_line(Vector2(-shell_radii.x * 0.7, -shell_radii.y * 0.3), Vector2(shell_radii.x * 0.7, -shell_radii.y * 0.3), shell_color.lightened(0.18), 1.0)
	_batch.draw(self)
