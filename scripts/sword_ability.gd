class_name SwordAbility
extends Node3D
## The Guardian's sword: a 3-hit combo on the action button. Hits 1 and 2 are
## quick slashes, hit 3 is a slower, stronger finisher with a wider arc.
## Pressing again during a hit or within combo_window continues the combo,
## otherwise it resets. Only revealed creatures take damage (Creature.is_revealed).
## A finisher on an Exposed creature (just hit by the Echo's pulse front) kills
## it instantly, with a hit-stop, a gold burst, its own sound and a big shake.
## Every swing makes noise: raises Depth Awareness and alerts nearby creatures.
## Rest pose (not attacking): the Guardian faces right or left on the screen
## (it flips only when the horizontal input changes sign; moving straight up or
## down keeps it) and the sword hangs lowered beside him, rest_angle_degrees
## below horizontal on that side. Flips and the return after a combo blend over
## rest_transition_time. Attacks aim along Player.get_attack_direction (the
## right stick on a gamepad, else the facing); while the stick aims, a faint
## tick shows it.
## Skills: "sword_arc_mult" widens both arcs (at most a full circle).
## Look (a placeholder blade until the Guardian's model, Phase C): a dark blade
## whose edge glows gold inside the Echo's light, a bright slash arc on the
## floor that trails the swing (drawn over rock), and a small body lunge per hit
## (get_lunge_offset, used by the body; the finisher pulls back first).
## 3D: lengths are world units; it lives on the Guardian but keeps its own
## world position (top_level), following his drawn (interpolated) position.

signal swung(hit_index: int)
signal hit_landed(creature: Creature, damage: int)
signal exposed_kill(creature_position: Vector3)

@export var player: Player

@export_group("Quick Slash (hits 1 and 2)")
@export var quick_damage: int = 1
@export var quick_range: float = 1.24
@export var quick_arc_degrees: float = 100.0
## Seconds the slash lasts (the next press is buffered meanwhile).
@export var quick_duration: float = 0.2
@export var quick_stagger: float = 0.3
@export var quick_knockback: float = 2.8

@export_group("Finisher (hit 3)")
@export var finisher_damage: int = 2
@export var finisher_range: float = 1.64
@export var finisher_arc_degrees: float = 170.0
## Wind-up before the finisher lands (makes it feel slower and heavier).
@export var finisher_windup: float = 0.14
@export var finisher_duration: float = 0.3
@export var finisher_stagger: float = 0.7
@export var finisher_knockback: float = 6.4
## Seconds after the finisher before a new combo can start.
@export var finisher_recovery: float = 0.35

@export_group("Exposed Kill")
## Real-time seconds the game freezes on an Exposed kill.
@export var hit_stop_duration: float = 0.08
## Engine time scale during the hit-stop (0 = full freeze).
@export_range(0.0, 1.0) var hit_stop_time_scale: float = 0.02
@export var burst_color: Color = Color(1.0, 0.8, 0.3)
@export var burst_energy: float = 4.0
@export var burst_radius: float = 1.9
@export var burst_time: float = 0.45
@export var burst_ray_count: int = 10
@export var burst_width: float = 0.08
@export var kill_shake_strength: float = 0.18
@export var kill_shake_duration: float = 0.3

@export_group("Combo")
## Seconds after a hit ends during which pressing continues the combo.
@export var combo_window: float = 0.45
## Deflectables (the Angler's orbs) are hit this much beyond the blade's reach.
@export var deflect_margin: float = 0.36

@export_group("Noise")
## Depth Awareness added by every swing.
@export var noise_awareness: float = 4.0
## Creatures within this distance hear the swing and come to investigate.
@export var noise_radius: float = 9.0

@export_group("Sound")
## AudioDirector sound names: a whoosh per combo hit (the third is heavier),
## the impact (heavier on the finisher), and the Exposed kill, which plays
## after a short silence (the hit-stop).
@export var whoosh_sounds: PackedStringArray = PackedStringArray(["sword_whoosh_1", "sword_whoosh_2", "sword_whoosh_3"])
@export var impact_sound: String = "sword_impact"
@export var heavy_impact_sound: String = "sword_impact_heavy"
@export var finisher_sound: String = "sword_finisher"
## Real seconds of silence before the finisher boom.
@export var finisher_silence: float = 0.12

