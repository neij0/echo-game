class_name Sonar
extends Node3D
## The sonar of the 3D world: keeps the running pulses (the Echo's pulse, the
## distress pulse, a Lure decoy: up to SLOTS at once, each with its own reach
## and speed), works out what each one can reach (a ring of rays against the
## rock, stored in a small texture) and feeds both to every shader that shows
## the sonar (rock and floor, the ripple pass, the marine snow).
## Pulses are added through the "sonar" group: add_pulse(origin, radius,
## expand_time). Nodes in the "sonar_targets" group get on_sonar_hit(origin)
## once when a wave front reaches them in line of sight of its origin
## (creatures, corals, shards...).
## The look is a wave of light (shaders/sonar.gdshaderinc, sonar_light): a
## soft bright band that lights the surfaces it passes, shaded from its
## origin, with soft shadows behind rock (never pure black), then a slow fade
## back into the dark. No outlines on rock; creatures show their own echo
## (CreatureBody). The impact, layered: a strong flash at the origin (a light
## and an over-bright glow), a refraction ripple travelling with the front
## (pulse_ripple.gdshader), the marine snow pushed outward by it; the deep
## thump is SonarAudio's, the camera shake SharedCamera's.

signal pulse_started(origin: Vector3, max_radius: float)
## The wave front has just reached rock; distance_ratio 0 = at the origin,
## 1 = at the pulse's full reach (the sonar ticks).
signal edge_hit(distance_ratio: float)

const SLOTS: int = 4
const RIPPLE_SHADER: Shader = preload("res://shaders/pulse_ripple.gdshader")
const FLASH_SHADER: Shader = preload("res://shaders/pulse_flash.gdshader")

@export_group("Timing")
## Seconds a pulse counts as active after its front reached its full reach
## (is_active, get_lifetime): hold + fade. The look's own fade is wave_fade.
@export var hold_time: float = 1.4
@export var fade_time: float = 2.2

@export_group("Light Wave")
@export var wave_color: Color = Color(0.65, 0.82, 0.95)
@export var wave_energy: float = 14.0
## Height of the light above the pulse's origin (shading of floor and rock).
@export var wave_height: float = 1.5
## Seconds until the lit surfaces are dark again.
@export var wave_fade: float = 3.6
## Fall-off with distance (per square unit).
@export var wave_falloff: float = 0.05
## The front band: its peak, its soft lead ahead and its tail behind (units),
## and how much its light wraps round surfaces that face away (0-1).
@export var wave_peak: float = 3.0
@export var wave_lead: float = 0.5
@export var wave_tail: float = 1.3
@export_range(0.0, 1.0) var wave_wrap: float = 0.55
## The light the band leaves behind (then fading over wave_fade).
@export var wave_rest: float = 0.7

@export_group("Shadows")
## Radial softness where a shadow starts behind a rock (units).
@export var occlusion_soft: float = 0.35
## Penumbra: radians per unit behind the rock (relative to the distance from
## the origin), and its widest angle.
@export var penumbra_rate: float = 0.35
@export var penumbra_max: float = 0.22
## Light left in a shadow right behind the rock / far behind it (never pure
## black), and the distance it takes to go from one to the other.
@export var shadow_light_near: float = 0.08
@export var shadow_light_far: float = 0.25
@export var shadow_fade: float = 8.0

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

@export_group("Flash")
## A short, strong flash at the pulse's origin (it does not reveal more): a
## light and an over-bright glow that blooms.
@export var flash_enabled: bool = true
@export var flash_energy: float = 22.0
@export var flash_range: float = 5.0
@export var flash_time: float = 0.25
@export var flash_color: Color = Color(0.75, 0.95, 1.0)
@export var flash_glow_energy: float = 6.0
## Size of the glow (units) at the start and at the end of the flash.
@export var flash_glow_start: float = 0.6
@export var flash_glow_end: float = 3.2
@export var flash_glow_time: float = 0.3

@export_group("Ripple")
## A refraction ripple travelling with the front (only while one expands).
@export var ripple_enabled: bool = true
## Width round the front (units) and strongest shift (share of the screen).
@export var ripple_width: float = 0.7
@export var ripple_strength: float = 0.004

@export_group("Marine Snow")
## How far the front pushes the snow outward (units), and the seconds it
## takes to drift back.
@export var push_distance: float = 0.5
@export var push_settle: float = 1.4

var _materials: Array[ShaderMaterial] = []
var _ripple_material: ShaderMaterial
var _ripple: MeshInstance3D
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
	_build_ripple_pass()


