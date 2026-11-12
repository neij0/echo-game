class_name Creature
extends CharacterBody3D
## A hostile deep-sea creature: wanders slowly, investigates pulses, sword
## noise and other creatures' alerts, and chases the nearest player it spots
## (close and in line of sight, or pulsing nearby). It follows the level's
## navigation mesh (NavigationServer3D: baked from the floor plans), so it
## goes through doorways and around rocks. A chase never makes it clearly
## faster than the player: its speed is a share of the chased player's top
## speed (per mode, a little higher with Depth Awareness). Close in, it lunges
## after a short telegraphed wind-up (eyes flare + sound), then needs a moment
## to recover. After losing sight it goes to where the player was heading and
## SEARCHes there for a few seconds before wandering again. Touching a player
## hurts them (see PlayerHealth).
## The Guardian's sword can damage it only while it is revealed (in the Echo's
## light, or shortly after a pulse front passed over it). A pulse front also
## makes it Exposed for a short time: a Guardian finisher on an Exposed creature
## kills it instantly. The unkillable type ignores damage and only staggers.
## Frenzy (set_frenzy, the collapse escape): it always chases the nearest
## standing player and never loses track.
## Subclasses (LightHunter, Sentinel) override the targeting hooks below.
## 3D: it moves on the floor plane (y = 0); lengths are world units (50 px of
## the 2D game = 1 unit). Its look is the CreatureBody child ($Body); it reads
## the visibility values below (silhouette_ratio, sense_ratio, is_lit_by_echo...).

enum State { WANDER, INVESTIGATE, CHASE, SEARCH }
## Phases of the close-range lunge (only during CHASE).
enum Lunge { NONE, WIND_UP, BURST, RECOVER }
enum Look { ROUND, SPIKY, ARROW }

## Emitted when the creature spots a player and starts chasing.
signal spotted(player: Player)
signal killed
## Emitted (in the next physics frame) whenever its state changes (CreatureVoice).
signal state_changed(old_state: State, new_state: State)
## Emitted when a lunge wind-up starts (the telegraph: CreatureVoice hisses).
signal lunge_started
## Emitted when a pulse front reaches it in line of sight (its sonar echo).
signal pinged
## Emitted when it gives up a pursuit at its pursuit limit (it rests a while).
signal gave_up

## Optional: if empty, the first node in the "depth_awareness" group is used.
@export var awareness: DepthAwareness

@export_group("Movement")
@export var min_speed: float = 0.9
@export var max_speed: float = 3.8
@export var steering: float = 4.0
@export var wander_radius: float = 6.0
@export var wander_pause: float = 1.5
@export var arrive_distance: float = 0.48

@export_group("Senses")
## Pulses further away than this are not heard.
@export var hearing_range: float = 36.0
## How strongly lit coral zones push the creature away.
@export var safe_zone_push: float = 8.0
## Near a lit coral's zone (this much beyond its edge) the creature steers
## around it instead of into it, so the push and the path never fight.
@export var safe_zone_steer_margin: float = 0.8
## Sliding around lit zones this long (not chasing, e.g. two zones block the
## way) = it gives up on that point and picks another.
@export var safe_zone_give_up_time: float = 1.0
## Spots a player this close if nothing blocks the line of sight.
@export var spot_distance: float = 4.4
## Spots a player who pulses this close (no line of sight needed).
@export var pulse_spot_distance: float = 7.0
## Seconds between line-of-sight checks (raycasts).
@export var spot_check_interval: float = 0.1
## Height of its line-of-sight rays: rock lower than this does not block them.
@export var sight_height: float = 0.4
@export_flags_3d_physics var wall_mask: int = 1

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
@export var reference_player_speed: float = 4.9
## The chase keeps going while the player is this close and in line of sight.
@export var lose_sight_distance: float = 12.0
## Seconds it keeps following the player's real position after losing sight
## (it "feels" where they went around the corner), then it SEARCHes.
@export var chase_memory: float = 0.5
## After a search ends, seconds before it can spot a player by sight again
## (a nearby pulse still gives the player away).
@export var respot_cooldown: float = 1.0
## Gives up a pursuit after this many seconds of CHASE + SEARCH in a row (re-
## spotting does not reset it; wandering lets it recover). 0 = never gives up.
## Set on creatures the players cannot kill, so they can always escape them.
@export var calm_pursuit_limit: float = 0.0
@export var challenge_pursuit_limit: float = 0.0
## Seconds of pursuit recovered per second of wandering.
@export var pursuit_recovery_rate: float = 1.0
## After giving up: seconds it ignores the players (no spotting by sight or
## pulse, no investigating) while it swims away.
@export var give_up_rest_time: float = 6.0
## While resting it swims this far away from the nearest player.
@export var give_up_retreat_distance: float = 8.0

