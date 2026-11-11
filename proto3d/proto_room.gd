class_name ProtoRoom
extends Node3D
## 3D isometric test room (prototype only, not part of the 2D game): builds one
## dark room with rocks of different heights, the Echo and the Guardian as
## capsules, one creature, the sonar, fog, marine snow and the camera.
## Run with F6. "-- capture <folder>" saves screenshots and measures the FPS
## (ProtoCapture).

const SURFACE_SHADER: Shader = preload("res://proto3d/proto_surface.gdshader")
const CHARACTER_SHADER: Shader = preload("res://proto3d/proto_character.gdshader")
const SEE_THROUGH_SHADER: Shader = preload("res://proto3d/proto_see_through.gdshader")
const SNOW_SHADER: Shader = preload("res://proto3d/proto_snow.gdshader")

## Rocks: x, z, half width, half depth, height, corner count.
const ROCKS: Array[Array] = [
	[-4.0, -3.0, 2.2, 1.6, 2.6, 9],
	[4.5, -4.5, 1.5, 1.5, 1.4, 8],
	[-6.5, 4.0, 1.3, 2.6, 3.2, 9],
	[2.0, 3.5, 1.2, 1.0, 0.4, 7],
	[6.5, 3.0, 1.8, 1.2, 2.0, 8],
	[-1.0, -8.0, 2.8, 1.0, 1.0, 9],
	[0.5, -1.0, 0.8, 0.8, 1.9, 7],
]

@export_group("Room")
@export var room_size: float = 24.0
@export var wall_thickness: float = 1.5
## The two walls behind the room (seen from the camera).
@export var far_wall_height: float = 3.5
## The two walls nearest the camera stay low so they hide nothing.
@export var near_wall_height: float = 0.5
@export var layout_seed: int = 7
@export var rock_jitter: float = 0.16
@export var rock_top_inset: float = 0.16
@export var rock_height_jitter: float = 0.1
@export var floor_color: Color = Color(0.15, 0.19, 0.25)
@export var rock_color: Color = Color(0.24, 0.29, 0.36)
@export var sonar_color: Color = Color(0.25, 0.85, 1.0)
## How strongly the pulse lights flat ground compared with rock.
@export var floor_fill_energy: float = 0.07
@export var rock_fill_energy: float = 0.24

@export_group("Darkness")
@export var ambient_color: Color = Color(0.1, 0.18, 0.32)
@export var ambient_energy: float = 0.06
@export var fog_density: float = 0.05
@export var fog_color: Color = Color(0.35, 0.55, 0.8)
@export var fog_anisotropy: float = 0.5
@export var glow_intensity: float = 0.9
@export var glow_bloom: float = 0.08
@export var glow_threshold: float = 1.0

@export_group("Echo")
@export var echo_start: Vector3 = Vector3(1.5, 0.0, 7.5)
@export var echo_radius: float = 0.3
@export var echo_height: float = 1.0
@export var echo_color: Color = Color(0.3, 0.9, 1.0)
@export var echo_rim_energy: float = 2.2
@export var echo_light_color: Color = Color(1.0, 0.86, 0.62)
## 2D: ~280 px.
@export var echo_light_range: float = 5.6
@export var echo_light_energy: float = 8.0
## Extra light for a moment on every pulse.
@export var pulse_flare: float = 2.0
@export var pulse_flare_time: float = 0.35

@export_group("Guardian")
@export var guardian_start: Vector3 = Vector3(3.5, 0.0, 7.0)
@export var guardian_radius: float = 0.36
@export var guardian_height: float = 1.6
@export var guardian_color: Color = Color(1.0, 0.75, 0.25)
@export var guardian_rim_energy: float = 1.1
@export var guardian_light_color: Color = Color(0.55, 0.7, 1.0)
@export var guardian_light_range: float = 2.2
@export var guardian_light_energy: float = 1.6

@export_group("Creature")
@export var creature_start: Vector3 = Vector3(-8.0, 0.0, -7.0)

@export_group("Marine Snow")
@export var snow_amount: int = 700
@export var snow_height: float = 4.0
@export var snow_size: float = 0.05
@export var snow_lifetime: float = 14.0

