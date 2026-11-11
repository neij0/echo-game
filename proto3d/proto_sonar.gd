class_name ProtoSonar
extends Node3D
## The 3D sonar: keeps the running pulses, works out what each one can reach
## (a ring of rays against the rocks, stored in a small texture) and feeds
## both to every shader that shows the sonar (room surfaces, the full-screen
## edge pass, the marine snow). Nodes in the "proto_sonar_targets" group get
## on_sonar_wave(origin, seen) once when a wave reaches them.

signal pulse_emitted(origin: Vector3)

const SLOTS: int = 2
const EDGE_SHADER: Shader = preload("res://proto3d/proto_sonar_edges.gdshader")

@export_group("Wave")
## World units per second.
@export var pulse_speed: float = 11.0
@export var pulse_radius: float = 17.0
## Seconds a revealed spot stays fully lit after the wave passed it.
@export var hold_time: float = 1.4
## Seconds it then takes to fade out.
@export var fade_time: float = 2.2
## Thickness of the bright wave front.
@export var front_width: float = 0.3

@export_group("Occlusion")
## Directions tested per pulse (columns of the occlusion texture).
@export var ray_count: int = 1024
## Height of the rays: rocks lower than this do not stop the pulse.
@export var ray_height: float = 0.6
## How far past a rock's front the reveal still reaches (its near rim).
@export var occlusion_bias: float = 0.3
@export_flags_3d_physics var wall_mask: int = 1

@export_group("Edges")
@export var edge_color: Color = Color(0.3, 0.9, 1.0)
@export var edge_energy: float = 3.2
@export var edge_width: float = 1.4

var _materials: Array[ShaderMaterial] = []
var _origins: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _notified: Array[Dictionary] = []
var _image: Image
var _texture: ImageTexture
var _next_slot: int = 0


func _ready() -> void:
	for i: int in SLOTS:
		_origins.append(Vector3.ZERO)
		_ages.append(-1.0)
		_notified.append({})
	_image = Image.create(ray_count, SLOTS, false, Image.FORMAT_RF)
	_image.fill(Color(pulse_radius * 2.0, 0.0, 0.0))
	_texture = ImageTexture.create_from_image(_image)
	_build_edge_pass()


## Every material using proto_sonar.gdshaderinc must be registered once.
func register_material(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter("occlusion_map", _texture)
	_push_settings(material)
	_push_pulses(material)


## Seconds from the pulse until its last glow is gone.
func get_lifetime() -> float:
	return pulse_radius / pulse_speed + hold_time + fade_time


## Sends a pulse from origin (call from the physics step: it casts rays).
func emit_pulse(origin: Vector3) -> void:
	var slot: int = _next_slot
	_next_slot = (_next_slot + 1) % SLOTS
	_origins[slot] = origin
	_ages[slot] = 0.0
	_notified[slot] = {}
	_trace_occlusion(slot, origin)
	pulse_emitted.emit(origin)


func _process(delta: float) -> void:
	var lifetime: float = get_lifetime()
	for i: int in SLOTS:
		if _ages[i] < 0.0:
			continue
		_ages[i] += delta
		if _ages[i] > lifetime:
			_ages[i] = -1.0
	for material: ShaderMaterial in _materials:
		_push_pulses(material)


func _physics_process(_delta: float) -> void:
	for i: int in SLOTS:
		if _ages[i] < 0.0:
			continue
		var reach: float = minf(_ages[i] * pulse_speed, pulse_radius)
		for target: Node in get_tree().get_nodes_in_group("proto_sonar_targets"):
			var body := target as Node3D
			if body == null or _notified[i].has(body.get_instance_id()):
				continue
			var offset: Vector3 = body.global_position - _origins[i]
			offset.y = 0.0
			if offset.length() > reach:
				continue
			_notified[i][body.get_instance_id()] = true
			if body.has_method("on_sonar_wave"):
				body.call("on_sonar_wave", _origins[i], _has_sight(_origins[i], body.global_position))


func _has_sight(from: Vector3, to: Vector3) -> bool:
	var start := Vector3(from.x, ray_height, from.z)
	var end := Vector3(to.x, ray_height, to.z)
	var query := PhysicsRayQueryParameters3D.create(start, end, wall_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## One ray per column: how far the pulse gets in that direction.
func _trace_occlusion(slot: int, origin: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start := Vector3(origin.x, ray_height, origin.z)
	var query := PhysicsRayQueryParameters3D.create(start, start, wall_mask)
	for i: int in ray_count:
		# Must match the angle the shader computes (atan(z, x) / TAU + 0.5).
		var angle: float = ((float(i) + 0.5) / float(ray_count) - 0.5) * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		query.to = start + direction * pulse_radius
		var hit: Dictionary = space.intersect_ray(query)
		var distance: float = pulse_radius * 2.0
		if not hit.is_empty():
			distance = start.distance_to(hit["position"] as Vector3)
		_image.set_pixel(i, slot, Color(distance, 0.0, 0.0))
	_texture.update(_image)


func _push_settings(material: ShaderMaterial) -> void:
	material.set_shader_parameter("pulse_speed", pulse_speed)
	material.set_shader_parameter("pulse_radius", pulse_radius)
	material.set_shader_parameter("pulse_hold", hold_time)
	material.set_shader_parameter("pulse_fade", fade_time)
	material.set_shader_parameter("front_width", front_width)
	material.set_shader_parameter("occlusion_bias", occlusion_bias)


func _push_pulses(material: ShaderMaterial) -> void:
	material.set_shader_parameter("pulse_origin", _origins)
	material.set_shader_parameter("pulse_age", _ages)


## A quad that always covers the screen (the shader ignores its transform).
func _build_edge_pass() -> void:
	var material := ShaderMaterial.new()
	material.shader = EDGE_SHADER
	material.set_shader_parameter("edge_color", edge_color)
	material.set_shader_parameter("edge_energy", edge_energy)
	material.set_shader_parameter("edge_width", edge_width)
	# Before the characters (also transparent), so a character in front of a
	# glowing edge covers it.
	material.render_priority = -10
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var instance := MeshInstance3D.new()
	instance.name = "SonarEdges"
	instance.mesh = quad
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3.ONE * -10000.0, Vector3.ONE * 20000.0)
	add_child(instance)
	register_material(material)
