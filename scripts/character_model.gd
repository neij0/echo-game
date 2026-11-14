class_name CharacterModel
extends Node3D
## A player's 3D model in place of the CapsuleBody. For now it shows the
## BLOCKOUT placeholders (assets/models/characters/blockout, not final art).
## It puts the game's shared character shader on every surface of the model
## (the model's own materials only say the colour and the glow of each part),
## the same outline through rock as the capsule, sets a standing pose on the
## T-posed rig (each bone aimed along a direction), and gives every bone chain
## of the model (<Name>_1 ... <Name>_end) a BoneSway. With a player: it
## follows the player's drawn position, turns to face where the player
## faces, hovers and bobs, leans into the movement, flares its glow with the
## pulse, sinks and dims when downed and takes the sword's small lunge.
## Without a player it just stands where it is put (tools).

const BODY_SHADER: Shader = preload("res://shaders/character.gdshader")
const SEE_THROUGH_SHADER: Shader = preload("res://shaders/see_through.gdshader")

@export var player: Player
## The model: a scene with a Skeleton3D and its skinned meshes. Its front is +z.
@export var model: PackedScene

@export_group("Look")
@export var rim_color: Color = Color(0.3, 0.9, 1.0)
@export var rim_energy: float = 0.6
@export var rim_power: float = 2.5
## Multiplies the glow of the model's glowing parts.
@export var glow_scale: float = 1.0
## Colour of the outline shown through rock.
@export var outline_color: Color = Color(0.3, 0.9, 1.0)

@export_group("Pose")
## Bone name -> the direction it points along, in the model's own space
## (x = the character's left, y = up, z = forward). Bones not listed keep
## their place on their parent.
@export var pose: Dictionary[String, Vector3] = {}
## Bone name -> a turn about its own length, in degrees, after the aim.
@export var rolls: Dictionary[String, float] = {}

@export_group("Motion")
## How fast it turns to the player's facing.
@export var turn_speed: float = 12.0
## Height it floats above the floor, and the size and speed of its bob.
@export var hover_height: float = 0.0
@export var bob_height: float = 0.0
@export var bob_speed: float = 1.6
## Forward lean at full speed (degrees), and how fast the lean follows.
@export var lean_degrees: float = 0.0
@export var lean_speed: float = 6.0

@export_group("Pulse")
## How much brighter the glow is right after the player's pulse (0 = no
## flare), and how long the flare lasts.
@export var pulse_flare: float = 0.0
@export var pulse_flare_time: float = 0.6

@export_group("Downed")
## Share of the glow and rim that is left, the forward tilt and the height.
@export_range(0.0, 1.0) var downed_glow_share: float = 0.25
@export var downed_tilt_degrees: float = 55.0
@export var downed_height: float = 0.0
@export var change_speed: float = 6.0

@export_group("Chains")
## Sway settings by chain name (the longest matching prefix wins); chains
## with no settings stay stiff.
@export var chains: Array[BoneChainSettings] = []

var _holder: Node3D
var _skeleton: Skeleton3D
var _see_through: ShaderMaterial
## The model's surfaces: {"material": ShaderMaterial, "glow": float}.
var _surfaces: Array[Dictionary] = []
var _sways: Array[BoneSway] = []
var _yaw: float = 0.0
var _downed: float = 0.0
var _lean: float = 0.0
var _flare: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	if player:
		top_level = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		player.pulse_emitted.connect(_on_pulse_emitted)
		_yaw = atan2(player.facing.x, player.facing.z)
	_build()


## Shows another model (same settings).
func set_model(scene: PackedScene) -> void:
	if scene == model and _holder != null:
		return
	model = scene
	if is_inside_tree():
		_build()


func get_skeleton() -> Skeleton3D:
	return _skeleton


## Names of the chains that sway.
func get_chain_names() -> PackedStringArray:
	var names := PackedStringArray()
	for sway: BoneSway in _sways:
		names.append(String(sway.name).trim_prefix("Sway"))
	return names


## The shared-shader materials of the model's surfaces.
func get_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for surface: Dictionary in _surfaces:
		materials.append(surface["material"] as ShaderMaterial)
	return materials


## Height above the floor it floats at.
func get_hover_height() -> float:
	return hover_height


## Starts the glow flare of a pulse.
func flare() -> void:
	_flare = 1.0


