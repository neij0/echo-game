class_name AncientLight
extends Node3D
## The goal in the level's exit room. It stays locked (dim, one empty socket
## per Echo Shard round its core) until every shard of the level is collected
## (the level flow calls set_shard_progress). Unlocked, a player standing next
## to it for activation_time seconds wakes it: a big light, an expanding ring
## on the floor and a swelling chord. Emits activated, then the level is
## cleared. The core and sockets are unlit (the darkness does not dim them).

signal activated

## Any player within this distance charges the light (units).
@export var activation_radius: float = 2.2
@export var activation_time: float = 3.0
## How fast the charge drains when nobody is near (seconds of charge per second).
@export var drain_speed: float = 1.5
## Height of the core above the floor (units).
@export var core_height: float = 1.0

@export_group("Idle")
@export var core_color: Color = Color(1.0, 0.95, 0.75)
@export var core_radius: float = 0.3
## HDR energy of the core while waiting (above 1 = it blooms).
@export var idle_energy: float = 2.4
## Slow breathing of the idle glow, cycles per second.
@export var idle_breath_speed: float = 0.3
@export var idle_light_energy: float = 1.2
@export var idle_light_radius: float = 4.4

@export_group("Lock")
## Core brightness while locked, as a share of the normal idle glow.
@export_range(0.0, 1.0) var locked_energy_scale: float = 0.4
## Shard sockets round the core: distance from its middle and size (units).
@export var socket_distance: float = 0.56
@export var socket_radius: float = 0.07
@export var socket_color: Color = Color(0.55, 0.95, 1.0)
@export var socket_energy: float = 4.0
## Opacity of an empty socket.
@export_range(0.0, 1.0) var empty_socket_alpha: float = 0.25
## Seconds of the bright flash when the last shard unlocks it.
@export var unlock_flash_time: float = 0.8

@export_group("Charging")
@export var ring_color: Color = Color(1.0, 0.9, 0.6)
@export var ring_energy: float = 3.0
@export var ring_width: float = 0.06
## Charge ring on the floor round it (units).
@export var ring_radius: float = 0.8

@export_group("Activation")
@export var active_energy: float = 10.0
@export var active_light_energy: float = 4.0
@export var active_light_radius: float = 18.0
## Seconds for the light to grow to full after activation.
@export var bloom_time: float = 1.5
## The expanding ring after activation (units).
@export var burst_radius: float = 28.0
@export var burst_time: float = 2.0
@export var burst_width: float = 0.2
@export var activation_stream: AudioStream
@export var activation_volume_db: float = 0.0

var charge: float = 0.0
var is_active: bool = false
## Shards needed to unlock and shards collected so far (set by the level flow).
var shards_needed: int = 0
var shards_have: int = 0
var _unlock_flash_left: float = 0.0
var _time: float = 0.0
var _active_time: float = 0.0
var _light: OmniLight3D
var _core: MeshInstance3D
var _core_material: StandardMaterial3D
var _sockets: Array[MeshInstance3D] = []
## Holds the sockets; turned to face the camera.
var _socket_ring: Node3D
var _rings: GlowLines
var _audio: AudioStreamPlayer


func _ready() -> void:
	add_to_group("ancient_light")
	add_to_group("level_exit")
	add_to_group("light_sources")
	_light = OmniLight3D.new()
	_light.light_color = core_color
	_light.light_energy = idle_light_energy
	_light.omni_range = idle_light_radius
	_light.shadow_enabled = true
	_light.position.y = core_height
	add_child(_light)

	var sphere := SphereMesh.new()
	sphere.radius = core_radius
	sphere.height = core_radius * 2.0
	_core_material = _unlit(core_color, idle_energy, 1.0)
	_core = MeshInstance3D.new()
	_core.mesh = sphere
	_core.material_override = _core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.position.y = core_height
	add_child(_core)

	_socket_ring = Node3D.new()
	_socket_ring.name = "Sockets"
	_socket_ring.position.y = core_height
	add_child(_socket_ring)

	_rings = GlowLines.new()
	_rings.name = "Rings"
	add_child(_rings)

	_audio = AudioStreamPlayer.new()
	_audio.stream = activation_stream
	_audio.bus = &"SFX"
	_audio.volume_db = activation_volume_db
	add_child(_audio)


