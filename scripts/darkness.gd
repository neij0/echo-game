class_name Darkness
extends CanvasModulate
## The ambient layer: everything in the world not lit by a light is multiplied
## by this colour. A near-black deep blue, so the level cannot be read from a
## distance: what is near is shown by real lights (the Echo's PlayerLight,
## corals, the ancient light), the far layout only by the pulse's sonar edges.
## Each stage has its own colours (StageDefinition): stage 1 is the brightest,
## the last one the darkest, and it fades a little darker as the players go
## down through the stage's levels (shared screen: uses their average depth).
## The Brightness setting (Game.brightness, a narrow range) scales it a little.

@export var level_builder: LevelBuilder
## 0-1 stage progress (0 = top of level 1, 1 = bottom of the last level) where
## darkening starts...
@export_range(0.0, 1.0) var darken_start_progress: float = 0.15
## ...and where it reaches the stage's deep ambient colour.
@export_range(0.0, 1.0) var darken_end_progress: float = 0.9

var ambient_color: Color = Color(0.18, 0.26, 0.31)
var deep_ambient_color: Color = Color(0.16, 0.23, 0.28)


func _ready() -> void:
	add_to_group("stage_listeners")


## Called (via the "stage_listeners" group) by StageManager.
func apply_stage(stage: StageDefinition) -> void:
	ambient_color = stage.ambient_color
	deep_ambient_color = stage.deep_ambient_color
	color = _with_brightness(ambient_color)


func _process(_delta: float) -> void:
	if level_builder == null:
		return
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return
	var total: float = 0.0
	for player: Player in players:
		total += level_builder.stage_progress_at(player.global_position.y)
	var progress: float = total / players.size()
	var t: float = clampf((progress - darken_start_progress) / (darken_end_progress - darken_start_progress), 0.0, 1.0)
	color = _with_brightness(ambient_color.lerp(deep_ambient_color, t))


func _with_brightness(base: Color) -> Color:
	return Color(base.r * Game.brightness, base.g * Game.brightness, base.b * Game.brightness, base.a)
