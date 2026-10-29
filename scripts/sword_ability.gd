class_name SwordAbility
extends Node2D
## The Guardian's sword: a 3-hit combo on the action button. Hits 1 and 2 are
## quick slashes, hit 3 is a slower, stronger finisher with a wider arc.
## Pressing again during a hit or within combo_window continues the combo,
## otherwise it resets. Only revealed creatures take damage (Creature.is_revealed).
## A finisher on an Exposed creature (just hit by the Echo's pulse front) kills
## it instantly, with a hit-stop, a gold burst, its own sound and a big shake.
## Every swing makes noise: raises Depth Awareness and alerts nearby creatures.
## Lives on a CanvasLayer with follow_viewport_enabled (drawn unlit, so the
## player can always see where the sword points); follows the player each frame.
## Rest pose (not attacking): the Guardian faces right or left (it flips only
## when the horizontal input changes sign; moving straight up or down keeps it)
## and the sword hangs lowered beside him, rest_angle_degrees below horizontal
## on that side. Flips and the return after a combo blend over rest_transition_time.
## Attacks are unchanged: each hit aims along player.facing.
## Skills: "sword_arc_mult" widens both arcs (at most a full circle).
## Look: a dark blade whose edge glows gold inside the Echo's light, a bright
## slash arc that trails the swing, and a small body lunge per hit (visual
## only, read by GuardianVisual; the finisher pulls back first, then lunges further).

signal swung(hit_index: int)
signal hit_landed(creature: Creature, damage: int)
signal exposed_kill(creature_position: Vector2)

@export var player: Player

@export_group("Quick Slash (hits 1 and 2)")
@export var quick_damage: int = 1
@export var quick_range: float = 62.0
@export var quick_arc_degrees: float = 100.0
## Seconds the slash lasts (the next press is buffered meanwhile).
@export var quick_duration: float = 0.2
@export var quick_stagger: float = 0.3
@export var quick_knockback: float = 140.0

@export_group("Finisher (hit 3)")
@export var finisher_damage: int = 2
@export var finisher_range: float = 82.0
@export var finisher_arc_degrees: float = 170.0
## Wind-up before the finisher lands (makes it feel slower and heavier).
@export var finisher_windup: float = 0.14
@export var finisher_duration: float = 0.3
@export var finisher_stagger: float = 0.7
@export var finisher_knockback: float = 320.0
## Seconds after the finisher before a new combo can start.
@export var finisher_recovery: float = 0.35

@export_group("Exposed Kill")
## Real-time seconds the game freezes on an Exposed kill.
@export var hit_stop_duration: float = 0.08
## Engine time scale during the hit-stop (0 = full freeze).
@export_range(0.0, 1.0) var hit_stop_time_scale: float = 0.02
@export var burst_color: Color = Color(1.0, 0.8, 0.3)
@export var burst_energy: float = 4.0
@export var burst_radius: float = 95.0
@export var burst_time: float = 0.45
@export var burst_ray_count: int = 10
@export var burst_width: float = 4.0
@export var kill_shake_strength: float = 9.0
@export var kill_shake_duration: float = 0.3

@export_group("Combo")
## Seconds after a hit ends during which pressing continues the combo.
@export var combo_window: float = 0.45

@export_group("Noise")
## Depth Awareness added by every swing.
@export var noise_awareness: float = 4.0
## Creatures within this distance hear the swing and come to investigate.
@export var noise_radius: float = 450.0

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
@export var sword_length: float = 34.0
## Blade width at the hilt (it narrows to a point).
@export var sword_width: float = 4.5
## Sword sits this far from the body centre.
@export var sword_offset: float = 12.0
@export var blade_color: Color = Color(0.05, 0.05, 0.07)
@export var edge_width: float = 1.2
@export var guard_width: float = 9.0
## Edge colour inside the Echo's light...
@export var lit_color: Color = Color(1.0, 0.78, 0.25)
@export var lit_energy: float = 1.8
## ...and outside of it.
@export var dark_color: Color = Color(0.32, 0.32, 0.36)

@export_group("Rest Pose")
## Degrees below horizontal the lowered sword points, on the facing side
## (45 = down-right when facing right, down-left when facing left).
@export_range(0.0, 90.0) var rest_angle_degrees: float = 45.0
## Seconds to blend into the rest pose (after a flip or a combo).
@export var rest_transition_time: float = 0.12
## Horizontal input needed to flip the facing (ignores near-vertical input).
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

