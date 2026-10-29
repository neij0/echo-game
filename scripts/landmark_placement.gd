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

@export_group("Variation")
## Every placement of the same landmark looks different: mirrored left-right,
## its size, a turn on the floor (only landmarks lying on the floor use it:
## the wreck, the whale), how damaged it is (which parts are left, broken
## ends, debris), and a variant number that picks the details (debris layout,
## lengths, leans).
@export var mirrored: bool = false
@export_range(0.6, 1.5) var size_scale: float = 1.0
@export_range(-180.0, 180.0) var floor_turn_degrees: float = 0.0
@export_range(0.0, 1.0) var damage: float = 0.5
@export var variant: int = 0
## Overrides the landmark's floor accent (alpha 0 = keep the scene's).
@export var accent_color: Color = Color(0.0, 0.0, 0.0, 0.0)