@export_group("Look")
@export var sword_length: float = 0.68
## Blade width at the hilt and its thickness.
@export var sword_width: float = 0.09
@export var sword_thickness: float = 0.03
## The hilt sits this far from the body's axis, at this height.
@export var sword_offset: float = 0.24
@export var hand_height: float = 0.75
@export var blade_color: Color = Color(0.05, 0.05, 0.07)
@export var guard_width: float = 0.18
## Edge colour inside the Echo's light...
@export var lit_color: Color = Color(1.0, 0.78, 0.25)
@export var lit_energy: float = 1.8
## ...and outside of it.
@export var dark_color: Color = Color(0.32, 0.32, 0.36)
@export var dark_energy: float = 0.3

@export_group("Rest Pose")
## Degrees below horizontal the lowered sword points, on the facing side.
@export_range(0.0, 90.0) var rest_angle_degrees: float = 45.0
## Seconds to blend into the rest pose (after a flip or a combo).
@export var rest_transition_time: float = 0.12
## Horizontal (screen) share of the facing needed to flip it.
@export_range(0.0, 1.0) var facing_flip_threshold: float = 0.3

@export_group("Slash Arc")
@export var arc_color: Color = Color(0.85, 0.9, 1.0)
@export var arc_energy: float = 2.2
## Opacity of the newest part of the arc (older parts and the end of the hit fade).
@export_range(0.0, 1.0) var arc_alpha: float = 0.55
## Inner edge of the arc band, as a share of the reach.
@export_range(0.0, 1.0) var arc_inner_ratio: float = 0.72
## The finisher's arc is this much brighter.
@export var finisher_arc_boost: float = 1.6

@export_group("Aim Tick")
## A faint mark beyond the blade tip while the right stick aims.
@export var aim_tick_color: Color = Color(0.85, 0.9, 1.0)
@export var aim_tick_energy: float = 1.2
@export_range(0.0, 1.0) var aim_tick_alpha: float = 0.45
@export var aim_tick_distance: float = 1.12
@export var aim_tick_length: float = 0.18
@export var aim_tick_width: float = 0.04

@export_group("Lunge")
## Body lunge towards the swing (world units, visual only).
@export var quick_lunge: float = 0.08
@export var finisher_lunge: float = 0.18
## The finisher pulls the body back this far during its wind-up.
@export var windup_pull: float = 0.12

## -1 = not attacking, otherwise 0, 1 or 2.
var hit_index: int = -1
var _next_index: int = 0
var _time_left: float = 0.0
var _elapsed: float = 0.0
var _window_left: float = 0.0
var _recovery_left: float = 0.0
var _buffered: bool = false
var _applied: bool = false
var _swing_dir: Vector3 = Vector3.BACK
var _awareness: DepthAwareness
## 1 = facing right on the screen, -1 = facing left (rest pose only).
var facing_sign: float = 1.0
## The blade's direction as drawn, and the rest blend.
var _blade_dir: Vector3 = Vector3.RIGHT
var _pose_from: Vector3 = Vector3.RIGHT
var _pose_t: float = 1.0
var _pose_sign: float = 1.0
var _was_attacking: bool = false
# Gold bursts of Exposed kills: world position and age in seconds.
var _burst_positions: PackedVector3Array = PackedVector3Array()
var _burst_ages: PackedFloat32Array = PackedFloat32Array()
var _blade: MeshInstance3D
var _guard: MeshInstance3D
var _blade_material: StandardMaterial3D
var _arc: GlowLines
var _bursts: GlowLines
var _tick: GlowLines


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_look()
	_blade_dir = _rest_direction(facing_sign)
	_pose_from = _blade_dir


func _process(delta: float) -> void:
	if player == null:
		return
	_recovery_left = maxf(_recovery_left - delta, 0.0)
	_window_left = maxf(_window_left - delta, 0.0)
	if _window_left <= 0.0 and hit_index < 0:
		_next_index = 0

	if player.try_action_pressed():
		_on_attack_pressed()
	if hit_index >= 0:
		_update_hit(delta)
	_update_rest_pose(delta)
	_update_bursts(delta)
	_update_look()


func is_attacking() -> bool:
	return hit_index >= 0


## Where the blade points right now (world space, unit): during a hit it
## sweeps through the slash (a character model aims its sword along it).
func get_blade_direction() -> Vector3:
	return _blade_dir.normalized()


