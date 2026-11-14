class_name GuardianMoves
extends CharacterMoves
## The Guardian's basic animations: a standing guard (a slight forward lean,
## one foot ahead, the greatsword held out low at his side at an angle, slow
## breathing), walking (legs stride, the free arm swings) and the sword swing
## (the sword arm and the blade follow the slash of the SwordAbility), blended
## by speed and by the attack.

## How far the legs and the free arm swing in a stride (as a lean of the bone),
## and how much the knee of the lifted leg bends.
@export var leg_swing: float = 0.5
@export var arm_swing: float = 0.3
@export var knee_bend: float = 0.55
## The forward lean of the spine and chest.
@export var lean: float = 0.16
@export var breath: float = 0.015
## Where the sword points at rest (out to his right, a little down and ahead:
## it shows from every side).
@export var sword_rest: Vector3 = Vector3(-0.7, -0.62, 0.35)
## How far below the slash the blade tips while swinging.
@export var swing_dip: float = 0.12


func aims(time: float, stride: float, speed: float, action: float, action_direction: Vector3) -> Dictionary[String, Vector3]:
	var result: Dictionary[String, Vector3] = {}
	var walk: float = smoothstep(0.0, 0.6, speed)
	var swing: float = sin(stride)
	var lift: float = cos(stride)
	var attack: float = smoothstep(0.0, 1.0, action)
	var slash: Vector3 = action_direction.normalized() if action_direction.length() > 0.01 else Vector3.BACK
	# Legs: a guard stance standing, a stride walking.
	var left_thigh := Vector3(0.08, -1.0, 0.16).lerp(Vector3(0.04, -1.0, leg_swing * swing), walk)
	var left_shin := Vector3(0.05, -1.0, -0.05).lerp(Vector3(0.04, -1.0, leg_swing * swing - knee_bend * maxf(lift, 0.0) - 0.05), walk)
	var right_thigh := Vector3(-0.1, -1.0, -0.1).lerp(Vector3(-0.04, -1.0, -leg_swing * swing), walk)
	var right_shin := Vector3(-0.08, -1.0, -0.24).lerp(Vector3(-0.04, -1.0, -leg_swing * swing - knee_bend * maxf(-lift, 0.0) - 0.05), walk)
	result["LeftUpperLeg"] = left_thigh
	result["LeftLowerLeg"] = left_shin
	result["RightUpperLeg"] = right_thigh
	result["RightLowerLeg"] = right_shin
	result["LeftFoot"] = Vector3(0.1, -0.2, 1.0).lerp(Vector3(0.0, -0.2 - 0.5 * maxf(lift, 0.0), 1.0), walk)
	result["RightFoot"] = Vector3(-0.18, -0.2, 1.0).lerp(Vector3(0.0, -0.2 - 0.5 * maxf(-lift, 0.0), 1.0), walk)
	# Body: leaning forward, breathing; it turns into the swing.
	var breathing: float = sin(time * idle_speed) * breath
	result["Spine"] = Vector3(0.0, 1.0, lean * 0.7)
	result["Chest"] = Vector3(0.0, 1.0, lean + breathing).lerp(Vector3(slash.x * 0.28, 1.0, lean + slash.z * 0.12), attack)
	result["Head"] = Vector3(0.0, 1.0, 0.08)
	# The free arm.
	result["LeftUpperArm"] = Vector3(0.26, -1.0, 0.05).lerp(Vector3(0.22, -1.0, -arm_swing * swing), walk)
	result["LeftLowerArm"] = Vector3(0.14, -1.0, 0.32).lerp(Vector3(0.14, -1.0, -arm_swing * swing + 0.28), walk)
	# The sword arm: held out low at his side; in a swing the arm and the
	# blade follow the slash.
	result["RightUpperArm"] = Vector3(-0.5, -1.0, 0.0).lerp((slash * 0.8 + Vector3(-0.2, -0.6, 0.0)).normalized(), attack)
	result["RightLowerArm"] = Vector3(-0.6, -0.9, 0.25).lerp((slash + Vector3(0.0, -0.28, 0.0)).normalized(), attack)
	result["Sword"] = sword_rest.normalized().lerp((slash + Vector3(0.0, -swing_dip, 0.0)).normalized(), attack)
	return result
