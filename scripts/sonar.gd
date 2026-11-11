class_name Sonar
extends Node3D
## The sonar of the 3D world: keeps the running pulses (the Echo's pulse, the
## distress pulse, a Lure decoy: up to SLOTS at once, each with its own reach
## and speed), works out what each one can reach (a ring of rays against the
## rock, stored in a small texture) and feeds both to every shader that shows
## the sonar (rock and floor, the full-screen edge pass, the marine snow).
## Pulses are added through the "sonar" group: add_pulse(origin, radius,
## expand_time). Nodes in the "sonar_targets" group get on_sonar_hit(origin)
## once when a wave front reaches them in line of sight of its origin
## (creatures, corals, shards...).

signal pulse_started(origin: Vector3, max_radius: float)
## The wave front has just reached rock; distance_ratio 0 = at the origin,
## 1 = at the pulse's full reach (the sonar ticks).
signal edge_hit(distance_ratio: float)

const SLOTS: int = 4
const EDGE_SHADER: Shader = preload("res://shaders/sonar_edges.gdshader")

@export_group("Afterglow")
## Seconds a revealed spot stays fully lit after the wave passed it.
@export var hold_time: float = 1.4
## Seconds it then takes to fade out.
@export var fade_time: float = 2.2
## Thickness of the bright wave front.
@export var front_width: float = 0.3

@export_group("Occlusion")
## Directions tested per pulse (columns of the occlusion texture).
@export var ray_count: int = 1024
## Height of the rays: rock lower than this does not stop the pulse.
@export var ray_height: float = 0.6
## How far past a rock's front the reveal still reaches (its near rim).
@export var occlusion_bias: float = 0.3
## How far back the top of a rock the pulse hits is shown, and from which
## height a point counts as "on top".
@export var top_reach: float = 2.6
@export var top_reach_height: float = 0.5
@export_flags_3d_physics var wall_mask: int = 1

@export_group("Edges")
@export var edge_color: Color = Color(0.45, 0.95, 1.0)
@export var edge_energy: float = 3.2
## Line thickness in pixels.
@export var edge_width: float = 1.4

@export_group("Flash")
## A short, small, bright light at the pulse's origin (it does not reveal more).
@export var flash_enabled: bool = true
@export var flash_energy: float = 10.0
@export var flash_range: float = 3.0
@export var flash_time: float = 0.18
@export var flash_color: Color = Color(0.75, 0.95, 1.0)

var _materials: Array[ShaderMaterial] = []
var _edge_material: ShaderMaterial
var _origins: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
## Per slot: the targets this wave has already reached (instance ids).
var _reached: Array[Dictionary] = []
## Per slot: the distances at which its rays hit rock, sorted, and how many of
## them the front has passed.
var _hits: Array[PackedFloat32Array] = []
var _hits_passed: PackedInt32Array = PackedInt32Array()
var _image: Image
var _texture: ImageTexture
## Milliseconds the last pulse's occlusion rays took (benchmark).
var last_trace_ms: float = 0.0


static func find(tree: SceneTree) -> Sonar:
	return tree.get_first_node_in_group("sonar") as Sonar if tree else null


func _ready() -> void:
	add_to_group("sonar")
	add_to_group("world_listeners")
	for i: int in SLOTS:
		_origins.append(Vector3.ZERO)
		_ages.append(-1.0)
		_speeds.append(1.0)
		_radii.append(1.0)
		_reached.append({})
		_hits.append(PackedFloat32Array())
		_hits_passed.append(0)
	_image = Image.create(ray_count, SLOTS, false, Image.FORMAT_RF)
	_image.fill(Color(100000.0, 0.0, 0.0))
	_texture = ImageTexture.create_from_image(_image)
	_build_edge_pass()


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	edge_color = world.edge_color
	_edge_material.set_shader_parameter("edge_color", edge_color)


