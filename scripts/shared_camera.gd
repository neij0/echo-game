class_name SharedCamera
extends Camera3D
## One orthographic, tilted camera for both players: follows their midpoint
## and widens its view so both stay on screen, up to max_size (the players'
## leash keeps them within that). Does the small shake on every Echo pulse;
## other systems shake it through the "shared_camera" group (call_group
## "shake_with"), so they do not depend on this script. Its AudioListener3D
## sits at the point it looks at (not at the camera, which is far away), so
## positional sounds are heard from where the players are.
## Movers ask it how input maps to the floor and how fast a direction must be
## to look right on screen (ViewMotion): keys_to_world, stick_to_world,
## speed_scale.

@export_group("Angle")
## Degrees the camera looks down from the horizon.
@export var pitch_degrees: float = 45.0
## Degrees turned round the vertical axis (45 = isometric, 0 = north is up).
@export var yaw_degrees: float = 45.0
@export var distance: float = 40.0
## Height above the floor the camera aims at.
@export var focus_height: float = 0.8
## How fast a new yaw / pitch is reached.
@export var turn_speed: float = 6.0

@export_group("Movement")
## 1 = every direction looks equally fast on screen, 0 = no compensation.
@export_range(0.0, 1.0) var speed_compensation: float = 1.0
## Keys: true = plain directions (two keys run along the walls at yaw 45),
## false = the exact screen direction, like the stick.
@export var keys_follow_walls: bool = true

@export_group("Follow")
## How fast the camera catches up with the midpoint (higher = snappier).
@export var follow_speed: float = 5.0
## How fast the view widens and narrows.
@export var zoom_speed: float = 2.5
## Height of the view in world units (the 2D game showed 14.4 at zoom 1).
@export var min_size: float = 14.0
## Widest view allowed.
@export var max_size: float = 21.0
## Space kept free around the players, in world units on the screen plane.
@export var margin: Vector2 = Vector2(5.2, 4.0)

@export_group("Shake")
@export var shake_enabled: bool = true
## Maximum offset in world units at the start of the shake.
@export var shake_strength: float = 0.06
@export var shake_duration: float = 0.15

var _focus: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _snapped: bool = false
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_amount: float = 0.0
var _listener: AudioListener3D
## Players whose pulse already shakes this camera (instance ids).
var _heard: Dictionary = {}


static func find(tree: SceneTree) -> SharedCamera:
	return tree.get_first_node_in_group("shared_camera") as SharedCamera if tree else null


func _ready() -> void:
	add_to_group("shared_camera")
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = min_size
	near = 0.1
	far = distance * 3.0
	_yaw = deg_to_rad(yaw_degrees)
	_pitch = deg_to_rad(pitch_degrees)
	rotation = Vector3(-_pitch, _yaw, 0.0)
	current = true
	_listener = AudioListener3D.new()
	_listener.top_level = true
	add_child(_listener)
	_listener.make_current()


func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


## The point on the floor plane (raised by focus_height) the camera looks at.
func get_focus() -> Vector3:
	return _focus


## Floor direction for a player's move keys (length = how hard they push).
func keys_to_world(input: Vector2) -> Vector3:
	if keys_follow_walls:
		return ViewMotion.plain(input, _yaw)
	return ViewMotion.screen_exact(input, _yaw, _pitch)


## Floor direction for a stick: exactly where it points on screen.
func stick_to_world(input: Vector2) -> Vector3:
	return ViewMotion.screen_exact(input, _yaw, _pitch)


## Speed multiplier for anything moving in direction (players, creatures).
func speed_scale(direction: Vector3) -> float:
	return ViewMotion.speed_scale(direction, _yaw, _pitch, speed_compensation)


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
	var turn: float = 1.0 - exp(-turn_speed * delta)
	_yaw = lerp_angle(_yaw, deg_to_rad(yaw_degrees), turn)
	_pitch = lerpf(_pitch, deg_to_rad(pitch_degrees), turn)
	rotation = Vector3(-_pitch, _yaw, 0.0)

	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return
	var middle := Vector3.ZERO
	for player: Player in players:
		middle += player.global_position
		_listen_to(player)
	middle /= float(players.size())
	middle.y += focus_height

	# How much screen the players need, measured on the camera's own axes.
	var half := Vector2.ZERO
	for player: Player in players:
		var offset: Vector3 = player.global_position - middle
		half.x = maxf(half.x, absf(offset.dot(global_basis.x)))
		half.y = maxf(half.y, absf(offset.dot(global_basis.y)))
	var view: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	var needed: float = maxf((half.y + margin.y) * 2.0, (half.x + margin.x) * 2.0 / aspect)
	var target_size: float = clampf(needed, min_size, max_size)

	if not _snapped:
		# First frame: jump straight to the players instead of sliding in.
		_snapped = true
		_focus = middle
		size = target_size
	else:
		_focus = _focus.lerp(middle, 1.0 - exp(-follow_speed * delta))
		size = lerpf(size, target_size, 1.0 - exp(-zoom_speed * delta))
	global_position = _focus + global_basis.z * distance
	_listener.global_transform = Transform3D(global_basis, _focus)
	_update_shake(delta)


func _listen_to(player: Player) -> void:
	if _heard.has(player.get_instance_id()):
		return
	_heard[player.get_instance_id()] = true
	player.pulse_emitted.connect(_on_pulse_emitted)


func _on_pulse_emitted(_origin: Vector3) -> void:
	shake()


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	# Quadratic falloff: strongest at the start, settles smoothly.
	var amount: float = _shake_amount * pow(_shake_left / _shake_total, 2.0)
	h_offset = randf_range(-1.0, 1.0) * amount
	v_offset = randf_range(-1.0, 1.0) * amount
