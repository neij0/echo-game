class_name EchoShard
extends Node3D
## One Echo Shard: a small glowing crystal hidden somewhere in the level. It is
## invisible in the dark until a player comes close (and no rock is in between)
## or a pulse front passes over it, then it glows for a while. Any player who
## is not downed picks it up by touching it. The level flow counts the shards;
## once all are collected the exit opens (the ancient light, or the boss
## arena's door). The crystal is unlit (the darkness does not dim it) and fades
## with its visibility; a small real light lights the floor and rock round it.

signal collected(shard: EchoShard)

## A player this close picks it up (units).
@export var pickup_radius: float = 0.88

@export_group("Visibility")
## Fades in from this distance to a player...
@export var show_distance: float = 4.8
## ...and is fully visible this close (units).
@export var full_distance: float = 2.6
## Seconds it stays visible after a pulse front passed over it.
@export var ping_show_time: float = 4.0
## Seconds of the fade at the end of a pulse reveal.
@export var ping_fade_time: float = 1.5
## Seconds between line-of-sight checks to the nearest player.
@export var sight_check_interval: float = 0.15
## Height of the line-of-sight ray (rock lower than this does not hide it).
@export var sight_height: float = 0.4
@export_flags_3d_physics var wall_mask: int = 1

@export_group("Look")
@export var color: Color = Color(0.55, 0.95, 1.0)
## HDR brightness (above 1 = it blooms).
@export var energy: float = 4.0
## Half height of the crystal (units); its width is a share of it.
@export var crystal_size: float = 0.22
@export_range(0.1, 1.0) var crystal_width: float = 0.55
## Height of its middle above the floor (units).
@export var float_height: float = 0.7
## Slow spin (radians per second) and bob (units, cycles per second).
@export var spin_speed: float = 1.2
@export var bob_amount: float = 0.06
@export var bob_speed: float = 0.5
@export var light_radius: float = 2.2
@export var light_energy: float = 1.2

@export_group("Hum")
## A faint glassy hum (AudioDirector loop) heard only close by.
@export var hum_sound: String = "world_shard_hum"

@export_group("Pickup")
@export var pickup_stream: AudioStream
@export var pickup_volume_db: float = -2.0
## Expanding ring on the floor after the pickup (units).
@export var burst_radius: float = 1.8
@export var burst_time: float = 0.6
@export var burst_width: float = 0.06

var is_collected: bool = false
var _time: float = 0.0
var _ping_left: float = 0.0
var _near: float = 0.0
var _sight_check_left: float = 0.0
var _blocked: bool = false
var _burst_left: float = 0.0
var _light: OmniLight3D
var _crystal: MeshInstance3D
var _crystal_material: StandardMaterial3D
var _burst: GlowLines
var _audio: AudioStreamPlayer3D
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("echo_shards")
	add_to_group("sonar_targets")
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.0
	_light.omni_range = light_radius
	_light.position.y = float_height
	add_child(_light)

	# A tall diamond: a four-sided double cone.
	var mesh := SphereMesh.new()
	mesh.radius = crystal_size * crystal_width
	mesh.height = crystal_size * 2.0
	mesh.radial_segments = 4
	mesh.rings = 1
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crystal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crystal_material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 0.0)
	_crystal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crystal = MeshInstance3D.new()
	_crystal.mesh = mesh
	_crystal.material_override = _crystal_material
	_crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crystal.position.y = float_height
	add_child(_crystal)

	_burst = GlowLines.new()
	_burst.name = "Burst"
	add_child(_burst)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = pickup_stream
	_audio.volume_db = pickup_volume_db
	_audio.bus = &"SFX"
	add_child(_audio)
	_start_hum.call_deferred()


func _start_hum() -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and not is_collected:
		_hum = audio.make_loop_player(hum_sound, self) as AudioStreamPlayer3D
		if _hum:
			_hum.play()


func _exit_tree() -> void:
	if _hum:
		_hum.stop()


func is_humming() -> bool:
	return _hum != null and _hum.playing


func _physics_process(delta: float) -> void:
	if is_collected:
		return
	var player: Player = _nearest_active_player()
	if player == null:
		_near = 0.0
		return
	var distance: float = Creature._flat_distance(global_position, player.global_position)
	if distance <= pickup_radius:
		collect()
		return
	_near = clampf((show_distance - distance) / maxf(show_distance - full_distance, 0.01), 0.0, 1.0)
	if _near > 0.0:
		_sight_check_left -= delta
		if _sight_check_left <= 0.0:
			_sight_check_left = sight_check_interval
			var lift := Vector3(0.0, sight_height, 0.0)
			var from: Vector3 = Creature._flat(player.global_position) + lift
			var to: Vector3 = Creature._flat(global_position) + lift
			var query := PhysicsRayQueryParameters3D.create(from, to, wall_mask)
			_blocked = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		if _blocked:
			_near = 0.0


func _process(delta: float) -> void:
	_time += delta
	_ping_left = maxf(_ping_left - delta, 0.0)
	_burst.clear()
	if is_collected:
		_burst_left = maxf(_burst_left - delta, 0.0)
		var t: float = 1.0 - _burst_left / maxf(burst_time, 0.01)
		_light.light_energy = light_energy * (1.0 - t) * 2.0
		_crystal.scale = Vector3.ONE * maxf(1.0 - t, 0.01)
		if t < 1.0:
			_burst.add_ring(global_position, burst_radius * t, burst_width * (1.0 - t) + 0.01, Color(color, 1.0 - t))
		_burst.commit()
		if _burst_left <= 0.0 and not _audio.playing:
			queue_free()
		return
	_burst.commit()
	var visibility: float = get_visibility()
	_light.light_energy = light_energy * visibility
	_crystal_material.albedo_color.a = visibility
	_crystal.visible = visibility > 0.0
	_crystal.position.y = float_height + sin(_time * TAU * bob_speed) * bob_amount
	_crystal.rotation.y = _time * spin_speed


## Called by the Sonar when a pulse front reaches it in line of sight.
func on_sonar_hit(_origin: Vector3) -> void:
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
		var distance: float = Creature._flat_distance(global_position, player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## Picked up (by touch; tests call it directly).
func collect() -> void:
	if is_collected:
		return
	is_collected = true
	remove_from_group("echo_shards")
	remove_from_group("sonar_targets")
	_burst_left = burst_time
	_crystal_material.albedo_color.a = 1.0
	_crystal.visible = true
	if _hum:
		_hum.stop()
	if pickup_stream:
		_audio.play()
	collected.emit(self)
