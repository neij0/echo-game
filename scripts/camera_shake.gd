class_name CameraShake
extends Camera2D
## A small, short camera shake (used on each sonar pulse). Shakes via offset, so
## it does not fight the camera's position smoothing.

@export var shake_enabled: bool = true
## Maximum offset in pixels at the start of the shake.
@export var strength: float = 3.0
@export var duration: float = 0.15

var _time_left: float = 0.0


func _ready() -> void:
	var player := get_parent() as Player
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)


func _on_pulse_emitted(_origin: Vector2) -> void:
	shake()


func shake() -> void:
	if shake_enabled:
		_time_left = duration


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	# Quadratic falloff: strongest at the start, settles smoothly.
	var amount: float = strength * pow(_time_left / duration, 2.0)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount
