class_name EchoShard
extends Node2D
## One Echo Shard: a small glowing crystal hidden somewhere in the level. It is
## invisible in the dark until a player comes close (and no rock is in between)
## or a pulse front passes over it, then it glows for a while. Any player who
## is not downed picks it up by touching it. The StageManager counts the
## shards; once all are collected the exit opens (the ancient light, or the
## boss arena's door). The glow is drawn on a child CanvasLayer (unlit), so the
## darkness does not dim it; a small real light lights the rock around it.

signal collected(shard: EchoShard)

## A player this close picks it up.
@export var pickup_radius: float = 44.0

@export_group("Visibility")
## Fades in from this distance to a player...
@export var show_distance: float = 240.0
## ...and is fully visible this close.
@export var full_distance: float = 130.0
## Seconds it stays visible after a pulse front passed over it.
@export var ping_show_time: float = 4.0
## Seconds of the fade at the end of a pulse reveal.
@export var ping_fade_time: float = 1.5
## Seconds between line-of-sight checks to the nearest player.
@export var sight_check_interval: float = 0.15
@export_flags_2d_physics var wall_mask: int = 1

@export_group("Look")
@export var color: Color = Color(0.55, 0.95, 1.0)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 2.4
## Half height of the crystal (pixels); its width is a share of it.
@export var crystal_size: float = 11.0
@export_range(0.1, 1.0) var crystal_width: float = 0.55
## Slow spin (radians per second) and bob (pixels, cycles per second).
@export var spin_speed: float = 0.6
@export var bob_amount: float = 3.0
@export var bob_speed: float = 0.5
## Soft halo around the crystal.
@export var halo_radius: float = 26.0
@export_range(0.0, 1.0) var halo_alpha: float = 0.18
@export var light_radius: float = 110.0
@export var light_energy: float = 0.7

@export_group("Pickup")
@export var pickup_stream: AudioStream
@export var pickup_volume_db: float = -2.0
## Expanding ring after the pickup.
@export var burst_radius: float = 90.0
@export var burst_time: float = 0.6
@export var burst_width: float = 3.0

var is_collected: bool = false
var _time: float = 0.0
var _ping_left: float = 0.0
var _near: float = 0.0
var _sight_check_left: float = 0.0
var _blocked: bool = false
var _burst_left: float = 0.0
var _light: PointLight2D
var _visual: Node2D
var _audio: AudioStreamPlayer2D


func _ready() -> void:
	add_to_group("echo_shards")
	add_to_group("sonar_targets")
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(128, 0.0)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, light_radius)
	_light.color = color
	_light.energy = 0.0
	add_child(_light)

	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_visual = Node2D.new()
	layer.add_child(_visual)
	_visual.draw.connect(_draw_visual)

	_audio = AudioStreamPlayer2D.new()
	_audio.stream = pickup_stream
	_audio.volume_db = pickup_volume_db
	add_child(_audio)


func _physics_process(delta: float) -> void:
	if is_collected:
		return
	var player: Player = _nearest_active_player()
	if player == null:
		_near = 0.0
		return
	var distance: float = global_position.distance_to(player.global_position)
	if distance <= pickup_radius:
		_collect()
		return
	_near = clampf((show_distance - distance) / maxf(show_distance - full_distance, 1.0), 0.0, 1.0)
	if _near > 0.0:
		_sight_check_left -= delta
		if _sight_check_left <= 0.0:
			_sight_check_left = sight_check_interval
			var query := PhysicsRayQueryParameters2D.create(player.global_position, global_position, wall_mask)
			_blocked = not get_world_2d().direct_space_state.intersect_ray(query).is_empty()
		if _blocked:
			_near = 0.0


func _process(delta: float) -> void:
	_time += delta
	_ping_left = maxf(_ping_left - delta, 0.0)
	_visual.global_position = global_position
	if is_collected:
		_burst_left = maxf(_burst_left - delta, 0.0)
		_light.energy = light_energy * (_burst_left / burst_time) * 2.0
		if _burst_left <= 0.0 and not _audio.playing:
			queue_free()
	else:
		_light.energy = light_energy * get_visibility()
	_visual.queue_redraw()


## Called by SonarOverlay when a pulse front reaches it in line of sight.
func on_sonar_hit(_origin: Vector2) -> void:
	if not is_collected:
		_ping_left = ping_show_time


## 0 = hidden, 1 = fully visible (near a player or recently pinged).
func get_visibility() -> float:
	var ping: float = clampf(_ping_left / maxf(ping_fade_time, 0.001), 0.0, 1.0)
	return maxf(_near, ping)


func _nearest_active_player() -> Player:
	var best: Player = null
	var best_distance: float = INF
	for player: Player in Players.all(get_tree()):
		if player.health.is_downed:
			continue
		var distance: float = global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _collect() -> void:
	is_collected = true
	remove_from_group("echo_shards")
	remove_from_group("sonar_targets")
	_burst_left = burst_time
	if pickup_stream:
		_audio.play()
	collected.emit(self)


static func _hdr(base: Color, boost: float, alpha: float) -> Color:
	return Color(base.r * boost, base.g * boost, base.b * boost, alpha)


func _draw_visual() -> void:
	if is_collected:
		var t: float = 1.0 - _burst_left / burst_time
		if t < 1.0:
			_visual.draw_arc(Vector2.ZERO, burst_radius * t, 0.0, TAU, 48, _hdr(color, energy * 1.5, 1.0 - t), burst_width * (1.0 - t) + 1.0, true)
			_visual.draw_circle(Vector2.ZERO, crystal_size * (1.0 - t), _hdr(color, energy * 2.0, 1.0 - t))
		return
	var alpha: float = get_visibility()
	if alpha <= 0.0:
		return
	var offset := Vector2(0.0, sin(_time * TAU * bob_speed) * bob_amount)
	_visual.draw_circle(offset, halo_radius, _hdr(color, 1.0, halo_alpha * alpha))
	# A tall diamond whose width breathes with the spin, like a turning crystal.
	var half_width: float = crystal_size * crystal_width * absf(cos(_time * spin_speed * PI))
	half_width = maxf(half_width, crystal_size * 0.12)
	var points := PackedVector2Array([
		offset + Vector2(0.0, -crystal_size),
		offset + Vector2(half_width, 0.0),
		offset + Vector2(0.0, crystal_size),
		offset + Vector2(-half_width, 0.0),
	])
	_visual.draw_colored_polygon(points, _hdr(color, energy, alpha))
