class_name Creature
extends CharacterBody2D
## A hostile deep-sea creature: wanders slowly, investigates pulses and sword
## noise it hears, and chases the nearest player it spots (close and in line of
## sight, or pulsing nearby) for a few seconds before losing track. Its speed
## scales with Depth Awareness. Touching a player hurts them (see PlayerHealth).
## The Guardian's sword can damage it only while it is revealed (in the Echo's
## light, or shortly after a pulse front passed over it). A pulse front also
## makes it Exposed for a short time: a Guardian finisher on an Exposed creature
## kills it instantly. The unkillable type ignores damage and only staggers.
## Subclasses (LightHunter) override the targeting hooks below.

enum State { WANDER, INVESTIGATE, CHASE }
enum Look { ROUND, SPIKY, ARROW }

## Emitted when the creature spots a player and starts chasing.
signal spotted(player: Player)
signal killed

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
## Speed while chasing: faster than normal, slower than the Echo's max speed
## (260) and close to the Guardian's (230), so reacting quickly lets players escape.
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

@export_group("Combat")
## Damage needed to kill it. One full Guardian combo = 1 + 1 + 2 = 4, so 8 =
## about two combos (or one finisher while it is Exposed).
@export var max_health: int = 8
## Ignores damage, only staggers (players must avoid it).
@export var unkillable: bool = false
## true = a finisher on an Exposed creature kills it instantly. Off for bosses:
## the finisher then only deals its normal damage.
@export var exposed_finisher_kills: bool = true
## Multiplies the stagger time of every hit (lower = shrugs hits off faster).
@export var stagger_scale: float = 1.0
## Seconds it stays revealed (hittable) after a pulse front passed over it.
@export var pulse_reveal_time: float = 1.5
## Seconds it stays Exposed after a pulse front passed over it. A Guardian
## finisher landing in that time kills it instantly.
@export var exposed_time: float = 1.5
## Seconds of the white flash when hit.
@export var hit_flash_time: float = 0.12
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0)

@export_group("Visual")
@export var look: Look = Look.ROUND
@export var body_radius: float = 20.0
@export var body_color: Color = Color(0.85, 0.25, 0.3)
@export var eye_color: Color = Color(1.0, 0.85, 0.3)
## Number of spikes for the SPIKY look.
@export var spike_count: int = 7
## Spike length compared to body_radius for the SPIKY look.
@export var spike_length: float = 0.55

@export_group("Sonar Visibility")
## true = invisible except for a red echo when the pulse front passes over it,
## and its body inside the Echo's light. false = always drawn (for comparison).
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
var health: int = 0
var _stagger_left: float = 0.0
var _revealed_left: float = 0.0
var _flash_left: float = 0.0
var _dying: bool = false
var _was_in_light: bool = false
var _exposed_left: float = 0.0

@onready var _hitbox: Area2D = $Hitbox
@onready var _alert: AudioStreamPlayer2D = $AlertSound
@onready var _echo: CreatureEcho = $EchoLayer/Echo


func _ready() -> void:
	_home = global_position
	target = global_position
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_to_group("sonar_targets")
	add_to_group("creatures")
	_alert.volume_db = alert_volume_db
	health = max_health


## Called (via the "creatures" group) by StageManager on every pulse.
func hear_pulse(origin: Vector2, player: Player) -> void:
	var distance: float = global_position.distance_to(origin)
	if player and distance <= pulse_spot_distance and _can_chase(player):
		_spot(player)
		return
	if state == State.CHASE or distance > hearing_range:
		return
	_investigate(origin)


## Called (via the "creatures" group) by the Guardian's sword on every swing.
func hear_noise(origin: Vector2, radius: float) -> void:
	if _dying or state == State.CHASE or global_position.distance_to(origin) > radius:
		return
	_investigate(origin)


## True while the Guardian can hurt it: inside a revealing light (the Echo's)
## or shortly after a pulse front passed over it.
func is_revealed() -> bool:
	return _revealed_left > 0.0 or is_in_echo_light()


func is_in_echo_light() -> bool:
	for player: Player in Players.all(get_tree()):
		if player.light_reveal_radius <= 0.0 or player.health.is_downed:
			continue
		if player.global_position.distance_to(global_position) <= player.light_reveal_radius + body_radius:
			return true
	return false


## Looked up on first use: the level (and its creatures) is ready before the
## DepthAwareness node has joined its group.
func _get_awareness() -> DepthAwareness:
	if awareness == null:
		awareness = get_tree().get_first_node_in_group("depth_awareness") as DepthAwareness
	return awareness


func is_dying() -> bool:
	return _dying


func is_exposed() -> bool:
	return _exposed_left > 0.0


## 1 right after the pulse front hit, 0 when Exposed runs out.
func get_exposed_ratio() -> float:
	return _exposed_left / exposed_time if exposed_time > 0.0 else 0.0