## Every material using sonar.gdshaderinc must be registered once.
func register_material(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter("occlusion_map", _texture)
	_push_look(material)
	_push_pulses(material)


## Seconds from a pulse with this expand time until it is no longer active.
func get_lifetime(expand_time: float) -> float:
	return expand_time + maxf(hold_time + fade_time, wave_fade)


## True while any pulse is still expanding or glowing.
func is_active() -> bool:
	for age: float in _ages:
		if age >= 0.0:
			return true
	return false


## True while a wave front is still on its way out (the ripple pass draws).
func is_expanding() -> bool:
	for i: int in SLOTS:
		if _ages[i] >= 0.0 and _ages[i] * _speeds[i] <= _radii[i] + ripple_width:
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
	_ripple.visible = ripple_enabled and is_expanding()


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


func _push_look(material: ShaderMaterial) -> void:
	material.set_shader_parameter("occlusion_bias", occlusion_bias)
	material.set_shader_parameter("occlusion_soft", occlusion_soft)
	material.set_shader_parameter("top_reach", top_reach)
	material.set_shader_parameter("top_reach_height", top_reach_height)
	material.set_shader_parameter("penumbra_rate", penumbra_rate)
	material.set_shader_parameter("penumbra_max", penumbra_max)
	material.set_shader_parameter("shadow_light_near", shadow_light_near)
	material.set_shader_parameter("shadow_light_far", shadow_light_far)
	material.set_shader_parameter("shadow_fade", shadow_fade)
	material.set_shader_parameter("wave_color", wave_color)
	material.set_shader_parameter("wave_energy", wave_energy)
	material.set_shader_parameter("wave_height", wave_height)
	material.set_shader_parameter("wave_fade", wave_fade)
	material.set_shader_parameter("wave_falloff", wave_falloff)
	material.set_shader_parameter("wave_peak", wave_peak)
	material.set_shader_parameter("wave_lead", wave_lead)
	material.set_shader_parameter("wave_tail", wave_tail)
	material.set_shader_parameter("wave_wrap", wave_wrap)
	material.set_shader_parameter("wave_rest", wave_rest)
	material.set_shader_parameter("push_distance", push_distance)
	material.set_shader_parameter("push_settle", push_settle)


## The flash at the origin: a strong light (real shadows) that dies quickly and
## an over-bright glow that grows and fades.
func _flash(origin: Vector3) -> void:
	var at := Vector3(origin.x, ray_height, origin.z)
	var light := OmniLight3D.new()
	light.light_color = flash_color
	light.light_energy = flash_energy
	light.omni_range = flash_range
	light.shadow_enabled = true
	add_child(light)
	light.global_position = at
	var tween: Tween = light.create_tween()
	# Quadratic falloff: a hard bright pop that dies quickly.
	tween.tween_property(light, "light_energy", 0.0, flash_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(light.queue_free)

	var material := ShaderMaterial.new()
	material.shader = FLASH_SHADER
	material.set_shader_parameter("flash_color", flash_color)
	material.set_shader_parameter("energy", flash_glow_energy)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var glow := MeshInstance3D.new()
	glow.name = "FlashGlow"
	glow.mesh = quad
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(glow)
	glow.global_position = at
	glow.scale = Vector3.ONE * flash_glow_start
	var grow: Tween = glow.create_tween().set_parallel(true)
	grow.tween_property(glow, "scale", Vector3.ONE * flash_glow_end, flash_glow_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	grow.tween_method(func(value: float) -> void: material.set_shader_parameter("strength", value), 1.0, 0.0, flash_glow_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	grow.chain().tween_callback(glow.queue_free)


## A quad that always covers the screen (the shader ignores its transform),
## drawn only while a front expands.
func _build_ripple_pass() -> void:
	_ripple_material = ShaderMaterial.new()
	_ripple_material.shader = RIPPLE_SHADER
	_ripple_material.set_shader_parameter("ripple_width", ripple_width)
	_ripple_material.set_shader_parameter("ripple_strength", ripple_strength)
	# Before the characters (also transparent), so they stay sharp.
	_ripple_material.render_priority = -10
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_ripple = MeshInstance3D.new()
	_ripple.name = "PulseRipple"
	_ripple.mesh = quad
	_ripple.material_override = _ripple_material
	_ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripple.custom_aabb = AABB(Vector3.ONE * -10000.0, Vector3.ONE * 20000.0)
	_ripple.visible = false
	add_child(_ripple)
	register_material(_ripple_material)
