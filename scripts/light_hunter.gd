class_name LightHunter
extends Creature
## A creature drawn to light. It hunts the Echo (the player whose light reveals)
## and ignores the Guardian unless he hits it. It moves at the full chase speed
## (Creature, per mode) while the Echo stands in a lit area (a lit coral, the
## ancient light) or right after she pulses, and slowly while she stays in the
## dark. Low health, so the Guardian can save her. Sound and other creatures'
## alerts do not interest it.

@export_group("Light Hunter")
## The hunter senses the Echo from this far (through rocks: it follows light).
@export var sense_range: float = 1100.0
## Speed towards the Echo while she stays in the dark, as a share of the
## chase speed (while she is lit or just pulsed it uses the full chase speed).
@export_range(0.0, 1.0) var dark_speed_ratio: float = 0.4
## Seconds of high speed after the Echo pulses (if it is within sense_range).
@export var pulse_frenzy_time: float = 2.5
## Seconds it turns on the Guardian after he hits it.
@export var provoke_time: float = 4.0

var _frenzy_left: float = 0.0
var _provoked_by: Player
var _provoke_left: float = 0.0


func _physics_process(delta: float) -> void:
	_frenzy_left = maxf(_frenzy_left - delta, 0.0)
	_provoke_left = maxf(_provoke_left - delta, 0.0)
	if _provoke_left <= 0.0:
		_provoked_by = null
	super(delta)


## The Echo: the player whose light reveals creatures.
func _find_echo() -> Player:
	for player: Player in Players.all(get_tree()):
		if player.light_reveal_radius > 0.0:
			return player
	return null


func is_echo_lit() -> bool:
	var echo: Player = _find_echo()
	if echo == null:
		return false
	if _frenzy_left > 0.0:
		return true
	for node: Node in get_tree().get_nodes_in_group("light_sources"):
		if node.call("lights_point", echo.global_position):
			return true
	return false


func hear_pulse(_origin: Vector2, player: Player) -> void:
	# Pulses are light to it: only the Echo's own pulses matter, and they make
	# it rush at her.
	if player and player == _find_echo() and global_position.distance_to(player.global_position) <= sense_range:
		_frenzy_left = pulse_frenzy_time


func hear_noise(_origin: Vector2, _radius: float) -> void:
	# Sound does not interest it.
	pass


func hear_alert(_source: Creature) -> void:
	pass


func _look_for_players(_delta: float) -> void:
	var prey: Player = _provoked_by if _provoked_by and _can_chase(_provoked_by) else null
	if prey == null:
		var echo: Player = _find_echo()
		if echo and _can_chase(echo) and global_position.distance_to(echo.global_position) <= sense_range:
			prey = echo
	if prey == null:
		return
	if state != State.CHASE or _chased != prey:
		_spot(prey)
	# Keep the chase alive while the prey is sensed (through rock too).
	_chase_left = chase_memory


func get_current_speed() -> float:
	if state == State.CHASE and _chased and _chased != _provoked_by and not is_echo_lit():
		return get_chase_speed() * dark_speed_ratio
	return super()


func _on_damaged(attacker: Player) -> void:
	if attacker != _find_echo():
		_provoked_by = attacker
		_provoke_left = provoke_time


func _can_hurt(player: Player) -> bool:
	return player == _find_echo() or player == _provoked_by
