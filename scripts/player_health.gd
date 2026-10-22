class_name PlayerHealth
extends Node
## Segmented health, measured in segments (value 0..segment_count). A creature
## touch removes hit_damage segments (per mode), knocks the player back and
## gives a short invulnerability. A segment that is only partly damaged refills
## on its own after partial_regen_delay seconds without damage; fully lost
## segments only come back through partner mending (PartnerMending), Echo
## Shards (StageManager) or a revive. At zero the player is downed: they cannot
## move or act until the partner revives them (ReviveHelper). When every player
## is downed, the StageManager restarts the level (Calm) or the stage (Challenge).

## PRESSURE = the world's survival meter ran out (Oxygen in the Ocean).
enum Cause { CREATURE, PRESSURE }

## Emitted on every creature touch that is not ignored (downing or not).
signal hit_taken
## Emitted on a non-downing hit (used for the red screen-edge flash).
signal hurt
signal downed(cause: Cause)
signal revived
## Emitted whenever the health value changes (damage, regeneration, healing).
signal health_changed(value: float, max_value: float)

## Below this, a segment counts as full / empty (float rounding).
const EPSILON: float = 0.001

@export var player: Player

@export_group("Segments")
@export var segment_count: int = 4
## Segments the player has right after being revived.
@export var revive_segments: float = 1.0
## At or below this many segments the low-health warning plays.
@export var low_health_segments: float = 1.0

@export_group("Damage")
## Segments lost per creature touch (Calm / Challenge). A share of a segment
## leaves it partly damaged, which then refills on its own.
@export var calm_hit_damage: float = 1.0
@export var challenge_hit_damage: float = 1.5
@export var invulnerable_time: float = 1.5
## Speed of the knockback push away from the creature.
@export var knockback_speed: float = 650.0
## Seconds of invulnerability right after being revived.
@export var revive_invulnerable_time: float = 2.0

@export_group("Partial Regeneration")
## Seconds without damage before a partly damaged segment starts refilling.
@export var calm_partial_regen_delay: float = 4.0
@export var challenge_partial_regen_delay: float = 4.0
## Segments per second while the partly damaged segment refills.
@export var partial_regen_speed: float = 0.5

var value: float = 0.0
var is_downed: bool = false
var last_cause: Cause = Cause.CREATURE
var challenge_mode: bool = false
var _invulnerable_left: float = 0.0
var _since_damage: float = 0.0


func _ready() -> void:
	value = float(segment_count)


func _process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_since_damage += delta
	if is_downed or _since_damage < _partial_regen_delay():
		return
	# Only the partly damaged segment refills, up to its own upper edge.
	var partial: float = value - floorf(value + EPSILON)
	if partial > EPSILON:
		var segment_top: float = floorf(value + EPSILON) + 1.0
		_set_value(minf(value + partial_regen_speed * delta, segment_top))


func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func get_max_value() -> float:
	return float(segment_count)


func get_ratio() -> float:
	return value / get_max_value() if segment_count > 0 else 0.0


func is_low() -> bool:
	return not is_downed and value <= low_health_segments + EPSILON


func is_full() -> bool:
	return value >= get_max_value() - EPSILON


## How full one segment is (0-1), index 0 = the first (lowest) segment.
func get_segment_fill(index: int) -> float:
	return clampf(value - float(index), 0.0, 1.0)


func get_hit_damage() -> float:
	return challenge_hit_damage if challenge_mode else calm_hit_damage


func take_hit(from_position: Vector2) -> void:
	if is_downed or is_invulnerable():
		return
	hit_taken.emit()
	_since_damage = 0.0
	_set_value(value - get_hit_damage())
	if value <= EPSILON:
		_set_value(0.0)
		down(Cause.CREATURE)
		return
	_invulnerable_left = invulnerable_time
	if player:
		player.knock_back(from_position.direction_to(player.global_position) * knockback_speed)
	hurt.emit()


## Adds segments (partner mending, Echo Shards). A downed player is not healed:
## only a revive brings them back.
func heal(segments: float) -> void:
	if is_downed:
		return
	_set_value(minf(value + segments, get_max_value()))


## Sets the value directly (stage start, retries), clamped to the segments.
func set_segments(segments: float) -> void:
	_set_value(clampf(segments, 0.0, get_max_value()))


func refill() -> void:
	set_segments(get_max_value())


func down(cause: Cause) -> void:
	if is_downed:
		return
	is_downed = true
	last_cause = cause
	if player:
		player.velocity = Vector2.ZERO
	downed.emit(cause)


func revive() -> void:
	if not is_downed:
		return
	is_downed = false
	_set_value(maxf(value, revive_segments))
	_invulnerable_left = revive_invulnerable_time
	revived.emit()


func _partial_regen_delay() -> float:
	return challenge_partial_regen_delay if challenge_mode else calm_partial_regen_delay


func _set_value(new_value: float) -> void:
	if is_equal_approx(new_value, value):
		return
	value = new_value
	health_changed.emit(value, get_max_value())