@export_group("Search")
## After losing sight: goes to the last seen position plus the player's
## velocity times this (where they were heading)...
@export var search_lead_time: float = 0.5
## ...then looks around there for this many seconds before wandering again.
@export var search_time: float = 4.0
## Search points are picked this far around that position.
@export var search_radius: float = 4.4
## Short stop at each search point.
@export var search_pause: float = 0.35

@export_group("Lunge")
@export var lunge_enabled: bool = true
## Starts a lunge when the chased player is this close (from the body's edge)
## and in line of sight.
@export var lunge_range: float = 2.4
## Telegraph: seconds it coils (slows down, eyes flare, sound) before the burst.
@export var lunge_wind_up: float = 0.3
## Movement speed while coiling, as a share of its chase speed.
@export_range(0.0, 1.0) var lunge_wind_up_speed_ratio: float = 0.15
## The burst: speed and duration (distance = speed x time).
@export var lunge_speed: float = 11.2
@export var lunge_time: float = 0.2
## Seconds after the burst when it drifts slowly (players can get away).
@export var lunge_recovery: float = 0.6
@export_range(0.0, 1.0) var lunge_recovery_speed_ratio: float = 0.2
## Seconds after a recovery before the next lunge can start.
@export var lunge_cooldown: float = 1.2
## Eye brightness multiplier at the peak of the flare (1 = no flare).
@export var lunge_eye_flare: float = 3.0

@export_group("Pathing")
## Follow the level's navigation mesh (doorways, corners). Off = straight line.
@export var use_navigation: bool = true
## A path point counts as reached this close.
@export var path_point_reach: float = 0.48
## Minimum seconds between two path requests.
@export var path_refresh_time: float = 0.25
## A new path is requested when the target moved this far from the last one.
@export var path_retarget_distance: float = 0.8
## Stuck recovery (CreatureStuckWatch): how far a nudge pushes it off the wall.
@export var unstick_nudge_distance: float = 0.48

@export_group("Alerting")
## Entering CHASE alerts the other creatures this close: they INVESTIGATE
## towards this creature (the noise).
@export var alert_radius: float = 14.0
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
@export var retarget_distance: float = 3.2
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
## finisher landing in that time kills it instantly. Longer with the Echo's
## skills (PlayerSkills stat "exposed_time_add"); it stays hittable while Exposed.
@export var exposed_time: float = 1.5
## Seconds of the white flash when hit.
@export var hit_flash_time: float = 0.12

@export_group("Visual")
## The placeholder shape (CreatureBody) until the creature models (Phase C).
@export var look: Look = Look.ROUND
@export var body_radius: float = 0.4
## Height of the body above the floor (the cut-away and the eyes use it).
@export var body_height: float = 0.8
@export var body_color: Color = Color(0.85, 0.25, 0.3)
## The colour that tells the type apart: its glowing outline when revealed and
## its sonar echo.
@export var type_color: Color = Color(1.0, 0.15, 0.12)
@export var eye_color: Color = Color(1.0, 0.85, 0.3)

@export_group("Sonar Visibility")
## true = invisible except for its echo when the pulse front passes over it,
## and its body inside the Echo's light. false = always revealed (comparison).
@export var hidden_until_pinged: bool = true

@export_group("Silhouette")
## Between the Echo's light_reveal_radius (full reveal, hittable) and the edge
## of her light, the creature shows only as a dark moving silhouette (no
## outline, not hittable, not Exposed) with faint eyes (CreatureEyes). It fades
## in as it gets closer. Hidden when a rock blocks her light.
@export var silhouette_enabled: bool = true
## Seconds between line-of-sight checks to the Echo (her light casts shadows).
@export var silhouette_check_interval: float = 0.1

