class_name EchoVisual
extends Node2D
## The Echo's look ("silhouette + glow"), all procedural vector shapes:
## a small dark body seen top-down but slightly from the front, with long
## ears, two thin antennae (Line2D) with glowing tips that sway, a flowing tail
## (VerletChain) that leaves a faint gold particle trail, and a softly glowing
## gold core in the chest. Floats: bobs when idle, leans where it moves.
## Pulse: the core flares, the antennae lift, a quick squash-and-stretch.
## Downed: the core dims and flickers, the body sinks.
## The dark silhouette is drawn in the world (lit by lights); the glowing
## parts on an own CanvasLayer that the darkness does not dim. Visual only.

@export_group("Body")
@export var body_color: Color = Color(0.05, 0.055, 0.075)
@export var head_radius: float = 6.5
@export var head_offset: Vector2 = Vector2(0.0, -9.0)
## Torso ellipse: half width and half height.
@export var torso_radii: Vector2 = Vector2(5.5, 8.0)
@export var torso_offset: Vector2 = Vector2(0.0, 3.0)

@export_group("Ears")
@export var ear_length: float = 16.0
@export var ear_width: float = 5.0
## Angle of the hanging ears from straight down, outward (degrees).
@export var ear_angle_degrees: float = 62.0
## Extra ear angle (degrees) per 100 px/s of sideways speed (they trail).
@export var ear_sway_degrees: float = 12.0

@export_group("Core")
@export var core_color: Color = Color(1.0, 0.78, 0.35)
@export var core_energy: float = 2.2
@export var core_radius: float = 3.0
@export var core_offset: Vector2 = Vector2(0.0, 1.0)
@export var halo_radius: float = 6.0
@export_range(0.0, 1.0) var halo_alpha: float = 0.18
## Slow breathing of the core, cycles per second.
@export var core_breath_speed: float = 0.45
## Extra core energy right at a pulse (fades out).
@export var pulse_flare_energy: float = 7.0
## How fast the flare fades (per second).
@export var flare_decay: float = 4.0

@export_group("Antennae")
@export var antenna_base: Vector2 = Vector2(2.5, -14.0)
@export var antenna_length: float = 20.0
## Angle from straight up, outward (degrees).
@export var antenna_angle_degrees: float = 22.0
@export var antenna_width: float = 1.2
@export var antenna_tip_radius: float = 1.7
@export var antenna_tip_energy: float = 3.0
@export var antenna_stiffness: float = 70.0
@export var antenna_damping: float = 9.0
## How far the tips trail behind per px/s of speed...
@export var antenna_drag: float = 0.03
## ...at most (pixels).
@export var antenna_max_trail: float = 9.0
## Pixels the tips lift at a pulse (fades with the flare).
@export var pulse_lift: float = 9.0

@export_group("Tail")
@export var tail_segments: int = 10
@export var tail_segment_length: float = 4.5
@export var tail_width: float = 3.5
@export var tail_anchor: Vector2 = Vector2(0.0, 10.0)
## Share of velocity kept per step (lower = more water drag).
@export_range(0.0, 1.0) var tail_damping: float = 0.86
## Pull of the tail downwards (behind her) when idle.
@export var tail_rest_force: float = 260.0
@export var tail_sway_force: float = 160.0
@export var tail_sway_speed: float = 0.6

@export_group("Trail")
@export var trail_amount: int = 28
@export var trail_lifetime: float = 1.2
@export var trail_color: Color = Color(1.0, 0.8, 0.4)
@export var trail_energy: float = 2.2
@export_range(0.0, 1.0) var trail_alpha: float = 0.5
@export var trail_size: float = 1.6
## The trail only emits above this speed (px/s).
@export var trail_min_speed: float = 40.0

@export_group("Float")
@export var bob_amount: float = 2.5
@export var bob_speed: float = 0.5
## Lean at full sideways speed (degrees).
@export var lean_degrees: float = 14.0
## Speed that counts as "full speed" for the lean (px/s).
@export var lean_full_speed: float = 260.0

