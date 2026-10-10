class_name Creature
extends CharacterBody2D
## A deep-sea creature: wanders slowly, investigates the last pulse it heard.
## Its speed scales with Depth Awareness. Touching the player hurts it (see PlayerHealth).

enum State { WANDER, INVESTIGATE }

@export var awareness: DepthAwareness
@export var player: Player

@export_group("Movement")
@export var min_speed: float = 45.0
@export var max_speed: float = 190.0
@export var steering: float = 4.0
@export var wander_radius: float = 300.0
@export var wander_pause: float = 1.5
@export var arrive_distance: float = 24.0

@export_group("Senses")
## Pulses further away than this are not heard.
@export var hearing_range: float = 1800.0
## How strongly lit coral zones push the creature away.
@export var safe_zone_push: float = 400.0

@export_group("Obstacle Avoidance")
## Seconds to slide along a wall after bumping into it while investigating.
@export var detour_time: float = 0.6
## Small push away from the wall while sliding, so it does not scrape along it.
@export var detour_wall_push: float = 0.2
## Total seconds of wall contact before picking a new point near the pulse.
@export var give_up_time: float = 2.5
## New investigation points are picked this far from the original pulse.
@export var retarget_distance: float = 160.0
## After this many new points, stop investigating and wander where it is.
@export var max_retargets: int = 3

@export_group("Visual")
@export var body_radius: float = 20.0
@export var body_color: Color = Color(0.85, 0.25, 0.3)

@export_group("Sonar Visibility")
## true = invisible except for a red echo when the pulse front passes over it.
## false = always drawn (the old version, for comparison).
@export var hidden_until_pinged: bool = true

var state: State = State.WANDER
var target: Vector2
var _home: Vector2
var _pause_left: float = 0.0
var _pulse_origin: Vector2
var _detour_dir: Vector2 = Vector2.ZERO
var _detour_left: float = 0.0
var _blocked_time: float = 0.0
var _retargets: int = 0

@onready var _hitbox: Area2D = $Hitbox
@onready var _echo: CreatureEcho = $EchoLayer/Echo


func _ready() -> void:
	_home = global_position
	target = global_position
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_to_group("sonar_targets")


func hear_pulse(origin: Vector2) -> void:
	if global_position.distance_to(origin) > hearing_range:
		return
	state = State.INVESTIGATE
	target = origin
	_pulse_origin = origin
	_pause_left = 0.0
	_retargets = 0
	_reset_detour()


## Called by SonarOverlay when a pulse front reaches this creature in line of sight.
func on_sonar_hit(_origin: Vector2) -> void:
	if hidden_until_pinged:
		_echo.flash(self, body_radius)


func get_state_name() -> String:
	var state_name: String = State.keys()[state]
	if _detour_left > 0.0:
		state_name += " +DETOUR"
	return state_name


func get_current_speed() -> float:
	var ratio: float = awareness.get_ratio() if awareness else 0.0
	return lerpf(min_speed, max_speed, ratio)


func _physics_process(delta: float) -> void:
	var desired: Vector2 = Vector2.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
	elif global_position.distance_to(target) <= arrive_distance:
		_on_target_reached()
	else:
		desired = _steer_direction(delta) * get_current_speed()

	desired += _safe_zone_push()
	velocity = velocity.lerp(desired, 1.0 - exp(-steering * delta))
	move_and_slide()

	if get_slide_collision_count() > 0:
		if state == State.WANDER:
			# Wandering: just pick another spot.
			_pick_wander_target()
		else:
			_on_blocked_while_investigating(delta)


func _steer_direction(delta: float) -> Vector2:
	if _detour_left > 0.0:
		_detour_left -= delta
		return _detour_dir
	return global_position.direction_to(target)


func _on_blocked_while_investigating(delta: float) -> void:
	_blocked_time += delta
	if _blocked_time >= give_up_time:
		_retarget_near_pulse()
		return
	if _detour_left > 0.0:
		return
	# Slide along the wall. Keep the same side as the last detour so it goes
	# around the rock instead of turning back and forth.
	var normal: Vector2 = get_slide_collision(0).get_normal()
	var tangent: Vector2 = normal.orthogonal()
	var reference: Vector2 = _detour_dir if _detour_dir != Vector2.ZERO else global_position.direction_to(target)
	if tangent.dot(reference) < 0.0:
		tangent = -tangent
	_detour_dir = (tangent + normal * detour_wall_push).normalized()
	_detour_left = detour_time


func _retarget_near_pulse() -> void:
	_retargets += 1
	_reset_detour()
	if _retargets > max_retargets:
		# Give up and wander where it is.
		_home = global_position
		state = State.WANDER
		_pick_wander_target()
		return
	target = _pulse_origin + Vector2.from_angle(randf() * TAU) * retarget_distance


func _reset_detour() -> void:
	_detour_dir = Vector2.ZERO
	_detour_left = 0.0
	_blocked_time = 0.0


func _on_target_reached() -> void:
	if state == State.INVESTIGATE:
		# Keep wandering around where the pulse was heard.
		_home = target
		state = State.WANDER
	_reset_detour()
	_pause_left = wander_pause
	_pick_wander_target()


func _pick_wander_target() -> void:
	var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * wander_radius
	target = _home + offset


func _safe_zone_push() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral and coral.is_in_safe_zone(global_position):
			push += coral.global_position.direction_to(global_position) * safe_zone_push
	return push


func _is_player_safe() -> bool:
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral and coral.is_in_safe_zone(player.global_position):
			return true
	return false


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == player and not _is_player_safe():
		player.health.take_hit(global_position)


func _draw() -> void:
	if hidden_until_pinged:
		return
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_circle(Vector2(body_radius * 0.45, 0.0), body_radius * 0.25, Color(1.0, 0.85, 0.3))
