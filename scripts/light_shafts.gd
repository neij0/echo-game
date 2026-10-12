class_name LightShafts
extends Node2D
## Environment light: faint, slowly swaying light shafts from the surface,
## drawn over the screen with additive blending. Only stages whose
## StageDefinition.light_shaft_strength is above 0 have them (the first stage),
## and they fade as the players go deeper through the stage. The look comes
## from the WorldConfig ("Light Shafts" group).
## Must live on a CanvasLayer (screen space) above the world.

@export var level_builder: LevelBuilder
## Soft edges: each shaft is drawn as this many nested bands.
@export var soft_layers: int = 8
## Seed for the shafts' positions and widths (the same layout every time).
@export var layout_seed: int = 7

var strength: float = 0.0
var color: Color = Color(0.55, 0.8, 0.95)
var alpha: float = 0.07
var count: int = 5
var width_min: float = 60.0
var width_max: float = 170.0
var angle_degrees: float = 18.0
var sway_amount: float = 40.0
var sway_speed: float = 0.05
var parallax: float = 0.15
var depth_fade: float = 0.7

var _offsets: PackedFloat32Array = PackedFloat32Array()
var _widths: PackedFloat32Array = PackedFloat32Array()
var _phases: PackedFloat32Array = PackedFloat32Array()
var _time: float = 0.0


func _ready() -> void:
	add_to_group("world_listeners")
	add_to_group("stage_listeners")
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	color = world.shaft_color
	alpha = world.shaft_alpha
	count = world.shaft_count
	width_min = world.shaft_width_min
	width_max = world.shaft_width_max
	angle_degrees = world.shaft_angle_degrees
	sway_amount = world.shaft_sway_amount
	sway_speed = world.shaft_sway_speed
	parallax = world.shaft_parallax
	depth_fade = world.shaft_depth_fade
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_offsets.resize(count)
	_widths.resize(count)
	_phases.resize(count)
	for i: int in count:
		# Spread over the screen width, with some randomness.
		_offsets[i] = (i + rng.randf_range(0.1, 0.9)) / count
		_widths[i] = rng.randf_range(width_min, width_max)
		_phases[i] = rng.randf() * TAU


## Called (via the "stage_listeners" group) by StageManager.
func apply_stage(stage: StageDefinition) -> void:
	strength = stage.light_shaft_strength
	visible = strength > 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var fade: float = 1.0 - depth_fade * _stage_progress()
	var shaft_alpha: float = alpha * strength * fade
	if shaft_alpha <= 0.0:
		return
	var screen: Vector2 = get_viewport_rect().size
	var camera: Camera2D = get_viewport().get_camera_2d()
	var camera_x: float = camera.get_screen_center_position().x if camera else 0.0
	var slant: float = tan(deg_to_rad(angle_degrees)) * screen.y
	var span: float = screen.x + width_max * 2.0 + absf(slant)
	for i: int in _offsets.size():
		var sway: float = sin(_time * TAU * sway_speed + _phases[i]) * sway_amount
		var x: float = fposmod(_offsets[i] * span - camera_x * parallax + sway, span) - width_max - maxf(slant, 0.0)
		for layer: int in soft_layers:
			# Nested bands: the narrower ones add up in the middle (soft edges).
			var width: float = _widths[i] * (1.0 - float(layer) / soft_layers)
			var top := Color(color, shaft_alpha / soft_layers)
			var bottom := Color(color, 0.0)
			var points := PackedVector2Array([
				Vector2(x - width * 0.5, 0.0), Vector2(x + width * 0.5, 0.0),
				Vector2(x + width * 0.5 + slant, screen.y), Vector2(x - width * 0.5 + slant, screen.y),
			])
			draw_polygon(points, PackedColorArray([top, top, bottom, bottom]))


## 0 at the top of the stage, 1 at its bottom (average of the players).
func _stage_progress() -> float:
	if level_builder == null:
		return 0.0
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return 0.0
	var total: float = 0.0
	for player: Player in players:
		total += level_builder.stage_progress_at(player.global_position.y)
	return total / players.size()