## Applies a sword hit. Returns true if it was an Exposed kill (a finisher on an
## Exposed creature), so the attacker can play the big hit effect.
func take_damage(amount: int, attacker: Player, stagger_time: float, knockback: float, is_finisher: bool = false) -> bool:
	if _dying:
		return false
	_stagger_left = stagger_time * stagger_scale
	velocity = attacker.global_position.direction_to(global_position) * knockback
	_flash_left = hit_flash_time
	_echo.flash(self, body_radius)
	queue_redraw()
	_on_damaged(attacker)
	if unkillable:
		return false
	if is_finisher and is_exposed() and exposed_finisher_kills:
		_exposed_left = 0.0
		health = 0
		_die()
		return true
	health -= amount
	if health <= 0:
		_die()
	return false


## Hook for subclasses: called on every sword hit.
func _on_damaged(_attacker: Player) -> void:
	pass


## Hook for subclasses: can touching this player hurt them?
func _can_hurt(_player: Player) -> bool:
	return true


func _die() -> void:
	_dying = true
	killed.emit()
	set_physics_process(false)
	_hitbox.set_deferred("monitoring", false)
	remove_from_group("creatures")
	remove_from_group("sonar_targets")
	queue_free()


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
	return not player.health.is_downed and not _is_player_safe(player)


func _look_for_players(delta: float) -> void:
	_respot_left = maxf(_respot_left - delta, 0.0)
	_spot_timer -= delta
	if state == State.CHASE or _respot_left > 0.0 or _spot_timer > 0.0:
		return
	_spot_timer = spot_check_interval
	# Spot the nearest player that is close, in line of sight and not downed.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var best: Player = null
	var best_distance: float = spot_distance
	for player: Player in Players.all(get_tree()):
		var distance: float = global_position.distance_to(player.global_position)
		if distance > best_distance or not _can_chase(player):
			continue
		var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position, wall_mask)
		if space.intersect_ray(query).is_empty():
			best = player
			best_distance = distance
	if best:
		_spot(best)


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
	_revealed_left = pulse_reveal_time
	if not unkillable and exposed_finisher_kills:
		_exposed_left = exposed_time
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
	var meter: DepthAwareness = _get_awareness()
	var ratio: float = meter.get_ratio() if meter else 0.0
	return lerpf(min_speed, max_speed, ratio)


func _physics_process(delta: float) -> void:
	_update_reveal(delta)
	if _stagger_left > 0.0:
		# Staggered: no steering, just slide out the knockback.
		_stagger_left -= delta
		velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))
		move_and_slide()
		return
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


func _update_reveal(delta: float) -> void:
	_revealed_left = maxf(_revealed_left - delta, 0.0)
	_exposed_left = maxf(_exposed_left - delta, 0.0)
	var in_light: bool = is_in_echo_light()
	# The ARROW look points where it moves, so it needs a redraw every frame.
	if look == Look.ARROW and in_light:
		queue_redraw()
	if in_light != _was_in_light or _flash_left > 0.0:
		_was_in_light = in_light
		_flash_left = maxf(_flash_left - delta, 0.0)
		queue_redraw()


func _on_hitbox_body_entered(body: Node2D) -> void:
	var player := body as Player
	if _dying or _stagger_left > 0.0:
		return
	if player and _can_hurt(player) and not _is_player_safe(player):
		player.health.take_hit(global_position)


func _draw() -> void:
	# Hidden creatures only show their body inside the Echo's light (drawn in the
	# world, so the light itself makes it visible).
	if hidden_until_pinged and not _was_in_light:
		return
	var color: Color = hit_flash_color if _flash_left > 0.0 else body_color
	if look == Look.SPIKY:
		var points := PackedVector2Array()
		for i: int in spike_count * 2:
			var radius: float = body_radius * (1.0 + spike_length if i % 2 == 0 else 0.8)
			points.append(Vector2.from_angle(TAU * i / (spike_count * 2)) * radius)
		draw_colored_polygon(points, color)
	elif look == Look.ARROW:
		# A thin arrowhead pointing where it is moving.
		var forward: Vector2 = velocity.normalized() if velocity.length() > 1.0 else Vector2.RIGHT
		var side: Vector2 = forward.orthogonal()
		var tip: Vector2 = forward * body_radius * 1.6
		var back: Vector2 = -forward * body_radius * 0.9
		draw_colored_polygon(PackedVector2Array([tip, back + side * body_radius, back * 0.4, back - side * body_radius]), color)
		draw_circle(forward * body_radius * 0.6, body_radius * 0.22, eye_color)
		return
	else:
		draw_circle(Vector2.ZERO, body_radius, color)
	draw_circle(Vector2(body_radius * 0.45, 0.0), body_radius * 0.25, eye_color)
