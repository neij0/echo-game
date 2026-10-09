class_name DepthAwareness
extends Node
## The "Depth Awareness" meter (0-100). Pulses raise it, time slowly lowers it.

signal value_changed(value: float)

@export var max_value: float = 100.0
@export var per_pulse: float = 20.0
@export var decay_per_second: float = 3.0
## Seconds after a pulse before decay starts.
@export var decay_delay: float = 1.5

var value: float = 0.0
var _decay_timer: float = 0.0


func _process(delta: float) -> void:
	if _decay_timer > 0.0:
		_decay_timer -= delta
		return
	if value > 0.0:
		_set_value(value - decay_per_second * delta)


func add_pulse() -> void:
	_set_value(value + per_pulse)
	_decay_timer = decay_delay


## 0.0 = calm, 1.0 = maximum awareness.
func get_ratio() -> float:
	return value / max_value


func _set_value(new_value: float) -> void:
	value = clampf(new_value, 0.0, max_value)
	value_changed.emit(value)
