class_name Darkness
extends CanvasModulate
## The base darkness of the world: everything not lit by a light is multiplied
## by this colour. Brighter = the floor shows a little inside lights, but areas
## far from any light also get less black. How much floor shows around the
## players depends mostly on their light energy.
## The colours come from the WorldConfig; it gets darker as the players go
## deeper through the run's stages (shared screen: uses their average depth).

@export var stage_builder: StageBuilder
## 0-1 run progress (0 = top of stage 1, 1 = bottom of the last stage) where
## darkening starts...
@export_range(0.0, 1.0) var darken_start_progress: float = 0.15
## ...and where it reaches the world's deep ambient colour.
@export_range(0.0, 1.0) var darken_end_progress: float = 0.9

var ambient_color: Color = Color(0.06, 0.08, 0.14)
var deep_ambient_color: Color = Color(0.02, 0.025, 0.05)


func _ready() -> void:
	add_to_group("world_listeners")


## Called (via the "world_listeners" group) by RunManager.
func apply_world(world: WorldConfig) -> void:
	ambient_color = world.ambient_color
	deep_ambient_color = world.deep_ambient_color
	color = ambient_color


func _process(_delta: float) -> void:
	if stage_builder == null:
		return
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return
	var total: float = 0.0
	for player: Player in players:
		total += stage_builder.run_progress_at(player.global_position.y)
	var progress: float = total / players.size()
	var t: float = clampf((progress - darken_start_progress) / (darken_end_progress - darken_start_progress), 0.0, 1.0)
	color = ambient_color.lerp(deep_ambient_color, t)
