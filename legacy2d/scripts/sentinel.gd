class_name Sentinel
extends Creature
## A creature that guards an Echo Shard. It keeps to its post (the spot it
## spawned on, next to the shard): it wanders only inside guard_radius, turns
## towards noises and investigates them (never further than guard_radius from
## the post), and chases a player only while that player is inside
## leash_radius of the post. Beyond that it gives up and swims back (the
## normal navigation). Tougher than a basic creature, so the intended answers
## are: kill it together (the Echo's pulse Exposes it, the Guardian's
## finisher kills it), sneak past it, or lure it away from the shard.
## Looks different (a crest of spines and pale cold eyes) and, when a pulse
## reveals it, shows a faint ring of the area it guards.
## The collapse escape (frenzy) ignores the post: then it hunts like any other.

@export_group("Guard")
## It wanders and investigates only this far from its post.
@export var calm_guard_radius: float = 260.0
@export var challenge_guard_radius: float = 300.0
## It chases a player only while the player is this close to its post.
@export var calm_leash_radius: float = 520.0
@export var challenge_leash_radius: float = 620.0
## Health per mode (a basic creature has 8).
@export var calm_max_health: int = 12
@export var challenge_max_health: int = 16

@export_group("Crest")
## Spines standing up around the back of the body (also in the silhouette and
## the sonar echo), so players learn "this one guards".
@export var crest_spines: int = 5
## Spine length compared to body_radius.
@export var crest_length: float = 0.7
## Spread of the crest around the back, in degrees.
@export var crest_spread_degrees: float = 160.0
@export var crest_width: float = 2.0

@export_group("Guard Ring")
## After a pulse reveals it: a faint ring around its post showing what it guards.
@export var ring_color: Color = Color(0.75, 0.7, 1.0)
@export var ring_energy: float = 1.4
@export_range(0.0, 1.0) var ring_alpha: float = 0.22
@export var ring_width: float = 2.0
@export var ring_dashes: int = 28
## Seconds the ring stays after a pulse (it fades over the last third).
@export var ring_show_time: float = 3.0

var post: Vector2
var _ring_left: float = 0.0
var _ring_node: Node2D


func _ready() -> void:
	super()
	post = global_position
	_ring_node = Node2D.new()
	_ring_node.top_level = true
	$EchoLayer.add_child(_ring_node)
	_ring_node.draw.connect(_draw_ring)


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
	return is_frenzied or player.global_position.distance_to(post) <= get_leash_radius()


func _investigate(origin: Vector2) -> void:
	# Turns towards the noise, but goes only to the edge of its guard area.
	_facing = global_position.direction_to(origin) if origin != global_position else _facing
	super(_clamp_to_guard(origin) if not is_frenzied else origin)


func _lose_track() -> void:
	super()
	if is_frenzied:
		return
	# Search only inside its guard area, then wander back to the post.
	_search_center = _clamp_to_guard(_search_center)
	target = _search_center
	_pulse_origin = _search_center


func _set_home(_at: Vector2) -> void:
	_home = post


func _pick_wander_target() -> void:
	_home = post
	var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.2, 1.0) * minf(wander_radius, get_guard_radius())
	target = post + offset


func _clamp_to_guard(point: Vector2) -> Vector2:
	return post + (point - post).limit_length(get_guard_radius())


func on_sonar_hit(origin: Vector2) -> void:
	super(origin)
	_ring_left = ring_show_time


func _process(delta: float) -> void:
	_ring_left = maxf(_ring_left - delta, 0.0)
	if _ring_node:
		_ring_node.queue_redraw()


func draw_shape(canvas: CanvasItem, fill: Color, outline: Color, with_eye: bool) -> void:
	_draw_crest(canvas, outline if outline.a > 0.0 else fill)
	super(canvas, fill, outline, with_eye)


## Spines fanning out behind the body, swaying a little.
func _draw_crest(canvas: CanvasItem, color: Color) -> void:
	var back: float = (-_facing).angle()
	var spread: float = deg_to_rad(crest_spread_degrees)
	for i: int in crest_spines:
		var t: float = float(i) / maxf(crest_spines - 1, 1) - 0.5
		var sway: float = sin(_anim_time * 1.3 + i) * 0.08
		var direction: Vector2 = Vector2.from_angle(back + t * spread + sway)
		var root: Vector2 = direction * body_radius * 0.8
		var length: float = body_radius * crest_length * (1.0 - absf(t) * 0.6)
		canvas.draw_line(root, root + direction * length, color, crest_width, true)


func _draw_ring() -> void:
	if _ring_left <= 0.0 or is_dying() or is_frenzied:
		return
	var fade: float = clampf(_ring_left / (ring_show_time / 3.0), 0.0, 1.0)
	var color := Color(ring_color.r * ring_energy, ring_color.g * ring_energy, ring_color.b * ring_energy, ring_alpha * fade)
	var radius: float = get_guard_radius()
	var step: float = TAU / maxf(ring_dashes, 1)
	for i: int in ring_dashes:
		var start: float = i * step
		_ring_node.draw_arc(post, radius, start, start + step * 0.5, 4, color, ring_width, true)
