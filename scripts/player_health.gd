class_name PlayerHealth
extends Node
## Decides what happens when a creature touches the player. With grace on, the
## first touch only knocks the player back and gives a short invulnerability; a
## second touch within second_hit_window kills. With grace off, any touch kills.

## Emitted on a non-lethal hit (used for the red screen-edge flash).
signal hurt
signal died

@export var player: Player
## Off = the first touch kills (the old behaviour).
@export var grace_enabled: bool = true
@export var invulnerable_time: float = 1.5
## A second touch within this many seconds of the first one kills.
@export var second_hit_window: float = 5.0
## Speed of the knockback push away from the creature.
@export var knockback_speed: float = 650.0

var _invulnerable_left: float = 0.0
var _window_left: float = 0.0


func _process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_window_left = maxf(_window_left - delta, 0.0)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func take_hit(from_position: Vector2) -> void:
	if is_invulnerable():
		return
	if not grace_enabled or _window_left > 0.0:
		died.emit()
		get_tree().reload_current_scene.call_deferred()
		return
	_invulnerable_left = invulnerable_time
	_window_left = second_hit_window
	if player:
		player.knock_back(from_position.direction_to(player.global_position) * knockback_speed)
	hurt.emit()
