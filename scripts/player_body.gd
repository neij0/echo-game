class_name PlayerBody
extends Node2D
## The player's grey-box circle. Does a quick squash-and-stretch on each pulse.

@export var body_radius: float = 14.0
@export var body_color: Color = Color(0.85, 0.9, 1.0)

@export_group("Pulse Squash")
## Scale right at the pulse (wide and flat).
@export var squash_scale: Vector2 = Vector2(1.35, 0.7)
## Overshoot the other way before settling.
@export var stretch_scale: Vector2 = Vector2(0.85, 1.15)
@export var squash_time: float = 0.05
@export var stretch_time: float = 0.08
@export var settle_time: float = 0.15

var _tween: Tween


func _ready() -> void:
	var player := get_parent() as Player
	if player:
		player.pulse_emitted.connect(_on_pulse_emitted)


func _on_pulse_emitted(_origin: Vector2) -> void:
	if _tween:
		_tween.kill()
	scale = Vector2.ONE
	_tween = create_tween()
	_tween.tween_property(self, "scale", squash_scale, squash_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", stretch_scale, stretch_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, settle_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, body_color)
