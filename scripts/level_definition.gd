class_name LevelDefinition
extends Resource
## One hand-designed level: a fixed, ordered list of chunks, so its layout is
## always the same. What is NOT fixed: which chunk markers get the creatures,
## corals and stations. The LevelBuilder reshuffles those with a new seed on
## every attempt (retries included), so the darkness is never quite the same.
## One .tres per level in worlds/<world>/ (listed in a StageDefinition).
## tools/propose_level.gd can generate a new one from the world's chunk pools.

## The main path, top to bottom: a start chunk first, then the middle chunks,
## and last the end chunk (a goal chunk, or a boss arena chunk for a boss level).
@export var chunks: Array[PackedScene] = []
## One pocket chunk per side opening of the main path, in order from top to
## bottom (SideLeft before SideRight in the same chunk). If the list is shorter
## than the number of openings, it starts again from the first pocket.
@export var pockets: Array[PackedScene] = []

@export_group("Spawns")
## Creature types and how many of each (placed on random Creature markers of
## every main chunk except the start chunk).
@export var creatures: Array[CreatureSpawn] = []
## Corals placed on random Coral markers.
@export var corals: int = 4
## Pressure stations, each in a different random side pocket.
@export var stations: int = 2
## 0 = stations on the marker closest to the main path inside each side
## pocket, 1 = the furthest one (riskier to reach).
@export_range(0.0, 1.0) var station_distance_bias: float = 0.0

@export_group("Boss")
## Empty = a normal level: activating the ancient light (Goal marker) clears it.
## Set = a boss level: the boss spawns on the end chunk's Boss marker, and
## beating it completes the stage.
@export var boss: PackedScene
## Overrides the boss scene's max_health (0 = keep the scene's value).
@export var boss_max_health: int = 0


func is_boss_level() -> bool:
	return boss != null