func _process(delta: float) -> void:
	_time += delta
	var speed_share: float = 0.0
	var downed: bool = false
	if player:
		var facing: Vector3 = player.facing
		_yaw = lerp_angle(_yaw, atan2(facing.x, facing.z), 1.0 - exp(-turn_speed * delta))
		var sword := player.get_node_or_null("Sword") as SwordAbility
		var lunge: Vector3 = sword.get_lunge_offset() if sword else Vector3.ZERO
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), player.get_global_transform_interpolated().origin + lunge)
		speed_share = clampf(Vector2(player.velocity.x, player.velocity.z).length() / maxf(player.max_speed, 0.01), 0.0, 1.0)
		downed = player.health != null and player.health.is_downed
	_downed = move_toward(_downed, 1.0 if downed else 0.0, change_speed * delta)
	_lean = lerpf(_lean, speed_share, 1.0 - exp(-lean_speed * delta))
	_flare = maxf(_flare - delta / maxf(pulse_flare_time, 0.01), 0.0)
	var height: float = lerpf(hover_height + sin(_time * bob_speed) * bob_height, downed_height, _downed)
	var tilt: float = deg_to_rad(lerpf(lean_degrees * _lean, downed_tilt_degrees, _downed))
	_holder.transform = Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0.0, height, 0.0))
	var dim: float = lerpf(1.0, downed_glow_share, _downed)
	for surface: Dictionary in _surfaces:
		var material := surface["material"] as ShaderMaterial
		material.set_shader_parameter("rim_energy", rim_energy * dim)
		material.set_shader_parameter("glow_energy", float(surface["glow"]) * glow_scale * dim * (1.0 + pulse_flare * _flare))


func _on_pulse_emitted(_origin: Vector3) -> void:
	flare()


func _build() -> void:
	if _holder:
		remove_child(_holder)
		_holder.free()
	_surfaces.clear()
	_sways.clear()
	_skeleton = null
	_holder = Node3D.new()
	_holder.name = "Model"
	add_child(_holder)
	if model == null:
		return
	_see_through = ShaderMaterial.new()
	_see_through.shader = SEE_THROUGH_SHADER
	_see_through.set_shader_parameter("outline_color", outline_color)
	var instance: Node = model.instantiate()
	_holder.add_child(instance)
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, _material_for(mesh_instance.mesh.surface_get_material(surface)))
	var skeletons: Array[Node] = instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_skeleton = skeletons[0] as Skeleton3D
	_apply_pose()
	_add_chains()


## The shared character material for one surface: the model's material gives
## the colour of the part and, if it glows, the glow.
func _material_for(source: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BODY_SHADER
	material.set_shader_parameter("rim_color", rim_color)
	material.set_shader_parameter("rim_energy", rim_energy)
	material.set_shader_parameter("rim_power", rim_power)
	var glow: float = 0.0
	var standard := source as BaseMaterial3D
	if standard:
		material.resource_name = standard.resource_name
		material.set_shader_parameter("body_color", standard.albedo_color)
		if standard.emission_enabled:
			glow = standard.emission_energy_multiplier
			material.set_shader_parameter("glow_color", standard.emission)
			material.set_shader_parameter("glow_energy", glow * glow_scale)
	material.next_pass = _see_through
	_surfaces.append({"material": material, "glow": glow})
	return material


## Aims the listed bones, parents before children.
func _apply_pose() -> void:
	_skeleton.reset_bone_poses()
	for bone: int in _skeleton.get_parentless_bones():
		_pose_bone(bone)


func _pose_bone(bone: int) -> void:
	var bone_name: String = _skeleton.get_bone_name(bone)
	if pose.has(bone_name) or rolls.has(bone_name):
		var global: Transform3D = _skeleton.get_bone_global_pose(bone)
		if pose.has(bone_name) and not pose[bone_name].is_zero_approx():
			# A bone points along its own y.
			global.basis = Basis(Quaternion(global.basis.y.normalized(), pose[bone_name].normalized())) * global.basis
		if rolls.has(bone_name):
			global.basis = Basis(global.basis.y.normalized(), deg_to_rad(rolls[bone_name])) * global.basis
		_skeleton.set_bone_global_pose(bone, global)
	for child: int in _skeleton.get_bone_children(bone):
		_pose_bone(child)


## A BoneSway for every chain (<Name>_1 ... <Name>_end) that has settings.
func _add_chains() -> void:
	for bone: int in _skeleton.get_bone_count():
		var first: String = _skeleton.get_bone_name(bone)
		if not first.ends_with("_1"):
			continue
		var chain: String = first.trim_suffix("_1")
		var settings: BoneChainSettings = _settings_for(chain)
		if settings == null or _skeleton.find_bone(chain + "_end") < 0:
			continue
		var sway := BoneSway.new()
		sway.name = "Sway" + chain
		_skeleton.add_child(sway)
		sway.setup(first, chain + "_end", settings, float(_sways.size()) * 1.9)
		_sways.append(sway)


func _settings_for(chain: String) -> BoneChainSettings:
	var best: BoneChainSettings = null
	for settings: BoneChainSettings in chains:
		if settings and chain.begins_with(settings.prefix) and (best == null or settings.prefix.length() > best.prefix.length()):
			best = settings
	return best
