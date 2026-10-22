class_name ReviveHelper
extends Node
## Lets this player revive a downed partner: stand within revive_distance and
## hold the action button for revive_time seconds. Letting go (or stepping away)
## does not lose the progress: it pauses, and only after decay_delay seconds it
## slowly decays. It resets once the partner is up again. Values per mode
## ("mode_listeners" group, set by the StageManager).

signal revived_partner(partner: Player)

@export var player: Player
@export var revive_distance: float = 70.0
@export var revive_time: float = 2.0
## 0-1: pressure meter the revived partner gets at least (so partners downed by
## an empty meter do not go down again immediately).
@export_range(0.0, 1.0) var revive_pressure_ratio: float = 0.2

@export_group("Interrupted")
## Seconds the progress stays paused after letting go, before it decays.
@export var calm_decay_delay: float = 1.0
@export var challenge_decay_delay: float = 1.0
## Share of the full revive (0-1) lost per second while decaying.
@export_range(0.0, 1.0) var calm_decay_per_second: float = 0.2
@export_range(0.0, 1.0) var challenge_decay_per_second: float = 0.2

## Seconds of reviving done so far (0..revive_time).
var progress: float = 0.0
var challenge_mode: bool = false
var _target: Player
var _paused_left: float = 0.0


func _ready() -> void:
	add_to_group("mode_listeners")


## Called (via the "mode_listeners" group) by StageManager.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


## True when a downed partner is within reach (the action button is then used
## for reviving, not for the ability).
func has_target() -> bool:
	return _target != null


func get_progress_ratio() -> float:
	return progress / revive_time


func get_target() -> Player:
	return _target


## True while the progress is waiting or decaying (not being held).
func is_interrupted() -> bool:
	return progress > 0.0 and not _is_reviving_now()


func _process(delta: float) -> void:
	_target = _find_target()
	var partner: Player = player.get_partner()
	if player.health.is_downed or partner == null or not partner.health.is_downed:
		progress = 0.0
		return
	if _is_reviving_now():
		_paused_left = challenge_decay_delay if challenge_mode else calm_decay_delay
		progress += delta
		if progress >= revive_time:
			_finish()
		return
	if _paused_left > 0.0:
		_paused_left -= delta
		return
	var decay: float = challenge_decay_per_second if challenge_mode else calm_decay_per_second
	progress = maxf(progress - decay * revive_time * delta, 0.0)


func _is_reviving_now() -> bool:
	return _target != null and not player.health.is_downed and Input.is_action_pressed(player.input_prefix + "action")


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
	partner.pressure.ensure_ratio(revive_pressure_ratio)
	partner.health.revive()
	revived_partner.emit(partner)
