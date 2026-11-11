class_name ProtoCameraShots
extends Node
## Pictures and numbers for the camera test (needs a window):
## godot --path . res://proto3d/camera_test.tscn -- shots <folder>
## Saves both views (yaw 45 and yaw 0) in the tunnel and in the maze, with a
## pulse, then lets the Echo swim in the 8 key directions in each view and
## prints her floor speed and how fast that looks on screen.

const DIRECTIONS: Array[Array] = [
	["up", ["move_up"]], ["up + right", ["move_up", "move_right"]],
	["right", ["move_right"]], ["down + right", ["move_down", "move_right"]],
	["down", ["move_down"]], ["down + left", ["move_down", "move_left"]],
	["left", ["move_left"]], ["up + left", ["move_up", "move_left"]],
]

@export var test: ProtoCameraTest
@export var folder: String = ""
@export var settle_time: float = 1.2
@export var swim_time: float = 1.2


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()


func _run() -> void:
	test.creature.ai_enabled = false
	for room: int in [0, 1]:
		var markers: Dictionary = test.room_markers[room]
		test.echo.global_position = markers["Player1"]
		test.guardian.global_position = markers["Player2"]
		test.creature.global_position = markers["Creature1"]
		for yaw: float in [test.isometric_yaw, test.flat_yaw]:
			test.camera.yaw_degrees = yaw
			await _wait(maxf(settle_time, test.pulse.get_cooldown_left() + 0.1))
			await get_tree().physics_frame
			test.pulse.try_emit()
			await _wait(1.3)
			var file_name: String = "view_yaw%d_room%d.png" % [int(yaw), room + 1]
			await ProtoCapture.save_screen(self, folder.path_join(file_name))
			print("saved ", file_name)
			await _wait(test.sonar.get_lifetime())
	await _check_speeds()
	get_tree().quit()


## The Echo swims through open water (no walls, no leash) in every key
## direction: with full compensation the on-screen speed must be the same.
func _check_speeds() -> void:
	test.echo.collision_mask = 0
	test.echo.leash_distance = 100000.0
	for yaw: float in [test.isometric_yaw, test.flat_yaw]:
		test.camera.yaw_degrees = yaw
		await _wait(settle_time)
		var camera_yaw: float = test.camera.get_yaw()
		var camera_pitch: float = deg_to_rad(test.camera.pitch_degrees)
		print("CAMERA TEST speeds at yaw %d, pitch %d, compensation %d %%:" % [
			int(yaw), int(test.camera.pitch_degrees), int(test.camera.speed_compensation * 100.0)])
		for entry: Array in DIRECTIONS:
			for action: String in entry[1]:
				Input.action_press(test.echo.input_prefix + action)
			await _wait(swim_time)
			var velocity: Vector3 = test.echo.velocity
			var on_screen: float = velocity.length() * ProtoViewMotion.screen_length(velocity, camera_yaw, camera_pitch)
			print("  %-13s floor %.2f units/s (x %+.2f, z %+.2f)   on screen %.2f" % [
				entry[0], velocity.length(), velocity.x, velocity.z, on_screen])
			for action: String in entry[1]:
				Input.action_release(test.echo.input_prefix + action)
			await _wait(0.2)
			test.echo.velocity = Vector3.ZERO
			test.guardian.global_position = test.echo.global_position + Vector3(1.0, 0.0, 0.0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
