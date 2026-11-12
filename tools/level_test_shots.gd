class_name LevelTestShots
extends Node
## Pictures and the FPS benchmark of the level test (needs a window):
## godot --path . res://tools/level_test.tscn -- shots <folder> [level number]
## Saves, for the largest level (or the one asked for): an overview with the
## lights up, the start with and without the near ambient (Darkness), the
## same near rock, a pulse, sand trails in the Echo's light and in a pulse's
## afterglow. Then measures the frame rate (vsync off, 1920x1080) on
## that level while the players run about, the creatures hunt and the Echo
## pulses: once with the sand trails on, once off (their cost).

@export var test: LevelTest
@export var folder: String = ""
## Level of the world to use (0-based); -1 = the one with the most rooms.
@export var bench_level: int = -1
## False = pictures only.
@export var benchmark: bool = true
@export var settle_time: float = 1.0
@export var bench_time: float = 8.0
@export var bench_pulse_every: float = 1.6
## Overview picture: camera view height (units) and ambient light.
@export var overview_size: float = 80.0
@export var overview_ambient: float = 2.0
## Pixels between the players and the rock in the "01_rock" pictures.
@export var rock_view_distance: float = 180.0

var _frames: int = 0
var _counting: bool = false
var _cpu_ms: float = 0.0
var _gpu_ms: float = 0.0
var _slow: int = 0
var _worst: float = 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()


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
	var number: int = bench_level if bench_level >= 0 else _largest_level()
	test.start_level(number / 3, number % 3)
	print("LEVEL TEST: world level %d, %d rooms, %d creatures; build %.2f s, of which navigation %.2f s" % [
		number + 1, test.world.get_level(number / 3, number % 3).rooms.size(), test.builder.get_creatures().size(),
		test.builder.build_seconds, test.builder.bake_seconds])
	test.set_creatures_frozen(true)
	await _wait(settle_time)

	# 0. Overview with the lights up (to check the build).
	var size_before: float = test.camera.size
	var ambient_before: float = test.darkness.ambient_energy
	test.camera.min_size = overview_size
	test.camera.max_size = overview_size
	test.camera.size = overview_size
	test.darkness.ambient_energy = overview_ambient
	var fog_before: bool = test.darkness.environment.fog_enabled
	var volumetric_before: bool = test.darkness.environment.volumetric_fog_enabled
	test.darkness.environment.fog_enabled = false
	test.darkness.environment.volumetric_fog_enabled = false
	await _wait(0.5)
	await _save("00_overview")
	test.darkness.environment.fog_enabled = fog_before
	test.darkness.environment.volumetric_fog_enabled = volumetric_before
	test.camera.min_size = 14.0
	test.camera.max_size = 21.0
	test.camera.size = size_before
	test.darkness.ambient_energy = ambient_before
	await _wait(0.5)

	# 1. The start and beside rock, with the near ambient and without it.
	await _save("01_start")
	test.darkness.near_enabled = false
	await _wait(0.1)
	await _save("01_start_no_near_ambient")
	test.darkness.near_enabled = true
	_move_players_near_rock()
	await _wait(0.6)
	await _save("01_rock")
	test.darkness.near_enabled = false
	await _wait(0.1)
	await _save("01_rock_no_near_ambient")
	test.darkness.near_enabled = true
	for player: Player in [test.echo, test.guardian]:
		player.global_position = test.builder.get_spawn_position(player.player_number)
		player.reset_physics_interpolation()
	await _wait(0.6)

	# 2. A pulse.
	var pulse := test.echo.get_node("Pulse") as PulseAbility
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _wait(0.9)
	await _save("02_pulse")
	await _wait(test.sonar.get_lifetime(pulse.pulse_expand_time))

	# 3. Trails: the players walk a loop near the start, then stand in the light.
	await _walk_loop(3.0)
	await _wait(0.3)
	await _save("03_trails_in_light")
	await _wait(pulse.cooldown_left + 0.1)
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _wait(1.2)
	await _save("04_trails_after_pulse")
	test.set_creatures_frozen(false)

	# 5. The benchmark, trails on and off.
	if not benchmark:
		get_tree().quit()
		return
	for trails_on: bool in [true, false]:
		test.trails.enabled = trails_on
		await _bench(number, trails_on)
	get_tree().quit()


