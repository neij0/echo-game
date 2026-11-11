class_name DashSkill
extends ActiveSkill
## The Guardian's Dash: the skill button pushes him "speed" px/s in his move
## direction (his facing when standing) for "time" seconds, invulnerable for
## "invulnerable_time"; "cooldown" seconds.

@export_group("Look")
@export var color: Color = Color(0.6, 0.75, 1.0)
@export var energy: float = 1.8
## Fading streaks left behind during the dash.
@export var trail_time: float = 0.3
@export var trail_width: float = 3.0

@export_group("Sound")
@export var dash_sound: String = "sword_whoosh_2"

var dashes: int = 0
var _dash_left: float = 0.0
var _trail_start: Vector2 = Vector2.ZERO
var _trail_age: float = 1.0


func is_in_use() -> bool:
	return _dash_left > 0.0


func _update(delta: float) -> void:
	_dash_left = maxf(_dash_left - delta, 0.0)
	_trail_age += delta
	if player.try_skill_pressed() and is_ready():
		dash()


func dash() -> void:
	_mark_used()
	dashes += 1
	var direction: Vector2 = player.get_move_input()
	direction = direction.normalized() if direction.length() > 0.1 else player.facing
	player.facing = direction
	var duration: float = value("time", 0.16)
	player.burst(direction * value("speed", 900.0), duration)
	player.health.make_invulnerable(value("invulnerable_time", 0.3))
	_dash_left = duration
	_trail_start = player.global_position
	_trail_age = 0.0
	_play(dash_sound, player.global_position)


func _draw() -> void:
	if _trail_age >= trail_time:
		return
	var fade: float = 1.0 - _trail_age / trail_time
	var side: Vector2 = player.facing.orthogonal() * 8.0
	for offset: Vector2 in [Vector2.ZERO, side, -side]:
		draw_line(_trail_start - global_position + offset, offset * 0.5, _hdr(color, energy, 0.5 * fade), trail_width * fade, true)
