class_name Coral
extends Node3D
## A bioluminescent coral. When the pulse front reaches it in line of sight
## (Sonar, "sonar_targets"), it lights up for a while and creates a small safe
## zone that creatures avoid (they slide round it, Creature). Dark and lit
## only by other lights while asleep.

@export var lit_duration: float = 6.0
@export var fade_time: float = 1.0
## Reach of its light (units).
@export var light_radius: float = 3.4
## Creatures are pushed out of this radius while the coral is lit (units).
@export var safe_radius: float = 2.6
@export var lit_energy: float = 1.6
## Its light casts shadows (costly with many corals lit at once).
@export var cast_shadows: bool = false
@export var light_color: Color = Color(0.3, 1.0, 0.75)
@export var dim_color: Color = Color(0.12, 0.22, 0.2)
@export var glow_color: Color = Color(0.5, 1.0, 0.85)
## HDR brightness of the lit coral (above 1 = it blooms).
@export var glow_energy: float = 2.4
## The coral's branches: [offset on the floor (x, z), radius] (units).
@export var branches: Array[Vector3] = [Vector3(0.0, 0.0, 0.2), Vector3(-0.24, 0.12, 0.14),
	Vector3(0.22, 0.16, 0.12), Vector3(0.06, -0.24, 0.12)]
## Height of the light above the floor.
@export var light_height: float = 0.7

var lit_time_left: float = 0.0
var _light: OmniLight3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("corals")
	add_to_group("sonar_targets")
	add_to_group("light_sources")
	_material = StandardMaterial3D.new()
	_material.albedo_color = dim_color
	_material.roughness = 0.8
	for branch: Vector3 in branches:
		var sphere := SphereMesh.new()
		sphere.radius = branch.z
		sphere.height = branch.z * 3.0
		sphere.radial_segments = 10
		sphere.rings = 6
		var part := MeshInstance3D.new()
		part.mesh = sphere
		part.material_override = _material
		part.position = Vector3(branch.x, branch.z * 1.4, branch.y)
		add_child(part)
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.light_energy = 0.0
	_light.omni_range = light_radius
	_light.shadow_enabled = cast_shadows
	_light.position.y = light_height
	_light.visible = false
	add_child(_light)


func _process(delta: float) -> void:
	if lit_time_left <= 0.0:
		return
	lit_time_left = maxf(lit_time_left - delta, 0.0)
	# Full brightness, then fade out during the last fade_time seconds.
	var share: float = clampf(lit_time_left / fade_time, 0.0, 1.0)
	_light.light_energy = lit_energy * share
	_light.visible = lit_time_left > 0.0
	_set_glow(share)


## Called by the Sonar when a pulse front reaches this coral in line of sight.
func on_sonar_hit(_origin: Vector3) -> void:
	wake()


func wake() -> void:
	lit_time_left = lit_duration
	_light.light_energy = lit_energy
	_light.visible = true
	_set_glow(1.0)


func is_lit() -> bool:
	return lit_time_left > 0.0


## Used by light-attracted creatures (LightHunter): is this point lit by me?
func lights_point(point: Vector3) -> bool:
	return is_lit() and Creature._flat_distance(global_position, point) <= light_radius


func is_in_safe_zone(point: Vector3) -> bool:
	return is_lit() and Creature._flat_distance(global_position, point) <= safe_radius


func _set_glow(share: float) -> void:
	_material.emission_enabled = share > 0.0
	_material.emission = glow_color
	_material.emission_energy_multiplier = glow_energy * share
