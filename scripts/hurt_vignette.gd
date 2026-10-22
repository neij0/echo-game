class_name HurtVignette
extends Control
## Red band along the screen edges: a short flash when a player takes a
## non-lethal hit, and a slow heartbeat pulse (with a heartbeat sound) while
## any living player is at low health. Only the edges: the band fades to
## nothing a short way in, so the centre of the screen is never tinted.
## (Co-op with a shared screen: any player's hit or low health shows it.)

@export var stage_manager: StageManager
@export var color: Color = Color(0.9, 0.05, 0.05)
## Opacity right at the screen edge at the moment of the hit.
@export_range(0.0, 1.0) var max_alpha: float = 0.18
## Seconds until the flash is gone.
@export var fade_time: float = 0.4
## Width of the band as a share of the screen's shorter side.
@export_range(0.0, 0.5) var band_width: float = 0.05

@export_group("Low Health")
## Seconds between heartbeats while a player is at low health.
@export var heartbeat_interval: float = 0.9
## Opacity at the edge on each beat (fades out until the next one).
@export_range(0.0, 1.0) var heartbeat_alpha: float = 0.12
## Seconds the band takes to fade after a beat.
@export var heartbeat_fade_time: float = 0.5
## Band width on a beat, as a share of the screen's shorter side.
@export_range(0.0, 0.5) var heartbeat_band_width: float = 0.08
@export var heartbeat_stream: AudioStream
@export var heartbeat_volume_db: float = -10.0
@export var heartbeat_pitch: float = 0.8

var _time_left: float = 0.0
var _beat_left: float = 0.0
var _beat_timer: float = 0.0
var _heartbeat: AudioStreamPlayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = heartbeat_stream
	_heartbeat.volume_db = heartbeat_volume_db
	_heartbeat.pitch_scale = heartbeat_pitch
	add_child(_heartbeat)
	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)


func _on_player_registered(player: Player) -> void:
	player.health.hurt.connect(_on_hurt)


func _on_hurt() -> void:
	_time_left = fade_time
	queue_redraw()


func _process(delta: float) -> void:
	_update_heartbeat(delta)
	if _time_left <= 0.0 and _beat_left <= 0.0:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_beat_left = maxf(_beat_left - delta, 0.0)
	queue_redraw()


func _update_heartbeat(delta: float) -> void:
	if not _any_player_low():
		_beat_timer = 0.0
		return
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		_beat_timer = heartbeat_interval
		_beat_left = heartbeat_fade_time
		if heartbeat_stream:
			_heartbeat.play()


func _any_player_low() -> bool:
	if stage_manager == null:
		return false
	for player: Player in stage_manager.players:
		if player.health.is_low():
			return true
	return false


func _draw() -> void:
	if _time_left > 0.0:
		_draw_band(max_alpha * _time_left / fade_time, band_width)
	if _beat_left > 0.0:
		_draw_band(heartbeat_alpha * _beat_left / heartbeat_fade_time, heartbeat_band_width)


func _draw_band(alpha: float, width_share: float) -> void:
	var outer := Color(color, alpha)
	var inner := Color(color, 0.0)
	var band: float = minf(size.x, size.y) * width_share
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
