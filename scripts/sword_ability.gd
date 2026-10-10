class_name SwordAbility
extends Node2D
## The Guardian's sword: a 3-hit combo on the action button. Hits 1 and 2 are
## quick slashes, hit 3 is a slower, stronger finisher with a wider arc.
## Pressing again during a hit or within combo_window continues the combo,
## otherwise it resets. Only revealed creatures take damage (Creature.is_revealed).
## Every swing makes noise: raises Depth Awareness and alerts nearby creatures.
## Lives on a CanvasLayer with follow_viewport_enabled (drawn unlit, so the
## player can always see where the sword points); follows the player each frame.

signal swung(hit_index: int)
signal hit_landed(creature: Creature, damage: int)

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

@export_group("Combo")
## Seconds after a hit ends during which pressing continues the combo.
@export var combo_window: float = 0.45

@export_group("Noise")
## Depth Awareness added by every swing.
@export var noise_awareness: float = 4.0
## Creatures within this distance hear the swing and come to investigate.
@export var noise_radius: float = 450.0

@export_group("Sound")
@export var swing_stream: AudioStream
@export var hit_stream: AudioStream
@export var swing_volume_db: float = -6.0
@export var hit_volume_db: float = -2.0

@export_group("Look")
@export var sword_length: float = 34.0
@export var sword_width: float = 3.5
## Sword sits this far from the body centre.
@export var sword_offset: float = 12.0
## Sword colour inside the Echo's light...
@export var lit_color: Color = Color(1.0, 0.78, 0.25)
@export var lit_energy: float = 1.8
## ...and outside of it.
@export var dark_color: Color = Color(0.32, 0.32, 0.36)
@export var arc_color: Color = Color(0.85, 0.9, 1.0)
@export var arc_energy: float = 1.6
## Opacity of the slash arc at its start (fades out over the hit).
@export_range(0.0, 1.0) var arc_alpha: float = 0.55

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
var _swing_audio: AudioStreamPlayer2D
var _hit_audio: AudioStreamPlayer2D


func _ready() -> void:
	_swing_audio = _make_audio(swing_stream, swing_volume_db)
	_hit_audio = _make_audio(hit_stream, hit_volume_db)


func _process(delta: float) -> void:
	if player == null:
		return
	global_position = player.global_position
	_recovery_left = maxf(_recovery_left - delta, 0.0)
	_window_left = maxf(_window_left - delta, 0.0)
	if _window_left <= 0.0 and hit_index < 0:
		_next_index = 0

	if player.try_action_pressed():
		_on_attack_pressed()
	if hit_index >= 0:
		_update_hit(delta)
	queue_redraw()


func is_attacking() -> bool:
	return hit_index >= 0


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
	if swing_stream:
		_swing_audio.pitch_scale = 0.8 if index == 2 else 1.0 + 0.08 * index
		_swing_audio.play()
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
	var half_arc: float = deg_to_rad(finisher_arc_degrees if is_finisher else quick_arc_degrees) * 0.5
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature == null or creature.is_dying():
			continue
		var offset: Vector2 = creature.global_position - player.global_position
		if offset.length() > reach + creature.body_radius:
			continue
		if absf(_swing_dir.angle_to(offset)) > half_arc:
			continue
		# Unrevealed creatures cannot be hurt: the Guardian only fights what the Echo shows.
		if not creature.is_revealed():
			continue
		var damage: int = finisher_damage if is_finisher else quick_damage
		creature.take_damage(damage, player.global_position,
			finisher_stagger if is_finisher else quick_stagger,
			finisher_knockback if is_finisher else quick_knockback)
		if hit_stream:
			_hit_audio.play()
		hit_landed.emit(creature, damage)


func _make_noise() -> void:
	# Looked up here, not in _ready: the players are ready before DepthAwareness.
	if _awareness == null:
		_awareness = get_tree().get_first_node_in_group("depth_awareness") as DepthAwareness
	if _awareness:
		_awareness.add_noise(noise_awareness)
	get_tree().call_group("creatures", "hear_noise", player.global_position, noise_radius)


func _windup(index: int) -> float:
	return finisher_windup if index == 2 else 0.0


func _make_audio(stream: AudioStream, volume_db: float) -> AudioStreamPlayer2D:
	var audio := AudioStreamPlayer2D.new()
	audio.stream = stream
	audio.volume_db = volume_db
	add_child(audio)
	return audio


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw() -> void:
	if player == null or player.health.is_downed:
		return
	var lit: bool = is_in_echo_light()
	var sword_color: Color = _hdr(lit_color, lit_energy, 1.0) if lit else dark_color
	var direction: Vector2 = player.facing

	if hit_index >= 0:
		var is_finisher: bool = hit_index == 2
		var reach: float = finisher_range if is_finisher else quick_range
		var half_arc: float = deg_to_rad(finisher_arc_degrees if is_finisher else quick_arc_degrees) * 0.5
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
			_draw_arc_shape(reach, half_arc, 1.0 - t)
			direction = _swing_dir.rotated(lerpf(-half_arc, half_arc, minf(t * 2.5, 1.0)) * side)

	var base: Vector2 = direction * sword_offset
	draw_line(base, base + direction * sword_length, sword_color, sword_width, true)


func _draw_arc_shape(reach: float, half_arc: float, fade: float) -> void:
	var color: Color = _hdr(arc_color, arc_energy, arc_alpha * fade)
	var steps: int = 16
	var points := PackedVector2Array([Vector2.ZERO])
	var start: float = _swing_dir.angle() - half_arc
	for i: int in steps + 1:
		points.append(Vector2.from_angle(start + 2.0 * half_arc * i / steps) * reach)
	draw_colored_polygon(points, color)
