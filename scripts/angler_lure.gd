class_name AnglerLure
extends Node2D
## The Angler's lure: a long bony stalk from its forehead with a glowing orb at
## the end, the brightest thing on the boss. The stalk is a chain of points,
## each pulled by a spring towards its rest shape (up from the head in the 3/4
## view, arching forward, the tip curling down); the springs get softer towards
## the tip, so the orb lags behind turns and sways like it has weight. Droop
## (stunned) lowers the rest shape. The orb carries a real PointLight2D (with
## shadows) that lights the Angler's own head and the arena. The stalk is drawn
## here, in the world (lit); the orb's glow is drawn by AnglerGlow.
## Driven by AnglerVisual (update_pose, set_glow).

@export_group("Stalk")
@export var segments: int = 9
## Rest shape: height above the head (3/4 view, up the screen), reach forward,
## and how far the tip curls down again.
@export var rest_height: float = 118.0
@export var rest_forward: float = 118.0
@export var tip_curl: float = 40.0
## Spring stiffness at the base and at the tip (softer = more lag).
@export var base_stiffness: float = 160.0
@export var tip_stiffness: float = 22.0
@export var damping: float = 6.5
## Slow idle sway: pixels sideways at the tip, cycles per second.
@export var sway_amount: float = 9.0
@export var sway_speed: float = 0.32
@export var base_width: float = 7.5
@export var tip_width: float = 2.2
@export var stalk_color: Color = Color(0.1, 0.095, 0.085)
@export var joint_color: Color = Color(0.16, 0.15, 0.13)
## Stunned: the stalk sags this share of its height and falls forward.
@export_range(0.0, 1.0) var droop_height_share: float = 0.75

@export_group("Light")
@export var light_radius: float = 320.0
@export_range(0.0, 1.0) var light_hard_edge: float = 0.15
@export var light_shadows: bool = true

var points: PackedVector2Array = PackedVector2Array()
var _velocities: PackedVector2Array = PackedVector2Array()
var _time: float = 0.0
var _light: PointLight2D
var _batch := ShapeBatch.new()
## Set by AnglerVisual.
var stalk_visible: bool = true
## The light sits this far from the orb (the fake lure of phase 2 moves it).
var light_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(256, light_hard_edge)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, light_radius)
	_light.shadow_enabled = light_shadows
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(_light)
	_light.add_to_group("falloff_lights")


func reset(base: Vector2, forward: Vector2) -> void:
	points.resize(segments)
	_velocities.resize(segments)
	for i: int in segments:
		points[i] = base + _rest_offset(i, forward, 0.0)
		_velocities[i] = Vector2.ZERO


## Mirrors the stalk round x = center_x (the Angler turned round).
func mirror_x(center_x: float) -> void:
	for i: int in points.size():
		points[i].x = 2.0 * center_x - points[i].x
		_velocities[i].x = -_velocities[i].x


## base = where the stalk leaves the head (world), forward = the heading.
func update_pose(base: Vector2, forward: Vector2, droop: float, delta: float) -> void:
	_time += delta
	if points.size() != segments:
		reset(base, forward)
	points[0] = base
	_velocities[0] = Vector2.ZERO
	var step: float = minf(delta, 1.0 / 30.0)
	for i: int in range(1, segments):
		var t: float = float(i) / float(segments - 1)
		var target: Vector2 = base + _rest_offset(i, forward, droop)
		var stiffness: float = lerpf(base_stiffness, tip_stiffness, t)
		_velocities[i] += ((target - points[i]) * stiffness - _velocities[i] * damping) * step
		points[i] += _velocities[i] * step
	# Keep the stalk from stretching (each link at most its rest length).
	for i: int in range(1, segments):
		var rest: float = (_rest_offset(i, forward, droop) - _rest_offset(i - 1, forward, droop)).length()
		var offset: Vector2 = points[i] - points[i - 1]
		if offset.length() > rest:
			points[i] = points[i - 1] + offset.normalized() * rest
	_light.position = to_local(get_orb_position() + light_offset)
	queue_redraw()


func get_orb_position() -> Vector2:
	return points[points.size() - 1] if not points.is_empty() else global_position


## The orb's light colour / energy (0 = off).
func set_glow(color: Color, energy: float) -> void:
	_light.color = color
	_light.energy = energy
	_light.visible = energy > 0.001


func get_light() -> PointLight2D:
	return _light


func _rest_offset(i: int, forward: Vector2, droop: float) -> Vector2:
	var t: float = float(i) / float(maxi(segments - 1, 1))
	var up := Vector2(0.0, -1.0)
	var height: float = rest_height * (1.0 - (1.0 - t) * (1.0 - t)) * (1.0 - droop_height_share * droop)
	height -= tip_curl * pow(t, 4.0) * (1.0 + droop)
	var reach: float = rest_forward * pow(t, 1.4) * (1.0 + 0.25 * droop)
	var sway: float = sin(_time * TAU * sway_speed + t * 1.5) * sway_amount * t * (1.0 - droop)
	return up * height + forward * reach + forward.orthogonal() * sway


func _draw() -> void:
	if not stalk_visible or points.size() < 2:
		return
	var local := PackedVector2Array()
	for point: Vector2 in points:
		local.append(to_local(point))
	_batch.add_band(local, base_width, tip_width, stalk_color)
	# Bony knobs along the stalk.
	for i: int in range(1, local.size() - 1, 2):
		var t: float = float(i) / float(local.size() - 1)
		_batch.add_dot(local[i], lerpf(base_width, tip_width, t) * 0.75, joint_color, 8)
	_batch.draw(self)