var state: State = State.WANDER
var target: Vector3
var _home: Vector3
var _pause_left: float = 0.0
var _pulse_origin: Vector3
var _detour_dir: Vector3 = Vector3.ZERO
var _detour_left: float = 0.0
var _blocked_time: float = 0.0
var _retargets: int = 0
var _chased: Player
var _chase_left: float = 0.0
## Line of sight to the chased player at the last check.
var _chase_in_sight: bool = false
var _sight_check_left: float = 0.0
var _last_seen: Vector3
var _last_seen_velocity: Vector3 = Vector3.ZERO
## Set by the StageManager: Challenge mode uses the challenge chase ratios.
var challenge_mode: bool = false
var _search_center: Vector3
var _search_arrived: bool = false
var _search_left: float = 0.0
var lunge_phase: Lunge = Lunge.NONE
var _lunge_left: float = 0.0
var _lunge_cooldown_left: float = 0.0
var _lunge_dir: Vector3 = Vector3.RIGHT
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _path_target: Vector3
var _path_refresh_left: float = 0.0
var _respot_left: float = 0.0
## Seconds of the current pursuit (CHASE + SEARCH) and of the rest after giving up.
var _pursuit_time: float = 0.0
var _rest_left: float = 0.0
var _spot_timer: float = 0.0
var health: int = 0
var _stagger_left: float = 0.0
var _revealed_left: float = 0.0
var _flash_left: float = 0.0
var _dying: bool = false
var _was_in_light: bool = false
var _exposed_left: float = 0.0
## Exposed time of the last pulse hit (base + skill bonus), for the ring.
var _exposed_total: float = 0.0
## Echo Mark skill: seconds the outline stays after a pulse hit ("mark_time_add").
var _marked_left: float = 0.0
var _marked_total: float = 0.0
## 0 = no silhouette, 1 = full silhouette (see the Silhouette group).
var silhouette_ratio: float = 0.0
## 0-1: how strongly a CloseSense (the Guardian) feels it right now. Keeps the
## silhouette and the eyes visible at melee range without the Echo's light.
var sense_ratio: float = 0.0
var _silhouette_check_left: float = 0.0
var _silhouette_blocked: bool = false
## Frenzy (collapse escape): chases the nearest standing player, never loses track.
var is_frenzied: bool = false
## Debug counters (CreatureStuckWatch): path requests and state changes so far.
var path_requests: int = 0
var state_changes: int = 0
var lunges_started: int = 0
var _last_state: State = State.WANDER
var _navigation_map: RID
var _last_wall_normal: Vector3 = Vector3.ZERO
## Which way it slides around a lit coral's zone (+1 / -1); flips on a wall.
var _zone_side: float = 0.0
var _steering_around_zone: bool = false
var _zone_time: float = 0.0
## Where the creature points (last movement direction, on the floor).
var facing: Vector3 = Vector3.RIGHT
var _camera: SharedCamera

@onready var _hitbox: Area3D = $Hitbox


func _ready() -> void:
	_home = global_position
	target = global_position
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_to_group("sonar_targets")
	add_to_group("creatures")
	add_to_group("cutaway_targets")
	health = max_health


## Called (via the "creatures" group) by StageManager on every pulse.
func hear_pulse(origin: Vector3, player: Player) -> void:
	if is_resting():
		return
	var distance: float = _flat_distance(global_position, origin)
	if player and distance <= pulse_spot_distance and _can_chase(player):
		_spot(player)
		return
	if state == State.CHASE or distance > hearing_range:
		return
	_investigate(origin)


## Called (via the "creatures" group) by the Guardian's sword on every swing.
func hear_noise(origin: Vector3, radius: float) -> void:
	if _dying or is_resting() or state == State.CHASE or _flat_distance(global_position, origin) > radius:
		return
	_investigate(origin)


## Called (via the "creatures" group) when another creature starts a chase:
## creatures within its alert_radius investigate towards it.
func hear_alert(source: Creature) -> void:
	if source == self or _dying or is_resting() or not responds_to_alerts or state == State.CHASE:
		return
	if _flat_distance(global_position, source.global_position) > source.alert_radius:
		return
	_investigate(source.global_position)


## Set by the StageManager when the level is built.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


## Starts chasing this player right away (a lockdown wave waking), if allowed.
func hunt(player: Player) -> void:
	if _can_chase(player):
		_spot(player)


## The collapse escape: from now on it chases the nearest standing player
## wherever they are, and never loses track (off again on a new level).
func set_frenzy(enabled: bool) -> void:
	is_frenzied = enabled
	if enabled:
		_update_frenzy()


## True if a swing from `from` along `direction` (reach, half arc in radians)
## reaches the body: within reach + body_radius and the centre inside the arc
## (on the floor plane). Bigger bodies (the bosses) measure their own shape.
func is_in_swing(from: Vector3, direction: Vector3, reach: float, half_arc: float) -> bool:
	var offset := Vector2(global_position.x - from.x, global_position.z - from.z)
	var aim := Vector2(direction.x, direction.z)
	return offset.length() <= reach + body_radius and absf(aim.angle_to(offset)) <= half_arc


## ViewCutaway ("cutaway_targets"): rock never hides it while it lunges or is
## Exposed (a danger, or a chance, the players must see).
func wants_cutaway() -> bool:
	return not _dying and (lunge_phase == Lunge.WIND_UP or lunge_phase == Lunge.BURST or is_exposed())


