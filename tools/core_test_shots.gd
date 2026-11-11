class_name CoreTestShots
extends Node
## Pictures and the FPS benchmark of the core test (needs a window):
## godot --path . res://tools/core_test.tscn -- shots <folder>
## Saves: a pulse in the maze (creatures echoing), the cut-away at tall rock
## (off / on), a sword swing on an Exposed creature, the Guardian downed with
## the revive ring and the goal arrow. Then measures the frame rate with vsync
## off at 1920x1080 and 1280x720 while the creatures hunt and the Echo pulses.

@export var test: CoreTest
@export var folder: String = ""
@export var settle_time: float = 1.0
@export var bench_time: float = 8.0
@export var bench_pulse_every: float = 1.6
## Grid step used to look for a covered spot, and how far round the start.
@export var search_step: float = 0.4
@export var search_radius: float = 9.0

var _frames: int = 0
var _worst: float = 0.0
var _counting: bool = false
var _cpu_ms: float = 0.0
var _gpu_ms: float = 0.0
## Frames slower than the 60 FPS budget, and when they came (seconds into the run).
var _slow_frames: PackedFloat32Array = PackedFloat32Array()
var _bench_started: int = 0
var _trace_ms: float = 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()


func _process(delta: float) -> void:
	if _counting:
		_frames += 1
		_worst = maxf(_worst, delta)
		var viewport: RID = get_viewport().get_viewport_rid()
		_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()
		_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		if delta > 1.0 / 60.0:
			_slow_frames.append(float(Time.get_ticks_usec() - _bench_started) / 1000000.0)


func _run() -> void:
	var pulse := test.echo.get_node("Pulse") as PulseAbility
	var maze: Dictionary = test.room_markers[1]
	_freeze_creatures(true)

	# 1. A pulse in the maze: the creatures echo in their colour.
	_place(test.echo, maze["Player1"])
	_place(test.guardian, maze["Player2"])
	await _wait(settle_time)
	await _pulse(pulse)
	await _wait(1.0)
	await _save("01_pulse_maze")
	await _wait(test.sonar.get_lifetime(pulse.pulse_expand_time))

	# 2. The cut-away at tall rock, off and on.
	test.set_tall_rocks(true)
	await _wait(0.3)
	await get_tree().physics_frame
	var covered: Vector3 = _find_covered_spot(maze["Player1"], 0.5)
	_place(test.guardian, covered)
	_place(test.echo, _find_free_spot(covered + Vector3(-1.8, 0.0, 1.8)))
	for cut: bool in [false, true]:
		test.set_cutaway(cut)
		await _wait(settle_time)
		await _save("02_tall_rocks_cutaway_%s" % ("on" if cut else "off"))
	test.set_tall_rocks(false)

	# 3. A sword swing on an Exposed creature (ring, slash arc, outline).
	var creature: Creature = _first_creature()
	_place(test.guardian, maze["Player1"])
	_place(test.echo, _find_free_spot(maze["Player1"] + Vector3(-1.2, 0.0, 1.2)))
	creature.global_position = _find_free_spot(maze["Player1"] + Vector3(1.0, 0.0, 0.0))
	creature.reset_physics_interpolation()
	test.guardian.facing = (creature.global_position - test.guardian.global_position).normalized()
	await _wait(pulse.cooldown_left + 0.2)
	await _pulse(pulse)
	await _wait(0.5)
	await _press("p2_action")
	await _wait(0.08)
	await _save("03_sword_exposed")
	await _wait(0.6)

	# 4. The Guardian downed, the Echo reviving, the goal arrow after a pulse.
	_freeze_creatures(true)
	test.guardian.health.down(PlayerHealth.Cause.CREATURE)
	_place(test.echo, test.guardian.global_position + Vector3(0.7, 0.0, 0.0))
	await _wait(pulse.cooldown_left + 0.2)
	await _pulse(pulse)
	_send("p1_action", true)
	await _wait(0.9)
	await _save("04_downed_revive_goal_arrow")
	_send("p1_action", false)
	test.reset_players()

	# 5. The benchmark.
	_freeze_creatures(false)
	await _bench(Vector2i(1920, 1080))
	await _bench(Vector2i(1280, 720))
	get_tree().quit()


