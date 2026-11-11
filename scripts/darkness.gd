class_name Darkness
extends WorldEnvironment
## The darkness of the 3D world: a black background, a very faint deep-blue
## ambient light (so the level cannot be read from a distance: what is near is
## shown by real lights, the far layout only by the pulse), volumetric fog that
## the lights shine into, and the glow of everything brighter than
## glow_threshold (sonar lines, rims, eyes).
## Each stage has its own ambient colour (StageDefinition, apply_stage). The
## Brightness setting (Game.brightness, a narrow range) scales it a little.

@export_group("Ambient")
@export var ambient_color: Color = Color(0.1, 0.18, 0.32)
## Strength of the ambient light: low on purpose.
@export var ambient_energy: float = 0.06

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


func _ready() -> void:
	add_to_group("stage_listeners")
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


func _process(_delta: float) -> void:
	_apply_ambient()


func _apply_ambient() -> void:
	# Looked up by path, so tools that run without autoloads can load this.
	var game := get_node_or_null("/root/Game") as GameState
	var brightness: float = game.brightness if game else 1.0
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy * brightness * (1.0 - extra_darkness)