## True while the right stick aims (the tick is drawn).
func is_showing_aim_tick() -> bool:
	return player != null and not player.health.is_downed and hit_index < 0 and player.get_stick_aim() != Vector3.ZERO


## Visual body offset for the current hit: pulled back during the finisher's
## wind-up, then a short lunge towards the swing that settles back.
func get_lunge_offset() -> Vector3:
	if hit_index < 0:
		return Vector3.ZERO
	var windup: float = _windup(hit_index)
	if _elapsed < windup:
		return -_swing_dir * windup_pull * (_elapsed / windup)
	var duration: float = finisher_duration if hit_index == 2 else quick_duration
	var t: float = clampf((_elapsed - windup) / duration, 0.0, 1.0)
	var start: float = -windup_pull if hit_index == 2 else 0.0
	var peak: float = finisher_lunge if hit_index == 2 else quick_lunge
	return _swing_dir * lerpf(start, peak, minf(t * 3.0, 1.0)) * (1.0 - smoothstep(0.5, 1.0, t))


## The floor direction that is "right" on the screen.
func _screen_right() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return Vector3.RIGHT
	var right: Vector3 = camera.global_basis.x
	return Vector3(right.x, 0.0, right.z).normalized()


## The lowered blade on one side of the screen: sideways, rest_angle_degrees down.
func _rest_direction(side_sign: float) -> Vector3:
	var below: float = deg_to_rad(rest_angle_degrees)
	return (_screen_right() * side_sign * cos(below) + Vector3.DOWN * sin(below)).normalized()


func _update_rest_pose(delta: float) -> void:
	var sideways: float = player.facing.dot(_screen_right())
	if absf(sideways) >= facing_flip_threshold:
		facing_sign = signf(sideways)
	if hit_index >= 0:
		_was_attacking = true
		return
	if _was_attacking or not is_equal_approx(facing_sign, _pose_sign):
		# Combo over or a flip: blend from where the blade is now.
		_was_attacking = false
		_pose_sign = facing_sign
		_pose_from = _blade_dir
		_pose_t = 0.0
	_pose_t = minf(_pose_t + delta / maxf(rest_transition_time, 0.001), 1.0)
	_blade_dir = _pose_from.slerp(_rest_direction(facing_sign), smoothstep(0.0, 1.0, _pose_t)).normalized()


func is_in_echo_light() -> bool:
	for other: Player in Players.all(get_tree()):
		if other != player and other.light_reveal_radius > 0.0 and not other.health.is_downed:
			if _flat_distance(other.global_position, player.global_position) <= other.light_reveal_radius:
				return true
	return false


func _on_attack_pressed() -> void:
	if _recovery_left > 0.0:
		return
	if hit_index >= 0:
		# Buffer the next hit while this one is still playing.
		if hit_index < 2:
			_buffered = true
		return
	_start_hit(_next_index if _window_left > 0.0 else 0)


func _start_hit(index: int) -> void:
	hit_index = index
	_elapsed = 0.0
	_time_left = _windup(index) + (finisher_duration if index == 2 else quick_duration)
	_buffered = false
	_applied = false
	_window_left = 0.0
	_swing_dir = player.get_attack_direction()
	if not whoosh_sounds.is_empty():
		_play(whoosh_sounds[mini(index, whoosh_sounds.size() - 1)], player.global_position)
	_make_noise()
	swung.emit(index)


func _update_hit(delta: float) -> void:
	_elapsed += delta
	_time_left -= delta
	if not _applied and _elapsed >= _windup(hit_index):
		_applied = true
		_apply_damage()
	if _time_left > 0.0:
		return
	var finished: int = hit_index
	hit_index = -1
	if finished == 2:
		_recovery_left = finisher_recovery
		_next_index = 0
	elif _buffered:
		_start_hit(finished + 1)
	else:
		_next_index = finished + 1
		_window_left = combo_window


