class_name GlowEnvironment
extends WorldEnvironment
## 2D HDR glow: only colours brighter than glow_threshold bloom (sonar lines, the
## wave front, lit corals), so the dark background stays black.
## Needs rendering/viewport/hdr_2d enabled in the project settings.

@export var glow_enabled: bool = true
## Colours above this brightness glow. 1.0 = only HDR (over-bright) colours.
@export var glow_threshold: float = 1.0
@export var glow_intensity: float = 0.9
@export var glow_strength: float = 1.0
## How much brightness above the threshold adds to the glow.
@export var glow_hdr_scale: float = 2.0
## Weight of each blur level (small, tight glow -> wide, soft glow).
@export var glow_levels: PackedFloat32Array = PackedFloat32Array([0.0, 0.6, 1.0, 0.8, 0.5, 0.0, 0.0])
## Canvas layers up to this one get the glow; higher layers (the HUD) do not.
@export var glow_max_canvas_layer: int = 1


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = glow_max_canvas_layer
	env.glow_enabled = glow_enabled
	env.glow_hdr_threshold = glow_threshold
	env.glow_intensity = glow_intensity
	env.glow_strength = glow_strength
	env.glow_hdr_scale = glow_hdr_scale
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i: int in mini(glow_levels.size(), 7):
		env.set_glow_level(i, glow_levels[i])
	environment = env
