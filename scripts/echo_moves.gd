class_name EchoMoves
extends CharacterMoves
## The Echo's basic animations: floating idle (arms loose, legs hanging, a
## slow sway), swimming (arms swept back, legs trailing with a flutter kick)
## and the pulse pose (arms flung wide, chest and head lifted), blended by
## speed and by the pulse.

## Size of the idle sway and of the swim kick (as a lean of the bone).
@export var idle_sway: float = 0.06
@export var kick_size: float = 0.32


func aims(time: float, stride: float, speed: float, action: float, _action_direction: Vector3) -> Dictionary[String, Vector3]:
	var result: Dictionary[String, Vector3] = {}
	var sway: float = sin(time * idle_speed) * idle_sway
	var pulse: float = smoothstep(0.0, 1.0, action)
	var swim: float = smoothstep(0.0, 1.0, speed)
	for side: float in [1.0, -1.0]:
		var prefix: String = "Left" if side > 0.0 else "Right"
		var kick: float = sin(stride) * side * kick_size
		# Floating: the left leg a little forward, the right hanging straight.
		var thigh_idle := Vector3(0.05 * side, -1.0, (0.2 if side > 0.0 else 0.03) + sway * side)
		var shin_idle := Vector3(0.03 * side, -1.0, -0.32 if side > 0.0 else -0.12)
		var upper_arm := Vector3(0.4 * side, -1.0, -0.15 + sway).lerp(Vector3(0.32 * side, -0.55, -0.8), swim)
		var lower_arm := Vector3(0.3 * side, -1.0, 0.2).lerp(Vector3(0.16 * side, -0.45, -0.9), swim)
		var thigh := thigh_idle.lerp(Vector3(0.05 * side, -1.0, -0.3 + kick), swim)
		var shin := shin_idle.lerp(Vector3(0.03 * side, -1.0, -0.75 + kick * 0.6), swim)
		var foot := Vector3(0.0, -0.46, 0.89).lerp(Vector3(0.0, -0.95, -0.3), swim)
		# The pulse: arms wide and raised, legs together.
		result[prefix + "UpperArm"] = upper_arm.lerp(Vector3(side, 0.35, 0.05), pulse)
		result[prefix + "LowerArm"] = lower_arm.lerp(Vector3(side, 0.65, 0.1), pulse)
		result[prefix + "UpperLeg"] = thigh.lerp(Vector3(0.04 * side, -1.0, 0.02), pulse)
		result[prefix + "LowerLeg"] = shin.lerp(Vector3(0.03 * side, -1.0, -0.1), pulse)
		result[prefix + "Foot"] = foot.lerp(Vector3(0.0, -0.8, 0.6), pulse)
	result["Chest"] = Vector3(0.0, 1.0, 0.0).lerp(Vector3(0.0, 1.0, -0.16), pulse)
	result["Head"] = Vector3(0.0, 1.0, sway * 0.5).lerp(Vector3(0.0, 1.0, -0.3), pulse)
	return result
