class_name PlayerHealth
extends Node
## Decides what happens when a creature touches the player. With grace on, the
## first touch only knocks the player back and gives a short invulnerability; a
## second touch within second_hit_window downs the player. With grace off, any
## touch downs. A downed player cannot move or act until the partner revives
## them (ReviveHelper). RunManager ends the run when every player is downed.

## PRESSURE = the world's survival meter ran out (Oxygen in the Ocean).
enum Cause { CREATURE, PRESSURE }

## Emitted on every creature touch that is not ignored (downing or not).
signal hit_taken
## Emitted on a non-downing hit (used for the red screen-edge flash).
signal hurt
signal downed(cause: Cause)
signal revived

@export var player: Player
## Off = the first touch downs the player.
@export var grace_enabled: bool = true
@export var invulnerable_time: float = 1.5
## A second touch within this many seconds of the first one downs the player.
@export var second_hit_window: float = 5.0
## Speed of the knockback push away from the creature.
@export var knockback_speed: float = 650.0
## Seconds of invulnerability right after being revived.
@export var revive_invulnerable_time: float = 2.0

var is_downed: bool = false
var last_cause: Cause = Cause.CREATURE
var _invulnerable_left: float = 0.0
var _window_left: float = 0.0


func _process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_window_left = maxf(_window_left - delta, 0.0)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func take_hit(from_position: Vector2) -> void:
	if is_downed or is_invulnerable():
		return
	hit_taken.emit()
	if not grace_enabled or _window_left > 0.0:
		down(Cause.CREATURE)
		return
	_invulnerable_left = invulnerable_time
	_window_left = second_hit_window
	if player:
		player.knock_back(from_position.direction_to(player.global_position) * knockback_speed)
	hurt.emit()


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
	_window_left = 0.0
	_invulnerable_left = revive_invulnerable_time
	revived.emit()
