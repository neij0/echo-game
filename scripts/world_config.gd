class_name WorldConfig
extends Resource
## Everything that makes one world (Ocean, Caves, Desert, Forest, Snow) look
## and play differently. One .tres per world in worlds/. Scripts read these
## values (via the "world_listeners" group, see RunManager) instead of
## hard-coding anything world-specific.

@export var world_name: String = "Ocean"

@export_group("Chunks")
## Hand-made chunk scenes (LevelChunk). A stage = one start chunk, a random
## number of middle chunks, one goal chunk; a pocket chunk is attached to every
## side opening of the main chunks.
@export var start_chunks: Array[PackedScene] = []
@export var middle_chunks: Array[PackedScene] = []
@export var pocket_chunks: Array[PackedScene] = []
@export var goal_chunks: Array[PackedScene] = []

@export_group("Stages")
## One entry per stage, in order. The run has stages.size() stages.
@export var stages: Array[StageSpawns] = []
@export var coral_scene: PackedScene
@export var station_scene: PackedScene
@export var goal_scene: PackedScene

@export_group("Depth")
## Depth shown in the HUD at the top of stage 1.
@export var surface_depth_m: float = 200.0
@export var meters_per_pixel: float = 0.1
## Extra depth added for every stage (each stage starts deeper).
@export var stage_depth_step_m: float = 400.0

@export_group("Palette")
## CanvasModulate colour at the start of the run...
@export var ambient_color: Color = Color(0.06, 0.08, 0.14)
## ...and at the bottom of the last stage.
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
## 0-1: share of a full meter added to each player at the start of every stage
## after the first (the meter carries over between stages).
@export_range(0.0, 1.0) var pressure_stage_refill: float = 0.4
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


## Settings for a stage (0-based). Uses the last entry if there are fewer.
func get_stage(stage_index: int) -> StageSpawns:
	return stages[clampi(stage_index, 0, stages.size() - 1)]
