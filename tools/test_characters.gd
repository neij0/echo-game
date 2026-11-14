extends Node3D
## Headless checks of the blockout character models (Phase C silhouette pass):
## godot --headless --path . --fixed-fps 60 res://tools/test_characters.tscn
## Every variant of the Echo and the Guardian: it loads, has the humanoid rig
## and its bone chains, wears the shared character shader, stands in its pose
## (arms down, not the T-pose), stays inside the triangle budget; the Echo is
## pale, glows only in the pulse's cyan / white (no gold), is small and has
## flat human feet; the Guardian is dark and tall, glows only in warm amber /
## gold and carries his sword; the chains drift a little at rest, trail when
## the character moves (without streaming out flat) and settle again.
## "-- log" prints how far every chain's end moves.

const HUMANOID: Array[String] = ["Hips", "Spine", "Chest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

@export var max_triangles: int = 4000
## Seconds a new model is left to settle (it starts in its modelled shape
## and is lifted to its hover height), the chains are watched at rest, and
## while the model moves.
@export var settle_time: float = 1.5
@export var rest_time: float = 4.0
@export var move_time: float = 1.5
## Largest angle (degrees) a chain's end may swing from its modelled place at
## rest, and while the character moves at its full speed.
@export var max_rest_swing: float = 30.0
@export var max_cloak_trail: float = 40.0
@export var max_chain_trail: float = 120.0

var _checks: int = 0
var _failed: int = 0
var _log: bool = false
## Chain name -> the end bone's place in the model's space, read after the
## skeleton's modifiers ran.
var _ends: Dictionary[String, Vector3] = {}
var _watched: CharacterModel


func _ready() -> void:
	_log = OS.get_cmdline_user_args().has("log")
	_run.call_deferred()


func _run() -> void:
	var heads: Dictionary[String, float] = {}
	for variant: int in 3:
		heads["echo"] = await _check_character("echo", variant, CharacterTest.ECHO_BLOCKOUT, 5.2)
		heads["guardian"] = await _check_character("guardian", variant, CharacterTest.GUARDIAN_BLOCKOUT, 4.6)
	_check(heads["guardian"] > heads["echo"] * 1.5, "the Guardian stands at least 1.5x as tall as the Echo (%.2f vs %.2f)" % [
		heads["guardian"], heads["echo"]])
	print("CHARACTER TEST: %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Returns the height of the top of the head (the rig's Head bone, at rest).
func _check_character(character: String, variant: int, scene: PackedScene, speed: float) -> float:
	var label: String = "%s %s" % [character, CharacterTest.VARIANTS[variant].to_upper()]
	var model := scene.instantiate() as CharacterModel
	model.model = CharacterTest.model_of(character, variant)
	add_child(model)
	var skeleton: Skeleton3D = model.get_skeleton()
	_check(skeleton != null, "%s: has a skeleton" % label)
	if skeleton == null:
		model.free()
		return 0.0
	var missing := PackedStringArray()
	for bone: String in HUMANOID:
		if skeleton.find_bone(bone) < 0:
			missing.append(bone)
	_check(missing.is_empty(), "%s: has every humanoid bone (missing: %s)" % [label, ", ".join(missing)])

	var triangles: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			triangles += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_check(triangles > 500 and triangles <= max_triangles, "%s: %d triangles (at most %d)" % [label, triangles, max_triangles])

	var materials: Array[ShaderMaterial] = model.get_materials()
	var shared: bool = not materials.is_empty()
	var glows: int = 0
	var wrong_glow := PackedStringArray()
	var body := Color.BLACK
	for material: ShaderMaterial in materials:
		shared = shared and material.shader == CharacterModel.BODY_SHADER and material.next_pass != null
		var energy: float = material.get_shader_parameter("glow_energy") if material.get_shader_parameter("glow_energy") != null else 0.0
		if energy > 0.0:
			glows += 1
			var glow: Color = material.get_shader_parameter("glow_color")
			# The Echo: cyan / white (blue at least as strong as red). The
			# Guardian: warm (red clearly stronger than blue).
			if (character == "echo" and glow.b < glow.r) or (character == "guardian" and glow.r <= glow.b):
				wrong_glow.append(material.resource_name)
		elif material.resource_name.ends_with("_body") or material.resource_name.ends_with("_cloak"):
			body = material.get_shader_parameter("body_color")
	_check(shared, "%s: every surface wears the shared character shader and the outline through rock" % label)
	_check(glows >= 2, "%s: has glowing parts (%d)" % [label, glows])
	if character == "echo":
		_check(wrong_glow.is_empty(), "%s: glows only in cyan / white, no gold (%s)" % [label, ", ".join(wrong_glow)])
		_check(body.get_luminance() > 0.4, "%s: the body is pale (%.2f)" % [label, body.get_luminance()])
	else:
		_check(wrong_glow.is_empty(), "%s: glows only in amber / gold (%s)" % [label, ", ".join(wrong_glow)])
		_check(body.get_luminance() < 0.25, "%s: the cloak is dark (%.2f)" % [label, body.get_luminance()])
		_check(skeleton.find_bone("Sword") >= 0, "%s: carries the sword on its own bone" % label)

	# The pose: arms down. The rest (T-pose): feet flat on the floor.
	var hand: float = skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.y
	var shoulder: float = skeleton.get_bone_global_pose(skeleton.find_bone("LeftUpperArm")).origin.y
	_check(hand < shoulder - 0.15 * shoulder, "%s: the arms hang down in the pose (hand %.2f, shoulder %.2f)" % [label, hand, shoulder])
	var hip: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("LeftUpperLeg")).origin
	var knee: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("LeftLowerLeg")).origin
	var ankle: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("LeftFoot")).origin
	var toes: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone("LeftToes")).origin
	var leg: float = hip.y - ankle.y
	# A human leg: the ankle sits just above the floor (no raised heel as on a
	# hoof or a toe-walker), the foot lies forward of it on the floor, and the
	# knee is on the straight line from hip to ankle (it does not bend back).
	_check(ankle.y < leg * 0.2 and toes.y <= ankle.y and toes.z > ankle.z + leg * 0.08,
		"%s: flat human feet (ankle %.2f high on a %.2f leg, toes %.2f ahead)" % [label, ankle.y, leg, toes.z - ankle.z])
	_check(knee.z > lerpf(hip.z, ankle.z, 0.5) - leg * 0.03 and absf(knee.y - lerpf(hip.y, ankle.y, 0.5)) < leg * 0.15,
		"%s: straight human legs (the knee does not bend backwards)" % label)

	# The chains.
	var chains: PackedStringArray = model.get_chain_names()
	var expected: Array[String] = ["AntennaL", "AntennaR", "Tail"]
	if character == "guardian":
		expected = ["CloakL", "CloakFL", "CloakFR", "CloakR", "CloakBR", "CloakBL"]
	var absent := PackedStringArray()
	for chain: String in expected:
		if not chains.has(chain):
			absent.append(chain)
	_check(absent.is_empty(), "%s: has its swaying chains (missing: %s; has %d)" % [label, ", ".join(absent), chains.size()])
	_watched = model
	skeleton.skeleton_updated.connect(_read_ends)
	await get_tree().process_frame
	await get_tree().process_frame
	var modelled: Dictionary[String, Vector3] = {}
	var roots: Dictionary[String, Vector3] = {}
	for chain: String in chains:
		modelled[chain] = skeleton.get_bone_global_pose(skeleton.find_bone(chain + "_end")).origin
		roots[chain] = skeleton.get_bone_global_pose(skeleton.find_bone(chain + "_1")).origin
	# At rest: every chain drifts, none swings far.
	var rest: Dictionary[String, Vector2] = await _watch(chains, modelled, roots, rest_time + settle_time, Vector3.ZERO, settle_time)
	var still := PackedStringArray()
	var wild := PackedStringArray()
	for chain: String in chains:
		if rest[chain].x < 0.3:
			still.append("%s %.1f" % [chain, rest[chain].x])
		if rest[chain].y > max_rest_swing:
			wild.append("%s %.0f" % [chain, rest[chain].y])
	_check(still.is_empty(), "%s: every chain drifts at rest (too still, degrees: %s)" % [label, ", ".join(still)])
	_check(wild.is_empty(), "%s: no chain swings far at rest (degrees: %s)" % [label, ", ".join(wild)])
	# Moving sideways at full speed: the chains trail, the cloak keeps its shape.
	var moving: Dictionary[String, Vector2] = await _watch(chains, modelled, roots, move_time, Vector3(speed, 0.0, 0.0))
	var stiff := PackedStringArray()
	var streaming := PackedStringArray()
	for chain: String in chains:
		if moving[chain].y < rest[chain].y + 1.0:
			stiff.append("%s %.1f" % [chain, moving[chain].y])
		if moving[chain].y > (max_cloak_trail if chain.begins_with("Cloak") else max_chain_trail):
			streaming.append("%s %.0f" % [chain, moving[chain].y])
	_check(stiff.is_empty(), "%s: every chain trails when the character moves (degrees: %s)" % [label, ", ".join(stiff)])
	_check(streaming.is_empty(), "%s: no chain streams out flat at full speed (degrees: %s)" % [label, ", ".join(streaming)])
	# Standing again: back near the modelled shape.
	var settled: Dictionary[String, Vector2] = await _watch(chains, modelled, roots, settle_time + 1.0, Vector3.ZERO, settle_time)
	var off := PackedStringArray()
	for chain: String in chains:
		if settled[chain].y > max_rest_swing:
			off.append("%s %.0f" % [chain, settled[chain].y])
	_check(off.is_empty(), "%s: the chains settle again after moving (degrees: %s)" % [label, ", ".join(off)])
	if _log:
		for chain: String in chains:
			print("  %s %-10s rest: drift %.1f, swing %.1f   moving: swing %.1f   settled: %.1f (degrees)" % [label, chain,
				rest[chain].x, rest[chain].y, moving[chain].y, settled[chain].y])

	var head: float = skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin.y
	_watched = null
	model.free()
	return head


