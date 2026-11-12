class_name Sentinel
extends Creature
## A creature that guards an Echo Shard. It keeps to its post (the spot it
## spawned on, next to the shard): it wanders only inside guard_radius,
## investigates noises (never further than guard_radius from the post), and
## chases a player only while that player is inside leash_radius of the post.
## Beyond that it gives up and swims back (the normal navigation). Tougher
## than a basic creature, so the intended answers are: kill it together (the
## Echo's pulse Exposes it, the Guardian's finisher kills it), sneak past it,
## or lure it away from the shard. Looks different (a crest of spines,
## CreatureBody.crest_spines, and pale cold eyes) and, when a pulse reveals it,
## shows a faint dashed ring of the area it guards on the floor.
## The collapse escape (frenzy) ignores the post: then it hunts like any other.

@export_group("Guard")
## It wanders and investigates only this far from its post (units).
@export var calm_guard_radius: float = 5.2
@export var challenge_guard_radius: float = 6.0
## It chases a player only while the player is this close to its post (units).
@export var calm_leash_radius: float = 10.4
@export var challenge_leash_radius: float = 12.4
## Health per mode (a basic creature has 8).
@export var calm_max_health: int = 12
@export var challenge_max_health: int = 16

@export_group("Guard Ring")
## After a pulse reveals it: a faint dashed ring round its post.
@export var ring_color: Color = Color(0.75, 0.7, 1.0)
@export var ring_energy: float = 1.4
@export_range(0.0, 1.0) var ring_alpha: float = 0.3
@export var ring_width: float = 0.04
@export var ring_dashes: int = 28
## Seconds the ring stays after a pulse (it fades over the last third).
@export var ring_show_time: float = 3.0

var post: Vector3
var _ring_left: float = 0.0
var _ring: GlowLines


func _ready() -> void:
	super()
	post = _flat(global_position)
	_ring = GlowLines.new()
	_ring.name = "GuardRing"
	_ring.energy = ring_energy
	_ring.top_level = true
	add_child(_ring)


func set_challenge_mode(enabled: bool) -> void:
	super(enabled)
	# Only at the start (full health): the mode is set when the level is built.
	if health == max_health:
		max_health = challenge_max_health if enabled else calm_max_health
		health = max_health


func get_guard_radius() -> float:
	return challenge_guard_radius if challenge_mode else calm_guard_radius


func get_leash_radius() -> float:
	return challenge_leash_radius if challenge_mode else calm_leash_radius


func _can_chase(player: Player) -> bool:
	if not super(player):
		return false
	return is_frenzied or _flat_distance(player.global_position, post) <= get_leash_radius()


func _investigate(origin: Vector3) -> void:
	# Goes towards the noise, but only to the edge of its guard area.
	super(_clamp_to_guard(origin) if not is_frenzied else origin)


func _lose_track() -> void:
	super()
	if is_frenzied:
		return
	# Search only inside its guard area, then wander back to the post.
	_search_center = _clamp_to_guard(_search_center)
	target = _search_center
	_pulse_origin = _search_center


func _set_home(_at: Vector3) -> void:
	_home = post


func _pick_wander_target() -> void:
	_home = post
	var angle: float = randf() * TAU
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.2, 1.0) * minf(wander_radius, get_guard_radius())
	target = post + offset


func _clamp_to_guard(point: Vector3) -> Vector3:
	var offset: Vector3 = _flat(point) - post
	return post + offset.limit_length(get_guard_radius())


func on_sonar_hit(origin: Vector3) -> void:
	super(origin)
	_ring_left = ring_show_time


func _process(delta: float) -> void:
	_ring_left = maxf(_ring_left - delta, 0.0)
	_ring.clear()
	if _ring_left > 0.0 and not is_dying() and not is_frenzied:
		var fade: float = clampf(_ring_left / (ring_show_time / 3.0), 0.0, 1.0)
		var color := Color(ring_color, ring_alpha * fade)
		var step: float = TAU / maxf(ring_dashes, 1)
		for i: int in ring_dashes:
			var start: float = i * step
			_ring.add_arc(post, get_guard_radius(), start, start + step * 0.5, ring_width, color)
	_ring.commit()


## The guard ring is showing (tests).
func is_ring_showing() -> bool:
	return _ring_left > 0.0