## The middle of the body (the cut-away keeps it visible).
func get_body_center() -> Vector3:
	return global_position + Vector3(0.0, body_height * 0.5, 0.0)


## True while the Guardian can hurt it: inside a revealing light (the Echo's),
## shortly after a pulse front passed over it, or fully inside a CloseSense
## (melee self-defence; only a pulse makes it Exposed for the instant kill).
func is_revealed() -> bool:
	return _revealed_left > 0.0 or is_exposed() or is_in_echo_light() or sense_ratio >= 1.0


## True while it is inside the Echo's full reveal (CreatureBody: full body
## with its glowing outline).
func is_lit_by_echo() -> bool:
	return _was_in_light or not hidden_until_pinged


## How much of the body shows (1 = full, the silhouette share outside the
## Echo's light, 0 = hidden).
func get_body_visibility() -> float:
	if is_lit_by_echo():
		return 1.0
	return maxf(silhouette_ratio, sense_ratio)


func is_in_echo_light() -> bool:
	for player: Player in Players.all(get_tree()):
		if player.light_reveal_radius <= 0.0 or player.health.is_downed:
			continue
		if _flat_distance(player.global_position, global_position) <= player.light_reveal_radius + body_radius:
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
	return _exposed_left / _exposed_total if _exposed_total > 0.0 else 0.0


## Echo Mark: an outline only (not hittable on its own), 1 right after the
## pulse hit, 0 when it runs out.
func get_mark_ratio() -> float:
	return _marked_left / _marked_total if _marked_total > 0.0 else 0.0


## 1 at the start of the white hit flash, 0 when it is over.
func get_flash_ratio() -> float:
	return _flash_left / hit_flash_time if hit_flash_time > 0.0 else 0.0


## Pushed back without damage (a blocked touch on the Guardian's Shield).
func repel(direction: Vector3, speed: float, stagger_time: float) -> void:
	if _dying:
		return
	_end_lunge()
	velocity = _flat(direction).normalized() * speed
	_stagger_left = maxf(_stagger_left, stagger_time * stagger_scale)


## Applies a sword hit. Returns true if it was an Exposed kill (a finisher on an
## Exposed creature), so the attacker can play the big hit effect.
func take_damage(amount: int, attacker: Player, stagger_time: float, knockback: float, is_finisher: bool = false) -> bool:
	if _dying:
		return false
	_stagger_left = stagger_time * stagger_scale
	_end_lunge()
	velocity = _flat(global_position - attacker.global_position).normalized() * knockback
	_flash_left = hit_flash_time
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


## Hook for subclasses: true while it is closing in quietly instead of
## openly chasing (CreatureVoice then uses its investigate voice, not a screech).
func is_stalking() -> bool:
	return false


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
	remove_from_group("cutaway_targets")
	queue_free()


func _investigate(origin: Vector3) -> void:
	state = State.INVESTIGATE
	target = _flat(origin)
	_pulse_origin = target
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
	_last_seen = _flat(player.global_position)
	_last_seen_velocity = _flat(player.velocity)
	_pause_left = 0.0
	_reset_detour()
	_reset_path()
	if not was_chasing:
		spotted.emit(player)
		get_tree().call_group("creatures", "hear_alert", self)


## True while it rests after giving up a pursuit (it ignores the players).
func is_resting() -> bool:
	return _rest_left > 0.0


## Seconds of CHASE + SEARCH before it gives up (0 = never) in this mode.
func get_pursuit_limit() -> float:
	return challenge_pursuit_limit if challenge_mode else calm_pursuit_limit


## Counts the pursuit, and gives it up at the limit (never while frenzied).
func _update_pursuit(delta: float) -> void:
	_rest_left = maxf(_rest_left - delta, 0.0)
	if state == State.CHASE or state == State.SEARCH:
		_pursuit_time += delta
		var limit: float = get_pursuit_limit()
		if limit > 0.0 and _pursuit_time >= limit and not is_frenzied:
			_give_up()
	elif state == State.WANDER:
		_pursuit_time = maxf(_pursuit_time - delta * pursuit_recovery_rate, 0.0)


