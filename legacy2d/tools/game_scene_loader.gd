class_name GameSceneLoader
extends RefCounted
## Loads the real game.tscn for the scene tests and the fight sim.
## game.tscn keeps the F6 playtest settings of the StageManager (test_stage_index,
## test_level_index, test_start_at, test_skills); they only apply when the game
## does not start from the menus, which is always the case in a test. They are
## reset here, so whatever is saved in the scene for playtesting never changes
## a test. Call before add_child (the StageManager reads them in _ready).

const GAME_SCENE: String = "res://scenes/game.tscn"


static func instantiate(mode: SaveData.Mode) -> Node2D:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	var stage := game.get_node("StageManager") as StageManager
	stage.test_stage_index = 0
	stage.test_level_index = 0
	stage.test_start_at = StageManager.TestStart.LEVEL_START
	stage.test_skills = PackedStringArray()
	stage.test_mode = mode
	return game
