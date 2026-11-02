class_name WaveRule
extends Control
## A thin glowing wave line across the control (under a title, between parts
## of a screen), drifting slowly, like the focused buttons' underline.

@export var color: Color = Color(0.5, 1.1, 1.3, 0.75)
@export var line_width: float = 1.4
@export var wave_length: float = 34.0
@export var amplitude: float = 2.0
## Cycles per second the wave drifts along the line.
@export var speed: float = 0.35

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var y: float = size.y * 0.5
	GlowFx.glow_line(self, GlowFx.wave_points(Vector2(0.0, y), Vector2(size.x, y), _time * speed, wave_length, amplitude),
		color, line_width)
