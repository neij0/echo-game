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


func _ready() -> void:
	texture = LightTextures.radial_smooth(texture_size, hard_edge)
	texture_scale = LightTextures.scale_for_radius(texture, radius)
	color = light_color
	energy = base_energy
	shadow_enabled = shadows
	shadow_filter = Light2D.SHADOW_FILTER_PCF13
	shadow_filter_smooth = shadow_smoothing


func _process(_delta: float) -> void:
	# Looked up by path (not the Game global), so tools that run without
	# autoloads (godot -s ...) can still load the player scripts.
	var game := get_node_or_null("/root/Game") as GameState
	energy = base_energy * (game.brightness if game else 1.0)