@export_group("Pulse Squash")
@export var squash_scale: Vector2 = Vector2(1.3, 0.75)
@export var stretch_scale: Vector2 = Vector2(0.88, 1.15)
@export var squash_time: float = 0.05
@export var stretch_time: float = 0.08
@export var settle_time: float = 0.15

@export_group("Downed")
@export var downed_sink: float = 5.0
@export var downed_scale: Vector2 = Vector2(1.15, 0.75)
## Share of the core energy left while downed.
@export_range(0.0, 1.0) var downed_core: float = 0.25
## Flickers per second of the dim core.
@export var downed_flicker_speed: float = 9.0
## How far the antennae droop while downed (pixels).
@export var downed_droop: float = 10.0

var squash: Vector2 = Vector2.ONE
var _player: Player
var _time: float = 0.0
var _flare: float = 0.0
var _down_amount: float = 0.0
var _tween: Tween
var _tips: Array[SpringPoint] = []
var _antennae: Array[Line2D] = []
var _tail: VerletChain
var _tail_line: Line2D
var _glow: Node2D
var _trail: CPUParticles2D
var _transform: Transform2D = Transform2D.IDENTITY


func _ready() -> void:
	_player = get_parent() as Player
	if _player:
		_player.pulse_emitted.connect(_on_pulse_emitted)
	for side: float in [-1.0, 1.0]:
		var line := _make_line(antenna_width, body_color)
		_antennae.append(line)
		# Springs work relative to the player, so moving only bends them by the drag.
		_tips.append(SpringPoint.new(_antenna_rest(side)))
	_tail = VerletChain.new(tail_segments, tail_segment_length, global_position + tail_anchor, Vector2.DOWN)
	_tail.damping = tail_damping
	_tail_line = _make_line(tail_width, body_color)
	_tail_line.width_curve = _taper_curve()
	_tail_line.show_behind_parent = true

	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_glow = Node2D.new()
	layer.add_child(_glow)
	_glow.draw.connect(_draw_glow)
	_trail = _make_trail()
	layer.add_child(_trail)


func _process(delta: float) -> void:
	_time += delta
	_flare = maxf(_flare - flare_decay * delta, 0.0)
	var downed: bool = _player != null and _player.health.is_downed
	_down_amount = move_toward(_down_amount, 1.0 if downed else 0.0, delta * 3.0)
	var velocity: Vector2 = _player.velocity if _player else Vector2.ZERO
	var speed_ratio: float = clampf(velocity.length() / lean_full_speed, 0.0, 1.0)

	# Float: bob when idle, lean where it moves, sink when downed.
	var bob: float = sin(_time * TAU * bob_speed) * bob_amount * (1.0 - speed_ratio * 0.7)
	var lean: float = deg_to_rad(lean_degrees) * clampf(velocity.x / lean_full_speed, -1.0, 1.0)
	var body_scale: Vector2 = squash * Vector2.ONE.lerp(downed_scale, _down_amount)
	_transform = Transform2D(lean * (1.0 - _down_amount), body_scale, 0.0, Vector2(0.0, bob + downed_sink * _down_amount))

	for i: int in _tips.size():
		var side: float = -1.0 if i == 0 else 1.0
		var base: Vector2 = global_position + _transform * Vector2(antenna_base.x * side, antenna_base.y)
		var lift: float = pulse_lift * minf(_flare, 1.0) - downed_droop * _down_amount
		var trail: Vector2 = (-velocity * antenna_drag).limit_length(antenna_max_trail)
		var target: Vector2 = _antenna_rest(side) + trail + Vector2(0.0, -lift)
		_tips[i].step(target, antenna_stiffness, antenna_damping, delta)
		var tip: Vector2 = global_position + _tips[i].position
		# The lower half stays stiff (rest direction); only the tip sways.
		var mid: Vector2 = base + Vector2.UP.rotated(deg_to_rad(antenna_angle_degrees) * side) * antenna_length * 0.5
		_antennae[i].points = PackedVector2Array([base, mid.lerp(tip, 0.25), tip])

	var sway := Vector2(sin(_time * TAU * tail_sway_speed) * tail_sway_force, tail_rest_force)
	_tail.step(global_position + _transform * tail_anchor, sway, delta)
	_tail_line.points = _tail.points

	_trail.global_position = _tail.points[_tail.points.size() - 1]
	_trail.emitting = velocity.length() > trail_min_speed and not downed
	_glow.global_position = global_position
	queue_redraw()
	_glow.queue_redraw()


