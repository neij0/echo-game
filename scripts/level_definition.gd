class_name LevelDefinition
extends Resource
## One hand-designed level: a small grid of rooms (e.g. 3x3 to 4x4 cells, not
## all filled). Each room chunk declares its openings (N/E/S/W) and can be
## turned in quarter turns; neighbouring rooms connect where both have an
## opening on the shared side, every other opening is sealed with rock. So the
## layout is always the same, with branches, loops and dead ends in any
## direction. What is NOT fixed: which room markers get the creatures, corals,
## stations and shards. The LevelBuilder reshuffles those with a new seed on
## every attempt (retries included).
## One .tres per level in worlds/<world>/ (listed in a StageDefinition).
## tools/propose_level.gd can generate a new grid from the world's room pool.

@export var rooms: Array[RoomPlacement] = []
## The room where the players start (its Player1 / Player2 markers).
@export var start_cell: Vector2i = Vector2i.ZERO
## The exit room: its Goal marker gets the ancient light (or, in a boss level,
## it is the boss arena and its Boss marker gets the boss).
@export var exit_cell: Vector2i = Vector2i.ZERO
## The lockdown room (LockdownRoom): when both players are inside, its
## doorways close and a wave of creatures wakes; they reopen once the wave is
## dead. (-1, -1) = none.
@export var lockdown_cell: Vector2i = Vector2i(-1, -1)
## Creatures in the lockdown wave (WorldConfig.lockdown_creature_scene).
@export var lockdown_wave_calm: int = 2
@export var lockdown_wave_challenge: int = 3

@export_group("Shards")
## Echo Shards to collect before the exit opens, each in a different room
## (never the start or exit room), spread over the branches.
@export var shard_count: int = 3
## Sentinels (WorldConfig.sentinel_scene) guarding that many of the shards
## (at most shard_count; which shards is picked by the spawn seed).
@export var sentinels: int = 1

@export_group("Spawns")
## Creature types and how many of each (placed on random Creature markers of
## every room except the start room).
@export var creatures: Array[CreatureSpawn] = []
## Corals placed on random Coral markers.
@export var corals: int = 4
## Pressure stations placed on random Station markers (not in the start room).
@export var stations: int = 2

@export_group("Collapse Escape")
## The stage's level-2 twist: after the last shard the level collapses
## (EscapeEvent). Every creature hunts the players and a timer runs; reaching
## the ancient light in time clears the level, otherwise both are downed.
@export var escape_event: bool = false
## Seconds to reach the exit per mode (tools/check_levels.gd checks they are at
## least 1.6x the longest shard -> exit walk at full speed).
@export var escape_time_calm: float = 90.0
@export var escape_time_challenge: float = 70.0

@export_group("Boss")
## Empty = a normal level: activating the ancient light clears it.
## Set = a boss level: the exit room must be a boss arena; the boss spawns on
## its Boss marker, and beating it completes the stage.
@export var boss: PackedScene
## Overrides the boss scene's max_health (0 = keep the scene's value).
@export var boss_max_health: int = 0


func is_boss_level() -> bool:
	return boss != null


func get_placement(cell: Vector2i) -> RoomPlacement:
	for placement: RoomPlacement in rooms:
		if placement.cell == cell:
			return placement
	return null


func has_lockdown() -> bool:
	return get_placement(lockdown_cell) != null


func get_lockdown_wave(challenge: bool) -> int:
	return lockdown_wave_challenge if challenge else lockdown_wave_calm


func get_escape_time(challenge: bool) -> float:
	return escape_time_challenge if challenge else escape_time_calm
