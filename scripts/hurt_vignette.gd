class_name HurtVignette
extends Control
## Flashes the screen edges red when a player takes a non-lethal hit.
## (Co-op with a shared screen: any player's hit flashes it.)

@export var stage_manager: StageManager
@export var color: Color = Color(0.9, 0.05, 0.05)
## Opacity of the edges right at the hit.
@export_range(0.0, 1.0) var max_alpha: float = 0.7
@export var fade_time: float = 0.6
## 0-1: distance from the screen centre where the red starts (higher = thinner edge).
@export_range(0.0, 1.0) var inner_radius: float = 0.55

var _texture: GradientTexture2D
var _time_left: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, inner_radius, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.0), color])
	_texture = GradientTexture2D.new()
	_texture.gradient = gradient
	_texture.fill = GradientTexture2D.FILL_RADIAL
	_texture.fill_from = Vector2(0.5, 0.5)
	_texture.fill_to = Vector2(1.0, 0.5)

	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)


func _on_player_registered(player: Player) -> void:
	player.health.hurt.connect(_on_hurt)


func _on_hurt() -> void:
	_time_left = fade_time
	queue_redraw()


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if _time_left <= 0.0:
		return
	var alpha: float = max_alpha * _time_left / fade_time
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false, Color(1.0, 1.0, 1.0, alpha))
