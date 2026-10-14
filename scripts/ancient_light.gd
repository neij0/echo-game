class_name AncientLight
extends Node2D
## The goal in the level's exit room. It stays locked (dim, one empty socket
## per Echo Shard around its core) until every shard of the level is collected
## (the StageManager calls set_shard_progress). Unlocked, a player standing next
## to it for activation_time seconds wakes it: a big light, an expanding ring
## and a swelling chord. Emits activated, then the StageManager clears the level.
## The visuals are drawn on a child CanvasLayer so the darkness does not dim them.

signal activated

## Any player within this distance charges the light.
@export var activation_radius: float = 110.0
@export var activation_time: float = 3.0
## How fast the charge drains when nobody is near (seconds of charge per second).
@export var drain_speed: float = 1.5

@export_group("Idle")
@export var core_color: Color = Color(1.0, 0.95, 0.75)
@export var core_radius: float = 16.0
## HDR multiplier of the core while waiting (above 1.0 = blooms).
@export var idle_energy: float = 1.6
## Slow breathing of the idle glow, cycles per second.
@export var idle_breath_speed: float = 0.3
@export var idle_light_energy: float = 0.5
@export var idle_light_radius: float = 220.0

@export_group("Lock")
## Core brightness while locked, as a share of the normal idle glow.
@export_range(0.0, 1.0) var locked_energy_scale: float = 0.4
## Shard sockets around the core: distance from the centre and dot size.
@export var socket_distance: float = 28.0
@export var socket_radius: float = 3.5
@export var socket_color: Color = Color(0.55, 0.95, 1.0)
@export var socket_energy: float = 2.4
## Opacity of an empty socket (a faint ring).
@export_range(0.0, 1.0) var empty_socket_alpha: float = 0.35
## Seconds of the bright flash when the last shard unlocks it.
@export var unlock_flash_time: float = 0.8

@export_group("Charging")
@export var ring_color: Color = Color(1.0, 0.9, 0.6)
@export var ring_energy: float = 3.0
@export var ring_width: float = 3.0
## Charge ring radius around the core.
@export var ring_radius: float = 40.0

@export_group("Activation")
@export var active_energy: float = 8.0
@export var active_light_energy: float = 3.0
@export var active_light_radius: float = 900.0
## Seconds for the light to grow to full after activation.
@export var bloom_time: float = 1.5
## The expanding ring after activation.
@export var burst_radius: float = 1400.0
@export var burst_time: float = 2.0
@export var burst_width: float = 10.0
@export var activation_stream: AudioStream
@export var activation_volume_db: float = 0.0

var charge: float = 0.0
var is_active: bool = false
## Shards needed to unlock and shards collected so far (set by the StageManager).
var shards_needed: int = 0
var shards_have: int = 0
var _unlock_flash_left: float = 0.0
var _time: float = 0.0
var _active_time: float = 0.0
var _light: PointLight2D
var _visual: Node2D
var _audio: AudioStreamPlayer


func _ready() -> void:
	add_to_group("ancient_light")
	add_to_group("level_exit")
	add_to_group("light_sources")
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(256, 0.0)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, idle_light_radius)
	_light.color = core_color
	_light.energy = idle_light_energy
	add_child(_light)

	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_visual = Node2D.new()
	layer.add_child(_visual)
	_visual.draw.connect(_draw_visual)

	_audio = AudioStreamPlayer.new()
	_audio.stream = activation_stream
	_audio.volume_db = activation_volume_db
	add_child(_audio)


func _process(delta: float) -> void:
	_time += delta
	_visual.global_position = global_position
	if is_active:
		_active_time += delta
		var grow: float = clampf(_active_time / bloom_time, 0.0, 1.0)
		_light.energy = lerpf(idle_light_energy, active_light_energy, grow)
		var radius: float = lerpf(idle_light_radius, active_light_radius, grow)
		_light.texture_scale = LightTextures.scale_for_radius(_light.texture, radius)
	else:
		_unlock_flash_left = maxf(_unlock_flash_left - delta, 0.0)
		if is_locked():
			charge = 0.0
		elif _any_player_near():
			charge = minf(charge + delta, activation_time)
		else:
			charge = maxf(charge - drain_speed * delta, 0.0)
		if charge >= activation_time:
			_activate()
	_visual.queue_redraw()


## Used by light-attracted creatures (LightHunter): is this point lit by me?
func lights_point(point: Vector2) -> bool:
	var radius: float = idle_light_radius
	if is_active:
		radius = lerpf(idle_light_radius, active_light_radius, clampf(_active_time / bloom_time, 0.0, 1.0))
	return global_position.distance_to(point) <= radius


func is_locked() -> bool:
	return shards_have < shards_needed


## Called by the StageManager whenever a shard is collected.
func set_shard_progress(have: int, needed: int) -> void:
	var was_locked: bool = is_locked()
	shards_have = have
	shards_needed = needed
	if was_locked and not is_locked():
		_unlock_flash_left = unlock_flash_time
	_light.energy = idle_light_energy * (locked_energy_scale if is_locked() else 1.0)


func get_charge_ratio() -> float:
	return charge / activation_time


func _any_player_near() -> bool:
	for player: Player in Players.all(get_tree()):
		if not player.health.is_downed and player.global_position.distance_to(global_position) <= activation_radius:
			return true
	return false


func _activate() -> void:
	is_active = true
	_active_time = 0.0
	if activation_stream:
		_audio.play()
	activated.emit()


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw_visual() -> void:
	if is_active:
		var grow: float = clampf(_active_time / bloom_time, 0.0, 1.0)
		_visual.draw_circle(Vector2.ZERO, core_radius * (1.0 + grow), _hdr(core_color, lerpf(idle_energy, active_energy, grow), 1.0))
		var t: float = clampf(_active_time / burst_time, 0.0, 1.0)
		if t < 1.0:
			var burst := _hdr(ring_color, ring_energy, 1.0 - t)
			_visual.draw_arc(Vector2.ZERO, burst_radius * t, 0.0, TAU, 96, burst, burst_width * (1.0 - t) + 1.0, true)
		return

	var breath: float = 0.75 + 0.25 * sin(_time * TAU * idle_breath_speed)
	var core_energy: float = idle_energy * breath * (locked_energy_scale if is_locked() else 1.0)
	if _unlock_flash_left > 0.0:
		core_energy += active_energy * (_unlock_flash_left / unlock_flash_time)
	_visual.draw_circle(Vector2.ZERO, core_radius, _hdr(core_color, core_energy, 1.0))
	# One socket per shard: filled when collected, a faint ring when not.
	for i: int in shards_needed:
		var at: Vector2 = Vector2.from_angle(-PI * 0.5 + TAU * i / shards_needed) * socket_distance
		if i < shards_have:
			_visual.draw_circle(at, socket_radius, _hdr(socket_color, socket_energy, 1.0))
		else:
			_visual.draw_arc(at, socket_radius, 0.0, TAU, 16, _hdr(socket_color, 1.0, empty_socket_alpha), 1.0, true)
	if charge > 0.0:
		var ring := _hdr(ring_color, ring_energy, 1.0)
		_visual.draw_arc(Vector2.ZERO, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * get_charge_ratio(), 64, ring, ring_width, true)
