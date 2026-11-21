extends SceneTree
## Writes the BoneMap of the hand-made Echo (EchoRig from
## tools/blender/rig_echo.py) into the import settings of
## assets/models/characters/final/echo.glb: its humanoid bones are mapped
## onto Godot's SkeletonProfileHumanoid (and renamed to the profile's names
## on import, e.g. UpperArm.L -> LeftUpperArm), so humanoid animations can be
## retargeted onto her. The extra bones (tails, skirt, ears, antennae...)
## keep their names. Run once (the setting stays when the .glb is exported
## again), then reimport:
##   godot --headless --path . -s res://tools/setup_echo_bone_map.gd
##   godot --headless --path . --import

const IMPORT_FILE: String = "res://assets/models/characters/final/echo.glb.import"
const SKELETON_PATH: String = "PATH:EchoRig/Skeleton3D"
## Profile bone -> EchoRig bone (the left side; the right side swaps .L for .R).
const CENTRE: Dictionary[String, String] = {
	"Root": "Root", "Hips": "Hips", "Spine": "Spine", "Chest": "Chest", "UpperChest": "UpperChest",
	"Neck": "Neck", "Head": "Head",
}
const SIDE: Dictionary[String, String] = {
	"Eye": "Eye", "Shoulder": "Shoulder", "UpperArm": "UpperArm", "LowerArm": "LowerArm", "Hand": "Hand",
	"ThumbMetacarpal": "Thumb_1", "ThumbProximal": "Thumb_2", "ThumbDistal": "Thumb_3",
	"IndexProximal": "Index_1", "IndexIntermediate": "Index_2", "IndexDistal": "Index_3",
	"MiddleProximal": "Middle_1", "MiddleIntermediate": "Middle_2", "MiddleDistal": "Middle_3",
	"RingProximal": "Ring_1", "RingIntermediate": "Ring_2", "RingDistal": "Ring_3",
	"LittleProximal": "Little_1", "LittleIntermediate": "Little_2", "LittleDistal": "Little_3",
	"UpperLeg": "UpperLeg", "LowerLeg": "LowerLeg", "Foot": "Foot", "Toes": "Toes",
}


func _init() -> void:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_bone: String in CENTRE:
		bone_map.set_skeleton_bone_name(StringName(profile_bone), StringName(CENTRE[profile_bone]))
	for part: String in SIDE:
		bone_map.set_skeleton_bone_name(StringName("Left" + part), StringName(SIDE[part] + ".L"))
		bone_map.set_skeleton_bone_name(StringName("Right" + part), StringName(SIDE[part] + ".R"))
	var unmapped: PackedStringArray = []
	for i: int in bone_map.profile.bone_size:
		var profile_bone: StringName = bone_map.profile.get_bone_name(i)
		if bone_map.get_skeleton_bone_name(profile_bone) == &"":
			unmapped.append(profile_bone)
	var config := ConfigFile.new()
	if config.load(IMPORT_FILE) != OK:
		push_error("no import file: " + IMPORT_FILE)
		quit(1)
		return
	var subresources: Dictionary = config.get_value("params", "_subresources", {})
	var nodes: Dictionary = subresources.get("nodes", {})
	var skeleton: Dictionary = nodes.get(SKELETON_PATH, {})
	skeleton["retarget/bone_map"] = bone_map
	nodes[SKELETON_PATH] = skeleton
	subresources["nodes"] = nodes
	config.set_value("params", "_subresources", subresources)
	config.save(IMPORT_FILE)
	print("BONE MAP: %d profile bones mapped, not mapped: %s -> %s" % [
		bone_map.profile.bone_size - unmapped.size(), ", ".join(unmapped), IMPORT_FILE])
	quit()