## Puts the players on open floor about rock_view_distance from the nearest
## rock of their room, so the near rock shows in the pictures.
func _move_players_near_rock() -> void:
	var layout: LevelBuilder.Layout = test.builder.get_layout()
	var start: Vector2 = test.builder.to_plan(test.echo.global_position)
	var best: Vector2 = start
	var best_score: float = INF
	for chunk: LevelChunk in layout.chunks:
		for polygon: PackedVector2Array in chunk.get_wall_polygons():
			for i: int in polygon.size():
				var a: Vector2 = polygon[i]
				var b: Vector2 = polygon[(i + 1) % polygon.size()]
				var normal: Vector2 = (b - a).orthogonal().normalized()
				if Geometry2D.is_point_in_polygon((a + b) * 0.5 + normal, polygon):
					normal = -normal
				var spot: Vector2 = (a + b) * 0.5 + normal * rock_view_distance
				var score: float = spot.distance_to(start)
				if score < best_score and layout.validator.is_reachable(spot) and not layout.validator.is_near_blocked(spot, rock_view_distance * 0.6):
					best_score = score
					best = spot
	for player: Player in [test.echo, test.guardian]:
		var offset := Vector3(0.6 if player == test.guardian else -0.6, 0.0, 0.0)
		player.global_position = test.builder.to_world(best) + offset
		player.reset_physics_interpolation()


## Both players walk a small loop (real input), leaving trails.
func _walk_loop(seconds: float) -> void:
	var directions: Array[String] = ["right", "down", "left", "up"]
	var step: float = seconds / directions.size()
	for direction: String in directions:
		for prefix: String in ["p1_", "p2_"]:
			Input.action_press(prefix + "move_" + direction)
		await _wait(step)
		for prefix: String in ["p1_", "p2_"]:
			Input.action_release(prefix + "move_" + direction)


func _bench(number: int, trails_on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	test.start_level(number / 3, number % 3)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait(1.0)
	_frames = 0
	_cpu_ms = 0.0
	_gpu_ms = 0.0
	_slow = 0
	_worst = 0.0
	var trace_ms: float = 0.0
	var started: int = Time.get_ticks_usec()
	_counting = true
	var left: float = bench_time
	var turn: int = 0
	while left > 0.0:
		# Walk back and forth (trails), pulse.
		var direction: String = ["right", "left"][turn % 2]
		for prefix: String in ["p1_", "p2_"]:
			Input.action_press(prefix + "move_" + direction)
		await get_tree().physics_frame
		test.sonar.add_pulse(test.echo.global_position, (test.echo.get_node("Pulse") as PulseAbility).get_radius(), 0.8)
		trace_ms = maxf(trace_ms, test.sonar.last_trace_ms)
		await _wait(minf(bench_pulse_every, left))
		for prefix: String in ["p1_", "p2_"]:
			Input.action_release(prefix + "move_" + direction)
		left -= bench_pulse_every
		turn += 1
	_counting = false
	var seconds: float = float(Time.get_ticks_usec() - started) / 1000000.0
	var count: float = maxf(float(_frames), 1.0)
	var size: Vector2i = get_window().size
	print("LEVEL TEST FPS (vsync off, %dx%d, trails %s, %d creatures, pulsing): average %.0f, worst frame %.1f ms, frames over 16.7 ms: %d" % [
		size.x, size.y, "ON" if trails_on else "off", get_tree().get_nodes_in_group("creatures").size(),
		float(_frames) / seconds, _worst * 1000.0, _slow])
	print("  per frame: render CPU %.2f ms, GPU %.2f ms; pulse rays up to %.1f ms; trail stamps so far %d, puffs %d" % [
		_cpu_ms / count, _gpu_ms / count, trace_ms, test.trails.stamps_drawn, test.trails.puffs_thrown])


func _largest_level() -> int:
	var best: int = 0
	var best_rooms: int = -1
	var number: int = 0
	for stage: int in test.world.get_stage_count():
		for level: int in test.world.get_level_count(stage):
			var rooms: int = test.world.get_level(stage, level).rooms.size()
			if rooms > best_rooms:
				best_rooms = rooms
				best = number
			number += 1
	return best


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
