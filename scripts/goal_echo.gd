class_name GoalEcho
extends Node2D
## Only the Echo knows the way: shortly after each of her pulses, a faint golden
## echo comes back from the direction of the ancient light, shown as a short
## arc with a chevron next to her, pointing towards it. It fades after show_time.
## Must live on the Echo's CanvasLayer with follow_viewport_enabled (unlit).

@export var player: Player
## Seconds between the pulse and the returning echo.
@export var return_delay: float = 0.4
@export var show_time: float = 2.0
## Distance of the arc from the Echo's centre.
@export var distance: float = 48.0
@export var arc_degrees: float = 50.0
@export var width: float = 3.0
@export var chevron_size: float = 9.0
@export var color: Color = Color(1.0, 0.82, 0.35)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 1.8
## Kept low so it stays a faint hint.
@export_range(0.0, 1.0) var max_alpha: float = 0.55
## Seconds of fade in at the start.
@export var fade_in_time: float = 0.25

var _delay_left: float = -1.0
var _show_left: float = 0.0


func _ready() -> void:
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)


func _on_pulse_emitted(_origin: Vector2) -> void:
	_delay_left = return_delay


func _process(delta: float) -> void:
	if player == null:
		return
	global_position = player.global_position
	if _delay_left >= 0.0:
		_delay_left -= delta
		if _delay_left < 0.0:
			_show_left = show_time
	_show_left = maxf(_show_left - delta, 0.0)
	queue_redraw()


func is_showing() -> bool:
	return _show_left > 0.0


func _find_goal() -> Node2D:
	return get_tree().get_first_node_in_group("ancient_light") as Node2D


func _draw() -> void:
	if _show_left <= 0.0:
		return
	var goal: Node2D = _find_goal()
	if goal == null:
		return
	var elapsed: float = show_time - _show_left
	var alpha: float = max_alpha * minf(elapsed / fade_in_time, 1.0) * (_show_left / show_time)
	var glow := Color(color.r * energy, color.g * energy, color.b * energy, alpha)
	var direction: Vector2 = player.global_position.direction_to(goal.global_position)
	var angle: float = direction.angle()
	var half: float = deg_to_rad(arc_degrees) * 0.5
	draw_arc(Vector2.ZERO, distance, angle - half, angle + half, 16, glow, width, true)
	var tip: Vector2 = direction * (distance + chevron_size)
	var side: Vector2 = direction.orthogonal() * chevron_size
	draw_polyline(PackedVector2Array([tip - direction * chevron_size + side, tip, tip - direction * chevron_size - side]), glow, width, true)
