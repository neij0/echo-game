class_name EscapeEvent
extends Node2D
## The collapse escape (each stage's level-2 twist, LevelDefinition.escape_event):
## after the last Echo Shard the cave starts to fall in. Falling rock and dust
## around the camera, a rolling rumble, repeated camera shakes, every creature
## in the level hunts the nearest player (frenzy), the lockdown breaks open,
## and the Echo's arrow points to the exit at once and stays on. A timer runs
## (per mode, from the LevelDefinition); at zero every player is downed by the
## collapse (the normal restart rules follow). Reaching the ancient light in
## time stops it (StageManager). Lives on a CanvasLayer with
## follow_viewport_enabled (the debris is unlit, so it reads in the dark).

signal started(time: float)
signal stopped
signal timed_out

@export_group("Shake")
@export var start_shake_strength: float = 10.0
@export var start_shake_time: float = 0.8
## A smaller shake every few seconds (random between the two).
@export var shake_strength: float = 4.0
@export var shake_time: float = 0.4
@export var shake_interval_min: float = 1.5
@export var shake_interval_max: float = 3.0

@export_group("Sound")
@export var rumble_stream: AudioStream
@export var rumble_volume_db: float = -4.0

@export_group("Falling Rock")
@export var debris_amount: int = 70
@export var debris_lifetime: float = 1.1
@export var debris_color: Color = Color(0.55, 0.5, 0.45, 0.8)
## Size at the start of the fall (near the camera) and at the floor.
@export var debris_size_start: float = 7.0
@export var debris_size_end: float = 2.0
@export var dust_amount: int = 24
@export var dust_lifetime: float = 2.2
@export var dust_color: Color = Color(0.7, 0.65, 0.6, 0.12)
@export var dust_size: float = 40.0
## Particles fall over the screen plus this margin (pixels, world space).
@export var spawn_margin: float = 100.0

var is_active: bool = false
var time_left: float = 0.0
var total_time: float = 0.0
var _shake_left: float = 0.0
var _rumble: AudioStreamPlayer
var _debris: CPUParticles2D
var _dust: CPUParticles2D


func _ready() -> void:
	_rumble = AudioStreamPlayer.new()
	_rumble.stream = rumble_stream
	_rumble.volume_db = rumble_volume_db
	_rumble.finished.connect(_on_rumble_finished)
	add_child(_rumble)
	_debris = _make_particles(debris_amount, debris_lifetime, debris_color, null)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, debris_size_end / maxf(debris_size_start, 0.01)))
	_debris.scale_amount_min = debris_size_start * 0.6
	_debris.scale_amount_max = debris_size_start
	_debris.scale_amount_curve = shrink
	_dust = _make_particles(dust_amount, dust_lifetime, dust_color, LightTextures.radial(64, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	_dust.scale_amount_min = dust_size / 64.0 * 0.6
	_dust.scale_amount_max = dust_size / 64.0
	_dust.scale_amount_curve = grow


func _make_particles(amount: int, lifetime: float, color: Color, texture: Texture2D) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.emitting = false
	particles.texture = texture
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.direction = Vector2.DOWN
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 25.0
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	particles.color_ramp = fade
	add_child(particles)
	return particles


## Starts the collapse with this many seconds to reach the exit.
func start(seconds: float) -> void:
	if is_active:
		return
	is_active = true
	total_time = seconds
	time_left = seconds
	_shake_left = randf_range(shake_interval_min, shake_interval_max)
	_shake(start_shake_strength, start_shake_time)
	if _rumble.stream:
		_rumble.play()
	_debris.emitting = true
	_dust.emitting = true
	get_tree().call_group("creatures", "set_frenzy", true)
	get_tree().call_group("lockdown_rooms", "cancel")
	get_tree().call_group("goal_echo", "set_forced", true)
	started.emit(seconds)


## Ends it (exit reached, or a new level is built).
func stop() -> void:
	if not is_active:
		return
	is_active = false
	_rumble.stop()
	_debris.emitting = false
	_dust.emitting = false
	get_tree().call_group("goal_echo", "set_forced", false)
	stopped.emit()


func _process(delta: float) -> void:
	_follow_camera()
	if not is_active:
		return
	time_left = maxf(time_left - delta, 0.0)
	_shake_left -= delta
	if _shake_left <= 0.0:
		_shake_left = randf_range(shake_interval_min, shake_interval_max)
		_shake(shake_strength, shake_time)
	if time_left <= 0.0:
		_time_out()


func _time_out() -> void:
	stop()
	timed_out.emit()
	for player: Player in Players.all(get_tree()):
		player.health.down(PlayerHealth.Cause.COLLAPSE)


func _follow_camera() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var half: Vector2 = get_viewport_rect().size / camera.zoom * 0.5 + Vector2.ONE * spawn_margin
	for particles: CPUParticles2D in [_debris, _dust]:
		particles.global_position = camera.get_screen_center_position()
		particles.emission_rect_extents = half


func _on_rumble_finished() -> void:
	if is_active:
		_rumble.play()


func _shake(strength: float, duration: float) -> void:
	get_tree().call_group("shared_camera", "shake_with", strength, duration)
