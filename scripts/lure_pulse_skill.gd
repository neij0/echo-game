class_name LurePulseSkill
extends ActiveSkill
## The Echo's Lure Pulse: the skill button throws a small decoy echo in her
## move direction (up to "range" px, stopped by rock). Where it lands it pings
## "pings" times, "ping_interval" s apart: every creature within "noise_radius"
## that is not chasing comes to INVESTIGATE it. Costs "cost" of a full pressure
## meter; "cooldown" seconds. It reveals nothing (no sonar, no Exposed).

@export_flags_2d_physics var wall_mask: int = 1
## The decoy stops this far in front of a rock it would hit.
@export var wall_margin: float = 24.0

@export_group("Look")
@export var color: Color = Color(0.45, 0.95, 1.0)
@export var orb_energy: float = 3.0
@export var orb_radius: float = 4.0
## Each ping: a ring growing to ring_radius over ring_time.
@export var ring_energy: float = 2.0
@export var ring_radius: float = 70.0
@export var ring_time: float = 0.6
@export var ring_width: float = 2.0

@export_group("Sound")
## AudioDirector sound names: the throw and each ping at the decoy.
@export var throw_sound: String = "sword_whoosh_1"
@export var ping_sound: String = "pulse_distress"

## World position of the decoy, while it flies or pings.
var decoy_position: Vector2 = Vector2.ZERO
var _from: Vector2 = Vector2.ZERO
var _flight_left: float = 0.0
var _pings_left: int = 0
var _next_ping_left: float = 0.0
## Ages of the rings still drawn (seconds).
var _ring_ages: PackedFloat32Array = PackedFloat32Array()


func is_in_use() -> bool:
	return _flight_left > 0.0 or _pings_left > 0


func _update(delta: float) -> void:
	if player.try_skill_pressed() and is_ready():
		throw_decoy()
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


## Where a throw from here would land (move direction, rock stops it).
func get_landing_point() -> Vector2:
	var start: Vector2 = player.global_position
	var direction: Vector2 = player.get_move_input()
	direction = direction.normalized() if direction.length() > 0.1 else player.facing
	var end: Vector2 = start + direction * value("range", 350.0)
	var query := PhysicsRayQueryParameters2D.create(start, end, wall_mask)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return end
	var hit_point: Vector2 = hit["position"]
	return start + direction * maxf(start.distance_to(hit_point) - wall_margin, 0.0)


func throw_decoy() -> void:
	_mark_used()
	_from = player.global_position
	decoy_position = get_landing_point()
	_flight_left = maxf(value("travel_time", 0.35), 0.01)
	_pings_left = maxi(roundi(value("pings", 2.0)), 1)
	player.pressure.spend_ratio(value("cost", 0.02))
	_play(throw_sound, player.global_position)


func _ping() -> void:
	_pings_left -= 1
	_next_ping_left = value("ping_interval", 1.2)
	_ring_ages.append(0.0)
	_play(ping_sound, decoy_position)
	get_tree().call_group("creatures", "hear_noise", decoy_position, value("noise_radius", 500.0))


func _draw() -> void:
	if _flight_left > 0.0:
		var t: float = 1.0 - _flight_left / maxf(value("travel_time", 0.35), 0.01)
		# A low arc from the Echo to the landing point.
		var point: Vector2 = _from.lerp(decoy_position, t) + Vector2(0.0, -sin(t * PI) * 30.0)
		draw_circle(point - global_position, orb_radius, _hdr(color, orb_energy, 1.0))
	elif _pings_left > 0:
		draw_circle(decoy_position - global_position, orb_radius * 0.7, _hdr(color, orb_energy, 0.8))
	for age: float in _ring_ages:
		var t: float = age / ring_time
		draw_arc(decoy_position - global_position, ring_radius * t, 0.0, TAU, 32, _hdr(color, ring_energy, 1.0 - t), ring_width, true)