func _apply_damage() -> void:
	var is_finisher: bool = hit_index == 2
	var reach: float = finisher_range if is_finisher else quick_range
	var half_arc: float = get_arc_radians(is_finisher) * 0.5
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature == null or creature.is_dying():
			continue
		# The creature's body (a circle, or a boss's own shape) in the swing.
		if not creature.is_in_swing(player.global_position, _swing_dir, reach, half_arc):
			continue
		# Unrevealed creatures cannot be hurt: the Guardian only fights what the Echo
		# shows, or what is right next to him (his close sense).
		if not creature.is_revealed():
			continue
		var damage: int = finisher_damage if is_finisher else quick_damage
		var creature_position: Vector3 = creature.global_position
		var killed_exposed: bool = creature.take_damage(damage, player,
			finisher_stagger if is_finisher else quick_stagger,
			finisher_knockback if is_finisher else quick_knockback, is_finisher)
		if killed_exposed:
			_on_exposed_kill(creature_position)
		else:
			_play(heavy_impact_sound if is_finisher else impact_sound, creature_position)
		hit_landed.emit(creature, damage)
	# Things the blade can knock back (the Angler's orbs): deflect(attacker).
	for node: Node in get_tree().get_nodes_in_group("deflectables"):
		var target := node as Node3D
		if target == null:
			continue
		var offset := Vector2(target.global_position.x - player.global_position.x, target.global_position.z - player.global_position.z)
		var aim := Vector2(_swing_dir.x, _swing_dir.z)
		if offset.length() <= reach + deflect_margin and absf(aim.angle_to(offset)) <= half_arc:
			if target.call("deflect", player):
				_play(impact_sound, target.global_position)


func _on_exposed_kill(creature_position: Vector3) -> void:
	_burst_positions.append(creature_position)
	_burst_ages.append(0.0)
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio:
		audio.play_after_silence(finisher_sound, creature_position, finisher_silence)
	get_tree().call_group("shared_camera", "shake_with", kill_shake_strength, kill_shake_duration)
	exposed_kill.emit(creature_position)
	_hit_stop()


func _hit_stop() -> void:
	Engine.time_scale = hit_stop_time_scale
	# This timer ignores the time scale, so it ends after real seconds.
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _update_bursts(delta: float) -> void:
	for i: int in range(_burst_ages.size() - 1, -1, -1):
		_burst_ages[i] += delta
		if _burst_ages[i] >= burst_time:
			_burst_ages.remove_at(i)
			_burst_positions.remove_at(i)


func _make_noise() -> void:
	# Looked up here, not in _ready: the players are ready before DepthAwareness.
	if _awareness == null:
		_awareness = get_tree().get_first_node_in_group("depth_awareness") as DepthAwareness
	if _awareness:
		_awareness.add_noise(noise_awareness)
	get_tree().call_group("creatures", "hear_noise", player.global_position, noise_radius)


## The full arc of a hit in radians, with the skills.
func get_arc_radians(is_finisher: bool) -> float:
	var skills: PlayerSkills = PlayerSkills.of(player)
	var multiplier: float = skills.get_multiplier("sword_arc_mult") if skills else 1.0
	return minf(deg_to_rad(finisher_arc_degrees if is_finisher else quick_arc_degrees) * multiplier, TAU)


func _windup(index: int) -> float:
	return finisher_windup if index == 2 else 0.0


func _play(sound_name: String, at: Vector3) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio:
		audio.play(sound_name, at)


# --- Look -----------------------------------------------------------------------

func _update_look() -> void:
	var origin: Vector3 = player.get_global_transform_interpolated().origin + get_lunge_offset()
	global_position = origin
	_arc.clear()
	_tick.clear()
	var downed: bool = player.health.is_downed
	_blade.visible = not downed
	_guard.visible = not downed
	if not downed:
		if hit_index >= 0:
			_update_swing_look(origin)
		_place_blade(origin)
		var lit: bool = is_in_echo_light()
		_blade_material.emission = lit_color if lit else dark_color
		_blade_material.emission_energy_multiplier = lit_energy if lit else dark_energy
		if is_showing_aim_tick():
			var aim: Vector3 = player.get_stick_aim()
			_tick.add_polyline(PackedVector3Array([origin + aim * aim_tick_distance, origin + aim * (aim_tick_distance + aim_tick_length)]),
				aim_tick_width, Color(aim_tick_color, aim_tick_alpha), hand_height)
	_arc.commit()
	_tick.commit()
	_draw_bursts()