@export_group("Lunge")
## Body lunge towards the swing (pixels, visual only).
@export var quick_lunge: float = 4.0
@export var finisher_lunge: float = 9.0
## The finisher pulls the body back this far during its wind-up.
@export var windup_pull: float = 6.0

## -1 = not attacking, otherwise 0, 1 or 2.
var hit_index: int = -1
var _next_index: int = 0
var _time_left: float = 0.0
var _elapsed: float = 0.0
var _window_left: float = 0.0
var _recovery_left: float = 0.0
var _buffered: bool = false
var _applied: bool = false
var _swing_dir: Vector2 = Vector2.DOWN
var _awareness: DepthAwareness
## 1 = facing right, -1 = facing left (rest pose only).
var facing_sign: float = 1.0
var _pose_angle: float = 0.0
var _pose_from: float = 0.0
var _pose_to: float = 0.0
var _pose_t: float = 1.0
var _was_attacking: bool = false
## Angle of the blade as last drawn (to blend back from an attack).
var _drawn_angle: float = 0.0
# Gold bursts of Exposed kills: world position and age in seconds.
var _burst_positions: PackedVector2Array = PackedVector2Array()
var _burst_ages: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_pose_angle = _rest_angle(facing_sign)
	_pose_to = _pose_angle
	_drawn_angle = _pose_angle


func _process(delta: float) -> void:
	if player == null:
		return
	global_position = player.global_position + get_lunge_offset()
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
	queue_redraw()


func is_attacking() -> bool:
	return hit_index >= 0


## Visual body offset for the current hit: pulled back during the finisher's
## wind-up, then a short lunge towards the swing that settles back.
func get_lunge_offset() -> Vector2:
	if hit_index < 0:
		return Vector2.ZERO
	var windup: float = _windup(hit_index)
	if _elapsed < windup:
		return -_swing_dir * windup_pull * (_elapsed / windup)
	var duration: float = finisher_duration if hit_index == 2 else quick_duration
	var t: float = clampf((_elapsed - windup) / duration, 0.0, 1.0)
	var start: float = -windup_pull if hit_index == 2 else 0.0
	var peak: float = finisher_lunge if hit_index == 2 else quick_lunge
	return _swing_dir * lerpf(start, peak, minf(t * 3.0, 1.0)) * (1.0 - smoothstep(0.5, 1.0, t))


## Godot angle of the rest pose for a facing (y points down, so "below
## horizontal" is a positive angle: 45 = down-right, 180 - 45 = down-left).
func _rest_angle(side_sign: float) -> float:
	var below: float = deg_to_rad(rest_angle_degrees)
	return below if side_sign > 0.0 else PI - below


func _update_rest_pose(delta: float) -> void:
	if absf(player.facing.x) >= facing_flip_threshold:
		facing_sign = signf(player.facing.x)
	if hit_index >= 0:
		_was_attacking = true
		return
	var target: float = _rest_angle(facing_sign)
	if _was_attacking:
		# Combo over (or between hits): blend from where the blade ended.
		_was_attacking = false
		_start_pose_blend(_drawn_angle, target)
	elif not is_equal_approx(target, _pose_to):
		_start_pose_blend(_pose_angle, target)
	_pose_t = minf(_pose_t + delta / maxf(rest_transition_time, 0.001), 1.0)
	_pose_angle = lerp_angle(_pose_from, _pose_to, smoothstep(0.0, 1.0, _pose_t))


func _start_pose_blend(from: float, to: float) -> void:
	_pose_from = from
	_pose_to = to
	_pose_t = 0.0


func is_in_echo_light() -> bool:
	for other: Player in Players.all(get_tree()):
		if other != player and other.light_reveal_radius > 0.0 and not other.health.is_downed:
			if other.global_position.distance_to(player.global_position) <= other.light_reveal_radius:
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
	_swing_dir = player.facing
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
		var offset: Vector2 = creature.global_position - player.global_position
		if offset.length() > reach + creature.body_radius:
			continue
		if absf(_swing_dir.angle_to(offset)) > half_arc:
			continue
		# Unrevealed creatures cannot be hurt: the Guardian only fights what the Echo
		# shows, or what is right next to him (his close sense).
		if not creature.is_revealed():
			continue
		var damage: int = finisher_damage if is_finisher else quick_damage
		var creature_position: Vector2 = creature.global_position
		var killed_exposed: bool = creature.take_damage(damage, player,
			finisher_stagger if is_finisher else quick_stagger,
			finisher_knockback if is_finisher else quick_knockback, is_finisher)
		if killed_exposed:
			_on_exposed_kill(creature_position)
		else:
			_play(heavy_impact_sound if is_finisher else impact_sound, creature_position)
		hit_landed.emit(creature, damage)


