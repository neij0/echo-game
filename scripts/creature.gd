class_name Creature
extends CharacterBody2D
## A hostile deep-sea creature: wanders slowly, investigates pulses, sword
## noise and other creatures' alerts, and chases the nearest player it spots
## (close and in line of sight, or pulsing nearby). It follows the level's
## navigation mesh (baked by the LevelBuilder), so it goes through doorways and
## around rocks. A chase never makes it clearly faster than the player: its
## speed is a share of the chased player's top speed (per mode, a little higher
## with Depth Awareness). Close in, it lunges after a short telegraphed wind-up
## (eyes flare + sound), then needs a moment to recover. After losing sight it
## goes to where the player was heading and SEARCHes there for a few seconds
## before wandering again. Touching a player hurts them (see PlayerHealth).
## The Guardian's sword can damage it only while it is revealed (in the Echo's
## light, or shortly after a pulse front passed over it). A pulse front also
## makes it Exposed for a short time: a Guardian finisher on an Exposed creature
## kills it instantly. The unkillable type ignores damage and only staggers.
## Subclasses (LightHunter) override the targeting hooks below.

enum State { WANDER, INVESTIGATE, CHASE, SEARCH }
## Phases of the close-range lunge (only during CHASE).
enum Lunge { NONE, WIND_UP, BURST, RECOVER }
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
## Chase speed = the chased player's max_speed times a ratio. The ratio goes
## from the _min value (Depth Awareness 0) to the _max value (full awareness).
## Calm mode: clearly slower than the players.
@export_range(0.0, 1.5) var calm_chase_ratio_min: float = 0.82
@export_range(0.0, 1.5) var calm_chase_ratio_max: float = 0.88
## Challenge mode: about as fast as the players, never clearly faster.
@export_range(0.0, 1.5) var challenge_chase_ratio_min: float = 0.95
@export_range(0.0, 1.5) var challenge_chase_ratio_max: float = 1.0
## Used for the chase speed when there is no chased player (rushing to the
## last seen position).
@export var reference_player_speed: float = 245.0
## The chase keeps going while the player is this close and in line of sight.
@export var lose_sight_distance: float = 600.0
## Seconds it keeps following the player's real position after losing sight
## (it "feels" where they went around the corner), then it SEARCHes.
@export var chase_memory: float = 0.5
## After a search ends, seconds before it can spot a player by sight again
## (a nearby pulse still gives the player away).
@export var respot_cooldown: float = 1.0
@export var alert_volume_db: float = 0.0

@export_group("Search")
## After losing sight: goes to the last seen position plus the player's
## velocity times this (where they were heading)...
@export var search_lead_time: float = 0.5
## ...then looks around there for this many seconds before wandering again.
@export var search_time: float = 4.0
## Search points are picked this far around that position.
@export var search_radius: float = 220.0
## Short stop at each search point.
@export var search_pause: float = 0.35

@export_group("Lunge")
@export var lunge_enabled: bool = true
## Starts a lunge when the chased player is this close (from the body's edge)
## and in line of sight.
@export var lunge_range: float = 120.0
## Telegraph: seconds it coils (slows down, eyes flare, sound) before the burst.
@export var lunge_wind_up: float = 0.3
## Movement speed while coiling, as a share of its chase speed.
@export_range(0.0, 1.0) var lunge_wind_up_speed_ratio: float = 0.15
## The burst: speed and duration (distance = speed x time).
@export var lunge_speed: float = 560.0
@export var lunge_time: float = 0.2
## Seconds after the burst when it drifts slowly (players can get away).
@export var lunge_recovery: float = 0.6
@export_range(0.0, 1.0) var lunge_recovery_speed_ratio: float = 0.2
## Seconds after a recovery before the next lunge can start.
@export var lunge_cooldown: float = 1.2
## Eye brightness multiplier at the peak of the flare (1 = no flare).
@export var lunge_eye_flare: float = 3.0
@export var lunge_volume_db: float = 0.0

@export_group("Pathing")
## Follow the level's navigation mesh (doorways, corners). Off = straight line.
@export var use_navigation: bool = true
## A path point counts as reached this close.
@export var path_point_reach: float = 24.0
## Minimum seconds between two path requests.
@export var path_refresh_time: float = 0.25
## A new path is requested when the target moved this far from the last one.
@export var path_retarget_distance: float = 40.0

