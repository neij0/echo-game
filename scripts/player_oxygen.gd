class_name PlayerOxygen
extends Node
## The diver's oxygen tank: drains steadily, and every sonar pulse costs air
## (the sonar is powered by the suit). Refilled by oxygen stations. Plays a
## repeating alarm while low; at zero the diver dies (PlayerHealth).

signal low_changed(is_low: bool)

@export var health: PlayerHealth
## The diver whose pulses cost oxygen.
@export var player: Player
@export var max_oxygen: float = 100.0
## Seconds a full tank lasts without pulsing. 180 = 3 minutes: together with
## the pulse cost, a careful run needs at least 2 of the 3 stations.
@export var full_tank_seconds: float = 180.0
## 0-1: share of a full tank each sonar pulse costs.
@export_range(0.0, 1.0) var pulse_cost_ratio: float = 0.03
## 0-1: below this the low-oxygen warning (HUD + alarm) is on.
@export_range(0.0, 1.0) var low_threshold: float = 0.25

@export_group("Alarm")
@export var alarm_stream: AudioStream
@export var alarm_volume_db: float = -8.0
## Seconds between alarm beeps at low_threshold...
@export var alarm_interval: float = 2.5
## ...and when the tank is almost empty.
@export var alarm_interval_empty: float = 0.9

var oxygen: float = 0.0
var _is_low: bool = false
var _alarm_timer: float = 0.0
var _alarm_player: AudioStreamPlayer


func _ready() -> void:
	oxygen = max_oxygen
	_alarm_player = AudioStreamPlayer.new()
	_alarm_player.stream = alarm_stream
	_alarm_player.volume_db = alarm_volume_db
	add_child(_alarm_player)
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)


func _process(delta: float) -> void:
	if health and health.is_dead:
		return
	oxygen = maxf(oxygen - max_oxygen / full_tank_seconds * delta, 0.0)
	_update_low()
	if _is_low:
		_update_alarm(delta)
	if oxygen <= 0.0 and health:
		health.kill(PlayerHealth.Cause.OXYGEN)


func get_ratio() -> float:
	return oxygen / max_oxygen


func is_low() -> bool:
	return _is_low


func _on_pulse_emitted(_origin: Vector2) -> void:
	oxygen = maxf(oxygen - max_oxygen * pulse_cost_ratio, 0.0)
	_update_low()


func refill() -> void:
	oxygen = max_oxygen
	_update_low()


func _update_low() -> void:
	var low: bool = get_ratio() < low_threshold
	if low == _is_low:
		return
	_is_low = low
	_alarm_timer = 0.0
	low_changed.emit(_is_low)


func _update_alarm(delta: float) -> void:
	_alarm_timer -= delta
	if _alarm_timer > 0.0:
		return
	if alarm_stream:
		_alarm_player.play()
	# Beeps get faster as the tank empties.
	_alarm_timer = lerpf(alarm_interval_empty, alarm_interval, get_ratio() / low_threshold)
