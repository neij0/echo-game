class_name DashSkill
extends ActiveSkill
## The Guardian's Dash: the skill button pushes him "speed" units/s in his move
## direction (his facing when standing) for "time" seconds, invulnerable for
## "invulnerable_time"; "cooldown" seconds.

@export_group("Look")
@export var color: Color = Color(0.6, 0.75, 1.0)
@export var energy: float = 1.8
## Fading streaks left behind during the dash (seconds, units).
@export var trail_time: float = 0.3
@export var trail_width: float = 0.06
@export var trail_spread: float = 0.16

@export_group("Sound")
@export var dash_sound: String = "sword_whoosh_2"

var dashes: int = 0
var _dash_left: float = 0.0
var _trail_start: Vector3 = Vector3.ZERO
var _trail_age: float = 1.0
var _lines: GlowLines


func _ready() -> void:
	super()
	_lines = GlowLines.new()
	_lines.energy = energy
	add_child(_lines)


func is_in_use() -> bool:
	return _dash_left > 0.0


func _update(delta: float) -> void:
	_dash_left = maxf(_dash_left - delta, 0.0)
	_trail_age += delta
	if player.try_skill_pressed() and is_ready():
		dash()
	_draw_marks()


func dash() -> void:
	_mark_used()
	dashes += 1
	var direction: Vector3 = player.get_move_direction()
	direction = direction.normalized() if direction.length() > 0.1 else player.facing
	player.facing = direction
	var duration: float = value("time", 0.16)
	player.burst(direction * value("speed", 18.0), duration)
	player.health.make_invulnerable(value("invulnerable_time", 0.3))
	_dash_left = duration
	_trail_start = player.global_position
	_trail_age = 0.0
	_play(dash_sound, player.global_position)
	# A dash kicks up the sand.
	var trails: SandTrails = SandTrails.find(get_tree())
	if trails:
		trails.throw_puff(player.global_position, 1.2)


func _draw_marks() -> void:
	_lines.clear()
	if _trail_age < trail_time:
		var fade: float = 1.0 - _trail_age / trail_time
		var here: Vector3 = player.get_global_transform_interpolated().origin
		var side: Vector3 = player.facing.cross(Vector3.UP).normalized() * trail_spread
		for offset: Vector3 in [Vector3.ZERO, side, -side]:
			_lines.add_polyline(PackedVector3Array([_trail_start + offset, here + offset * 0.5]), trail_width * fade, Color(color, 0.5 * fade), 0.3)
	_lines.commit()
