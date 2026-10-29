class_name ShieldSkill
extends ActiveSkill
## The Guardian's Shield: hold the skill button to raise it in his facing
## direction. Creature touches from the front ("arc_degrees" wide) are blocked
## (no damage, the creature is pushed back "repel_speed" and staggered), also
## for the Echo when she stands behind him (within "protect_distance", on the
## far side from the creature). While held he moves at "speed_scale" and cannot
## swing the sword. No cooldown (hold), so "cooldown" is 0.

@export_group("Look")
@export var color: Color = Color(0.75, 0.85, 1.0)
@export var energy: float = 1.6
@export var block_color: Color = Color(1.0, 0.85, 0.45)
@export var block_energy: float = 3.0
## Seconds the shield glows after a block.
@export var block_flash_time: float = 0.25
@export var radius: float = 30.0
@export var width: float = 3.0
## Seconds to raise / lower it (look only; it blocks as soon as it is held).
@export var raise_time: float = 0.08

@export_group("Sound")
@export var block_sound: String = "sword_impact"

var is_raised: bool = false
var blocks: int = 0
var _raise: float = 0.0
var _flash_left: float = 0.0


func _ready() -> void:
	add_to_group("hit_blockers")


func is_in_use() -> bool:
	return is_raised


func blocks_actions() -> bool:
	return is_raised


func _update(delta: float) -> void:
	is_raised = player.is_skill_held() and not player.is_reviving()
	player.speed_scale = value("speed_scale", 0.55) if is_raised else 1.0
	_raise = move_toward(_raise, 1.0 if is_raised else 0.0, delta / maxf(raise_time, 0.01))
	_flash_left = maxf(_flash_left - delta, 0.0)


func _exit_tree() -> void:
	if player:
		player.speed_scale = 1.0


## Called by PlayerHealth.take_hit on every player ("hit_blockers" group).
func blocks_hit(target: Player, from_position: Vector2, source: Node2D) -> bool:
	if not is_raised or player.health.is_downed:
		return false
	var to_attacker: Vector2 = from_position - player.global_position
	if to_attacker.length() < 0.01:
		return false
	if absf(player.facing.angle_to(to_attacker)) > deg_to_rad(value("arc_degrees", 120.0)) * 0.5:
		return false
	if target != player:
		var to_target: Vector2 = target.global_position - player.global_position
		if to_target.length() > value("protect_distance", 120.0):
			return false
		# Behind him: on the other side than the attacker.
		if to_target.length() > 0.01 and to_target.normalized().dot(to_attacker.normalized()) > 0.0:
			return false
	_on_block(from_position, source)
	return true


func _on_block(from_position: Vector2, source: Node2D) -> void:
	blocks += 1
	_flash_left = block_flash_time
	_play(block_sound, from_position)
	var creature := source as Creature
	if creature:
		creature.repel(player.global_position.direction_to(creature.global_position), value("repel_speed", 320.0), value("repel_stagger", 0.5))


func _draw() -> void:
	if _raise <= 0.0:
		return
	var half: float = deg_to_rad(value("arc_degrees", 120.0)) * 0.5
	var flash: float = _flash_left / block_flash_time if block_flash_time > 0.0 else 0.0
	var base: Color = _hdr(color, energy, 0.6 * _raise)
	var glow: Color = base.lerp(_hdr(block_color, block_energy, 1.0), flash)
	var angle: float = player.facing.angle()
	draw_arc(Vector2.ZERO, radius, angle - half, angle + half, 24, glow, width * (1.0 + flash), true)