var sonar: ProtoSonar
var camera: ProtoCamera
var echo: ProtoPlayer
var guardian: ProtoPlayer
var creature: ProtoCreature
var pulse: ProtoPulse
var _echo_light: OmniLight3D
var _guardian_light: OmniLight3D
var _snow_material: ShaderMaterial
var _snow: GPUParticles3D
var _rng := RandomNumberGenerator.new()
var _info: Label


func _ready() -> void:
	_rng.seed = layout_seed
	_build_environment()
	sonar = ProtoSonar.new()
	sonar.name = "Sonar"
	sonar.edge_color = sonar_color
	add_child(sonar)
	camera = ProtoCamera.new()
	camera.name = "Camera"
	add_child(camera)
	_build_room()
	_build_players()
	_build_creature()
	_build_snow()
	_build_info()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "capture":
		var capture := ProtoCapture.new()
		capture.room = self
		capture.folder = arguments[1]
		add_child(capture)


func _process(_delta: float) -> void:
	_snow_material.set_shader_parameter("light_pos", PackedVector3Array([
		_echo_light.global_position, _guardian_light.global_position]))
	_snow_material.set_shader_parameter("light_range", PackedFloat32Array([
		_echo_light.omni_range, _guardian_light.omni_range]))
	_info.text = _info_text()


func _info_text() -> String:
	return "PROTO 3D   %d FPS\nEcho: WASD + Space (pulse)   Guardian: arrows + Enter (sword)   or two gamepads" % [
		int(Engine.get_frames_per_second())]


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = glow_intensity
	environment.glow_bloom = glow_bloom
	environment.glow_hdr_threshold = glow_threshold
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = fog_density
	environment.volumetric_fog_albedo = fog_color
	environment.volumetric_fog_anisotropy = fog_anisotropy
	environment.volumetric_fog_length = 96.0
	environment.volumetric_fog_ambient_inject = 0.0
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)


func _surface_material(color: Color, fill_energy: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("sonar_color", sonar_color)
	material.set_shader_parameter("fill_energy", fill_energy)
	sonar.register_material(material)
	return material


func _build_room() -> void:
	var floor_material: ShaderMaterial = _surface_material(floor_color, floor_fill_energy)
	var rock_material: ShaderMaterial = _surface_material(rock_color, rock_fill_energy)
	var outer: float = room_size + wall_thickness * 2.0

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(outer, outer)
	var floor_instance := MeshInstance3D.new()
	floor_instance.name = "Floor"
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = floor_material
	add_child(floor_instance)

	for rock: Array in ROCKS:
		var outline: PackedVector2Array = ProtoBuild.rock_outline(
				Vector2(rock[2] as float, rock[3] as float), rock[5] as int, rock_jitter, _rng)
		var height: float = rock[4] as float
		var mesh: ArrayMesh = ProtoBuild.prism_mesh(outline, height, rock_top_inset, rock_height_jitter, _rng)
		var body: StaticBody3D = ProtoBuild.rock_body(outline, height, mesh, rock_material)
		body.name = "Rock"
		body.position = Vector3(rock[0] as float, 0.0, rock[1] as float)
		add_child(body, true)

	# Walls: the camera looks from +x / +z, so those two stay low.
	var half: float = room_size * 0.5 + wall_thickness * 0.5
	var long_side := Vector2(outer * 0.5, wall_thickness * 0.5)
	var short_side := Vector2(wall_thickness * 0.5, room_size * 0.5)
	_add_wall(Vector3(0.0, 0.0, -half), long_side, far_wall_height, rock_material)
	_add_wall(Vector3(0.0, 0.0, half), long_side, near_wall_height, rock_material)
	_add_wall(Vector3(-half, 0.0, 0.0), short_side, far_wall_height, rock_material)
	_add_wall(Vector3(half, 0.0, 0.0), short_side, near_wall_height, rock_material)


func _add_wall(at: Vector3, half_size: Vector2, height: float, material: Material) -> void:
	var outline: PackedVector2Array = ProtoBuild.box_outline(half_size)
	var mesh: ArrayMesh = ProtoBuild.prism_mesh(outline, height, 0.0, 0.0, _rng)
	var body: StaticBody3D = ProtoBuild.rock_body(outline, height, mesh, material)
	body.name = "Wall"
	body.position = at
	add_child(body, true)


func _build_players() -> void:
	echo = _make_player("Echo", "p1_", true, echo_radius, echo_height, echo_color, echo_rim_energy)
	echo.position = echo_start
	_echo_light = _make_light(echo, echo_light_color, echo_light_range, echo_light_energy, echo_height + 0.5, true)
	pulse = ProtoPulse.new()
	pulse.name = "Pulse"
	pulse.player = echo
	pulse.sonar = sonar
	pulse.emitted.connect(_on_pulse_emitted)
	echo.add_child(pulse)

	guardian = _make_player("Guardian", "p2_", false, guardian_radius, guardian_height, guardian_color, guardian_rim_energy)
	guardian.position = guardian_start
	_guardian_light = _make_light(guardian, guardian_light_color, guardian_light_range, guardian_light_energy, guardian_height * 0.7, false)
	var sword := ProtoSword.new()
	sword.name = "Sword"
	sword.player = guardian
	guardian.add_child(sword)


func _make_player(player_name: String, prefix: String, is_echo: bool, radius: float, height: float, color: Color, rim_energy: float) -> ProtoPlayer:
	var player := ProtoPlayer.new()
	player.name = player_name
	player.input_prefix = prefix
	player.is_echo = is_echo
	player.body_radius = radius
	player.camera = camera
	player.collision_layer = 2
	player.collision_mask = 1

	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = height * 0.5
	player.add_child(collider)

	var see_through := ShaderMaterial.new()
	see_through.shader = SEE_THROUGH_SHADER
	see_through.set_shader_parameter("outline_color", color)
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_SHADER
	material.set_shader_parameter("body_color", color.darkened(0.9))
	material.set_shader_parameter("rim_color", color)
	material.set_shader_parameter("rim_energy", rim_energy)
	material.next_pass = see_through
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.material_override = material
	body.position.y = height * 0.5
	player.add_child(body)
	add_child(player)
	return player


func _make_light(player: ProtoPlayer, color: Color, light_range: float, energy: float, height: float, shadows: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.0
	light.shadow_enabled = shadows
	light.light_volumetric_fog_energy = 2.0
	light.position.y = height
	player.add_child(light)
	return light


func _build_creature() -> void:
	creature = ProtoCreature.new()
	creature.name = "Creature"
	creature.position = creature_start
	creature.roam_extent = room_size * 0.5 - 2.0
	creature.camera = camera
	add_child(creature)


func _build_snow() -> void:
	_snow_material = ShaderMaterial.new()
	_snow_material.shader = SNOW_SHADER
	_snow_material.set_shader_parameter("sonar_color", sonar_color)
	_snow_material.set_shader_parameter("light_gain", PackedFloat32Array([0.55, 0.2]))
	sonar.register_material(_snow_material)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(room_size * 0.5, snow_height * 0.5, room_size * 0.5)
	process.direction = Vector3(0.3, -1.0, 0.2)
	process.spread = 60.0
	process.initial_velocity_min = 0.03
	process.initial_velocity_max = 0.14
	process.gravity = Vector3(0.0, -0.01, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.4

	var quad := QuadMesh.new()
	quad.size = Vector2(snow_size, snow_size)
	quad.material = _snow_material
	_snow = GPUParticles3D.new()
	_snow.name = "MarineSnow"
	_snow.amount = snow_amount
	_snow.lifetime = snow_lifetime
	_snow.preprocess = snow_lifetime
	_snow.process_material = process
	_snow.draw_pass_1 = quad
	_snow.position.y = snow_height * 0.5
	_snow.visibility_aabb = AABB(Vector3.ONE * -room_size, Vector3.ONE * room_size * 2.0)
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow)


func _build_info() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Info"
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(16.0, 12.0)
	_info.modulate = Color(0.6, 0.8, 0.9, 0.7)
	layer.add_child(_info)


func _on_pulse_emitted() -> void:
	camera.shake()
	var tween: Tween = create_tween()
	_echo_light.light_energy = echo_light_energy * pulse_flare
	tween.tween_property(_echo_light, "light_energy", echo_light_energy, pulse_flare_time)
