class_name GoalEcho
extends GlowLines
## Only the Echo knows the way: shortly after each of her pulses, a faint echo
## comes back, shown as a short arc with a chevron on the floor next to her
## (drawn over rock). While Echo Shards are left it points (in the shard
## colour) to the nearest one ("echo_shards" group), in a straight line; once
## all are collected it points (gold) to the nearest open way out
## ("level_exit" group: the ancient light, the closed arena door, or the boss
## once the door is open). It fades after show_time. While forced (the
## collapse escape, EscapeEvent) it stays on all the time.

@export var player: Player
## Seconds between the pulse and the returning echo.
@export var return_delay: float = 0.4
@export var show_time: float = 2.0
## Distance of the arc from the Echo's centre (world units).
@export var distance: float = 0.96
@export var arc_degrees: float = 50.0
@export var width: float = 0.06
@export var chevron_size: float = 0.18
@export var color: Color = Color(1.0, 0.82, 0.35)
## Colour while it points to a shard.
@export var shard_color: Color = Color(0.55, 0.95, 1.0)
## Kept low so it stays a faint hint.
@export_range(0.0, 1.0) var max_alpha: float = 0.55
## Seconds of fade in at the start.
@export var fade_in_time: float = 0.25

var _delay_left: float = -1.0
var _show_left: float = 0.0
var _forced: bool = false


func _ready() -> void:
	super()
	add_to_group("goal_echo")
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)


## Called (via the "goal_echo" group) by EscapeEvent: on = always showing.
func set_forced(enabled: bool) -> void:
	_forced = enabled
	if enabled:
		_show_left = show_time


func _on_pulse_emitted(_origin: Vector3) -> void:
	_delay_left = return_delay


func _process(delta: float) -> void:
	if player == null:
		return
	if _delay_left >= 0.0:
		_delay_left -= delta
		if _delay_left < 0.0:
			_show_left = show_time
	_show_left = maxf(_show_left - delta, 0.0)
	if _forced:
		# Stays at full strength (past the fade-in, before the fade-out).
		_show_left = maxf(_show_left, show_time - fade_in_time)
	_draw_echo()


func is_showing() -> bool:
	return _show_left > 0.0


## What it points at right now: the nearest uncollected shard, else the
## nearest node of the level exit (null if none).
func get_target() -> Node3D:
	var shard: Node3D = _nearest_in_group("echo_shards")
	return shard if shard else _nearest_in_group("level_exit")


func _nearest_in_group(group_name: String) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(group_name):
		var target := node as Node3D
		if target == null:
			continue
		var distance_squared: float = player.global_position.distance_squared_to(target.global_position)
		if distance_squared < best_distance:
			best_distance = distance_squared
			best = target
	return best


func _draw_echo() -> void:
	clear()
	var goal: Node3D = get_target() if _show_left > 0.0 else null
	if goal:
		var elapsed: float = show_time - _show_left
		var alpha: float = max_alpha * minf(elapsed / fade_in_time, 1.0) * (_show_left / show_time)
		var tint: Color = shard_color if goal.is_in_group("echo_shards") else color
		var glow := Color(tint, alpha)
		var center: Vector3 = player.get_global_transform_interpolated().origin
		var offset: Vector3 = goal.global_position - center
		var direction: Vector3 = Vector3(offset.x, 0.0, offset.z).normalized()
		var angle: float = atan2(direction.z, direction.x)
		var half: float = deg_to_rad(arc_degrees) * 0.5
		add_arc(center, distance, angle - half, angle + half, width, glow)
		var tip: Vector3 = center + direction * (distance + chevron_size)
		var side: Vector3 = direction.cross(Vector3.UP) * chevron_size
		var back: Vector3 = tip - direction * chevron_size
		add_polyline(PackedVector3Array([back + side, tip, back - side]), width, glow)
	commit()
