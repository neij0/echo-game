class_name ReviveHelper
extends Node
## Lets this player revive a downed partner: stand within revive_distance and
## hold the action button for revive_time seconds. Letting go drains progress.

signal revived_partner(partner: Player)

@export var player: Player
@export var revive_distance: float = 70.0
@export var revive_time: float = 2.0
## Progress lost per second while the button is not held (seconds of progress).
@export var drain_speed: float = 2.0
## 0-1: oxygen the revived partner gets at least (so oxygen-downed partners do
## not go down again immediately).
@export_range(0.0, 1.0) var revive_oxygen_ratio: float = 0.2

var progress: float = 0.0
var _target: Player


## True when a downed partner is within reach (the action button is then used
## for reviving, not for the ability).
func has_target() -> bool:
	return _target != null


func get_progress_ratio() -> float:
	return progress / revive_time


func get_target() -> Player:
	return _target


func _process(delta: float) -> void:
	_target = _find_target()
	if _target == null or player.health.is_downed:
		progress = 0.0
		return
	if Input.is_action_pressed(player.input_prefix + "action"):
		progress += delta
		if progress >= revive_time:
			_finish()
	else:
		progress = maxf(progress - drain_speed * delta, 0.0)


func _find_target() -> Player:
	var partner: Player = player.get_partner()
	if partner == null or not partner.health.is_downed:
		return null
	if partner.global_position.distance_to(player.global_position) > revive_distance:
		return null
	return partner


func _finish() -> void:
	var partner: Player = _target
	progress = 0.0
	_target = null
	partner.oxygen.oxygen = maxf(partner.oxygen.oxygen, partner.oxygen.max_oxygen * revive_oxygen_ratio)
	partner.health.revive()
	revived_partner.emit(partner)
