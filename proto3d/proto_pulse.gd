class_name ProtoPulse
extends Node
## The Echo's pulse button: sends a sonar pulse from her position, with the
## 2D game's cooldown.

signal emitted

@export var player: ProtoPlayer
@export var sonar: ProtoSonar
@export var cooldown: float = 3.0

var _left: float = 0.0


func get_cooldown_left() -> float:
	return _left


func _physics_process(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	if Input.is_action_just_pressed(player.input_prefix + "action"):
		try_emit()


func try_emit() -> bool:
	if _left > 0.0:
		return false
	_left = cooldown
	sonar.emit_pulse(player.global_position)
	emitted.emit()
	return true