@export_group("Alerting")
## Entering CHASE alerts the other creatures this close: they INVESTIGATE
## towards this creature (the noise).
@export var alert_radius: float = 700.0
## Reacts to other creatures' alerts.
@export var responds_to_alerts: bool = true

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
## SPIKY shell rotation (radians per second).
@export var spike_spin_speed: float = 0.4
## When fully revealed: dark body (body_color darkened by this) with a glowing
## outline in the type colour (the same as its sonar echo).
@export_range(0.0, 1.0) var fill_darken: float = 0.75
@export var outline_energy: float = 1.8
@export var outline_width: float = 1.5
@export var eye_energy: float = 2.0
## Tendrils trailing behind (ROUND look; fewer on the others).
@export var tendril_count: int = 5
@export var tendril_segments: int = 6
## Tendril length compared to body_radius.
@export var tendril_length: float = 1.6
## Tendril thickness compared to body_radius.
@export var tendril_width: float = 0.09
@export var tendril_wave_amount: float = 5.0
@export var tendril_wave_speed: float = 0.9
## Opacity of the tendrils / fins outline compared to the body outline.
@export_range(0.0, 1.0) var tendril_alpha: float = 0.7
## Fin flaps per second (ARROW look).
@export var fin_flap_speed: float = 1.6

@export_group("Sonar Visibility")
## true = invisible except for a red echo when the pulse front passes over it,
## and its body inside the Echo's light. false = always drawn (for comparison).
@export var hidden_until_pinged: bool = true

@export_group("Silhouette")
## Between the Echo's light_reveal_radius (full reveal, hittable) and the edge
## of her light, the creature shows only as a dark moving silhouette (no
## outline, not hittable, not Exposed) with faint eyes (CreatureEyes). It fades
## in as it gets closer. Hidden when a rock blocks her light.
@export var silhouette_enabled: bool = true
@export var silhouette_color: Color = Color(0.01, 0.015, 0.025)
## Opacity of the silhouette right at the edge of the full reveal.
@export_range(0.0, 1.0) var silhouette_max_alpha: float = 0.9
## Seconds between line-of-sight checks to the Echo (her light casts shadows).
@export var silhouette_check_interval: float = 0.1

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
## Line of sight to the chased player at the last check.
var _chase_in_sight: bool = false
var _sight_check_left: float = 0.0
var _last_seen: Vector2
var _last_seen_velocity: Vector2 = Vector2.ZERO
## Set by the StageManager: Challenge mode uses the challenge chase ratios.
var challenge_mode: bool = false
var _search_center: Vector2
var _search_arrived: bool = false
var _search_left: float = 0.0
var lunge_phase: Lunge = Lunge.NONE
var _lunge_left: float = 0.0
var _lunge_cooldown_left: float = 0.0
var _lunge_dir: Vector2 = Vector2.RIGHT
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _path_target: Vector2
var _path_refresh_left: float = 0.0
var _respot_left: float = 0.0
var _spot_timer: float = 0.0
var health: int = 0
var _stagger_left: float = 0.0
var _revealed_left: float = 0.0
var _flash_left: float = 0.0
var _dying: bool = false
var _was_in_light: bool = false
var _exposed_left: float = 0.0
## 0 = no silhouette, 1 = full silhouette (see the Silhouette group).
var silhouette_ratio: float = 0.0
var _silhouette_check_left: float = 0.0
var _silhouette_blocked: bool = false
var _anim_time: float = 0.0
## Where the creature points (last movement direction).
var _facing: Vector2 = Vector2.RIGHT

@onready var _hitbox: Area2D = $Hitbox
@onready var _alert: AudioStreamPlayer2D = $AlertSound
@onready var _lunge_sound: AudioStreamPlayer2D = get_node_or_null("LungeSound") as AudioStreamPlayer2D
@onready var _echo: CreatureEcho = $EchoLayer/Echo


func _ready() -> void:
	_home = global_position
	target = global_position
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_to_group("sonar_targets")
	add_to_group("creatures")
	_alert.volume_db = alert_volume_db
	if _lunge_sound:
		_lunge_sound.volume_db = lunge_volume_db
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


