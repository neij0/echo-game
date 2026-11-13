class_name ShieldSkill
extends ActiveSkill
## The Guardian's Shield: hold the skill button to raise it. It points to
## shield_direction (on the floor), set when raised from
## Player.get_aim_direction (right stick, else move direction, else facing) and
## then locked:
## - gamepad: the right stick turns it right away; the left stick strafes;
## - keyboard: the move keys turn it towards them at keyboard_turn_speed while
##   he strafes slowly.
## Creature touches from that side ("arc_degrees" wide) are blocked
## (no damage, the creature is pushed back "repel_speed" and staggered), also
## for the Echo when she stands behind him (within "protect_distance", on the
## far side from the creature). While held he moves at "speed_scale" and cannot
## swing the sword. No cooldown (hold), so "cooldown" is 0.

@export_group("Look")
@export var color: Color = Color(0.75, 0.85, 1.0)
@export var energy: float = 1.2
@export var block_color: Color = Color(1.0, 0.85, 0.45)
## How much brighter the arc is right after a block.
@export var block_boost: float = 1.8
## Seconds the shield glows after a block.
@export var block_flash_time: float = 0.25
## Radius and width of the arc on the floor (units).
@export var radius: float = 0.75
@export var width: float = 0.07
## Seconds to raise / lower it (look only; it blocks as soon as it is held).
@export var raise_time: float = 0.08
## Opacity of the soft wedge showing the blocked area.
@export_range(0.0, 1.0) var wedge_alpha: float = 0.03

@export_group("Aim")
## Keyboard: degrees per second the shield turns towards the move keys.
@export var keyboard_turn_speed: float = 240.0

@export_group("Sound")
@export var block_sound: String = "sword_impact"

var is_raised: bool = false
## Where the raised shield points (blocks_hit, the arc), on the floor.
var shield_direction: Vector3 = Vector3.RIGHT
var blocks: int = 0
var _raise: float = 0.0
var _flash_left: float = 0.0
var _lines: GlowLines


func _ready() -> void:
	super()
	add_to_group("hit_blockers")
	_lines = GlowLines.new()
	_lines.energy = energy
	add_child(_lines)


func is_in_use() -> bool:
	return is_raised


func blocks_actions() -> bool:
	return is_raised


func _update(delta: float) -> void:
	var holding: bool = player.is_skill_held() and not player.is_reviving()
	if holding and not is_raised:
		shield_direction = player.get_aim_direction()
	is_raised = holding
	if is_raised:
		_aim(delta)
	player.speed_scale = value("speed_scale", 0.55) if is_raised else 1.0
	_raise = move_toward(_raise, 1.0 if is_raised else 0.0, delta / maxf(raise_time, 0.01))
	_flash_left = maxf(_flash_left - delta, 0.0)
	_draw_marks()


func _aim(delta: float) -> void:
	var stick: Vector3 = player.get_stick_aim()
	if stick != Vector3.ZERO:
		shield_direction = stick
		return
	if player.uses_gamepad:
		return
	var keys: Vector3 = player.get_move_direction()
	if keys.length() <= 0.1:
		return
	var turn: float = _flat(shield_direction).angle_to(_flat(keys))
	var step: float = deg_to_rad(keyboard_turn_speed) * delta
	var turned: Vector2 = _flat(shield_direction).rotated(clampf(turn, -step, step)).normalized()
	shield_direction = Vector3(turned.x, 0.0, turned.y)


func _exit_tree() -> void:
	if player:
		player.speed_scale = 1.0


## Called by PlayerHealth.take_hit on every player ("hit_blockers" group).
func blocks_hit(target: Player, from_position: Vector3, source: Node3D) -> bool:
	if not is_raised or player.health.is_downed:
		return false
	var to_attacker: Vector2 = _flat(from_position - player.global_position)
	if to_attacker.length() < 0.001:
		return false
	if absf(_flat(shield_direction).angle_to(to_attacker)) > deg_to_rad(value("arc_degrees", 120.0)) * 0.5:
		return false
	if target != player:
		var to_target: Vector2 = _flat(target.global_position - player.global_position)
		if to_target.length() > value("protect_distance", 2.4):
			return false
		# Behind him: on the other side than the attacker.
		if to_target.length() > 0.001 and to_target.normalized().dot(to_attacker.normalized()) > 0.0:
			return false
	_on_block(from_position, source)
	return true


func _on_block(from_position: Vector3, source: Node3D) -> void:
	blocks += 1
	_flash_left = block_flash_time
	_play(block_sound, from_position)
	var creature := source as Creature
	if creature:
		var away: Vector3 = creature.global_position - player.global_position
		away.y = 0.0
		creature.repel(away.normalized(), value("repel_speed", 6.4), value("repel_stagger", 0.5))


func _draw_marks() -> void:
	_lines.clear()
	if _raise > 0.0:
		var half: float = deg_to_rad(value("arc_degrees", 120.0)) * 0.5
		var flash: float = _flash_left / block_flash_time if block_flash_time > 0.0 else 0.0
		var tint: Color = color.lerp(block_color, flash)
		var glow := Color(tint.r, tint.g, tint.b, minf(0.6 * _raise * (1.0 + flash * block_boost), 1.0))
		var angle: float = atan2(shield_direction.z, shield_direction.x)
		var center: Vector3 = player.get_global_transform_interpolated().origin
		_lines.add_band(center, 0.0, radius, angle - half, angle + half, Color(glow, wedge_alpha * _raise), Color(glow, wedge_alpha * _raise))
		_lines.add_arc(center, radius, angle - half, angle + half, width * (1.0 + flash), glow)
	_lines.commit()


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