## The blade sweeps across the arc; the slash band trails it.
func _update_swing_look(origin: Vector3) -> void:
	var is_finisher: bool = hit_index == 2
	var reach: float = finisher_range if is_finisher else quick_range
	var half_arc: float = get_arc_radians(is_finisher) * 0.5
	var swing_time: float = _elapsed - _windup(hit_index)
	var duration: float = finisher_duration if is_finisher else quick_duration
	# Alternate the slash direction so the combo reads as left, right, big.
	var side: float = -1.0 if hit_index == 1 else 1.0
	var base_angle: float = atan2(_swing_dir.z, _swing_dir.x)
	if swing_time < 0.0:
		# Wind-up: sword pulled back to the start of the arc.
		_blade_dir = _floor_direction(base_angle - half_arc * side * 1.1)
		return
	var t: float = clampf(swing_time / duration, 0.0, 1.0)
	var sweep: float = minf(t * 2.5, 1.0)
	var start: float = base_angle - half_arc * side
	var now: float = start + 2.0 * half_arc * side * sweep
	if sweep > 0.0:
		var boost: float = finisher_arc_boost if is_finisher else 1.0
		var fade: float = 1.0 - t
		_arc.set_energy(arc_energy * boost)
		_arc.add_band(origin, reach * arc_inner_ratio, reach, start, now,
			Color(arc_color, 0.0), Color(arc_color, arc_alpha * fade), hand_height)
	_blade_dir = _floor_direction(now)


func _place_blade(origin: Vector3) -> void:
	var direction: Vector3 = _blade_dir.normalized()
	var hilt: Vector3 = origin + Vector3(0.0, hand_height, 0.0) + _flat(direction).normalized() * sword_offset
	# The blade's length runs along its local z.
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var x_axis: Vector3 = up.cross(direction).normalized()
	var y_axis: Vector3 = direction.cross(x_axis).normalized()
	var blade_basis := Basis(x_axis, y_axis, direction)
	_blade.global_transform = Transform3D(blade_basis, hilt + direction * sword_length * 0.5)
	_guard.global_transform = Transform3D(blade_basis, hilt)


func _draw_bursts() -> void:
	_bursts.clear()
	for i: int in _burst_ages.size():
		var t: float = _burst_ages[i] / burst_time
		var center: Vector3 = _burst_positions[i]
		var color := Color(burst_color, 1.0 - t)
		var radius: float = burst_radius * (0.3 + 0.7 * t)
		_bursts.add_ring(center, radius, burst_width * (1.0 - t) + 0.02, color)
		for r: int in burst_ray_count:
			var out: Vector3 = _floor_direction(TAU * r / burst_ray_count)
			_bursts.add_polyline(PackedVector3Array([center + out * radius * 0.3, center + out * radius * 1.15]), 0.04, color)
	_bursts.commit()


func _build_look() -> void:
	_blade_material = StandardMaterial3D.new()
	_blade_material.albedo_color = blade_color
	_blade_material.emission_enabled = true
	_blade_material.emission = dark_color
	_blade_material.roughness = 0.6
	var blade_mesh := PrismMesh.new()
	# A flat blade narrowing to a point along +z.
	blade_mesh.size = Vector3(sword_width, sword_length, sword_thickness)
	# The prism's point is its +y: the Shape child lays it along the blade's z.
	var holder := Node3D.new()
	holder.name = "BladeHolder"
	add_child(holder)
	_blade = MeshInstance3D.new()
	_blade.name = "Blade"
	holder.add_child(_blade)
	var point_forward := MeshInstance3D.new()
	point_forward.name = "Shape"
	point_forward.mesh = blade_mesh
	point_forward.material_override = _blade_material
	point_forward.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_blade.add_child(point_forward)
	_blade.top_level = true
	_blade.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(guard_width, sword_thickness * 1.5, sword_thickness * 1.5)
	_guard = MeshInstance3D.new()
	_guard.name = "Guard"
	_guard.mesh = guard_mesh
	_guard.material_override = _blade_material
	_guard.top_level = true
	_guard.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	holder.add_child(_guard)
	_arc = _add_lines("SlashArc", arc_energy)
	_bursts = _add_lines("KillBursts", burst_energy)
	_tick = _add_lines("AimTick", aim_tick_energy)


func _add_lines(node_name: String, line_energy: float) -> GlowLines:
	var lines := GlowLines.new()
	lines.name = node_name
	lines.energy = line_energy
	add_child(lines)
	return lines


static func _floor_direction(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