## Breaks off the pursuit: rests for give_up_rest_time, swimming away from
## the nearest player.
func _give_up() -> void:
	forget_players()
	_pursuit_time = 0.0
	_rest_left = give_up_rest_time
	_respot_left = give_up_rest_time
	var nearest: Player = null
	var nearest_distance: float = INF
	for player: Player in Players.all(get_tree()):
		var distance: float = _flat_distance(global_position, player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = player
	if nearest:
		var away: Vector3 = _flat(global_position - nearest.global_position).normalized()
		_set_home(global_position + away * give_up_retreat_distance)
		_pick_wander_target()
	gave_up.emit()


## Drops whatever it was doing (chase, search, investigation) and wanders
## where it is.
func forget_players() -> void:
	_chased = null
	_chase_in_sight = false
	_end_lunge()
	state = State.WANDER
	_pause_left = 0.0
	_reset_detour()
	_set_home(global_position)
	_reset_path()
	_pick_wander_target()


## Lost sight: go to where the player was heading and SEARCH there.
func _lose_track() -> void:
	var last_known: Vector3 = _last_seen + _last_seen_velocity * search_lead_time
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
	_set_home(global_position)
	_respot_left = respot_cooldown
	_reset_path()
	_pick_wander_target()


## Frenzy: chase the nearest player it may chase (switching when another one
## gets closer).
func _update_frenzy() -> void:
	var best: Player = null
	var best_distance: float = INF
	for player: Player in Players.all(get_tree()):
		if not _can_chase(player):
			continue
		var distance: float = _flat_distance(global_position, player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	if best and (state != State.CHASE or _chased != best):
		_spot(best)


func _can_chase(player: Player) -> bool:
	return not player.health.is_downed and not _is_player_safe(player)


func _look_for_players(delta: float) -> void:
	_respot_left = maxf(_respot_left - delta, 0.0)
	_spot_timer -= delta
	if state == State.CHASE or is_resting() or _respot_left > 0.0 or _spot_timer > 0.0:
		return
	_spot_timer = spot_check_interval
	# Spot the nearest player that is close, in line of sight and not downed.
	var best: Player = null
	var best_distance: float = spot_distance
	for player: Player in Players.all(get_tree()):
		var distance: float = _flat_distance(global_position, player.global_position)
		if distance > best_distance or not _can_chase(player):
			continue
		if _has_line_of_sight(global_position, player.global_position):
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
			_last_seen = _flat(_chased.global_position)
			_last_seen_velocity = _flat(_chased.velocity)
	if is_frenzied:
		# It knows where the player is, even around corners.
		_chase_left = chase_memory
	_chase_left -= delta
	if _chase_left <= 0.0:
		_lose_track()
		return
	target = _flat(_chased.global_position)
	_pulse_origin = target


func _update_search(delta: float) -> void:
	if state != State.SEARCH or not _search_arrived:
		return
	_search_left -= delta
	if _search_left <= 0.0:
		_end_search()


## True if the player is within max_distance and no rock is in between.
func _can_see(player: Player, max_distance: float) -> bool:
	if _flat_distance(global_position, player.global_position) > max_distance:
		return false
	return _has_line_of_sight(global_position, player.global_position)


## No rock between two floor points (checked at sight_height).
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var lift := Vector3(0.0, sight_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(_flat(from) + lift, _flat(to) + lift, wall_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Lunge --------------------------------------------------------------------

## Runs the lunge phases. Returns true while the lunge controls the movement.
func _update_lunge(delta: float) -> bool:
	_lunge_cooldown_left = maxf(_lunge_cooldown_left - delta, 0.0)
	if lunge_phase == Lunge.NONE:
		if not _can_start_lunge():
			return false
		lunge_phase = Lunge.WIND_UP
		lunges_started += 1
		_lunge_left = lunge_wind_up
		lunge_started.emit()
	_lunge_left -= delta
	match lunge_phase:
		Lunge.WIND_UP:
			if state != State.CHASE or not is_instance_valid(_chased):
				_end_lunge()
				return false
			# Coil: nearly stop and keep turning towards the prey.
			_lunge_dir = _flat(_chased.global_position - global_position).normalized()
			var coil: Vector3 = _lunge_dir * get_chase_speed() * lunge_wind_up_speed_ratio * _view_scale(_lunge_dir)
			velocity = velocity.lerp(coil, 1.0 - exp(-steering * 2.0 * delta))
			if _lunge_left <= 0.0:
				lunge_phase = Lunge.BURST
				_lunge_left = lunge_time
				velocity = _lunge_dir * lunge_speed * _view_scale(_lunge_dir)
				_hurt_overlapping_players()
		Lunge.BURST:
			velocity = _lunge_dir * lunge_speed * _view_scale(_lunge_dir)
			if _lunge_left <= 0.0:
				lunge_phase = Lunge.RECOVER
				_lunge_left = lunge_recovery
		Lunge.RECOVER:
			var drift: Vector3 = _lunge_dir * get_chase_speed() * lunge_recovery_speed_ratio * _view_scale(_lunge_dir)
			velocity = velocity.lerp(drift, 1.0 - exp(-steering * delta))
			if _lunge_left <= 0.0:
				_end_lunge()
	return true


func _can_start_lunge() -> bool:
	if not lunge_enabled or state != State.CHASE or _lunge_cooldown_left > 0.0:
		return false
	if not is_instance_valid(_chased) or not _chase_in_sight:
		return false
	return _flat_distance(global_position, _chased.global_position) <= lunge_range + body_radius


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
	for body: Node3D in _hitbox.get_overlapping_bodies():
		_on_hitbox_body_entered(body)


## Called by the Sonar when a pulse front reaches this creature in line of sight.
func on_sonar_hit(_origin: Vector3) -> void:
	_revealed_left = pulse_reveal_time
	if not unkillable and exposed_finisher_kills:
		_exposed_total = exposed_time + PlayerSkills.team_bonus(get_tree(), "exposed_time_add")
		_exposed_left = _exposed_total
	var mark_time: float = PlayerSkills.team_bonus(get_tree(), "mark_time_add")
	if mark_time > 0.0:
		_marked_total = mark_time
		_marked_left = mark_time
	pinged.emit()


## The player this creature is chasing right now (null when not in CHASE).
func get_chased_player() -> Player:
	if state == State.CHASE and is_instance_valid(_chased):
		return _chased
	return null


func get_state_name() -> String:
	var state_name: String = State.keys()[state]
	if lunge_phase != Lunge.NONE:
		state_name += " +" + String(Lunge.keys()[lunge_phase])
	if _detour_left > 0.0:
		state_name += " +DETOUR"
	if is_resting():
		state_name += " +RESTING"
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


## Speed while chasing (and while rushing to the last seen position). The
## players are leashed together, so a pair flees at the slower one's speed:
## the chase is measured against that (else it would outrun the Echo held back
## by the Guardian).
func get_chase_speed() -> float:
	var player_speed: float = reference_player_speed
	if is_instance_valid(_chased):
		player_speed = _chased.max_speed
		var partner: Player = _chased.get_partner()
		if partner and not partner.health.is_downed:
			player_speed = minf(player_speed, partner.max_speed)
	return player_speed * get_chase_ratio()


func get_current_speed() -> float:
	if state == State.CHASE or (state == State.SEARCH and not _search_arrived):
		return get_chase_speed()
	return lerpf(min_speed, max_speed, _get_awareness_ratio())


func _physics_process(delta: float) -> void:
	_update_reveal(delta)
	if state != _last_state:
		var old_state: State = _last_state
		_last_state = state
		state_changes += 1
		state_changed.emit(old_state, state)
	_update_pursuit(delta)
	if _stagger_left > 0.0:
		# Staggered: no steering, just slide out the knockback.
		_stagger_left -= delta
		velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-steering * delta))
		_move()
		return
	if is_frenzied:
		_update_frenzy()
	_look_for_players(delta)
	_update_chase(delta)
	_update_search(delta)
	if _update_lunge(delta):
		_move()
		return

	var desired: Vector3 = Vector3.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
	elif state != State.CHASE and (_flat_distance(global_position, target) <= arrive_distance or _is_path_finished() or _target_behind_safe_zone()):
		_on_target_reached()
	else:
		var direction: Vector3 = _steer_direction(delta)
		desired = direction * get_current_speed() * _view_scale(direction)

	desired = _steer_around_safe_zones(desired) + _safe_zone_push()
	_zone_time = _zone_time + delta if _steering_around_zone else 0.0
	if _zone_time >= safe_zone_give_up_time and state != State.CHASE:
		_zone_time = 0.0
		_on_target_reached()
	velocity = velocity.lerp(desired, 1.0 - exp(-steering * delta))
	_move()

	if get_slide_collision_count() > 0:
		_last_wall_normal = _flat(get_slide_collision(0).get_normal()).normalized()
		if _steering_around_zone:
			# This way round the zone runs into rock: try the other side.
			_zone_side = -_zone_side
		if not _path.is_empty():
			# Following the navigation mesh: only give up after a long contact.
			_on_blocked_on_path(delta)
		elif state == State.WANDER:
			# Wandering without a path: just pick another spot.
			_pick_wander_target()
		else:
			_on_blocked_while_investigating(delta)


## Moves on the floor plane only.
func _move() -> void:
	FloorMotion.move(self)


func _steer_direction(delta: float) -> Vector3:
	if _detour_left > 0.0:
		_detour_left -= delta
		return _detour_dir
	return _flat(_next_path_point(delta) - global_position).normalized()


# --- Pathing (navigation mesh baked from the floor plans) ----------------------

## The next point to steer to: along the navigation path to target, or target
## itself when there is no path (navigation off or not ready yet).
func _next_path_point(delta: float) -> Vector3:
	if not use_navigation:
		return target
	_path_refresh_left -= delta
	if _path_refresh_left <= 0.0 and (_path.is_empty() or _flat_distance(_path_target, target) > path_retarget_distance):
		_request_path()
	if _path.is_empty():
		return target
	while _path_index < _path.size() - 1 and _flat_distance(global_position, _path[_path_index]) <= path_point_reach:
		_path_index += 1
	return _path[_path_index]


func _request_path() -> void:
	path_requests += 1
	_path_target = target
	_path_refresh_left = path_refresh_time
	var path: PackedVector3Array = NavigationServer3D.map_get_path(get_navigation_map(), global_position, target, true)
	# The mesh lies a little above the floor: the path is used on the floor.
	for i: int in path.size():
		path[i].y = 0.0
	_path = path
	_path_index = 0


## The navigation map for its size: a level that bakes one per size answers
## navigation_map_for(radius) ("level" group); else the world's own map.
## Looked up once.
func get_navigation_map() -> RID:
	if not _navigation_map.is_valid():
		var level: Node = get_tree().get_first_node_in_group("level")
		if level and level.has_method("navigation_map_for"):
			_navigation_map = level.call("navigation_map_for", body_radius)
		else:
			_navigation_map = get_world_3d().navigation_map
	return _navigation_map


## Stuck recovery, step 1: drop the path and ask for a new one now.
func force_repath() -> void:
	_reset_detour()
	_reset_path()
	if use_navigation:
		_request_path()


## Stuck recovery, step 2: move it off the wall (along the last wall normal),
## or onto the nearest point of its navigation mesh, then repath.
func nudge_unstuck() -> void:
	var on_mesh: Vector3 = _flat(NavigationServer3D.map_get_closest_point(get_navigation_map(), global_position))
	if _flat_distance(on_mesh, global_position) > 0.02:
		global_position = on_mesh
	elif _last_wall_normal != Vector3.ZERO:
		global_position += _last_wall_normal * unstick_nudge_distance
	velocity = Vector3.ZERO
	force_repath()


## True when it has reached the end of a path that stops short of the target
## (the target is somewhere it cannot fit): standing there is not being stuck.
func is_at_path_end() -> bool:
	return _is_path_finished()


## The navigation path it follows right now (debug drawing, stuck logs).
func get_path_points() -> PackedVector3Array:
	return _path


func get_path_size() -> int:
	return _path.size()


## The path point it steers to (its target when there is no path).
func get_next_path_point() -> Vector3:
	return _path[_path_index] if _path_index < _path.size() else target


func get_blocked_time() -> float:
	return _blocked_time


func is_staggered() -> bool:
	return _stagger_left > 0.0


## The path ends short of the target (target inside rock): treat as reached.
func _is_path_finished() -> bool:
	if _path.is_empty() or _path_index < _path.size() - 1:
		return false
	return _flat_distance(global_position, _path[_path.size() - 1]) <= path_point_reach


func _reset_path() -> void:
	_path = PackedVector3Array()
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
	var normal: Vector3 = _flat(get_slide_collision(0).get_normal()).normalized()
	var tangent: Vector3 = normal.cross(Vector3.UP)
	var reference: Vector3 = _detour_dir if _detour_dir != Vector3.ZERO else _flat(target - global_position).normalized()
	if tangent.dot(reference) < 0.0:
		tangent = -tangent
	_detour_dir = (tangent + normal * detour_wall_push).normalized()
	_detour_left = detour_time


func _retarget_near_pulse() -> void:
	_retargets += 1
	_reset_detour()
	if _retargets > max_retargets:
		# Give up and wander where it is.
		_set_home(global_position)
		state = State.WANDER
		_pick_wander_target()
		return
	target = _pulse_origin + _random_direction() * retarget_distance
	_reset_path()


func _reset_detour() -> void:
	_detour_dir = Vector3.ZERO
	_detour_left = 0.0
	_blocked_time = 0.0


func _on_target_reached() -> void:
	_reset_detour()
	_reset_path()
	if state == State.SEARCH:
		# Look around the last known position until the search time runs out.
		_search_arrived = true
		_pause_left = search_pause
		target = _search_center + _random_direction() * randf_range(0.3, 1.0) * search_radius
		return
	if state == State.INVESTIGATE:
		# Keep wandering around where the pulse was heard.
		_set_home(target)
		state = State.WANDER
	_pause_left = wander_pause
	_pick_wander_target()


## Hook for subclasses: where it wanders around from now on (a Sentinel keeps
## its post).
func _set_home(at: Vector3) -> void:
	_home = _flat(at)


func _pick_wander_target() -> void:
	target = _home + _random_direction() * randf_range(0.3, 1.0) * wander_radius


# --- Lit corals (safe zones) ---------------------------------------------------
# Corals are found through the "corals" group and read by duck typing
# (is_lit(), safe_radius, is_in_safe_zone(point)) until Coral is ported (Phase B).

## Removes the part of the steering that points into a lit coral's zone when
## it is close to it, so it slides around the zone (no tug-of-war with the push).
func _steer_around_safe_zones(desired: Vector3) -> Vector3:
	_steering_around_zone = false
	for coral: Node3D in _lit_corals():
		var offset: Vector3 = _flat(global_position - coral.global_position)
		if offset.length() > float(coral.get("safe_radius")) + safe_zone_steer_margin or offset == Vector3.ZERO:
			continue
		var outward: Vector3 = offset.normalized()
		var inward: float = desired.dot(outward)
		if inward < 0.0:
			# Keep the speed: slide along the edge instead of pushing in.
			var tangent: Vector3 = outward.cross(Vector3.UP)
			if _zone_side == 0.0:
				_zone_side = 1.0 if desired.dot(tangent) >= 0.0 else -1.0
			var slid: Vector3 = desired - outward * inward
			if slid.dot(tangent * _zone_side) <= 0.0:
				slid = tangent * _zone_side * desired.length()
			desired = slid.normalized() * desired.length()
			_steering_around_zone = true
	if not _steering_around_zone:
		_zone_side = 0.0
	return desired


## Its (non-chase) target lies in a lit coral's zone and it is at that zone's
## edge: as close as it may get, so it counts as arrived.
func _target_behind_safe_zone() -> bool:
	for coral: Node3D in _lit_corals():
		if coral.call("is_in_safe_zone", target) \
				and _flat_distance(global_position, coral.global_position) <= float(coral.get("safe_radius")) + safe_zone_steer_margin:
			return true
	return false


func _safe_zone_push() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for coral: Node3D in _lit_corals():
		if coral.call("is_in_safe_zone", global_position):
			push += _flat(global_position - coral.global_position).normalized() * safe_zone_push
	return push


func _is_player_safe(player: Player) -> bool:
	for coral: Node3D in _lit_corals():
		if coral.call("is_in_safe_zone", player.global_position):
			return true
	return false


func _lit_corals() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Node3D
		if coral and coral.has_method("is_lit") and coral.call("is_lit"):
			result.append(coral)
	return result


## The player closest to this creature (null if there are none).
func get_nearest_player() -> Player:
	return Players.nearest(get_tree(), global_position)


func _update_reveal(delta: float) -> void:
	_revealed_left = maxf(_revealed_left - delta, 0.0)
	_exposed_left = maxf(_exposed_left - delta, 0.0)
	_marked_left = maxf(_marked_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	_was_in_light = is_in_echo_light()
	var moving := Vector3(velocity.x, 0.0, velocity.z)
	if moving.length() > 0.02:
		facing = facing.lerp(moving.normalized(), 1.0 - exp(-8.0 * delta)).normalized()
	sense_ratio = _compute_sense()
	silhouette_ratio = 0.0 if _was_in_light else maxf(_compute_silhouette(delta), sense_ratio)


## The strongest CloseSense on this creature (0 = nobody senses it).
func _compute_sense() -> float:
	if not silhouette_enabled or not hidden_until_pinged:
		return 0.0
	var best: float = 0.0
	for node: Node in get_tree().get_nodes_in_group("close_senses"):
		var sense := node as CloseSense
		if sense:
			best = maxf(best, sense.get_sense_ratio(global_position, body_radius))
	return best


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
		var distance: float = _flat_distance(global_position, player.global_position)
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
		_silhouette_blocked = not _has_line_of_sight(source.global_position, global_position)
	return 0.0 if _silhouette_blocked else best


func _on_hitbox_body_entered(body: Node3D) -> void:
	var player := body as Player
	if _dying or _stagger_left > 0.0:
		return
	if player and _can_hurt(player) and not _is_player_safe(player):
		player.health.take_hit(global_position, self)


## How much faster this direction must be to look as fast as sideways on screen
## (the tilted camera; 1 without one, e.g. in headless tests).
func _view_scale(direction: Vector3) -> float:
	if _camera == null or not is_instance_valid(_camera):
		_camera = SharedCamera.find(get_tree())
	return _camera.speed_scale(direction) if _camera else 1.0


func _random_direction() -> Vector3:
	var angle: float = randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
