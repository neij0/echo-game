class_name CharacterMoves
extends Resource
## The basic animations of a character model, made in code until the final
## rig and clips (Mixamo for the Guardian) replace them: for every frame, the
## direction each bone points along, in the model's own space (x = the
## character's left, y = up, z = forward). CharacterModel aims the bones.
## One script per character extends this (EchoMoves, GuardianMoves).

## World units the character travels in one full stride (two steps / kicks).
@export var stride_length: float = 1.4
## How fast the idle motion runs.
@export var idle_speed: float = 1.4


## time: seconds; stride: the phase of the stride (radians, grows with the
## distance travelled); speed: 0 standing ... 1 full speed; action: 0 ... 1,
## how far into its action the character is (the Echo's pulse pose, the
## Guardian's swing); action_direction: where the action points (the blade).
func aims(_time: float, _stride: float, _speed: float, _action: float, _action_direction: Vector3) -> Dictionary[String, Vector3]:
	return {}