func _on_exposed_kill(creature_position: Vector2) -> void:
	_burst_positions.append(creature_position)
	_burst_ages.append(0.0)
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio:
		audio.play_after_silence(finisher_sound, creature_position, finisher_silence)
	var camera := get_viewport().get_camera_2d() as SharedCamera
	if camera:
		camera.shake_with(kill_shake_strength, kill_shake_duration)
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


func _play(sound_name: String, at: Vector2) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio:
		audio.play(sound_name, at)


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw() -> void:
	_draw_bursts()
	if player == null or player.health.is_downed:
		return
	var lit: bool = is_in_echo_light()
	var edge_color: Color = _hdr(lit_color, lit_energy, 1.0) if lit else dark_color
	var direction: Vector2 = Vector2.from_angle(_pose_angle)

	if hit_index >= 0:
		var is_finisher: bool = hit_index == 2
		var reach: float = finisher_range if is_finisher else quick_range
		var half_arc: float = get_arc_radians(is_finisher) * 0.5
		var windup: float = _windup(hit_index)
		var swing_time: float = _elapsed - windup
		var duration: float = finisher_duration if is_finisher else quick_duration
		# Alternate the slash direction so the combo reads as left, right, big.
		var side: float = -1.0 if hit_index == 1 else 1.0
		if swing_time < 0.0:
			# Wind-up: sword pulled back to the start of the arc.
			direction = _swing_dir.rotated(-half_arc * side * 1.1)
		else:
			var t: float = clampf(swing_time / duration, 0.0, 1.0)
			var sweep: float = minf(t * 2.5, 1.0)
			_draw_arc_band(reach, half_arc, side, sweep, 1.0 - t, finisher_arc_boost if is_finisher else 1.0)
			direction = _swing_dir.rotated(lerpf(-half_arc, half_arc, sweep) * side)
	_drawn_angle = direction.angle()
	_draw_blade(direction, edge_color)


## A dark blade narrowing to a point, a small cross-guard, and a glowing edge.
func _draw_blade(direction: Vector2, edge_color: Color) -> void:
	var side: Vector2 = direction.orthogonal()
	var base: Vector2 = direction * sword_offset
	var tip: Vector2 = base + direction * sword_length
	var half: float = sword_width * 0.5
	var blade := PackedVector2Array([base + side * half, tip, base - side * half])
	draw_colored_polygon(blade, blade_color)
	draw_polyline(PackedVector2Array([base + side * half, tip, base - side * half]), edge_color, edge_width, true)
	draw_line(base + side * guard_width * 0.5, base - side * guard_width * 0.5, edge_color, edge_width * 1.5, true)


func _draw_bursts() -> void:
	for i: int in _burst_ages.size():
		var t: float = _burst_ages[i] / burst_time
		var center: Vector2 = _burst_positions[i] - global_position
		var color: Color = _hdr(burst_color, burst_energy, 1.0 - t)
		var radius: float = burst_radius * (0.3 + 0.7 * t)
		draw_arc(center, radius, 0.0, TAU, 48, color, burst_width * (1.0 - t) + 1.0, true)
		for r: int in burst_ray_count:
			var direction: Vector2 = Vector2.from_angle(TAU * r / burst_ray_count)
			draw_line(center + direction * radius * 0.3, center + direction * radius * 1.15, color, 2.0, true)


## The slash: a crescent band from where the swing started to where the blade
## is now, brightest at the blade and fading behind it.
func _draw_arc_band(reach: float, half_arc: float, side: float, sweep: float, fade: float, boost: float) -> void:
	if sweep <= 0.0:
		return
	var steps: int = 20
	var start: float = _swing_dir.angle() - half_arc * side
	var span: float = 2.0 * half_arc * side * sweep
	var inner: float = reach * arc_inner_ratio
	for i: int in steps:
		var a0: float = start + span * float(i) / steps
		var a1: float = start + span * float(i + 1) / steps
		# Older parts of the arc (near its start) are fainter.
		var c0: Color = _hdr(arc_color, arc_energy * boost, arc_alpha * fade * float(i) / steps)
		var c1: Color = _hdr(arc_color, arc_energy * boost, arc_alpha * fade * float(i + 1) / steps)
		var quad := PackedVector2Array([
			Vector2.from_angle(a0) * inner, Vector2.from_angle(a0) * reach,
			Vector2.from_angle(a1) * reach, Vector2.from_angle(a1) * inner,
		])
		draw_polygon(quad, PackedColorArray([c0, c0, c1, c1]))
