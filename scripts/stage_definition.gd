class_name StageDefinition
extends Resource
## One stage of a world: its levels in order (3 per stage) and its lighting.
## The last level ends in a boss arena. Progress is saved after every completed
## stage. Stored inside the world's WorldConfig (.tres).

@export var levels: Array[LevelDefinition] = []

@export_group("Lighting")
## Base darkness (CanvasModulate) at the top of the stage's first level. Deeper
## stages use darker colours. Bright enough that rocks and the floor show as
## faint silhouettes; creatures stay hidden anyway (drawn only in the Echo's light).
@export var ambient_color: Color = Color(0.36, 0.52, 0.62)
## Base darkness at the bottom of the stage's last level (it fades towards
## this as the players go down).
@export var deep_ambient_color: Color = Color(0.32, 0.47, 0.57)
## 0 = no light shafts from above. 1 = the world's full shaft brightness.
@export_range(0.0, 1.0) var light_shaft_strength: float = 0.0


func get_level_count() -> int:
	return levels.size()
