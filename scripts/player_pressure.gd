class_name PlayerPressure
extends Node
## A player's own survival meter for the current world's pressure (Ocean =
## Oxygen, Snow = Cold, Desert = Heat...). It drains steadily, and every Echo
## pulse costs a share of it. Refilled by pressure stations and partly at every
## new level of a stage. Plays a repeating alarm while low; at zero the player is downed
## (PlayerHealth). Does not drain while the player is downed. All
## world-specific values come from the WorldConfig (apply_world).

signal low_changed(is_low: bool)

@export var health: PlayerHealth
## The player whose pulses cost pressure (only the Echo pulses).
@export var player: Player
@export var max_value: float = 100.0

@export_group("Alarm")
@export var alarm_stream: AudioStream
@export var alarm_volume_db: float = -8.0
## Seconds between alarm beeps at the low threshold...
@export var alarm_interval: float = 2.5
## ...and when the meter is almost empty.
@export var alarm_interval_empty: float = 0.9

## Set by the WorldConfig.
var pressure_name: String = "Pressure"
var drain_seconds: float = 180.0
var low_threshold: float = 0.25
var pulse_cost_ratio: float = 0.0
var level_refill_ratio: float = 0.0
## Set by the StageManager: Calm mode makes the meter last longer (> 1).
var drain_multiplier: float = 1.0
## Share of the passive drain that applies right now (set by an active
## LockdownRoom: 0 = paused). Pulses still cost their full share.
var drain_scale: float = 1.0

var value: float = 0.0
var _is_low: bool = false
var _alarm_timer: float = 0.0
var _alarm_player: AudioStreamPlayer


func _ready() -> void:
	add_to_group("world_listeners")
	value = max_value
	_alarm_player = AudioStreamPlayer.new()
	_alarm_player.stream = alarm_stream
	_alarm_player.volume_db = alarm_volume_db
	_alarm_player.bus = &"SFX"
	add_child(_alarm_player)
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	pressure_name = world.pressure_name
	drain_seconds = world.pressure_drain_seconds
	low_threshold = world.pressure_low_threshold
	pulse_cost_ratio = world.pulse_cost_ratio
	level_refill_ratio = world.pressure_level_refill


func _process(delta: float) -> void:
	if health and health.is_downed:
		return
	value = maxf(value - max_value / (drain_seconds * drain_multiplier) * drain_scale * delta, 0.0)
	_update_low()
	if _is_low:
		_update_alarm(delta)
	if value <= 0.0 and health:
		health.down(PlayerHealth.Cause.PRESSURE)


func get_ratio() -> float:
	return value / max_value


func is_low() -> bool:
	return _is_low


func _on_pulse_emitted(_origin: Vector2) -> void:
	value = maxf(value - max_value * pulse_cost_ratio, 0.0)
	_update_low()


func refill() -> void:
	value = max_value
	_update_low()


## Adds a share (0-1) of a full meter, e.g. at the start of a new level.
func add_ratio(ratio: float) -> void:
	value = minf(value + max_value * ratio, max_value)
	_update_low()


## Makes sure the meter is at least this share (0-1) full (used on revive).
func ensure_ratio(ratio: float) -> void:
	value = maxf(value, max_value * ratio)
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
	# Beeps get faster as the meter empties.
	_alarm_timer = lerpf(alarm_interval_empty, alarm_interval, get_ratio() / low_threshold)
