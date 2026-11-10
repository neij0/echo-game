class_name ScreenFader
extends CanvasLayer
## Screens fade through black (Game._change_scene): fade_out() covers the
## screen, the next scene loads behind the black, fade_in() uncovers it. It
## starts covered, so the game opens with a fade in. While covered it blocks
## the mouse. Created by the Game autoload; runs while the game is paused and
## ignores the hit-stop's time scale.

@export var color: Color = Color(0.0, 0.004, 0.012)
@export var fade_out_time: float = 0.35
@export var fade_in_time: float = 0.6
@export var draw_layer: int = 128

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = draw_layer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = color
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)


## Covers the screen; await it. seconds < 0 = fade_out_time (the level
## changes use a shorter fade).
func fade_out(seconds: float = -1.0) -> void:
	await _fade_to(1.0, fade_out_time if seconds < 0.0 else seconds)


## Uncovers the screen; await it (or not). seconds < 0 = fade_in_time.
func fade_in(seconds: float = -1.0) -> void:
	await _fade_to(0.0, fade_in_time if seconds < 0.0 else seconds)


func is_covered() -> bool:
	return _rect.color.a >= 1.0


## 0 = clear, 1 = black.
func get_cover() -> float:
	return _rect.color.a


func _fade_to(alpha: float, seconds: float) -> void:
	if _tween:
		_tween.kill()
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "color:a", alpha, seconds * absf(_rect.color.a - alpha))
	await _tween.finished
	if alpha <= 0.0:
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