## Called (via the "creatures" group) when another creature starts a chase:
## creatures within its alert_radius investigate towards it.
func hear_alert(source: Creature) -> void:
	if source == self or _dying or not responds_to_alerts or state == State.CHASE:
		return
	if global_position.distance_to(source.global_position) > source.alert_radius:
		return
	_investigate(source.global_position)


## Set by the StageManager when the level is built.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


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
	_end_lunge()
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
	_reset_path()


func _spot(player: Player) -> void:
	var was_chasing: bool = state == State.CHASE
	state = State.CHASE
	_chased = player
	_chase_left = chase_memory
	_chase_in_sight = true
	_sight_check_left = spot_check_interval
	_last_seen = player.global_position
	_last_seen_velocity = player.velocity
	_pause_left = 0.0
	_reset_detour()
	_reset_path()
	if not was_chasing:
		_alert.play()
		spotted.emit(player)
		get_tree().call_group("creatures", "hear_alert", self)


## Lost sight: go to where the player was heading and SEARCH there.
func _lose_track() -> void:
	var last_known: Vector2 = _last_seen + _last_seen_velocity * search_lead_time
	_chased = null
	_chase_in_sight = false
	if lunge_phase == Lunge.WIND_UP:
		_end_lunge()
	state = State.SEARCH
	target = last_known
	_pulse_origin = last_known
	_search_center = last_known
	_search_arrived = false
	_search_left = search_time
	_retargets = 0
	_pause_left = 0.0
	_reset_detour()
	_reset_path()


## Search over: wander around where it gave up.
func _end_search() -> void:
	state = State.WANDER
	_home = global_position
	_respot_left = respot_cooldown
	_reset_path()
	_pick_wander_target()


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
	if not is_instance_valid(_chased) or not _can_chase(_chased):
		_lose_track()
		return
	# Line of sight check: while it sees the player, the chase is refreshed.
	_sight_check_left -= delta
	if _sight_check_left <= 0.0:
		_sight_check_left = spot_check_interval
		_chase_in_sight = _can_see(_chased, lose_sight_distance)
		if _chase_in_sight:
			_chase_left = chase_memory
			_last_seen = _chased.global_position
			_last_seen_velocity = _chased.velocity
	_chase_left -= delta
	if _chase_left <= 0.0:
		_lose_track()
		return
	target = _chased.global_position
	_pulse_origin = target


func _update_search(delta: float) -> void:
	if state != State.SEARCH or not _search_arrived:
		return
	_search_left -= delta
	if _search_left <= 0.0:
		_end_search()


## True if the player is within max_distance and no rock is in between.
func _can_see(player: Player, max_distance: float) -> bool:
	if global_position.distance_to(player.global_position) > max_distance:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position, wall_mask)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# --- Lunge --------------------------------------------------------------------

## Runs the lunge phases. Returns true while the lunge controls the movement.
func _update_lunge(delta: float) -> bool:
	_lunge_cooldown_left = maxf(_lunge_cooldown_left - delta, 0.0)
	if lunge_phase == Lunge.NONE:
		if not _can_start_lunge():
			return false
		lunge_phase = Lunge.WIND_UP
		_lunge_left = lunge_wind_up
		if _lunge_sound:
			_lunge_sound.play()
	_lunge_left -= delta
	match lunge_phase:
		Lunge.WIND_UP:
			if state != State.CHASE or not is_instance_valid(_chased):
				_end_lunge()
				return false
			# Coil: nearly stop and keep turning towards the prey.
			_lunge_dir = global_position.direction_to(_chased.global_position)
			var coil: Vector2 = _lunge_dir * get_chase_speed() * lunge_wind_up_speed_ratio
			velocity = velocity.lerp(coil, 1.0 - exp(-steering * 2.0 * delta))
			if _lunge_left <= 0.0:
				lunge_phase = Lunge.BURST
				_lunge_left = lunge_time
				velocity = _lunge_dir * lunge_speed
				_hurt_overlapping_players()
		Lunge.BURST:
			velocity = _lunge_dir * lunge_speed
			if _lunge_left <= 0.0:
				lunge_phase = Lunge.RECOVER
				_lunge_left = lunge_recovery
		Lunge.RECOVER:
			var drift: Vector2 = _lunge_dir * get_chase_speed() * lunge_recovery_speed_ratio
			velocity = velocity.lerp(drift, 1.0 - exp(-steering * delta))
			if _lunge_left <= 0.0:
				_end_lunge()
	return true


