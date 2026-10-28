class_name PlayerLight
extends PointLight2D
## A player's own light, with real shadows: rocks (their LightOccluder2D) block
## it and cast shadows. The Echo carries the main light of the game (warm,
## soft, ~280 px); the Guardian only a very faint, small one, just enough to
## see himself, so he has to stay near the Echo to see.
## The Brightness setting (Game.brightness) scales the energy a little.

## Distance in pixels where the light has faded to nothing.
@export var radius: float = 280.0
## 0-1: share of the radius that stays at full brightness before the soft
## fade (0 = fades all the way from the centre).
@export_range(0.0, 1.0) var hard_edge: float = 0.0
@export var base_energy: float = 1.6
@export var light_color: Color = Color(1.0, 0.86, 0.66)
@export var shadows: bool = true
## Softness of the shadow edges.
@export var shadow_smoothing: float = 4.0
## Size of the generated light texture in pixels.
@export var texture_size: int = 512

@export_group("Rock Tops (3/4 view)")
## A rock's top is drawn higher on screen than its base, so it is farther
## from this light than the floor in front of it and would look darker (a pit,
## not a raised rock). A copy of this light raised by top_light_raise pixels
## lights only the light layer top_light_layer (the tops, RockWall), with
## top_light_share of the energy and no shadows, as if each top were lit
## where it stands.
@export var top_light_raise: float = 48.0
@export_range(0.0, 2.0) var top_light_share: float = 0.5
@export var top_light_layer: int = 2

var _top_light: PointLight2D


func _ready() -> void:
	# Rock tops near this light keep their full colour (TopLightFalloff).
	add_to_group("falloff_lights")
	texture = LightTextures.radial_smooth(texture_size, hard_edge)
	texture_scale = LightTextures.scale_for_radius(texture, radius)
	color = light_color
	energy = base_energy
	shadow_enabled = shadows
	shadow_filter = Light2D.SHADOW_FILTER_PCF13
	shadow_filter_smooth = shadow_smoothing
	if top_light_share > 0.0:
		_top_light = PointLight2D.new()
		_top_light.texture = texture
		_top_light.texture_scale = texture_scale
		_top_light.color = light_color
		_top_light.range_item_cull_mask = 1 << (top_light_layer - 1)
		_top_light.position = Vector2(0.0, -top_light_raise)
		add_child(_top_light)


func _process(_delta: float) -> void:
	# Looked up by path (not the Game global), so tools that run without
	# autoloads (godot -s ...) can still load the player scripts.
	var game := get_node_or_null("/root/Game") as GameState
	energy = base_energy * (game.brightness if game else 1.0)
	if _top_light:
		_top_light.energy = energy * top_light_share
