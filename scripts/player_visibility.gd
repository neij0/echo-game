class_name PlayerVisibility
extends Node
## Local visibility: gives every registered player a soft light (no shadows)
## so the floor and rocks close by show as faint dark silhouettes, fading
## smoothly to near black further away. The far level is only seen with the
## pulse's sonar edges. Radius, falloff and colour come from the WorldConfig
## ("Local Visibility"), the brightness from the stage
## (StageDefinition.visibility_energy) times the Brightness setting.
## Creatures are not revealed by it (they are only drawn in the Echo's light).

@export var stage_manager: StageManager
## Size of the generated light texture in pixels.
@export var texture_size: int = 256

var radius: float = 280.0
var falloff: float = 140.0
var color: Color = Color(0.5, 0.75, 0.9)
var stage_energy: float = 0.25

var _lights: Array[PointLight2D] = []
var _texture: GradientTexture2D


func _ready() -> void:
	add_to_group("world_listeners")
	add_to_group("stage_listeners")
	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	radius = world.visibility_radius
	falloff = world.visibility_falloff
	color = world.visibility_color
	_texture = LightTextures.radial_smooth(texture_size, radius / maxf(radius + falloff, 1.0))
	for light: PointLight2D in _lights:
		_setup(light)


## Called (via the "stage_listeners" group) by StageManager.
func apply_stage(stage: StageDefinition) -> void:
	stage_energy = stage.visibility_energy


func _on_player_registered(player: Player) -> void:
	var light := PointLight2D.new()
	light.name = "VisibilityLight"
	light.shadow_enabled = false
	_setup(light)
	player.add_child(light)
	_lights.append(light)


func _setup(light: PointLight2D) -> void:
	if _texture == null:
		_texture = LightTextures.radial_smooth(texture_size, radius / maxf(radius + falloff, 1.0))
	light.texture = _texture
	light.texture_scale = LightTextures.scale_for_radius(_texture, radius + falloff)
	light.color = color


func _process(_delta: float) -> void:
	# Read every frame so the Brightness setting applies right away.
	var energy: float = stage_energy * Game.brightness
	for light: PointLight2D in _lights:
		light.energy = energy
