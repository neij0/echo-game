class_name Jellyfish
extends AmbientLife
## A slow drifting jellyfish: a soft translucent bell that contracts in a
## calm rhythm (each beat lifts it a little), with trailing tentacles and a
## faint pale glow. Drifts gently away from a player who comes close; a pulse
## makes its glow flare softly for a moment.

@export var bell_radius: float = 13.0
@export var tentacle_count: int = 5
@export var tentacle_length: float = 34.0
## Beats per second, how much a beat squeezes the bell and lifts it.
@export var beat_rate: float = 0.45
@export_range(0.0, 0.5) var beat_squeeze: float = 0.18
@export var beat_lift: float = 10.0
## Slow drift around its spot (pixels / s) within wander_radius.
@export var drift_speed: float = 10.0
@export var wander_radius: float = 140.0
## A player closer than this pushes it away slowly.
@export var shy_radius: float = 110.0
@export var shy_speed: float = 28.0
@export var body_color: Color = Color(0.7, 0.68, 1.0)
@export var glow_energy: float = 1.1
@export_range(0.0, 1.0) var glow_alpha: float = 0.3
@export var flare_time: float = 0.9

var _home := Vector2.ZERO
var _drift := Vector2.ZERO
var _flare_left: float = 0.0
var _beat_phase: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("sonar_targets")
	_home = position
	_beat_phase = randf()
	_drift = Vector2.from_angle(randf() * TAU) * drift_speed


## Called by SonarOverlay when a pulse reaches it.
func on_sonar_hit(_origin: Vector2) -> void:
	_flare_left = flare_time


func _update(delta: float) -> void:
	_beat_phase = fposmod(_beat_phase + delta * beat_rate, 1.0)
	_flare_left = maxf(_flare_left - delta, 0.0)
	# Wander, turning back towards home when too far.
	_drift = _drift.rotated(sin(_time * 0.3 + _home.x) * delta * 0.5)
	if position.distance_to(_home) > wander_radius:
		_drift = _drift.lerp(position.direction_to(_home) * drift_speed, clampf(delta, 0.0, 1.0))
	var push := Vector2.ZERO
	var player: Player = nearest_player_within(shy_radius)
	if player:
		push = player.global_position.direction_to(global_position) * shy_speed
	# A beat lifts it; between beats it sinks back a little.
	var lift: float = -beat_lift * beat_rate * TAU * maxf(sin(_beat_phase * TAU), 0.0) * 0.5 + beat_lift * beat_rate * 0.35
	position += (_drift + push + Vector2(0.0, lift)) * delta


func _squeeze() -> float:
	return 1.0 - beat_squeeze * maxf(sin(_beat_phase * TAU), 0.0)


func _is_moving() -> bool:
	# Drawn on the glow layer only.
	return false


func _has_glow() -> bool:
	return true


func _draw_glow(canvas: Node2D) -> void:
	var flare: float = 1.0 + 1.2 * (_flare_left / maxf(flare_time, 0.01))
	var squeeze: float = _squeeze()
	var radii := Vector2(bell_radius * squeeze, bell_radius * (2.0 - squeeze) * 0.75)
	var bell := PackedVector2Array()
	for k: int in 13:
		var angle: float = lerpf(PI, TAU, k / 12.0)
		bell.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	# The dome (convex, closed by a straight bottom), its glowing edge and a
	# soft wavy rim underneath.
	_batch.add_convex(bell, AmbientLife.hdr(body_color, glow_energy, glow_alpha * 0.35 * flare))
	_batch.add_polyline(bell, AmbientLife.hdr(body_color, glow_energy, glow_alpha * flare), 1.2)
	var rim := PackedVector2Array()
	for k: int in 9:
		var t: float = float(k) / 8.0
		rim.append(Vector2(lerpf(radii.x, -radii.x, t), 2.0 * sin(t * PI * 4.0 + _time * 3.0)))
	_batch.add_polyline(rim, AmbientLife.hdr(body_color, glow_energy, glow_alpha * 0.6 * flare), 1.0)
	# Tentacles trailing below, swaying.
	for i: int in tentacle_count:
		var x: float = lerpf(-radii.x * 0.7, radii.x * 0.7, float(i) / maxf(tentacle_count - 1, 1))
		var line := PackedVector2Array()
		for k: int in 7:
			var t: float = k / 6.0
			line.append(Vector2(x + sin(_time * 1.6 + i * 1.1 + t * 3.0) * 4.0 * t, t * tentacle_length * (0.7 + 0.3 * squeeze)))
		_batch.add_polyline(line, AmbientLife.hdr(body_color, glow_energy, glow_alpha * 0.5 * flare), 1.0)
	_batch.draw(canvas)