func _can_start_lunge() -> bool:
	if not lunge_enabled or state != State.CHASE or _lunge_cooldown_left > 0.0:
		return false
	if not is_instance_valid(_chased) or not _chase_in_sight:
		return false
	return global_position.distance_to(_chased.global_position) <= lunge_range + body_radius


func _end_lunge() -> void:
	if lunge_phase != Lunge.NONE:
		_lunge_cooldown_left = lunge_cooldown
	lunge_phase = Lunge.NONE
	_lunge_left = 0.0


## 0-1 brightness boost of the eyes: rises during the wind-up (the telegraph),
## full during the burst, fades during the recovery.
func get_lunge_flare() -> float:
	match lunge_phase:
		Lunge.WIND_UP:
			return clampf(1.0 - _lunge_left / maxf(lunge_wind_up, 0.001), 0.25, 1.0)
		Lunge.BURST:
			return 1.0
		Lunge.RECOVER:
			return clampf(_lunge_left / maxf(lunge_recovery, 0.001), 0.0, 1.0) * 0.6
	return 0.0


## The burst also hits a player who was already touching it (body_entered
## only fires on a new contact).
func _hurt_overlapping_players() -> void:
	if not _hitbox.monitoring:
		return
	for body: Node2D in _hitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)


## Called by SonarOverlay when a pulse front reaches this creature in line of sight.
func on_sonar_hit(_origin: Vector2) -> void:
	_revealed_left = pulse_reveal_time
	if not unkillable and exposed_finisher_kills:
		_exposed_left = exposed_time
	if hidden_until_pinged:
		_echo.flash(self, body_radius)


func get_state_name() -> String:
	var state_name: String = State.keys()[state]
	if lunge_phase != Lunge.NONE:
		state_name += " +" + String(Lunge.keys()[lunge_phase])
	if _detour_left > 0.0:
		state_name += " +DETOUR"
	return state_name


func _get_awareness_ratio() -> float:
	var meter: DepthAwareness = _get_awareness()
	return meter.get_ratio() if meter else 0.0


## Chase speed share of the player's speed for the current mode and awareness.
func get_chase_ratio() -> float:
	var awareness_ratio: float = _get_awareness_ratio()
	if challenge_mode:
		return lerpf(challenge_chase_ratio_min, challenge_chase_ratio_max, awareness_ratio)
	return lerpf(calm_chase_ratio_min, calm_chase_ratio_max, awareness_ratio)


## Speed while chasing (and while rushing to the last seen position).
func get_chase_speed() -> float:
	var player_speed: float = _chased.max_speed if is_instance_valid(_chased) else reference_player_speed
	return player_speed * get_chase_ratio()


func get_current_speed() -> float:
	if state == State.CHASE or (state == State.SEARCH and not _search_arrived):
		return get_chase_speed()
	return lerpf(min_speed, max_speed, _get_awareness_ratio())


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
	_update_search(delta)
	if _update_lunge(delta):
		move_and_slide()
		return

	var desired: Vector2 = Vector2.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
	elif state != State.CHASE and (global_position.distance_to(target) <= arrive_distance or _is_path_finished()):
		_on_target_reached()
	else:
		desired = _steer_direction(delta) * get_current_speed()

	desired += _safe_zone_push()
	velocity = velocity.lerp(desired, 1.0 - exp(-steering * delta))
	move_and_slide()

	if get_slide_collision_count() > 0:
		if not _path.is_empty():
			# Following the navigation mesh: only give up after a long contact.
			_on_blocked_on_path(delta)
		elif state == State.WANDER:
			# Wandering without a path: just pick another spot.
			_pick_wander_target()
		else:
			_on_blocked_while_investigating(delta)


func _steer_direction(delta: float) -> Vector2:
	if _detour_left > 0.0:
		_detour_left -= delta
		return _detour_dir
	return global_position.direction_to(_next_path_point(delta))


