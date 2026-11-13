class_name ArenaPillar
extends RockWall
## A rock pillar in a boss arena's floor plan. In 3D the room scenes are plans
## (never in the tree): the LevelBuilder builds every pillar as rock like any
## wall (LevelChunk.get_wall_polygons). The breaking (a charging boss that
## runs into it is stunned and the pillar takes the blow: cracks after
## crack_at, breaks after break_at: rubble, dust, no collision, navigation
## rebaked) comes back with the Angler in Phase D; its values stay here.

@export_group("Blows")
@export var crack_at: int = 2
@export var break_at: int = 3

@export_group("Breaking")
@export var break_fade_time: float = 0.5
@export var rubble_count: int = 9
## World units.
@export var shake_strength: float = 0.18
@export var shake_time: float = 0.5
@export var crack_sound: String = "world_rock_fall"
@export var break_sound: String = "world_barrier_close"
