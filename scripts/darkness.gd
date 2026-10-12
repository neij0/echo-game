class_name Darkness
extends CanvasModulate
## The ambient layer: everything in the world not lit by a light is multiplied
## by this colour. It is a deep blue/teal, bright enough that rocks and the
## floor show as faint silhouettes; creatures stay hidden (their body is only
## drawn inside the Echo's light). Each stage has its own colours
## (StageDefinition): stage 1 is the brightest, the last one the darkest, and
## it fades a little darker as the players go down through the stage's levels
## (shared screen: uses their average depth).
## The Brightness setting (Game.brightness) multiplies this ambient colour only;
## lights, the pulse and the sonar are not affected.

@export var level_builder: LevelBuilder
## 0-1 stage progress (0 = top of level 1, 1 = bottom of the last level) where
## darkening starts...
@export_range(0.0, 1.0) var darken_start_progress: float = 0.15
## ...and where it reaches the stage's deep ambient colour.
@export_range(0.0, 1.0) var darken_end_progress: float = 0.9

var ambient_color: Color = Color(0.36, 0.52, 0.62)
var deep_ambient_color: Color = Color(0.32, 0.47, 0.57)


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
	var scale: float = Game.brightness
	return Color(minf(base.r * scale, 1.0), minf(base.g * scale, 1.0), minf(base.b * scale, 1.0), base.a)
