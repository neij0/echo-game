class_name LandmarkPlacement
extends Resource
## One landmark of a level (part of LevelDefinition.landmarks): the same spot
## on every attempt, so the players learn it ("we're back at the wreck").

## Grid cell (column, row) of the room it stands in.
@export var cell: Vector2i = Vector2i.ZERO
## A Landmark scene (scenes/landmarks/<world>/).
@export var scene: PackedScene
## Its base point inside the room (pixels from the cell's top-left corner, in
## the level's orientation, i.e. after the room's quarter turns).
@export var offset: Vector2 = Vector2(800.0, 800.0)