## Rest position of an antenna tip, relative to the player.
func _antenna_rest(side: float) -> Vector2:
	var base := Vector2(antenna_base.x * side, antenna_base.y)
	return _transform * base + Vector2.UP.rotated(deg_to_rad(antenna_angle_degrees) * side) * antenna_length


func _on_pulse_emitted(_origin: Vector2) -> void:
	_flare = 1.0
	if _tween:
		_tween.kill()
	squash = Vector2.ONE
	_tween = create_tween()
	_tween.tween_property(self, "squash", squash_scale, squash_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "squash", stretch_scale, stretch_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "squash", Vector2.ONE, settle_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Dark silhouette (world, lit by lights) ----------------------------------

func _draw() -> void:
	var velocity_x: float = _player.velocity.x if _player else 0.0
	var ear_extra: float = deg_to_rad(ear_sway_degrees) * velocity_x / 100.0
	for side: float in [-1.0, 1.0]:
		# Negative angle = outward on that side (Vector2.DOWN rotated).
		var angle: float = -deg_to_rad(ear_angle_degrees) * side - ear_extra
		var attach := Vector2(head_radius * 0.75 * side, head_offset.y + 1.0)
		draw_colored_polygon(_xf(_leaf(attach, Vector2.DOWN.rotated(angle), ear_length, ear_width)), body_color)
	draw_colored_polygon(_xf(_ellipse(torso_offset, torso_radii, 20)), body_color)
	draw_colored_polygon(_xf(_ellipse(head_offset, Vector2(head_radius, head_radius * 0.95), 20)), body_color)


func _xf(points: PackedVector2Array) -> PackedVector2Array:
	return _transform * points


static func _ellipse(center: Vector2, radii: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in steps:
		var angle: float = TAU * i / steps
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


## A leaf / ear shape from base along direction.
static func _leaf(base: Vector2, direction: Vector2, length: float, width: float) -> PackedVector2Array:
	var side: Vector2 = direction.orthogonal() * width * 0.5
	return PackedVector2Array([
		base - side * 0.6, base + direction * length * 0.45 - side,
		base + direction * length, base + direction * length * 0.45 + side, base + side * 0.6,
	])


# --- Glowing parts (unlit layer) ---------------------------------------------

static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw_glow() -> void:
	var breath: float = 0.85 + 0.15 * sin(_time * TAU * core_breath_speed)
	var energy: float = core_energy * breath + pulse_flare_energy * _flare
	if _down_amount > 0.0:
		var flicker: float = 0.6 + 0.4 * sin(_time * TAU * downed_flicker_speed) * sin(_time * 3.7)
		energy = lerpf(energy, core_energy * downed_core * flicker, _down_amount)
	var core: Vector2 = _transform * core_offset
	_glow.draw_circle(core, halo_radius * (1.0 + _flare * 0.6), _hdr(core_color, 1.0, halo_alpha * clampf(energy / core_energy, 0.2, 1.5)))
	_glow.draw_circle(core, core_radius * (1.0 + _flare * 0.4), _hdr(core_color, energy, 1.0))
	var tip_energy: float = antenna_tip_energy * (1.0 + _flare) * lerpf(1.0, downed_core, _down_amount)
	for tip: SpringPoint in _tips:
		_glow.draw_circle(tip.position, antenna_tip_radius, _hdr(core_color, tip_energy, 1.0))


# --- Building blocks ---------------------------------------------------------

func _make_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.top_level = true
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	add_child(line)
	return line


func _taper_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	return curve


func _make_trail() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = trail_amount
	particles.lifetime = trail_lifetime
	particles.local_coords = false
	particles.emitting = false
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 8.0
	particles.scale_amount_min = trail_size * 0.6
	particles.scale_amount_max = trail_size
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([_hdr(trail_color, trail_energy, trail_alpha), _hdr(trail_color, trail_energy, 0.0)])
	particles.color_ramp = ramp
	return particles