## Watches the chains' ends for some seconds while the model moves at
## velocity (skip: seconds ignored at the start). Per chain: x = how far the
## end wandered (degrees, seen from the chain's root), y = its largest angle
## from the modelled place.
func _watch(chains: PackedStringArray, modelled: Dictionary[String, Vector3], roots: Dictionary[String, Vector3], seconds: float,
		velocity: Vector3, skip: float = 0.0) -> Dictionary[String, Vector2]:
	var low: Dictionary[String, float] = {}
	var high: Dictionary[String, float] = {}
	var first: Dictionary[String, Vector3] = {}
	var wander: Dictionary[String, float] = {}
	var left: float = seconds
	while left > 0.0:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		left -= delta
		_watched.position += velocity * delta
		if seconds - left < skip:
			continue
		for chain: String in chains:
			if not _ends.has(chain):
				continue
			var now: Vector3 = _ends[chain] - roots[chain]
			var angle: float = rad_to_deg(now.angle_to(modelled[chain] - roots[chain]))
			high[chain] = maxf(high.get(chain, 0.0), angle)
			if not first.has(chain):
				first[chain] = now
			wander[chain] = maxf(wander.get(chain, 0.0), rad_to_deg(now.angle_to(first[chain])))
	var result: Dictionary[String, Vector2] = {}
	for chain: String in chains:
		result[chain] = Vector2(wander.get(chain, 0.0), high.get(chain, 0.0))
	return result


func _read_ends() -> void:
	if _watched == null:
		return
	var skeleton: Skeleton3D = _watched.get_skeleton()
	for chain: String in _watched.get_chain_names():
		_ends[chain] = skeleton.get_bone_global_pose(skeleton.find_bone(chain + "_end")).origin


func _check(passed: bool, text: String) -> void:
	_checks += 1
	if not passed:
		_failed += 1
	print("%s  %s" % ["ok  " if passed else "FAIL", text])
