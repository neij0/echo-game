class_name HurtVignette
extends Control
## Flashes a thin red band along the screen edges when a player takes a
## non-lethal hit. Only the edges: the band fades to nothing a short way in, so
## the centre of the screen is never tinted. (Co-op with a shared screen: any
## player's hit flashes it.)

@export var stage_manager: StageManager
@export var color: Color = Color(0.9, 0.05, 0.05)
## Opacity right at the screen edge at the moment of the hit.
@export_range(0.0, 1.0) var max_alpha: float = 0.18
## Seconds until the flash is gone.
@export var fade_time: float = 0.4
## Width of the band as a share of the screen's shorter side.
@export_range(0.0, 0.5) var band_width: float = 0.05

var _time_left: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var outer := Color(color, alpha)
	var inner := Color(color, 0.0)
	var band: float = minf(size.x, size.y) * band_width
	var o0 := Vector2.ZERO
	var o1 := Vector2(size.x, 0.0)
	var o2 := size
	var o3 := Vector2(0.0, size.y)
	var i0 := Vector2(band, band)
	var i1 := Vector2(size.x - band, band)
	var i2 := Vector2(size.x - band, size.y - band)
	var i3 := Vector2(band, size.y - band)
	# One trapezoid per edge: opaque at the screen edge, transparent inside.
	var colors := PackedColorArray([outer, outer, inner, inner])
	draw_polygon(PackedVector2Array([o0, o1, i1, i0]), colors)
	draw_polygon(PackedVector2Array([o1, o2, i2, i1]), colors)
	draw_polygon(PackedVector2Array([o2, o3, i3, i2]), colors)
	draw_polygon(PackedVector2Array([o3, o0, i0, i3]), colors)
