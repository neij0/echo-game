class_name BoneSway
extends SpringBoneSimulator3D
## One swaying bone chain of a character model (a tail, an antenna, an ear, a
## strip of cloak): springs that trail behind when the character moves, plus
## a slow drift as if the water moved it (its own phase, so no two chains
## sway alike). A child of the model's Skeleton3D; made by CharacterModel.

var settings: BoneChainSettings
## Shifts this chain's drift against the others.
var phase: float = 0.0
var _time: float = 0.0


## The chain from root_bone to end_bone (names), with these settings.
func setup(root_bone: String, end_bone: String, chain_settings: BoneChainSettings, chain_phase: float) -> void:
	settings = chain_settings
	phase = chain_phase
	setting_count = 1
	set_root_bone_name(0, root_bone)
	set_end_bone_name(0, end_bone)
	set_stiffness(0, settings.stiffness)
	set_drag(0, settings.drag)
	set_gravity(0, settings.gravity)
	set_radius(0, 0.0)


func _process(delta: float) -> void:
	if settings == null:
		return
	_time += delta * settings.sway_speed
	# Three slow waves that never line up: a drift that does not repeat.
	external_force = Vector3(sin(_time + phase), 0.4 * sin(_time * 0.71 + phase * 1.7),
		sin(_time * 0.83 + phase * 2.3)) * settings.sway
