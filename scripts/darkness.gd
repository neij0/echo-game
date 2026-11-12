class_name Darkness
extends WorldEnvironment
## The darkness of the 3D world: a black background, a near-zero ambient light
## on everything (so creatures and characters are only seen by real lights and
## reveals), volumetric fog that the lights shine into, and the glow of
## everything brighter than glow_threshold (sonar lines, rims, eyes).
## World ambient: the world's own faint deep-blue light from the far surface,
## uniform on every level surface (floor, rock, outer rock; the materials are
## registered with register_material), sinking into darkness with distance
## from the camera's focus like fog (shaders/world_ambient.gdshaderinc). So the
## floor and rock silhouettes on screen read faintly while the far layout
## stays black: the pulse is still the way to see it. Values from the
## WorldConfig (apply_world), a share per stage (StageDefinition.
## world_ambient_scale, apply_stage). The Brightness setting (Game.brightness,
## a narrow range) scales both ambients a little.

@export_group("Ambient")
## The far ambient on everything (characters, creatures): near zero on purpose.
@export var ambient_color: Color = Color(0.1, 0.18, 0.32)
@export var ambient_energy: float = 0.042

@export_group("World Ambient")
## Set from the WorldConfig (world_ambient_*) when a world is applied.
@export var world_color: Color = Color(0.14, 0.26, 0.62)
@export var world_energy: float = 0.6
## Distance from the camera's focus (world units, on the floor) where the fog
## starts / where the world ambient has sunk into darkness.
@export var world_fog_begin: float = 9.0
@export var world_fog_end: float = 22.0
## Off = no world ambient (a debug comparison: level test key L).
@export var world_enabled: bool = true

@export_group("Fog")
@export var fog_enabled: bool = true
@export var fog_density: float = 0.05
@export var fog_color: Color = Color(0.35, 0.55, 0.8)
## 0 = light spreads evenly in the fog, towards 1 = it glows round the lights.
@export_range(-0.9, 0.9) var fog_anisotropy: float = 0.5
## How far from the camera the fog is computed (the camera is far away).
@export var fog_length: float = 96.0

@export_group("Glow")
@export var glow_enabled: bool = true
## Colours above this brightness glow. 1.0 = only HDR (over-bright) colours.
@export var glow_threshold: float = 1.0
@export var glow_intensity: float = 0.9
@export var glow_bloom: float = 0.08

## 0-1: share taken off the ambient on top of everything (a boss phase
## darkens its arena; set_extra_darkness, "darkness" group).
var extra_darkness: float = 0.0
## Share of the world ambient this stage uses (apply_stage).
var stage_scale: float = 1.0
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	add_to_group("stage_listeners")
	add_to_group("world_listeners")
	add_to_group("darkness")
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = glow_enabled
	environment.glow_intensity = glow_intensity
	environment.glow_bloom = glow_bloom
	environment.glow_hdr_threshold = glow_threshold
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.volumetric_fog_enabled = fog_enabled
	environment.volumetric_fog_density = fog_density
	environment.volumetric_fog_albedo = fog_color
	environment.volumetric_fog_anisotropy = fog_anisotropy
	environment.volumetric_fog_length = fog_length
	environment.volumetric_fog_ambient_inject = 0.0
	_apply_ambient()


## Called (via the "darkness" group), e.g. by the Angler's last phase; 0 = off.
func set_extra_darkness(amount: float) -> void:
	extra_darkness = clampf(amount, 0.0, 1.0)


## Called (via the "stage_listeners" group) by StageManager.
func apply_stage(stage: StageDefinition) -> void:
	ambient_color = stage.ambient_color
	stage_scale = stage.world_ambient_scale


## Called (via the "world_listeners" group) when a world is applied.
func apply_world(world: WorldConfig) -> void:
	world_color = world.world_ambient_color
	world_energy = world.world_ambient_energy
	world_fog_begin = world.world_ambient_fog_begin
	world_fog_end = world.world_ambient_fog_end


## A level surface material (a shader including world_ambient.gdshaderinc)
## that takes the world ambient.
func register_material(material: ShaderMaterial) -> void:
	if not material in _materials:
		_materials.append(material)
	_push(material, _focus())


static func find(tree: SceneTree) -> Darkness:
	return tree.get_first_node_in_group("darkness") as Darkness


func _process(_delta: float) -> void:
	_apply_ambient()
	var focus: Vector3 = _focus()
	for material: ShaderMaterial in _materials:
		_push(material, focus)


## The world ambient's energy right now (brightness, stage, boss darkness).
func get_world_energy() -> float:
	if not world_enabled:
		return 0.0
	return world_energy * stage_scale * _brightness() * (1.0 - extra_darkness)


func _push(material: ShaderMaterial, focus: Vector3) -> void:
	material.set_shader_parameter("world_ambient_color", world_color)
	material.set_shader_parameter("world_ambient_energy", get_world_energy())
	material.set_shader_parameter("world_ambient_focus", focus)
	material.set_shader_parameter("world_ambient_fog_begin", world_fog_begin)
	material.set_shader_parameter("world_ambient_fog_end", world_fog_end)


## The camera's focus (the fog is measured from it), else the players' middle.
func _focus() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var camera := get_tree().get_first_node_in_group("shared_camera") as SharedCamera
	if camera:
		return camera.get_focus()
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for player: Player in players:
		sum += player.global_position
	return sum / players.size()


func _apply_ambient() -> void:
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy * _brightness() * (1.0 - extra_darkness)


func _brightness() -> float:
	# Looked up by path, so tools that run without autoloads can load this.
	var game := get_node_or_null("/root/Game") as GameState
	return game.brightness if game else 1.0
