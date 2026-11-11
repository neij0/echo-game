class_name ProtoCapture
extends Node
## Screenshots + FPS for the prototype (needs a window):
## godot --path . res://proto3d/proto_room.tscn -- capture <folder>
## Poses the characters, saves the room without and with a pulse, a character
## behind a rock, then measures the frame rate with vsync off while pulsing.

@export var room: ProtoRoom
@export var folder: String = ""
@export var settle_time: float = 1.5
@export var bench_time: float = 6.0
@export var bench_pulse_every: float = 1.6

var _frames: int = 0
var _worst: float = 0.0
var _counting: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _counting:
		_frames += 1
		_worst = maxf(_worst, delta)


func _run() -> void:
	# The poses are fixed: nobody moves on their own.
	room.creature.ai_enabled = false
	room.creature.global_position = Vector3(-1.5, 0.0, 1.0)
	await _wait(settle_time)
	await _save("01_no_pulse")

	await get_tree().physics_frame
	room.pulse.try_emit()
	await _wait(0.5)
	await _save("02_pulse_wave")
	await _wait(0.9)
	await _save("03_pulse_revealed")
	await _wait(room.sonar.get_lifetime())

	# Guardian and creature behind the tall rocks, seen from the camera.
	room.guardian.global_position = Vector3(-8.2, 0.0, 2.6)
	room.echo.global_position = Vector3(-4.5, 0.0, 6.5)
	room.creature.global_position = Vector3(-5.6, 0.0, -4.6)
	await _wait(0.8)
	await _save("04_behind_rocks_no_pulse")
	await get_tree().physics_frame
	room.pulse.try_emit()
	await _wait(1.3)
	await _save("05_behind_rocks_pulse")

	await _check_play()
	await _bench()
	get_tree().quit()


## Plays a little through the real input actions: the Echo swims for a second
## (speed check) and the Guardian does a full combo on the revealed creature.
func _check_play() -> void:
	await _wait(room.sonar.get_lifetime())
	room.echo.global_position = Vector3(1.0, 0.0, 8.0)
	room.guardian.global_position = Vector3(3.0, 0.0, 8.0)
	room.guardian.facing = Vector3.RIGHT
	room.creature.global_position = Vector3(4.1, 0.0, 8.0)
	await _wait(1.0)
	var from: Vector3 = room.echo.global_position
	Input.action_press("p1_move_left")
	await _wait(1.0)
	var mid: Vector3 = room.echo.global_position
	await _wait(1.0)
	print("PROTO3D Echo speed: %.2f units/s after 1 s (max %.2f)" % [
		room.echo.global_position.distance_to(mid), room.echo.max_speed])
	Input.action_release("p1_move_left")
	room.echo.global_position = from
	await _wait(0.5)
	await get_tree().physics_frame
	room.pulse.try_emit()
	await _wait(0.6)
	var sword := room.guardian.get_node("Sword") as ProtoSword
	sword.hit_landed.connect(func(finisher: bool, killed: bool) -> void:
		print("PROTO3D sword hit: finisher=", finisher, " killed=", killed))
	for hit: int in 3:
		await _press("p2_action")
		await _wait(0.3)
	await _wait(0.3)
	print("PROTO3D combo on an Exposed creature: ", "killed" if room.creature.state == ProtoCreature.State.DEAD else "NOT killed")

	# One more swing for the picture, on the creature after it came back.
	room.creature.ai_enabled = true
	await _wait(room.creature.respawn_time + 0.5)
	room.creature.ai_enabled = false
	room.guardian.global_position = Vector3(3.0, 0.0, 8.0)
	room.guardian.facing = Vector3.RIGHT
	room.creature.global_position = Vector3(4.2, 0.0, 7.7)
	await get_tree().physics_frame
	room.pulse.try_emit()
	await _wait(0.6)
	await _press("p2_action")
	await _wait(0.07)
	await _save("06_sword_swing")


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _bench() -> void:
	room.creature.ai_enabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _wait(1.0)
	_frames = 0
	_worst = 0.0
	_counting = true
	var left: float = bench_time
	while left > 0.0:
		await get_tree().physics_frame
		room.sonar.emit_pulse(room.echo.global_position)
		await _wait(minf(bench_pulse_every, left))
		left -= bench_pulse_every
	_counting = false
	var size: Vector2i = get_window().size
	print("PROTO3D FPS (vsync off, %dx%d, pulsing): average %.0f, worst frame %.1f ms" % [
		size.x, size.y, float(_frames) / bench_time, _worst * 1000.0])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(file_name: String) -> void:
	await save_screen(self, folder.path_join(file_name + ".png"))
	print("saved ", file_name)


## Saves what node's viewport shows. The viewport is linear float data (HDR
## 2D): it is converted for the PNG.
static func save_screen(node: Node, path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = node.get_viewport().get_texture().get_image()
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		for y: int in image.get_height():
			for x: int in image.get_width():
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
		image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
