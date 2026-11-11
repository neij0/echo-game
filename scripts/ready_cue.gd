class_name ReadyCue
extends Node3D
## A short "ready again" cue on the character in the world, so players notice
## a recharged ability without looking at the HUD: a soft ring grows out of
## the character on the floor and fades, with a soft chime. Played by
## ActiveSkill and the Echo's PulseAbility when their cooldown ends. Follows
## its player.

@export var player: Player
@export var color: Color = Color(0.45, 0.95, 1.0)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 2.2
## World units.
@export var start_radius: float = 0.32
@export var end_radius: float = 0.88
@export var width: float = 0.05
## Height above the floor the ring is drawn at.
@export var height: float = 0.08
## Seconds the ring grows and fades.
@export var time: float = 0.45
## AudioDirector sound name (empty = silent, e.g. the Echo's pulse) and its volume offset.
@export var sound: String = "skill_ready"
@export var volume_offset_db: float = 0.0

## Times played (tests).
var plays: int = 0
var _age: float = -1.0
var _ring: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	# A flat ring of radius 1, scaled while it plays.
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0 - width
	mesh.outer_radius = 1.0 + width
	mesh.rings = 48
	mesh.ring_segments = 4
	_ring = MeshInstance3D.new()
	_ring.mesh = mesh
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func play() -> void:
	plays += 1
	_age = 0.0
	_follow()
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and sound != "":
		audio.play(sound, global_position, volume_offset_db)
	_update_ring()


func is_playing() -> bool:
	return _age >= 0.0 and _age < time


func _process(delta: float) -> void:
	if _age < 0.0:
		return
	_follow()
	_age += delta
	if _age >= time:
		_age = -1.0
	_update_ring()


func _follow() -> void:
	if player:
		global_position = player.get_global_transform_interpolated().origin + Vector3(0.0, height, 0.0)


func _update_ring() -> void:
	_ring.visible = is_playing()
	if not _ring.visible:
		return
	var t: float = _age / time
	var radius: float = lerpf(start_radius, end_radius, 1.0 - (1.0 - t) * (1.0 - t))
	# Flat on the floor: the torus is only stretched sideways.
	_ring.scale = Vector3(radius, 0.02, radius)
	_material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, (1.0 - t) * 0.9)
