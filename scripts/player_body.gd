class_name PlayerBody
extends Node2D
## The player's grey-box body: a circle (Echo) or a tall capsule (Guardian).
## Does a quick squash-and-stretch on each pulse, and lies flat and grey while
## the player is downed.

@export var body_radius: float = 14.0
## 0 = circle. Above 2 * body_radius = a standing capsule this tall.
@export var body_height: float = 0.0
@export var body_color: Color = Color(0.85, 0.9, 1.0)
@export var downed_color: Color = Color(0.35, 0.35, 0.4)
## Scale while downed (lying down: wide and flat).
@export var downed_scale: Vector2 = Vector2(1.3, 0.55)

@export_group("Pulse Squash")
## Scale right at the pulse (wide and flat).
@export var squash_scale: Vector2 = Vector2(1.35, 0.7)
## Overshoot the other way before settling.
@export var stretch_scale: Vector2 = Vector2(0.85, 1.15)
@export var squash_time: float = 0.05
@export var stretch_time: float = 0.08
@export var settle_time: float = 0.15

var _tween: Tween
var _player: Player
var _was_downed: bool = false


func _ready() -> void:
	_player = get_parent() as Player
	if _player:
		_player.pulse_emitted.connect(_on_pulse_emitted)


func _process(_delta: float) -> void:
	if _player == null or _player.health == null:
		return
	var downed: bool = _player.health.is_downed
	if downed == _was_downed:
		return
	_was_downed = downed
	if _tween:
		_tween.kill()
	scale = downed_scale if downed else Vector2.ONE
	queue_redraw()


func _on_pulse_emitted(_origin: Vector2) -> void:
	if _tween:
		_tween.kill()
	scale = Vector2.ONE
	_tween = create_tween()
	_tween.tween_property(self, "scale", squash_scale, squash_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", stretch_scale, stretch_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, settle_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var color: Color = downed_color if _was_downed else body_color
	var straight: float = maxf(body_height * 0.5 - body_radius, 0.0)
	if straight <= 0.0:
		draw_circle(Vector2.ZERO, body_radius, color)
		return
	draw_rect(Rect2(-body_radius, -straight, body_radius * 2.0, straight * 2.0), color)
	draw_circle(Vector2(0.0, -straight), body_radius, color)
	draw_circle(Vector2(0.0, straight), body_radius, color)
