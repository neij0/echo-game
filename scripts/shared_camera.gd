class_name SharedCamera
extends Camera2D
## One camera for both players: follows their midpoint and zooms out smoothly
## so both stay on screen, down to min_zoom (the players' leash keeps them
## within that). Also does the small shake on every Echo pulse. Other systems
## shake it through the "shared_camera" group (call_group "shake_with"), so
## they do not depend on this script.

@export var stage_manager: StageManager
## How fast the camera catches up with the midpoint (higher = snappier).
@export var follow_speed: float = 5.0
## How fast the zoom changes.
@export var zoom_speed: float = 2.5
@export var max_zoom: float = 1.0
## Furthest zoom-out allowed.
@export var min_zoom: float = 0.6
## Screen space kept free around the players, in pixels.
@export var margin: Vector2 = Vector2(260.0, 200.0)

@export_group("Shake")
@export var shake_enabled: bool = true
## Maximum offset in pixels at the start of the shake.
@export var shake_strength: float = 3.0
@export var shake_duration: float = 0.15

var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_amount: float = 0.0
var _snapped: bool = false


func _ready() -> void:
	add_to_group("shared_camera")
	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)


func _on_player_registered(player: Player) -> void:
	player.pulse_emitted.connect(_on_pulse_emitted)


func _on_pulse_emitted(_origin: Vector2) -> void:
	shake()


## Jump straight to the players on the next frame (e.g. a new level).
func snap_to_players() -> void:
	_snapped = false


func shake() -> void:
	shake_with(shake_strength, shake_duration)


## A shake with its own strength (e.g. the big one on an Exposed kill).
func shake_with(strength: float, duration: float) -> void:
	if shake_enabled and duration > 0.0:
		_shake_left = duration
		_shake_total = duration
		_shake_amount = strength


func _process(delta: float) -> void:
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return
	var bounds := Rect2(players[0].global_position, Vector2.ZERO)
	for player: Player in players:
		bounds = bounds.expand(player.global_position)

	var view: Vector2 = get_viewport_rect().size
	var needed: Vector2 = bounds.size + margin * 2.0
	var target_zoom: float = clampf(minf(view.x / needed.x, view.y / needed.y), min_zoom, max_zoom)

	if not _snapped:
		# First frame: jump straight to the players instead of sliding in.
		_snapped = true
		global_position = bounds.get_center()
		zoom = Vector2.ONE * target_zoom
	else:
		global_position = global_position.lerp(bounds.get_center(), 1.0 - exp(-follow_speed * delta))
		zoom = zoom.lerp(Vector2.ONE * target_zoom, 1.0 - exp(-zoom_speed * delta))
	_update_shake(delta)


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		offset = Vector2.ZERO
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	# Quadratic falloff: strongest at the start, settles smoothly.
	var amount: float = _shake_amount * pow(_shake_left / _shake_total, 2.0)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount
