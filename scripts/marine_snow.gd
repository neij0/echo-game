class_name MarineSnow
extends GPUParticles3D
## Environment light: tiny glowing particles ("marine snow") slowly drifting
## down and swaying. They live in a box round the camera's focus and follow
## it, so they cover the whole level at a fixed cost. Almost invisible in the
## dark, they catch the players' lights and flash when a sonar wave passes
## (marine_snow.gdshader). All values come from the WorldConfig ("Marine
## Snow" group), in world units.

const SNOW_SHADER: Shader = preload("res://shaders/marine_snow.gdshader")

## The box the particles live in: its side on the floor and its height.
@export var box_size: float = 44.0
@export var box_height: float = 4.0
## Seconds a particle drifts before it starts again somewhere in the box.
@export var particle_lifetime: float = 14.0
## How much the players' lights brighten the snow: a light of
## light_reference_energy adds light_gain at its centre.
@export var light_gain: float = 0.55
@export var light_reference_energy: float = 8.0
## How strongly a passing sonar wave lights the snow.
@export var sonar_gain: float = 1.2

var count: int = 2200
var color: Color = Color(0.7, 0.9, 1.0)
var alpha_min: float = 0.01
var alpha_max: float = 0.05
var size_min: float = 0.03
var size_max: float = 0.07
var fall_speed: float = 0.18
var sway_amount: float = 0.24
var sway_speed: float = 0.12
var twinkle_speed: float = 0.25

var _material: ShaderMaterial


func _ready() -> void:
	add_to_group("world_listeners")
	_material = ShaderMaterial.new()
	_material.shader = SNOW_SHADER
	var sonar: Sonar = Sonar.find(get_tree())
	if sonar:
		sonar.register_material(_material)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild()


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	count = world.snow_count
	color = world.snow_color
	alpha_min = world.snow_alpha_min
	alpha_max = world.snow_alpha_max
	size_min = world.snow_size_min
	size_max = world.snow_size_max
	fall_speed = world.snow_fall_speed
	sway_amount = world.snow_sway_amount
	sway_speed = world.snow_sway_speed
	twinkle_speed = world.snow_twinkle_speed
	edge_tint(world.edge_color)
	_rebuild()


## The colour of the flash a sonar wave gives the snow.
func edge_tint(sonar_color: Color) -> void:
	_material.set_shader_parameter("sonar_color", sonar_color)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d() as SharedCamera
	if camera:
		var focus: Vector3 = camera.get_focus()
		global_position = Vector3(focus.x, box_height * 0.5, focus.z)

	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var ranges := PackedFloat32Array([0.0, 0.0])
	var gains := PackedFloat32Array([0.0, 0.0])
	var index: int = 0
	for node: Node in get_tree().get_nodes_in_group("player_lights"):
		var light := node as PlayerLight
		if light == null or index >= 2:
			continue
		positions[index] = light.global_position
		ranges[index] = light.radius
		gains[index] = light_gain * clampf(light.base_energy / light_reference_energy, 0.0, 1.0)
		index += 1
	_material.set_shader_parameter("light_pos", positions)
	_material.set_shader_parameter("light_range", ranges)
	_material.set_shader_parameter("light_gain", gains)


func _rebuild() -> void:
	_material.set_shader_parameter("tint", color)
	_material.set_shader_parameter("glow_min", alpha_min)
	_material.set_shader_parameter("glow_max", alpha_max)
	_material.set_shader_parameter("twinkle_speed", twinkle_speed)
	_material.set_shader_parameter("sway_amount", sway_amount)
	_material.set_shader_parameter("sway_speed", sway_speed)
	_material.set_shader_parameter("sonar_gain", sonar_gain)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(box_size * 0.5, box_height * 0.5, box_size * 0.5)
	process.direction = Vector3.DOWN
	process.spread = 25.0
	process.initial_velocity_min = fall_speed * 0.3
	process.initial_velocity_max = fall_speed
	process.gravity = Vector3.ZERO
	# The quad is 1 unit wide: the particle's scale is its size.
	process.scale_min = size_min
	process.scale_max = size_max
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material

	amount = count
	lifetime = particle_lifetime
	preprocess = particle_lifetime
	process_material = process
	draw_pass_1 = quad
	visibility_aabb = AABB(Vector3.ONE * -box_size, Vector3.ONE * box_size * 2.0)
