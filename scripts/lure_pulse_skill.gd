class_name LurePulseSkill
extends ActiveSkill
## The Echo's Lure Pulse: throws a small decoy echo (up to "range" units,
## stopped by rock). Where it lands it pings "pings" times, "ping_interval" s
## apart: every creature within "noise_radius" that is not chasing comes to
## INVESTIGATE it. Costs "cost" of a full pressure meter; "cooldown" seconds.
## It reveals nothing (no sonar, no Exposed). Bosses in the "decoy_listeners"
## group hear each ping too (hear_decoy: the Angler charges at it).
## Aiming:
## - gamepad: the skill button throws towards the right stick (independent of
##   moving); stick neutral = the move direction, else the facing;
## - keyboard: hold the skill button: she stops, the move keys aim; release
##   to throw.
## While aiming a dashed line and a target circle on the floor show the
## landing point.

@export_flags_3d_physics var wall_mask: int = 1
## The decoy stops this far in front of a rock it would hit (units).
@export var wall_margin: float = 0.48
## Height of the ray that looks for rock.
@export var ray_height: float = 0.6

@export_group("Look")
@export var color: Color = Color(0.45, 0.95, 1.0)
@export var orb_energy: float = 3.0
@export var orb_radius: float = 0.12
## Height of the throw's arc at its middle.
@export var arc_height: float = 0.7
## Each ping: a ring growing to ring_radius over ring_time.
@export var ring_radius: float = 1.4
@export var ring_time: float = 0.6
@export var ring_width: float = 0.05

@export_group("Aim Indicator")
@export_range(0.0, 1.0) var aim_alpha: float = 0.12
## Length of a dash and of the gap after it (units).
@export var aim_dash: float = 0.2
@export var aim_width: float = 0.04
@export var target_radius: float = 0.32

@export_group("Sound")
## AudioDirector sound names: the throw and each ping at the decoy.
@export var throw_sound: String = "sword_whoosh_1"
@export var ping_sound: String = "pulse_distress"

## World position of the decoy, while it flies or pings.
var decoy_position: Vector3 = Vector3.ZERO
## Keyboard: true while the skill button is held to aim.
var is_key_aiming: bool = false
## The direction the keyboard aim points to (on the floor).
var key_aim_direction: Vector3 = Vector3.RIGHT
var _from: Vector3 = Vector3.ZERO
var _flight_left: float = 0.0
var _pings_left: int = 0
var _next_ping_left: float = 0.0
## Ages of the rings still drawn (seconds).
var _ring_ages: PackedFloat32Array = PackedFloat32Array()
var _lines: GlowLines


func _ready() -> void:
	super()
	_lines = GlowLines.new()
	_lines.energy = orb_energy
	add_child(_lines)


func is_in_use() -> bool:
	return is_key_aiming or _flight_left > 0.0 or _pings_left > 0


## True while the aim indicator shows (keyboard hold, or the right stick pushed).
func is_aiming() -> bool:
	if is_key_aiming:
		return true
	return player.uses_gamepad and is_ready() and player.get_stick_aim() != Vector3.ZERO


## The direction a throw would go right now.
func get_throw_direction() -> Vector3:
	return key_aim_direction if is_key_aiming else player.get_aim_direction()


func _update(delta: float) -> void:
	if player.uses_gamepad:
		_cancel_key_aim()
		if player.try_skill_pressed() and is_ready():
			throw_decoy(player.get_aim_direction())
	else:
		_update_key_aim()
	if _flight_left > 0.0:
		_flight_left -= delta
		if _flight_left <= 0.0:
			_next_ping_left = 0.0
	elif _pings_left > 0:
		_next_ping_left -= delta
		if _next_ping_left <= 0.0:
			_ping()
	for i: int in range(_ring_ages.size() - 1, -1, -1):
		_ring_ages[i] += delta
		if _ring_ages[i] >= ring_time:
			_ring_ages.remove_at(i)
	_draw_marks()


## Keyboard: hold = stand still and aim with the move keys, release = throw.
func _update_key_aim() -> void:
	if not is_key_aiming:
		if player.try_skill_pressed() and is_ready():
			is_key_aiming = true
			key_aim_direction = player.facing
			player.move_locked = true
		return
	if player.health.is_downed or player.is_reviving():
		_cancel_key_aim()
		return
	var keys: Vector3 = player.get_move_direction()
	if keys.length() > 0.1:
		key_aim_direction = keys.normalized()
	if not player.is_skill_held():
		var direction: Vector3 = key_aim_direction
		_cancel_key_aim()
		throw_decoy(direction)


func _cancel_key_aim() -> void:
	if is_key_aiming:
		is_key_aiming = false
		player.move_locked = false


func _exit_tree() -> void:
	if player:
		player.move_locked = false


## Where a throw in this direction would land on the floor (rock stops it).
func get_landing_point(direction: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	var start: Vector3 = player.global_position
	var end: Vector3 = start + flat * value("range", 7.0)
	var up := Vector3(0.0, ray_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(start + up, end + up, wall_mask)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return end
	var reached: float = Creature._flat_distance(start, hit["position"] as Vector3)
	return start + flat * maxf(reached - wall_margin, 0.0)


func throw_decoy(direction: Vector3) -> void:
	_mark_used()
	_from = player.global_position
	decoy_position = get_landing_point(direction)
	_flight_left = maxf(value("travel_time", 0.35), 0.01)
	_pings_left = maxi(roundi(value("pings", 2.0)), 1)
	player.pressure.spend_ratio(value("cost", 0.02))
	_play(throw_sound, player.global_position)


func _ping() -> void:
	_pings_left -= 1
	_next_ping_left = value("ping_interval", 1.2)
	_ring_ages.append(0.0)
	_play(ping_sound, decoy_position)
	get_tree().call_group("creatures", "hear_noise", decoy_position, value("noise_radius", 10.0))
	# Bosses that can be baited (the Angler charges at the decoy).
	get_tree().call_group("decoy_listeners", "hear_decoy", decoy_position, value("noise_radius", 10.0))


func _draw_marks() -> void:
	_lines.clear()
	if is_aiming():
		var from: Vector3 = player.get_global_transform_interpolated().origin
		var landing: Vector3 = get_landing_point(get_throw_direction())
		var aim_color := Color(color, aim_alpha)
		var length: float = Creature._flat_distance(from, landing)
		var along: Vector3 = (landing - from).normalized() if length > 0.001 else Vector3.RIGHT
		var at: float = 0.0
		while at < length:
			_lines.add_polyline(PackedVector3Array([from + along * at, from + along * minf(at + aim_dash, length)]), aim_width, aim_color)
			at += aim_dash * 2.0
		_lines.add_ring(landing, target_radius, aim_width * 1.5, aim_color)
		_lines.add_disc(landing, aim_width * 1.5, aim_color)
	if _flight_left > 0.0:
		var t: float = 1.0 - _flight_left / maxf(value("travel_time", 0.35), 0.01)
		# A low arc from the Echo to the landing point.
		_lines.add_disc(_from.lerp(decoy_position, t), orb_radius, Color(color, 1.0), 0.3 + sin(t * PI) * arc_height)
	elif _pings_left > 0:
		_lines.add_disc(decoy_position, orb_radius * 0.8, Color(color, 0.8), 0.2)
	for age: float in _ring_ages:
		var t: float = age / ring_time
		_lines.add_ring(decoy_position, ring_radius * t, ring_width, Color(color, 1.0 - t))
	_lines.commit()