## Every material using sonar.gdshaderinc must be registered once.
func register_material(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter("occlusion_map", _texture)
	material.set_shader_parameter("pulse_hold", hold_time)
	material.set_shader_parameter("pulse_fade", fade_time)
	material.set_shader_parameter("front_width", front_width)
	material.set_shader_parameter("occlusion_bias", occlusion_bias)
	material.set_shader_parameter("top_reach", top_reach)
	material.set_shader_parameter("top_reach_height", top_reach_height)
	_push_pulses(material)


## Seconds from a pulse with this expand time until its last glow is gone.
func get_lifetime(expand_time: float) -> float:
	return expand_time + hold_time + fade_time


## True while any pulse is still expanding or glowing.
func is_active() -> bool:
	for age: float in _ages:
		if age >= 0.0:
			return true
	return false


## Starts a pulse: its front reaches max_radius after expand_time seconds.
## Call from the physics step (it casts rays).
func add_pulse(origin: Vector3, max_radius: float, expand_time: float) -> void:
	var slot: int = _free_slot()
	_origins[slot] = origin
	_ages[slot] = 0.0
	_radii[slot] = max_radius
	_speeds[slot] = max_radius / maxf(expand_time, 0.01)
	_reached[slot] = {}
	_trace_occlusion(slot, origin, max_radius)
	if flash_enabled:
		_flash(origin)
	pulse_started.emit(origin, max_radius)


func _process(delta: float) -> void:
	for i: int in SLOTS:
		if _ages[i] < 0.0:
			continue
		_ages[i] += delta
		if _ages[i] > get_lifetime(_radii[i] / _speeds[i]):
			_ages[i] = -1.0
	for material: ShaderMaterial in _materials:
		_push_pulses(material)


func _physics_process(_delta: float) -> void:
	for i: int in SLOTS:
		if _ages[i] < 0.0:
			continue
		var reach: float = minf(_ages[i] * _speeds[i], _radii[i])
		_check_edges(i, reach)
		_check_targets(i, reach)


## Ticks: the front has passed more rock since the last step.
func _check_edges(slot: int, reach: float) -> void:
	var hits: PackedFloat32Array = _hits[slot]
	var passed: int = _hits_passed[slot]
	if passed >= hits.size() or hits[passed] > reach:
		return
	var nearest: float = hits[passed]
	while passed < hits.size() and hits[passed] <= reach:
		passed += 1
	_hits_passed[slot] = passed
	edge_hit.emit(nearest / _radii[slot])


## Calls on_sonar_hit(origin) on every sonar target the front has just
## reached, if it is in line of sight of the pulse's origin.
func _check_targets(slot: int, reach: float) -> void:
	var origin: Vector3 = _origins[slot]
	for node: Node in get_tree().get_nodes_in_group("sonar_targets"):
		var target := node as Node3D
		if target == null or _reached[slot].has(target.get_instance_id()):
			continue
		var offset: Vector3 = target.global_position - origin
		if Vector2(offset.x, offset.z).length() > reach:
			continue
		_reached[slot][target.get_instance_id()] = true
		if _has_sight(origin, target.global_position):
			target.call("on_sonar_hit", origin)


func _has_sight(from: Vector3, to: Vector3) -> bool:
	var start := Vector3(from.x, ray_height, from.z)
	var end := Vector3(to.x, ray_height, to.z)
	var query := PhysicsRayQueryParameters3D.create(start, end, wall_mask)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The slot for a new pulse: an unused one, else the oldest.
func _free_slot() -> int:
	var oldest: int = 0
	for i: int in SLOTS:
		if _ages[i] < 0.0:
			return i
		if _ages[i] > _ages[oldest]:
			oldest = i
	return oldest


## One ray per column: how far the pulse gets in that direction.
func _trace_occlusion(slot: int, origin: Vector3, max_radius: float) -> void:
	var started: int = Time.get_ticks_usec()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start := Vector3(origin.x, ray_height, origin.z)
	var query := PhysicsRayQueryParameters3D.create(start, start, wall_mask)
	var hits := PackedFloat32Array()
	for i: int in ray_count:
		# Must match the angle the shader computes (atan(z, x) / TAU + 0.5).
		var angle: float = ((float(i) + 0.5) / float(ray_count) - 0.5) * TAU
		query.to = start + Vector3(cos(angle), 0.0, sin(angle)) * max_radius
		var hit: Dictionary = space.intersect_ray(query)
		var distance: float = max_radius * 2.0
		if not hit.is_empty():
			distance = start.distance_to(hit["position"] as Vector3)
			hits.append(distance)
		_image.set_pixel(i, slot, Color(distance, 0.0, 0.0))
	_texture.update(_image)
	hits.sort()
	_hits[slot] = hits
	_hits_passed[slot] = 0
	last_trace_ms = float(Time.get_ticks_usec() - started) / 1000.0


func _push_pulses(material: ShaderMaterial) -> void:
	material.set_shader_parameter("pulse_origin", _origins)
	material.set_shader_parameter("pulse_age", _ages)
	material.set_shader_parameter("pulse_speed", _speeds)
	material.set_shader_parameter("pulse_radius", _radii)


func _flash(origin: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = flash_color
	light.light_energy = flash_energy
	light.omni_range = flash_range
	light.shadow_enabled = true
	add_child(light)
	light.global_position = Vector3(origin.x, ray_height, origin.z)
	var tween: Tween = light.create_tween()
	# Quadratic falloff: a hard bright pop that dies quickly.
	tween.tween_property(light, "light_energy", 0.0, flash_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(light.queue_free)


## A quad that always covers the screen (the shader ignores its transform).
func _build_edge_pass() -> void:
	_edge_material = ShaderMaterial.new()
	_edge_material.shader = EDGE_SHADER
	_edge_material.set_shader_parameter("edge_color", edge_color)
	_edge_material.set_shader_parameter("edge_energy", edge_energy)
	_edge_material.set_shader_parameter("edge_width", edge_width)
	# Before the characters (also transparent), so a character in front of a
	# glowing edge covers it.
	_edge_material.render_priority = -10
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var instance := MeshInstance3D.new()
	instance.name = "SonarEdges"
	instance.mesh = quad
	instance.material_override = _edge_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3.ONE * -10000.0, Vector3.ONE * 20000.0)
	add_child(instance)
	register_material(_edge_material)