# --- Pathing (navigation mesh baked by the LevelBuilder) -----------------------

## The next point to steer to: along the navigation path to target, or target
## itself when there is no path (navigation off or not ready yet).
func _next_path_point(delta: float) -> Vector2:
	if not use_navigation:
		return target
	_path_refresh_left -= delta
	if _path_refresh_left <= 0.0 and (_path.is_empty() or _path_target.distance_to(target) > path_retarget_distance):
		_request_path()
	if _path.is_empty():
		return target
	while _path_index < _path.size() - 1 and global_position.distance_to(_path[_path_index]) <= path_point_reach:
		_path_index += 1
	return _path[_path_index]


func _request_path() -> void:
	_path_target = target
	_path_refresh_left = path_refresh_time
	_path = NavigationServer2D.map_get_path(get_world_2d().navigation_map, global_position, target, true)
	_path_index = 0


## The path ends short of the target (target inside rock): treat as reached.
func _is_path_finished() -> bool:
	if _path.is_empty() or _path_index < _path.size() - 1:
		return false
	return global_position.distance_to(_path[_path.size() - 1]) <= path_point_reach


func _reset_path() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_path_refresh_left = 0.0


func _on_blocked_on_path(delta: float) -> void:
	_blocked_time += delta
	if _blocked_time < give_up_time or state == State.CHASE:
		return
	if state == State.WANDER:
		_reset_detour()
		_reset_path()
		_pick_wander_target()
	else:
		_retarget_near_pulse()


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
	_reset_path()


func _reset_detour() -> void:
	_detour_dir = Vector2.ZERO
	_detour_left = 0.0
	_blocked_time = 0.0


func _on_target_reached() -> void:
	_reset_detour()
	_reset_path()
	if state == State.SEARCH:
		# Look around the last known position until the search time runs out.
		_search_arrived = true
		_pause_left = search_pause
		target = _search_center + Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * search_radius
		return
	if state == State.INVESTIGATE:
		# Keep wandering around where the pulse was heard.
		_home = target
		state = State.WANDER
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
	if in_light != _was_in_light or _flash_left > 0.0:
		_was_in_light = in_light
		_flash_left = maxf(_flash_left - delta, 0.0)
		queue_redraw()
	_anim_time += delta
	if velocity.length() > 1.0:
		_facing = _facing.lerp(velocity.normalized(), 1.0 - exp(-8.0 * delta)).normalized()
	var previous_silhouette: float = silhouette_ratio
	silhouette_ratio = 0.0 if in_light else _compute_silhouette(delta)
	# Visible shapes move (tendrils, fins), so they redraw every frame.
	if in_light or silhouette_ratio > 0.0 or previous_silhouette > 0.0 or not hidden_until_pinged:
		queue_redraw()


## 1 at the edge of the Echo's full reveal, 0 at the edge of her light.
func _compute_silhouette(delta: float) -> float:
	if not silhouette_enabled or not hidden_until_pinged:
		return 0.0
	var best: float = 0.0
	var source: Player = null
	for player: Player in Players.all(get_tree()):
		if player.light_reveal_radius <= 0.0 or player.health.is_downed:
			continue
		var inner: float = player.light_reveal_radius + body_radius
		var outer: float = player.get_light_radius()
		var distance: float = global_position.distance_to(player.global_position)
		if outer <= inner or distance >= outer:
			continue
		var ratio: float = smoothstep(outer, inner, distance)
		if ratio > best:
			best = ratio
			source = player
	if source == null:
		return 0.0
	# Her light casts shadows: no silhouette behind a rock.
	_silhouette_check_left -= delta
	if _silhouette_check_left <= 0.0:
		_silhouette_check_left = silhouette_check_interval
		var query := PhysicsRayQueryParameters2D.create(source.global_position, global_position, wall_mask)
		_silhouette_blocked = not get_world_2d().direct_space_state.intersect_ray(query).is_empty()
	return 0.0 if _silhouette_blocked else best


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
		if silhouette_ratio > 0.0:
			# Dark shape only: no outline and no eye dot (CreatureEyes adds faint eyes).
			draw_shape(self, Color(silhouette_color, silhouette_ratio * silhouette_max_alpha), Color(0.0, 0.0, 0.0, 0.0), false)
		return
	var fill: Color = hit_flash_color if _flash_left > 0.0 else body_color.darkened(fill_darken)
	draw_shape(self, fill, _hdr(get_type_color(), outline_energy, 1.0), true)


