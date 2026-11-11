class_name PartnerMending
extends Node3D
## Partner mending: while the two players stay close together, neither is
## downed and no creature is chasing either of them (a boss decides itself:
## allows_mending(a, b)), both slowly get lost health back (one segment per
## seconds_per_segment, per mode: "mode_listeners" group). A soft glowing link
## sways between them while it mends, drawn over rock. A soft hum loops while
## it mends, fading with the link. Skills: each player mends at their own
## "mend_rate_mult"; the range uses the larger "mend_distance_mult" of the two.

## Emitted when mending starts / stops (for sounds or effects later).
signal mending_changed(is_mending: bool)

## The players must be at most this far apart (world units, on the floor).
@export var mend_distance: float = 3.0
## Seconds to mend one full segment (Calm / Challenge).
@export var calm_seconds_per_segment: float = 6.0
@export var challenge_seconds_per_segment: float = 10.0

@export_group("Hum")
## AudioDirector sound name of the hum (a loop) and its level at full strength.
@export var hum_sound: String = "player_mending_hum"
@export var hum_volume_db: float = -14.0

@export_group("Link")
@export var link_color: Color = Color(0.55, 1.0, 0.8)
## HDR brightness multiplier of the link's core (above 1.0 = blooms).
@export var link_energy: float = 1.6
@export_range(0.0, 1.0) var link_alpha: float = 0.35
@export var link_width: float = 0.04
## Width and opacity of the soft halo around the core.
@export var halo_width: float = 0.18
@export_range(0.0, 1.0) var halo_alpha: float = 0.08
## Height of the link above the floor (between the bodies' middles).
@export var link_height: float = 0.5
## The link sways sideways like a thread in the current.
@export var sway_amount: float = 0.12
@export var sway_speed: float = 0.7
@export var link_segments: int = 16
## Seconds to fade the link in / out.
@export var fade_time: float = 0.5
## Small motes travelling along the link.
@export var mote_count: int = 3
@export var mote_speed: float = 0.35
@export var mote_radius: float = 0.05
@export var mote_energy: float = 2.5

var is_mending: bool = false
var challenge_mode: bool = false
var _strength: float = 0.0
var _time: float = 0.0
var _a: Player
var _b: Player
var _hum: AudioStreamPlayer
var _halo: GlowLines
var _core: GlowLines
var _motes: GlowLines


func _ready() -> void:
	add_to_group("mode_listeners")
	_halo = _add_lines("Halo", 1.0)
	_core = _add_lines("Core", link_energy)
	_motes = _add_lines("Motes", mote_energy)


## Called (via the "mode_listeners" group) by StageManager.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


func _process(delta: float) -> void:
	_time += delta
	_pick_players()
	var mending: bool = _can_mend()
	if mending != is_mending:
		is_mending = mending
		mending_changed.emit(is_mending)
	if is_mending:
		var rate: float = 1.0 / maxf(_seconds_per_segment(), 0.01)
		_a.health.heal(rate * _skill_multiplier(_a, "mend_rate_mult") * delta)
		_b.health.heal(rate * _skill_multiplier(_b, "mend_rate_mult") * delta)
	var fade_step: float = delta / maxf(fade_time, 0.01)
	_strength = move_toward(_strength, 1.0 if is_mending else 0.0, fade_step)
	_update_hum()
	_draw_link()


func _update_hum() -> void:
	if _hum == null:
		var audio: AudioDirector = AudioDirector.find(get_tree())
		if audio == null:
			return
		# A plain Node parent: the hum is not positional (it is between the two).
		var holder := Node.new()
		add_child(holder)
		_hum = audio.make_loop_player(hum_sound, holder) as AudioStreamPlayer
		if _hum == null:
			return
	if _strength <= 0.0:
		if _hum.playing:
			_hum.stop()
		return
	_hum.volume_db = hum_volume_db + linear_to_db(_strength)
	if not _hum.playing:
		_hum.play()


func is_humming() -> bool:
	return _hum != null and _hum.playing


## The players' distance limit, with the better of their skills.
func get_mend_distance() -> float:
	if _a == null or _b == null:
		_pick_players()
	var best: float = 1.0
	for each: Player in [_a, _b]:
		if each:
			best = maxf(best, _skill_multiplier(each, "mend_distance_mult"))
	return mend_distance * best


static func _skill_multiplier(target: Player, stat: String) -> float:
	var skills: PlayerSkills = PlayerSkills.of(target)
	return skills.get_multiplier(stat) if skills else 1.0


func _seconds_per_segment() -> float:
	return challenge_seconds_per_segment if challenge_mode else calm_seconds_per_segment


func _pick_players() -> void:
	var players: Array[Player] = Players.all(get_tree())
	_a = players[0] if players.size() > 0 else null
	_b = players[1] if players.size() > 1 else null


func _can_mend() -> bool:
	if _a == null or _b == null:
		return false
	if _a.health.is_downed or _b.health.is_downed:
		return false
	# Nothing to mend.
	if _a.health.is_full() and _b.health.is_full():
		return false
	var apart: Vector3 = _a.global_position - _b.global_position
	if Vector2(apart.x, apart.z).length() > get_mend_distance():
		return false
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		# A boss decides itself (open moments and distance).
		if node.has_method("allows_mending"):
			if not node.call("allows_mending", _a, _b):
				return false
			continue
		var creature := node as Creature
		if creature == null:
			continue
		var chased: Player = creature.get_chased_player()
		if chased == _a or chased == _b:
			return false
	return true


func _draw_link() -> void:
	for lines: GlowLines in [_halo, _core, _motes]:
		lines.clear()
	if _strength > 0.0 and _a != null and _b != null:
		var lift := Vector3(0.0, link_height, 0.0)
		var start: Vector3 = _a.get_global_transform_interpolated().origin + lift
		var end: Vector3 = _b.get_global_transform_interpolated().origin + lift
		var along := Vector3(end.x - start.x, 0.0, end.z - start.z)
		var side: Vector3 = along.cross(Vector3.UP).normalized()
		var points := PackedVector3Array()
		var count: int = maxi(link_segments, 2)
		for i: int in count + 1:
			var t: float = float(i) / float(count)
			# Sway is zero at both ends, strongest in the middle.
			var sway: float = sin(t * PI) * sin(_time * TAU * sway_speed + t * PI * 2.0) * sway_amount
			points.append(start.lerp(end, t) + side * sway)
		_halo.add_line_3d(points, halo_width, Color(link_color, halo_alpha * _strength))
		_core.add_line_3d(points, link_width, Color(link_color, link_alpha * _strength))
		for m: int in mote_count:
			var along_link: float = fmod(_time * mote_speed + float(m) / float(maxi(mote_count, 1)), 1.0)
			var index: int = clampi(roundi(along_link * count), 0, count)
			var point: Vector3 = points[index]
			_motes.add_disc(point, mote_radius, Color(link_color, _strength * sin(along_link * PI)), point.y - _motes.floor_height)
	for lines: GlowLines in [_halo, _core, _motes]:
		lines.commit()


func _add_lines(node_name: String, line_energy: float) -> GlowLines:
	var lines := GlowLines.new()
	lines.name = node_name
	lines.energy = line_energy
	add_child(lines)
	return lines
