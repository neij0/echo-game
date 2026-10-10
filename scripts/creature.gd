class_name Creature
extends CharacterBody2D
## A deep-sea creature: wanders slowly, investigates the last pulse it heard,
## and chases a diver it spots (close and in line of sight, or pulsing nearby)
## for a few seconds before losing track. Its speed scales with Depth Awareness. Touching a player hurts them (see
## PlayerHealth). Works with any number of players (no fixed player reference).

enum State { WANDER, INVESTIGATE, CHASE }

## Emitted when the creature spots a player and starts chasing.
signal spotted(player: Player)

## Optional: if empty, the first node in the "depth_awareness" group is used.
@export var awareness: DepthAwareness

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
## Spots a player this close if nothing blocks the line of sight.
@export var spot_distance: float = 220.0
## Spots a player who pulses this close (no line of sight needed).
@export var pulse_spot_distance: float = 350.0
## Seconds between line-of-sight checks (raycasts).
@export var spot_check_interval: float = 0.1
@export_flags_2d_physics var wall_mask: int = 1

@export_group("Chase")
## Seconds the creature follows the player's real position after spotting.
@export var chase_time: float = 3.0
## Speed while chasing: faster than normal, slower than the diver's max speed
## (260), so reacting quickly lets the player escape.
@export var chase_speed: float = 215.0
## After losing track, seconds before it can spot a player by sight again
## (a nearby pulse still gives the player away).
@export var respot_cooldown: float = 2.0
@export var alert_volume_db: float = 0.0

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
var _chased: Player
var _chase_left: float = 0.0
var _respot_left: float = 0.0
var _spot_timer: float = 0.0

@onready var _hitbox: Area2D = $Hitbox
@onready var _alert: AudioStreamPlayer2D = $AlertSound
@onready var _echo: CreatureEcho = $EchoLayer/Echo


func _ready() -> void:
	_home = global_position
	target = global_position
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_to_group("sonar_targets")
	add_to_group("creatures")
	if awareness == null:
		awareness = get_tree().get_first_node_in_group("depth_awareness") as DepthAwareness
	_alert.volume_db = alert_volume_db


## Called (via the "creatures" group) by RunManager on every pulse.
func hear_pulse(origin: Vector2, player: Player) -> void:
	var distance: float = global_position.distance_to(origin)
	if player and distance <= pulse_spot_distance and _can_chase(player):
		_spot(player)
		return
	if state == State.CHASE or distance > hearing_range:
		return
	_investigate(origin)


func _investigate(origin: Vector2) -> void:
	state = State.INVESTIGATE
	target = origin
	_pulse_origin = origin
	_pause_left = 0.0
	_retargets = 0
	_reset_detour()


func _spot(player: Player) -> void:
	var was_chasing: bool = state == State.CHASE
	state = State.CHASE
	_chased = player
	_chase_left = chase_time
	_pause_left = 0.0
	_reset_detour()
	if not was_chasing:
		_alert.play()
		spotted.emit(player)


## Chase over: go to the last known position and investigate there.
func _lose_track() -> void:
	var last_known: Vector2 = _chased.global_position if is_instance_valid(_chased) else target
	_chased = null
	_respot_left = respot_cooldown
	_investigate(last_known)


func _can_chase(player: Player) -> bool:
	return not player.health.is_dead and not _is_player_safe(player)


func _look_for_players(delta: float) -> void:
	_respot_left = maxf(_respot_left - delta, 0.0)
	_spot_timer -= delta
	if state == State.CHASE or _respot_left > 0.0 or _spot_timer > 0.0:
		return
	_spot_timer = spot_check_interval
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for player: Player in Players.all(get_tree()):
		if global_position.distance_to(player.global_position) > spot_distance or not _can_chase(player):
			continue
		var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position, wall_mask)
		if space.intersect_ray(query).is_empty():
			_spot(player)
			return


func _update_chase(delta: float) -> void:
	if state != State.CHASE:
		return
	_chase_left -= delta
	if _chase_left <= 0.0 or not is_instance_valid(_chased) or not _can_chase(_chased):
		_lose_track()
		return
	target = _chased.global_position
	_pulse_origin = target


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
	if state == State.CHASE:
		return chase_speed
	var ratio: float = awareness.get_ratio() if awareness else 0.0
	return lerpf(min_speed, max_speed, ratio)


func _physics_process(delta: float) -> void:
	_look_for_players(delta)
	_update_chase(delta)

	var desired: Vector2 = Vector2.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
	elif state != State.CHASE and global_position.distance_to(target) <= arrive_distance:
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
	# While chasing, only slide around rocks; the chase itself ends on its timer.
	if _blocked_time >= give_up_time and state != State.CHASE:
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


## The player closest to this creature (null if there are none).
func get_nearest_player() -> Player:
	return Players.nearest(get_tree(), global_position)


func _is_player_safe(player: Player) -> bool:
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral and coral.is_in_safe_zone(player.global_position):
			return true
	return false


func _on_hitbox_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player and not _is_player_safe(player):
		player.health.take_hit(global_position)


func _draw() -> void:
	if hidden_until_pinged:
		return
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_circle(Vector2(body_radius * 0.45, 0.0), body_radius * 0.25, Color(1.0, 0.85, 0.3))
