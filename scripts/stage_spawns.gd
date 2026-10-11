class_name StageSpawns
extends Resource
## What one stage of a world contains (part of WorldConfig.stages).

## Creature types and how many of each (picked from chunk creature markers).
@export var creatures: Array[CreatureSpawn] = []
@export var corals: int = 4
@export var stations: int = 2
## 0 = stations on the marker closest to the main path inside each side
## pocket, 1 = the furthest one (riskier to reach).
@export_range(0.0, 1.0) var station_distance_bias: float = 0.0
@export var middle_chunks_min: int = 5
@export var middle_chunks_max: int = 7
