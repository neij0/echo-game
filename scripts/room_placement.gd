class_name RoomPlacement
extends Resource
## One room of a level's grid (part of LevelDefinition.rooms).

## Grid cell (column, row). Rows grow downwards.
@export var cell: Vector2i = Vector2i.ZERO
## A room chunk scene (LevelChunk).
@export var room: PackedScene
## Clockwise quarter turns (0-3) applied to the room (and its openings).
@export_range(0, 3) var quarter_turns: int = 0
