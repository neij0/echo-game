class_name WorldConfig
extends Resource
## Everything that makes one world (Ocean, Caves, Forest, Desert, Snow) look
## and play differently. One .tres per world in worlds/. Scripts read these
## values (via the "world_listeners" group, see StageManager) instead of
## hard-coding anything world-specific.
## Structure: World -> 3 stages (StageDefinition) -> 3 levels each (LevelDefinition).

## Must match an entry of the Game autoload's world_ids (used by the save file,
## the World Map and the story file names).
@export var world_id: String = "ocean"
@export var world_name: String = "Ocean"

@export_group("Stages")
## The world's stages, in order. Each one lists its levels.
@export var stages: Array[StageDefinition] = []
@export var coral_scene: PackedScene
@export var station_scene: PackedScene
@export var goal_scene: PackedScene

@export_group("Chunk Pools")
## Hand-made chunk scenes (LevelChunk) the level generator tool
## (tools/propose_level.gd) picks from. The game itself only uses the chunks
## listed in each LevelDefinition.
@export var start_chunks: Array[PackedScene] = []
@export var middle_chunks: Array[PackedScene] = []
@export var pocket_chunks: Array[PackedScene] = []
@export var goal_chunks: Array[PackedScene] = []
@export var boss_arena_chunks: Array[PackedScene] = []

@export_group("Depth")
## Depth shown in the HUD at the top of the world's first level.
@export var surface_depth_m: float = 200.0
@export var meters_per_pixel: float = 0.1
## Extra depth added for every level (each level starts deeper).
@export var level_depth_step_m: float = 400.0

@export_group("Palette")
## CanvasModulate colour at the start of a stage...
@export var ambient_color: Color = Color(0.06, 0.08, 0.14)
## ...and at the bottom of the stage's last level.
@export var deep_ambient_color: Color = Color(0.02, 0.025, 0.05)
@export var floor_color_shallow: Color = Color(0.16, 0.22, 0.27)
@export var floor_color_deep: Color = Color(0.08, 0.11, 0.14)
@export var rock_color: Color = Color(0.45, 0.42, 0.40)
## Sonar colours (wave front and revealed edges).
@export var ring_color: Color = Color(0.4, 0.9, 1.0, 0.9)
@export var edge_color: Color = Color(0.45, 0.95, 1.0)

@export_group("Pressure")
## What the world's survival pressure is called in the HUD (Oxygen, Cold, Heat...).
@export var pressure_name: String = "Oxygen"
## Seconds a full meter lasts without using abilities.
@export var pressure_drain_seconds: float = 180.0
## 0-1: below this the low warning (HUD + alarm) is on.
@export_range(0.0, 1.0) var pressure_low_threshold: float = 0.25
## 0-1: share of a full meter added to each player at the start of every level
## after the first one of a stage (the meter carries over between levels).
@export_range(0.0, 1.0) var pressure_level_refill: float = 0.4
@export var pressure_color: Color = Color(0.35, 0.8, 1.0)

@export_group("Pulse")
## Echo pulse in this world.
@export var pulse_radius: float = 650.0
## Seconds for the pulse front to reach pulse_radius (lower = faster).
@export var pulse_expand_time: float = 0.8
## 0-1: share of a full pressure meter each pulse costs.
@export_range(0.0, 1.0) var pulse_cost_ratio: float = 0.03


func get_stage_count() -> int:
	return stages.size()


## The stage (0-based). Uses the last entry if there are fewer.
func get_stage(stage_index: int) -> StageDefinition:
	return stages[clampi(stage_index, 0, stages.size() - 1)]


func get_level_count(stage_index: int) -> int:
	return get_stage(stage_index).get_level_count()


func get_level(stage_index: int, level_index: int) -> LevelDefinition:
	var stage: StageDefinition = get_stage(stage_index)
	return stage.levels[clampi(level_index, 0, stage.levels.size() - 1)]


## Index of a level counted from the world's very first level (for depth).
func get_global_level_index(stage_index: int, level_index: int) -> int:
	var total: int = 0
	for i: int in clampi(stage_index, 0, stages.size()):
		total += stages[i].get_level_count()
	return total + level_index
