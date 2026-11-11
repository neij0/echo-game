extends Node2D
## Look preview of the Angler boss, in the game's real lighting (stage 1
## darkness, the Echo's and Guardian's own lights, HDR glow).
## Interactive (run tools/angler_preview.tscn with F6): 1 idle, 2 telegraph,
## 3 charge, 4 bite, 5 Exposed on/off, 6 stunned, 7 phase change (roar),
## 8 death, 9 intro, 0 hit, R reset. Arrow keys / WASD move the players as usual.
## Capture (needs a window, not --headless):
##   godot --path . res://tools/angler_preview.tscn -- capture <folder>
## saves one PNG per state into <folder> (linear HDR -> sRGB per pixel).

const ECHO_SCENE: String = "res://scenes/echo.tscn"
const GUARDIAN_SCENE: String = "res://scenes/guardian.tscn"

@export var boss_position: Vector2 = Vector2(640.0, 330.0)
@export var echo_offset: Vector2 = Vector2(-250.0, 150.0)
@export var guardian_offset: Vector2 = Vector2(-175.0, 165.0)
@export var floor_size: Vector2 = Vector2(4000.0, 3000.0)

var _boss: Node2D
var _visual: AnglerVisual
var _title: BossTitle
var _camera: Camera2D
var _echo: Player
var _guardian: Player
var _charge_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	var world: WorldConfig = Game.get_world_config("ocean")
	var stage: StageDefinition = world.get_stage(0) if world else null
	var darkness := CanvasModulate.new()
	darkness.color = stage.ambient_color if stage else Color(0.18, 0.26, 0.31)
	add_child(darkness)
	var floor_rect := ColorRect.new()
	floor_rect.color = world.floor_color_shallow if world else Color(0.2, 0.3, 0.36)
	floor_rect.size = floor_size
	floor_rect.position = boss_position - floor_size * 0.5
	floor_rect.z_index = -4
	add_child(floor_rect)
	add_child(GlowEnvironment.new())
	var audio := AudioDirector.new()
	add_child(audio)
	_camera = Camera2D.new()
	_camera.position = boss_position
	add_child(_camera)
	_echo = (load(ECHO_SCENE) as PackedScene).instantiate() as Player
	_guardian = (load(GUARDIAN_SCENE) as PackedScene).instantiate() as Player
	add_child(_echo)
	add_child(_guardian)
	_title = BossTitle.new()
	add_child(_title)
	_reset()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "capture":
		_capture_all.call_deferred(args[1])


func _process(delta: float) -> void:
	if _boss and _charge_velocity != Vector2.ZERO:
		_boss.position += _charge_velocity * delta
		_camera.position = _boss.position
	# The players never lose their meters in the preview.
	for player: Player in [_echo, _guardian]:
		player.pressure.refill()


func _reset() -> void:
	if _boss:
		_boss.queue_free()
	_charge_velocity = Vector2.ZERO
	_camera.position = boss_position
	_echo.global_position = boss_position + echo_offset
	_guardian.global_position = boss_position + guardian_offset
	_boss = Node2D.new()
	_boss.position = boss_position
	add_child(_boss)
	_visual = AnglerVisual.new()
	_boss.add_child(_visual)
	var voice := AnglerVoice.new()
	voice.visual = _visual
	_boss.add_child(voice)
	_visual.snap_heading(Vector2(-1.0, 0.25))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_reset()
		KEY_2:
			_telegraph()
		KEY_3:
			_charge()
		KEY_4:
			_visual.bite()
		KEY_5:
			_visual.set_exposed(0.0 if _visual._exposed_target > 0.5 else 1.0)
		KEY_6:
			_visual.set_state(AnglerVisual.State.STUNNED)
		KEY_7:
			_visual.roar()
		KEY_8:
			_visual.die()
		KEY_9:
			_intro()
		KEY_0:
			_visual.hit(_guardian.global_position)
		KEY_R:
			_reset()


