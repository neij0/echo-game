class_name PlayerLight
extends OmniLight3D
## A player's own light, with real shadows: rock blocks it. The Echo carries
## the main light of the game (warm, soft, 5.6 units = the 2D game's ~280 px);
## the Guardian only a faint, small one, just enough to see himself and the
## rock right beside him, so he has to stay near the Echo to see. It also
## lights the fog round the player (volumetric fog).
## The Brightness setting (Game.brightness) scales the energy a little.

## Distance in world units where the light has faded to nothing.
@export var radius: float = 5.6
@export var base_energy: float = 8.0
@export var light_color_tint: Color = Color(1.0, 0.86, 0.62)
## How fast the light falls off with distance (1 = natural, higher = tighter).
@export var falloff: float = 1.0
@export var shadows: bool = true
## How strongly it lights the fog.
@export var fog_energy: float = 2.0


func _ready() -> void:
	add_to_group("player_lights")
	omni_range = radius
	omni_attenuation = falloff
	light_color = light_color_tint
	light_energy = base_energy
	shadow_enabled = shadows
	light_volumetric_fog_energy = fog_energy


func _process(_delta: float) -> void:
	# Looked up by path (not the Game global), so tools that run without
	# autoloads (godot -s ...) can still load the player scripts.
	var game := get_node_or_null("/root/Game") as GameState
	light_energy = base_energy * (game.brightness if game else 1.0)