func _process(delta: float) -> void:
	_time += delta
	_rings.clear()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		_socket_ring.global_rotation = Vector3(0.0, camera.global_rotation.y, 0.0)
	if is_active:
		_active_time += delta
		var grow: float = clampf(_active_time / bloom_time, 0.0, 1.0)
		_light.light_energy = lerpf(idle_light_energy, active_light_energy, grow)
		_light.omni_range = lerpf(idle_light_radius, active_light_radius, grow)
		_core.scale = Vector3.ONE * (1.0 + grow)
		_set_energy(_core_material, core_color, lerpf(idle_energy, active_energy, grow), 1.0)
		var t: float = clampf(_active_time / burst_time, 0.0, 1.0)
		if t < 1.0:
			_rings.add_ring(global_position, burst_radius * t, burst_width * (1.0 - t) + 0.02, Color(ring_color, 1.0 - t))
		_rings.commit()
		return
	_unlock_flash_left = maxf(_unlock_flash_left - delta, 0.0)
	if is_locked():
		charge = 0.0
	elif _any_player_near():
		charge = minf(charge + delta, activation_time)
	else:
		charge = maxf(charge - drain_speed * delta, 0.0)
	if charge >= activation_time:
		_activate()
	var breath: float = 0.75 + 0.25 * sin(_time * TAU * idle_breath_speed)
	var core_energy: float = idle_energy * breath * (locked_energy_scale if is_locked() else 1.0)
	if _unlock_flash_left > 0.0:
		core_energy += active_energy * (_unlock_flash_left / unlock_flash_time)
	_set_energy(_core_material, core_color, core_energy, 1.0)
	if charge > 0.0:
		var start: float = _screen_up_angle()
		_rings.add_arc(global_position, ring_radius, start, start + TAU * get_charge_ratio(), ring_width, Color(ring_color, 1.0))
	_rings.commit()


## Used by light-attracted creatures (LightHunter): is this point lit by me?
func lights_point(point: Vector3) -> bool:
	var radius: float = idle_light_radius
	if is_active:
		radius = lerpf(idle_light_radius, active_light_radius, clampf(_active_time / bloom_time, 0.0, 1.0))
	return Creature._flat_distance(global_position, point) <= radius


func is_locked() -> bool:
	return shards_have < shards_needed


## Called by the level flow whenever a shard is collected.
func set_shard_progress(have: int, needed: int) -> void:
	var was_locked: bool = is_locked()
	shards_have = have
	shards_needed = needed
	if was_locked and not is_locked():
		_unlock_flash_left = unlock_flash_time
	_light.light_energy = idle_light_energy * (locked_energy_scale if is_locked() else 1.0)
	_build_sockets()


func get_charge_ratio() -> float:
	return charge / activation_time


func _any_player_near() -> bool:
	for player: Player in Players.all(get_tree()):
		if not player.health.is_downed and Creature._flat_distance(player.global_position, global_position) <= activation_radius:
			return true
	return false


func _activate() -> void:
	is_active = true
	_active_time = 0.0
	for socket: MeshInstance3D in _sockets:
		socket.visible = false
	if activation_stream:
		_audio.play()
	activated.emit()


## One socket per shard round the core, upright and facing the camera:
## filled when collected, faint when not.
func _build_sockets() -> void:
	for socket: MeshInstance3D in _sockets:
		socket.queue_free()
	_sockets.clear()
	for i: int in shards_needed:
		var angle: float = -PI * 0.5 + TAU * i / maxf(shards_needed, 1)
		var sphere := SphereMesh.new()
		sphere.radius = socket_radius
		sphere.height = socket_radius * 2.0
		var socket := MeshInstance3D.new()
		socket.mesh = sphere
		var filled: bool = i < shards_have
		socket.material_override = _unlit(socket_color, socket_energy if filled else 1.0, 1.0 if filled else empty_socket_alpha)
		socket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		socket.position = Vector3(cos(angle) * socket_distance, -sin(angle) * socket_distance, 0.0)
		_socket_ring.add_child(socket)
		_sockets.append(socket)


## The floor angle that points up on the screen (away from the camera).
func _screen_up_angle() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return -PI * 0.5
	var away: Vector3 = -camera.global_basis.z
	return atan2(away.z, away.x)


static func _unlit(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_set_energy(material, color, energy, alpha)
	return material


static func _set_energy(material: StandardMaterial3D, color: Color, energy: float, alpha: float) -> void:
	material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