func _telegraph() -> void:
	_visual.face(_echo.global_position - _boss.global_position)
	_visual.set_state(AnglerVisual.State.TELEGRAPH)


func _charge() -> void:
	_boss.position = boss_position + Vector2(380.0, -60.0)
	_visual.snap_heading(Vector2(-1.0, 0.15))
	_visual.face(Vector2.ZERO)
	_charge_velocity = Vector2(-1.0, 0.15).normalized() * 560.0
	_visual.set_motion(_charge_velocity)
	_visual.set_state(AnglerVisual.State.CHARGE)


## The lure alone far away swims closer, then the flash reveals the body.
func _intro() -> void:
	_reset()
	_boss.position = boss_position + Vector2(0.0, -420.0)
	_visual.snap_heading(Vector2.DOWN)
	_visual.hide_for_intro()
	_charge_velocity = Vector2(0.0, 150.0)
	_visual.set_motion(_charge_velocity)
	await get_tree().create_timer(2.6).timeout
	if not is_instance_valid(_visual):
		return
	_charge_velocity = Vector2.ZERO
	_visual.set_motion(Vector2.ZERO)
	_visual.reveal()
	_title.show_title("boss_angler_name", "boss_angler_subtitle")


# --- Capture -------------------------------------------------------------------

func _capture_all(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	await _wait(1.0)
	_reset()
	_visual.set_motion(Vector2(-35.0, 8.0))
	await _wait(2.5)
	await _shot(folder, "01_idle")

	_reset()
	await _wait(0.8)
	_telegraph()
	await _wait(0.7)
	await _shot(folder, "02_telegraph")

	_reset()
	_charge()
	await _wait(0.42)
	await _shot(folder, "03_charge")

	_reset()
	await _wait(1.2)
	_visual.bite()
	await _wait(_visual.bite_snap_at + 0.03)
	await _shot(folder, "04_bite")

	_reset()
	await _wait(1.0)
	_visual.hit(_guardian.global_position)
	await _wait(0.06)
	await _shot(folder, "05_hit")

	_reset()
	await _wait(0.8)
	_visual.set_exposed(1.0)
	await _wait(0.6)
	await _shot(folder, "06_exposed")

	_reset()
	await _wait(0.6)
	_visual.set_state(AnglerVisual.State.STUNNED)
	await _wait(1.4)
	await _shot(folder, "07_stunned")

	_reset()
	await _wait(1.0)
	_visual.roar()
	await _wait(0.3)
	await _shot(folder, "08_phase_change")

	_reset()
	await _wait(1.0)
	_visual.die()
	await _wait(1.6)
	await _shot(folder, "09_death_a")
	await _wait(1.8)
	await _shot(folder, "10_death_b")

	# Swimming up / down the screen: still a side view, only tilted.
	_reset()
	_visual.set_motion(Vector2(-10.0, 120.0))
	await _wait(2.0)
	await _shot(folder, "13_swim_down")
	_reset()
	_visual.set_motion(Vector2(10.0, -120.0))
	await _wait(2.0)
	await _shot(folder, "14_swim_up_turned")

	_intro()
	await _wait(1.3)
	await _shot(folder, "11_intro_lure")
	await _wait(1.3 + 0.45)
	await _shot(folder, "12_intro_reveal")
	print("CAPTURE DONE")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Saves the screen as an 8-bit sRGB PNG (the viewport holds linear HDR values).
func _shot(folder: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGBAF)
	var data: PackedFloat32Array = image.get_data().to_float32_array()
	for i: int in range(0, data.size(), 4):
		for c: int in 3:
			var x: float = clampf(data[i + c], 0.0, 1.0)
			data[i + c] = 12.92 * x if x <= 0.0031308 else 1.055 * pow(x, 1.0 / 2.4) - 0.055
	var srgb := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBAF, data.to_byte_array())
	srgb.convert(Image.FORMAT_RGBA8)
	srgb.save_png(folder.path_join(file_name + ".png"))
	print("saved ", file_name)
