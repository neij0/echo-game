class_name StageDefinition
extends Resource
## One stage of a world: its levels in order (3 per stage). The last level ends
## in a boss arena. Progress is saved after every completed stage.

@export var levels: Array[LevelDefinition] = []


func get_level_count() -> int:
	return levels.size()
