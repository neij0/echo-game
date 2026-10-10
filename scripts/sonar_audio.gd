class_name SonarAudio
extends Node
## Sonar sounds: a deep ping on each pulse, and a soft tick when the wave front
## hits rock edges (rate-limited, quieter for far edges).

@export var player: Player
@export var sonar_overlay: SonarOverlay

@export_group("Ping")
@export var ping_stream: AudioStream
@export var ping_volume_db: float = -4.0
## Random pitch variation (+/-) so repeated pings do not sound identical.
@export var ping_pitch_jitter: float = 0.03
## How many pings can ring at once (the echo tail is longer than the cooldown).
@export var ping_polyphony: int = 3

@export_group("Tick")
@export var tick_stream: AudioStream
## Volume of a tick from an edge right next to the pulse origin.
@export var tick_near_db: float = -10.0
## Volume of a tick from an edge at the pulse's max radius.
@export var tick_far_db: float = -28.0
## Minimum seconds between two ticks, so a long wall does not become noise.
@export var tick_min_interval: float = 0.09
@export var tick_pitch_jitter: float = 0.12
@export var tick_polyphony: int = 4

var _ping_player: AudioStreamPlayer
var _tick_player: AudioStreamPlayer
var _tick_cooldown: float = 0.0


func _ready() -> void:
	_ping_player = _make_player(ping_stream, ping_polyphony)
	_tick_player = _make_player(tick_stream, tick_polyphony)
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)
	if sonar_overlay:
		sonar_overlay.edge_hit.connect(_on_edge_hit)


func _process(delta: float) -> void:
	_tick_cooldown = maxf(_tick_cooldown - delta, 0.0)


func _make_player(stream: AudioStream, polyphony: int) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.max_polyphony = polyphony
	add_child(audio)
	return audio


func _on_pulse_emitted(_origin: Vector2) -> void:
	if ping_stream == null:
		return
	_ping_player.volume_db = ping_volume_db
	_ping_player.pitch_scale = 1.0 + randf_range(-ping_pitch_jitter, ping_pitch_jitter)
	_ping_player.play()


func _on_edge_hit(_point: Vector2, distance_ratio: float) -> void:
	if tick_stream == null or _tick_cooldown > 0.0:
		return
	_tick_cooldown = tick_min_interval
	_tick_player.volume_db = lerpf(tick_near_db, tick_far_db, clampf(distance_ratio, 0.0, 1.0))
	_tick_player.pitch_scale = 1.0 + randf_range(-tick_pitch_jitter, tick_pitch_jitter)
	_tick_player.play()
