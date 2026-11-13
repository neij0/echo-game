class_name EscapeEvent
extends Node3D
## The collapse escape (each stage's level-2 twist, LevelDefinition.escape_event):
## after the last Echo Shard the cave starts to fall in. Falling rock and dust
## around the camera, a rolling rumble, repeated camera shakes, every creature
## in the level hunts the nearest player (frenzy), the lockdown breaks open,
## and the Echo's arrow points to the exit at once and stays on. A timer runs
## (per mode, from the LevelDefinition); at zero every player is downed by the
## collapse (the normal restart rules follow). Reaching the ancient light in
## time stops it (StageManager). The falling rock and the dust follow the
## camera's focus and are unlit, so they read in the dark.

signal started(time: float)
signal stopped
signal timed_out

@export_group("Shake")
## World units.
@export var start_shake_strength: float = 0.2
@export var start_shake_time: float = 0.8
## A smaller shake every few seconds (random between the two).
@export var shake_strength: float = 0.08
@export var shake_time: float = 0.4
@export var shake_interval_min: float = 1.5
@export var shake_interval_max: float = 3.0

@export_group("Sound")
## A rolling rumble loop, and falling rocks (AudioDirector) around the camera.
@export var rumble_stream: AudioStream
@export var rumble_volume_db: float = -4.0
@export var rock_fall_sound: String = "world_rock_fall"
@export var rock_fall_interval_min: float = 0.4
@export var rock_fall_interval_max: float = 1.4
@export var rock_fall_radius: float = 13.0

@export_group("Falling Rock")
@export var debris_amount: int = 70
@export var debris_lifetime: float = 1.1
@export var debris_color: Color = Color(0.3, 0.28, 0.26, 0.9)
## Size of a piece (units) and the height it falls from.
@export var debris_size: float = 0.11
@export var debris_height: float = 7.0
@export var dust_amount: int = 24
@export var dust_lifetime: float = 2.2
@export var dust_color: Color = Color(0.5, 0.47, 0.43, 0.1)
@export var dust_size: float = 1.6
## Half size of the area round the camera's focus where it falls (units).
@export var fall_area: Vector2 = Vector2(16.0, 11.0)

var is_active: bool = false
var time_left: float = 0.0
var total_time: float = 0.0
var _shake_left: float = 0.0
var _rock_left: float = 0.0
var _rumble: AudioStreamPlayer
var _debris: GPUParticles3D
var _dust: GPUParticles3D


func _ready() -> void:
	_rumble = AudioStreamPlayer.new()
	_rumble.stream = rumble_stream
	_rumble.volume_db = rumble_volume_db
	_rumble.bus = &"SFX"
	_rumble.finished.connect(_on_rumble_finished)
	add_child(_rumble)
	# Rock pieces fall from above to the floor; dust drifts just over it.
	_debris = _make_particles(debris_amount, debris_lifetime, debris_color, debris_size, LightTextures.radial(32, 0.75),
		Vector3(fall_area.x, 0.5, fall_area.y), debris_height, Vector3(0.0, -2.0 * debris_height / (debris_lifetime * debris_lifetime), 0.0))
	_dust = _make_particles(dust_amount, dust_lifetime, dust_color, dust_size, LightTextures.radial(64, 0.0),
		Vector3(fall_area.x, 0.3, fall_area.y), 0.6, Vector3(0.0, 0.15, 0.0))


func _make_particles(amount: int, lifetime: float, color: Color, size: float, texture: Texture2D,
		area: Vector3, height: float, gravity: Vector3) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = area
	process.direction = Vector3.DOWN
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.5
	process.gravity = gravity
	process.scale_min = 0.6
	process.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.15, Color.WHITE)
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.albedo_texture = texture
	material.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.emitting = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-area.x - 2.0, -height - 2.0, -area.z - 2.0), Vector3(area.x * 2.0 + 4.0, height + 4.0, area.z * 2.0 + 4.0))
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	particles.position.y = height
	particles.set_meta("height", height)
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
	_rock_left -= delta
	if _rock_left <= 0.0:
		_rock_left = randf_range(rock_fall_interval_min, rock_fall_interval_max)
		_play_rock_fall()
	if time_left <= 0.0:
		_time_out()


func _time_out() -> void:
	stop()
	timed_out.emit()
	for player: Player in Players.all(get_tree()):
		player.health.down(PlayerHealth.Cause.COLLAPSE)


func _follow_camera() -> void:
	var camera: SharedCamera = SharedCamera.find(get_tree())
	if camera == null:
		return
	var focus: Vector3 = camera.get_focus()
	for particles: GPUParticles3D in [_debris, _dust]:
		particles.global_position = Vector3(focus.x, float(particles.get_meta("height")), focus.z)


func _play_rock_fall() -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	var camera: SharedCamera = SharedCamera.find(get_tree())
	if audio == null or camera == null:
		return
	var angle: float = randf() * TAU
	var at: Vector3 = camera.get_focus() + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.2, 1.0) * rock_fall_radius
	audio.play(rock_fall_sound, Vector3(at.x, 0.0, at.z))


func _on_rumble_finished() -> void:
	if is_active:
		_rumble.play()


func _shake(strength: float, duration: float) -> void:
	get_tree().call_group("shared_camera", "shake_with", strength, duration)
