class_name Darkness
extends WorldEnvironment
## The darkness of the 3D world: a black background, a near-zero ambient light
## everywhere (so the level cannot be read from a distance: what is near is
## shown by real lights, the far layout only by the pulse), volumetric fog that
## the lights shine into, and the glow of everything brighter than
## glow_threshold (sonar lines, rims, eyes).
## Near ambient: a faint deep-blue fill round each player (a soft light high
## above them, no shadows, fading out by near_radius), so the floor and the
## rock silhouettes near the players are faintly readable, never far ones.
## Its colour, strength and reach come from the WorldConfig (apply_world),
## each stage scales it (StageDefinition.near_ambient_scale, apply_stage).
## Each stage also has its own far ambient colour. The Brightness setting
## (Game.brightness, a narrow range) scales both a little.

@export_group("Ambient")
@export var ambient_color: Color = Color(0.1, 0.18, 0.32)
## Strength of the ambient light: low on purpose.
@export var ambient_energy: float = 0.06

@export_group("Near Ambient")
## Set from the WorldConfig (near_ambient_*) when a world is applied.
@export var near_color: Color = Color(0.14, 0.26, 0.62)
@export var near_energy: float = 4.5
## Distance (units) round a player where the fill has faded to nothing.
@export var near_radius: float = 9.0
## Height of the fill light above the player (high = the floor and the rock
## tops are lit evenly, the rock faces a little).
@export var near_height: float = 3.0
## Fall-off curve (1 = natural, below 1 = flatter, then a soft edge).
@export var near_falloff: float = 0.6
## Off = only the far ambient (a debug comparison: level test key L).
@export var near_enabled: bool = true

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
## Share of the near ambient this stage uses (apply_stage).
var stage_scale: float = 1.0
## One fill light per player, in the order of Players.all.
var _near_lights: Array[OmniLight3D] = []


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
	stage_scale = stage.near_ambient_scale


## Called (via the "world_listeners" group) when a world is applied.
func apply_world(world: WorldConfig) -> void:
	near_color = world.near_ambient_color
	near_energy = world.near_ambient_energy
	near_radius = world.near_ambient_radius


func _process(_delta: float) -> void:
	_apply_ambient()
	_update_near_lights()


## The energy of the near fill right now (brightness, stage, boss darkness).
func get_near_energy() -> float:
	return near_energy * stage_scale * _brightness() * (1.0 - extra_darkness)


func _apply_ambient() -> void:
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy * _brightness() * (1.0 - extra_darkness)


func _brightness() -> float:
	# Looked up by path, so tools that run without autoloads can load this.
	var game := get_node_or_null("/root/Game") as GameState
	return game.brightness if game else 1.0


func _update_near_lights() -> void:
	var players: Array[Player] = Players.all(get_tree())
	while _near_lights.size() < players.size():
		var light := OmniLight3D.new()
		light.name = "NearAmbient%d" % (_near_lights.size() + 1)
		light.shadow_enabled = false
		light.light_volumetric_fog_energy = 0.0
		light.light_specular = 0.0
		# Follows the drawn (interpolated) player in _process.
		light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(light)
		_near_lights.append(light)
	var energy: float = get_near_energy() if near_enabled else 0.0
	for i: int in _near_lights.size():
		var light: OmniLight3D = _near_lights[i]
		light.visible = i < players.size() and energy > 0.0
		if not light.visible:
			continue
		light.light_color = near_color
		light.light_energy = energy
		light.omni_range = near_radius
		light.omni_attenuation = near_falloff
		var at: Vector3 = players[i].get_global_transform_interpolated().origin
		light.global_position = Vector3(at.x, near_height, at.z)