func _bench(window_size: Vector2i) -> void:
	get_window().size = window_size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	test.reset_players()
	_place(test.echo, test.room_markers[1]["Player1"])
	_place(test.guardian, test.room_markers[1]["Player2"])
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _wait(1.0)
	_frames = 0
	_worst = 0.0
	_cpu_ms = 0.0
	_gpu_ms = 0.0
	_slow_frames.clear()
	_bench_started = Time.get_ticks_usec()
	_trace_ms = 0.0
	var traces: int = 0
	_counting = true
	var started: int = Time.get_ticks_usec()
	var left: float = bench_time
	while left > 0.0:
		await get_tree().physics_frame
		test.sonar.add_pulse(test.echo.global_position, (test.echo.get_node("Pulse") as PulseAbility).get_radius(), 0.8)
		_trace_ms = maxf(_trace_ms, test.sonar.last_trace_ms)
		traces += 1
		await _wait(minf(bench_pulse_every, left))
		left -= bench_pulse_every
	_counting = false
	var seconds: float = float(Time.get_ticks_usec() - started) / 1000000.0
	var size: Vector2i = get_window().size
	var count: float = maxf(float(_frames), 1.0)
	print("CORE TEST FPS (vsync off, %dx%d, %d creatures, pulsing): average %.0f, worst frame %.1f ms" % [
		size.x, size.y, get_tree().get_nodes_in_group("creatures").size(), float(_frames) / seconds, _worst * 1000.0])
	var when := PackedStringArray()
	for at: float in _slow_frames:
		when.append("%.1f s" % at)
	print("  per frame: render CPU %.2f ms, GPU %.2f ms; pulse rays (%d pulses) up to %.1f ms; frames over 16.7 ms: %d %s" % [
		_cpu_ms / count, _gpu_ms / count, traces, _trace_ms, _slow_frames.size(), when])


func _first_creature() -> Creature:
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature and not creature.unkillable:
			return creature
	return null


func _freeze_creatures(frozen: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		node.set_physics_process(not frozen)
		(node as Creature).velocity = Vector3.ZERO


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = at
	node.reset_physics_interpolation()
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO
	test.camera.snap_to_players()


func _pulse(pulse: PulseAbility) -> void:
	await get_tree().physics_frame
	pulse.emit_pulse()


## A real input event (handled at the start of the next frame, like a key), so
## the press is seen whenever the reader checks it.
func _press(action: String) -> void:
	_send(action, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_send(action, false)


func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## A free floor spot near start where rock covers a standing character from
## the camera up to at least this height (start itself if there is none).
func _find_covered_spot(start: Vector3, covered_height: float) -> Vector3:
	var best: Vector3 = start
	var best_distance: float = INF
	var steps: int = int(search_radius / search_step)
	for x: int in range(-steps, steps + 1):
		for z: int in range(-steps, steps + 1):
			var spot: Vector3 = start + Vector3(x, 0.0, z) * search_step
			var distance: float = spot.distance_to(start)
			if distance >= best_distance or not _is_free(spot):
				continue
			if _hits_rock(spot + Vector3(0.0, covered_height, 0.0), test.camera.global_basis.z * 14.0):
				best = spot
				best_distance = distance
	return best


func _find_free_spot(near: Vector3) -> Vector3:
	for ring: int in range(0, 12):
		for step: int in 8:
			var spot: Vector3 = near + Vector3.RIGHT.rotated(Vector3.UP, step * TAU / 8.0) * ring * 0.4
			if _is_free(spot):
				return spot
	return near


## No rock on or right round this floor spot.
func _is_free(spot: Vector3) -> bool:
	if _hits_rock(spot + Vector3(0.0, 6.0, 0.0), Vector3(0.0, -5.9, 0.0)):
		return false
	for step: int in 8:
		var offset: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, step * TAU / 8.0) * 0.5
		if _hits_rock(spot + offset + Vector3(0.0, 6.0, 0.0), Vector3(0.0, -5.9, 0.0)):
			return false
	return true


func _hits_rock(from: Vector3, along: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from + along, 1)
	return not test.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The viewport is linear float data (HDR 2D): it is converted for the PNG.
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
