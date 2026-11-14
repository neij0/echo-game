class_name LookdevShots
extends Node
## Before / after pictures and the frame rate of the look-dev room (needs a
## window):
## godot --path . res://tools/lookdev_room.tscn -- look <folder> [level number] [pictures]
## For the classic and the natural look, from the same two spots of the same
## level (same seed): the start and a spot beside rock, each dark (no pulse),
## with a pulse's front on its way and in its afterglow; plus one picture of
## each look with the lights up (to judge the shapes). Then the frame rate of
## both looks (vsync off, 1920x1080) while the players swim about and the
## Echo pulses, on this level and on the world's largest one.

@export var test: LookdevRoom
@export var folder: String = ""
## Level of the world (0-based).
@export var level_number: int = 0
@export var benchmark: bool = true
@export var settle_time: float = 0.8
@export var bench_time: float = 6.0
@export var bench_pulse_every: float = 1.6
## Lights-up picture: the ambient light and the camera's view height (units).
@export var lit_ambient: float = 1.6
@export var lit_size: float = 26.0
## Energy of the sun used for that picture only.
@export var lit_sun: float = 2.2
## The seed both looks are built with.
@export var seed_value: int = 4242

var _frames: int = 0
var _counting: bool = false
var _cpu_ms: float = 0.0
var _gpu_ms: float = 0.0
var _slow: int = 0
var _worst: float = 0.0
var _helper: LevelTestShots


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_helper = LevelTestShots.new()
	_helper.test = test
	_run.call_deferred()


func _exit_tree() -> void:
	if _helper:
		_helper.free()


func _process(delta: float) -> void:
	if not _counting:
		return
	_frames += 1
	_worst = maxf(_worst, delta)
	if delta > 1.0 / 60.0:
		_slow += 1
	var viewport: RID = get_viewport().get_viewport_rid()
	_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport)


func _run() -> void:
	get_window().size = Vector2i(1920, 1080)
	test.builder.forced_seed = seed_value
	test._hud.visible = false
	test._info.visible = false
	for natural: bool in [false, true]:
		var look: String = "new" if natural else "old"
		test.builder.natural_look = natural
		test.start_level(level_number / 3, level_number % 3)
		test.set_creatures_frozen(true)
		print("LOOKDEV %s look: build %.2f s (navigation %.2f s), %d kit pieces" % [look, test.builder.build_seconds,
			test.builder.bake_seconds, test.builder.get_dressing_piece_count()])
		await _wait(settle_time)
		await _lit_picture(look)
		await _pictures(look, "start")
		_helper._move_players_near_rock()
		test.camera.snap_to_players()
		await _wait(settle_time)
		await _pictures(look, "rock")
	if benchmark:
		var largest: int = _helper._largest_level()
		for number: int in [level_number, largest]:
			for natural: bool in [false, true]:
				await _bench(number, natural)
	get_tree().quit()


## Dark, the pulse's front on its way, its afterglow.
func _pictures(look: String, spot: String) -> void:
	var pulse := test.echo.get_node("Pulse") as PulseAbility
	await _save("%s_%s_1_dark" % [spot, look])
	await _wait(maxf(pulse.cooldown_left, 0.0) + 0.1)
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _wait(pulse.pulse_expand_time * 0.45)
	await _save("%s_%s_2_pulse_front" % [spot, look])
	await _wait(pulse.pulse_expand_time * 0.55 + 1.0)
	await _save("%s_%s_3_pulse_glow" % [spot, look])
	await _wait(test.sonar.get_lifetime(pulse.pulse_expand_time))


## The start with the lights up and a wider view (shapes, not mood).
func _lit_picture(look: String) -> void:
	var ambient_before: float = test.darkness.ambient_energy
	var volumetric_before: bool = test.darkness.environment.volumetric_fog_enabled
	test.camera.min_size = lit_size
	test.camera.max_size = lit_size
	test.camera.size = lit_size
	test.darkness.ambient_energy = lit_ambient
	test.darkness.environment.volumetric_fog_enabled = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 25.0, 0.0)
	sun.light_energy = lit_sun
	sun.shadow_enabled = true
	add_child(sun)
	await _wait(0.4)
	await _save("lit_%s" % look)
	sun.queue_free()
	test.darkness.environment.volumetric_fog_enabled = volumetric_before
	test.darkness.ambient_energy = ambient_before
	test.camera.min_size = 14.0
	test.camera.max_size = 21.0
	test.camera.size = 14.0
	await _wait(0.4)


func _bench(number: int, natural: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	test.builder.natural_look = natural
	test.start_level(number / 3, number % 3)
	test.set_creatures_frozen(false)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait(1.0)
	_frames = 0
	_cpu_ms = 0.0
	_gpu_ms = 0.0
	_slow = 0
	_worst = 0.0
	var started: int = Time.get_ticks_usec()
	_counting = true
	var left: float = bench_time
	var turn: int = 0
	while left > 0.0:
		var direction: String = ["right", "left"][turn % 2]
		for prefix: String in ["p1_", "p2_"]:
			Input.action_press(prefix + "move_" + direction)
		await get_tree().physics_frame
		test.sonar.add_pulse(test.echo.global_position, (test.echo.get_node("Pulse") as PulseAbility).get_radius(), 0.8)
		await _wait(minf(bench_pulse_every, left))
		for prefix: String in ["p1_", "p2_"]:
			Input.action_release(prefix + "move_" + direction)
		left -= bench_pulse_every
		turn += 1
	_counting = false
	var seconds: float = float(Time.get_ticks_usec() - started) / 1000000.0
	var count: float = maxf(float(_frames), 1.0)
	var size: Vector2i = get_window().size
	print("LOOKDEV FPS (vsync off, %dx%d, world level %d, %d rooms, %s look, %d kit pieces, pulsing): average %.0f, worst frame %.1f ms, frames over 16.7 ms: %d; render CPU %.2f ms, GPU %.2f ms; build %.2f s" % [
		size.x, size.y, number + 1, test.world.get_level(number / 3, number % 3).rooms.size(), "NATURAL" if natural else "classic",
		test.builder.get_dressing_piece_count(), float(_frames) / seconds, _worst * 1000.0, _slow, _cpu_ms / count, _gpu_ms / count,
		test.builder.build_seconds])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The viewport is linear float data (HDR): converted for the PNG.
func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		for y: int in image.get_height():
			for x: int in image.get_width():
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
		image.convert(Image.FORMAT_RGB8)
	image.save_png(folder.path_join(file_name + ".png"))
	print("saved ", file_name)
