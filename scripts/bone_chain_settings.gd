class_name BoneChainSettings
extends Resource
## How the bone chains of one kind sway on a CharacterModel (BoneSway): every
## chain whose name starts with prefix ("Tail", "Antenna", "Cloak"...).

## Start of the chain's name in the model (<Name>_1 ... <Name>_end).
@export var prefix: String = ""
## Pull back to the modelled shape (0 = limp).
@export var stiffness: float = 1.0
## How much the water slows it (0 = swings freely, 1 = does not swing).
@export_range(0.0, 1.0) var drag: float = 0.5
## Weight pulling it down (negative = it floats up).
@export var gravity: float = 0.0
## Strength of the slow drift of the water, and how fast it changes.
@export var sway: float = 0.3
@export var sway_speed: float = 1.1