## The colour that tells the creature type apart (the same as its sonar echo).
func get_type_color() -> Color:
	return _echo.color if _echo else body_color


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


## Draws the creature's shape (body, fins / tendrils, eye) on canvas, centred on
## canvas's origin, with the current procedural motion. Used for the full body,
## the silhouette and the sonar echo (CreatureEcho), so all three match.
## outline alpha 0 = no outline (tendrils then use the fill colour).
func draw_shape(canvas: CanvasItem, fill: Color, outline: Color, with_eye: bool) -> void:
	var forward: Vector2 = _facing
	var side: Vector2 = forward.orthogonal()
	var has_outline: bool = outline.a > 0.0
	var limb_color: Color = Color(outline, outline.a * tendril_alpha) if has_outline else fill
	var body := PackedVector2Array()
	var tendrils: int = tendril_count
	match look:
		Look.SPIKY:
			# Slowly turning spiky shell.
			var spin: float = _anim_time * spike_spin_speed
			for i: int in spike_count * 2:
				var radius: float = body_radius * (1.0 + spike_length if i % 2 == 0 else 0.8)
				body.append(Vector2.from_angle(TAU * i / (spike_count * 2) + spin) * radius)
			tendrils = mini(tendril_count, 3)
		Look.ARROW:
			# A thin arrowhead with two flapping side fins.
			var tip: Vector2 = forward * body_radius * 1.6
			var back: Vector2 = -forward * body_radius * 0.9
			body = PackedVector2Array([tip, back + side * body_radius * 0.8, back * 0.4, back - side * body_radius * 0.8])
			var flap: float = sin(_anim_time * TAU * fin_flap_speed)
			for s: float in [-1.0, 1.0]:
				var root: Vector2 = side * s * body_radius * 0.35
				var fin_tip: Vector2 = side * s * body_radius * (1.3 + 0.25 * flap) - forward * body_radius * 0.5
				var fin := PackedVector2Array([root + forward * body_radius * 0.4, fin_tip, root - forward * body_radius * 0.5])
				canvas.draw_colored_polygon(fin, fill)
				if has_outline:
					canvas.draw_polyline(_closed(fin), limb_color, outline_width, true)
			tendrils = mini(tendril_count, 2)
		_:
			# A soft oval body, a little longer than wide, pointing where it moves.
			for i: int in 20:
				var angle: float = TAU * i / 20.0
				body.append(forward * cos(angle) * body_radius * 1.15 + side * sin(angle) * body_radius * 0.85)
	_draw_tendrils(canvas, forward, side, tendrils, limb_color)
	canvas.draw_colored_polygon(body, fill)
	if has_outline:
		canvas.draw_polyline(_closed(body), outline, outline_width, true)
	if with_eye:
		var flare: float = lerpf(1.0, lunge_eye_flare, get_lunge_flare())
		canvas.draw_circle(forward * body_radius * 0.55, body_radius * 0.18 * sqrt(flare), _hdr(eye_color, eye_energy * flare, 1.0))


## Wavy tendrils trailing behind the body.
func _draw_tendrils(canvas: CanvasItem, forward: Vector2, side: Vector2, count: int, color: Color) -> void:
	for i: int in count:
		var spread: float = (float(i) / maxf(count - 1, 1) - 0.5) * 2.0 if count > 1 else 0.0
		var root: Vector2 = -forward * body_radius * 0.75 + side * spread * body_radius * 0.55
		var line := PackedVector2Array([root])
		for k: int in range(1, tendril_segments + 1):
			var along: float = float(k) / tendril_segments
			var wave: float = sin(_anim_time * TAU * tendril_wave_speed + i * 1.3 - k * 0.8) * tendril_wave_amount * along
			line.append(root - forward * body_radius * tendril_length * along + side * (wave + spread * along * body_radius * 0.4))
		canvas.draw_polyline(line, color, maxf(body_radius * tendril_width, 1.0), true)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	result.append(points[0])
	return result
