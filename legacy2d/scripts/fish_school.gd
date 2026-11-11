class_name FishSchool
extends AmbientLife
## A small school of tiny glowing fish (soft cyan dashes) circling slowly
## around its spot. When a player comes near, or a pulse reaches it, the fish
## dart away from it and spread, then calm down and gather again.

@export var fish_count: int = 9
## The school circles its spot at this distance, at this speed (pixels / s).
@export var roam_radius: float = 110.0
@export var roam_speed: float = 26.0
## How far the fish keep from the school's middle, and how fast they follow it.
@export var spread: float = 26.0
@export var follow_speed: float = 60.0
## A player this close scatters them; a pulse whose origin is this close too.
@export var scatter_radius: float = 150.0
@export var pulse_scatter_radius: float = 450.0
@export var scatter_speed: float = 230.0
## Seconds before a scattered school gathers again.
@export var calm_time: float = 3.0
@export var fish_length: float = 7.0
@export var fish_width: float = 2.2
@export var fish_color: Color = Color(0.45, 0.85, 1.0)
@export var glow_energy: float = 1.3
@export_range(0.0, 1.0) var glow_alpha: float = 0.45

var _positions := PackedVector2Array()
var _velocities := PackedVector2Array()
var _phase: float = 0.0
## Time left of the current scatter.
var _scared_left: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("sonar_targets")
	_phase = randf() * TAU
	for i: int in fish_count:
		_positions.append(Vector2.from_angle(randf() * TAU) * randf() * spread)
		_velocities.append(Vector2.ZERO)


## Called by SonarOverlay when a pulse reaches the school.
func on_sonar_hit(origin: Vector2) -> void:
	if origin.distance_to(global_position + _middle()) <= pulse_scatter_radius:
		scatter(origin)


## Darts every fish away from point (global).
func scatter(point: Vector2) -> void:
	if _scared_left <= 0.0:
		for i: int in fish_count:
			var away: Vector2 = (global_position + _positions[i] - point).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			_velocities[i] = away.rotated(randf_range(-0.7, 0.7)) * scatter_speed * randf_range(0.7, 1.1)
	_scared_left = calm_time


func is_scattered() -> bool:
	return _scared_left > 0.0


func _middle() -> Vector2:
	var sum := Vector2.ZERO
	for p: Vector2 in _positions:
		sum += p
	return sum / maxf(_positions.size(), 1.0)


func _update(delta: float) -> void:
	var player: Player = nearest_player_within(scatter_radius + roam_radius)
	if player and player.global_position.distance_to(global_position + _middle()) < scatter_radius:
		scatter(player.global_position)
	_phase += delta * roam_speed / maxf(roam_radius, 1.0)
	var center: Vector2 = Vector2(cos(_phase), sin(_phase) * 0.6) * roam_radius
	_scared_left = maxf(_scared_left - delta, 0.0)
	for i: int in fish_count:
		var target: Vector2 = center + Vector2.from_angle(_phase * 2.0 + i * TAU / fish_count) * spread
		var wanted: Vector2 = (target - _positions[i]).limit_length(1.0) * follow_speed
		if _scared_left > 0.0:
			# Keep darting, slowing down as the fright passes.
			wanted = _velocities[i].normalized() * lerpf(follow_speed, scatter_speed, _scared_left / calm_time)
		_velocities[i] = _velocities[i].lerp(wanted, clampf(delta * 3.0, 0.0, 1.0))
		_positions[i] += _velocities[i] * delta


func _is_moving() -> bool:
	# Drawn on the glow layer only.
	return false


func _has_glow() -> bool:
	return true


func _draw_glow(canvas: Node2D) -> void:
	var color_value: Color = AmbientLife.hdr(fish_color, glow_energy, glow_alpha)
	for i: int in fish_count:
		var heading: Vector2 = _velocities[i].normalized() if _velocities[i].length() > 1.0 else Vector2.RIGHT
		var side: Vector2 = heading.orthogonal() * fish_width * 0.5
		var p: Vector2 = _positions[i]
		var wiggle: Vector2 = side * sin(_time * 14.0 + i) * 0.8
		_batch.add_convex(PackedVector2Array([p + heading * fish_length * 0.5, p + side, p - heading * fish_length * 0.35 + wiggle, p - side]), color_value)
		# A tiny tail.
		var tail: Vector2 = p - heading * fish_length * 0.35 + wiggle
		_batch.add_line(tail, tail - heading * fish_length * 0.3 + side * 1.2, Color(color_value, glow_alpha * 0.6), 1.0)
	_batch.draw(canvas)
