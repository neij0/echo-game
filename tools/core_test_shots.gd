class_name CoreTestShots
extends Node
## Pictures and checks for the core test (needs a window):
## godot --path . res://tools/core_test.tscn -- shots <folder>
## Puts the Guardian on a spot where rock covers him from the camera, saves
## the view with the cut-away off and on (with a pulse), and prints what the
## real classes did (pulse reach, creature hit by the sonar, health, revive).

@export var test: CoreTest
@export var folder: String = ""
@export var settle_time: float = 1.2
## Grid step used to look for a covered spot, and how far round the start.
@export var search_step: float = 0.4
@export var search_radius: float = 9.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()


func _run() -> void:
	test.creature.ai_enabled = false
	var pulse := test.echo.get_node("Pulse") as PulseAbility
	for tall: bool in [false, true]:
		test.set_tall_rocks(tall)
		await _wait(0.3)
		await get_tree().physics_frame
		var start: Vector3 = test.room_markers[1]["Player1"]
		var covered: Vector3 = _find_covered_spot(start, 0.5 if tall else 0.2)
		test.guardian.global_position = covered
		test.echo.global_position = _find_free_spot(covered + Vector3(-1.8, 0.0, 1.8))
		test.creature.global_position = _find_free_spot(covered + Vector3(1.6, 0.0, -1.6))
		test.camera.snap_to_players()
		for cut: bool in [false, true]:
			test.set_cutaway(cut)
			await _wait(maxf(settle_time, pulse.cooldown_left + 0.1))
			await get_tree().physics_frame
			pulse.emit_pulse()
			await _wait(1.3)
			var file_name: String = "%s_rocks_cutaway_%s.png" % ["tall" if tall else "normal", "on" if cut else "off"]
			await _save(folder.path_join(file_name))
			print("saved ", file_name, "   hole open: Guardian %.2f, Echo %.2f" % [
				test.cutaway.get_openness(test.guardian), test.cutaway.get_openness(test.echo)])
			await _wait(test.sonar.get_lifetime(pulse.pulse_expand_time))
	test.set_tall_rocks(false)
	await _wait(0.3)
	test.guardian.global_position = test.room_markers[1]["Player1"]
	test.echo.global_position = test.room_markers[1]["Player2"]
	test.creature.global_position = _find_free_spot(test.echo.global_position + Vector3(1.5, 0.0, 0.0))
	await _wait(pulse.cooldown_left + 0.2)
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _wait(0.6)
	await _check_rules()
	get_tree().quit()


## The real classes working together: a creature hit, going down, a revive.
func _check_rules() -> void:
	var health: PlayerHealth = test.guardian.health
	print("CORE TEST pulse radius %.1f units, expand %.2f s" % [
		(test.echo.get_node("Pulse") as PulseAbility).get_radius(), (test.echo.get_node("Pulse") as PulseAbility).pulse_expand_time])
	print("CORE TEST creature Exposed by the last pulse: ", test.creature.is_exposed() or test.creature.is_hittable())
	health.take_hit(test.guardian.global_position + Vector3(1.0, 0.0, 0.0), test.creature)
	print("CORE TEST Guardian after one hit: %.1f segments, pushed %.1f units/s" % [health.value, test.guardian.velocity.length()])
	health.set_segments(0.5)
	health.make_invulnerable(0.0)
	await _wait(1.6)
	health.take_hit(test.guardian.global_position + Vector3(1.0, 0.0, 0.0), test.creature)
	print("CORE TEST Guardian downed: ", health.is_downed)
	test.echo.global_position = test.guardian.global_position + Vector3(0.6, 0.0, 0.0)
	await _wait(0.2)
	Input.action_press("p1_action")
	await _wait(2.3)
	Input.action_release("p1_action")
	print("CORE TEST Guardian revived by the Echo: ", not health.is_downed, " (%.1f segments)" % health.value)


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
		var offset: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, step * TAU / 8.0) * 0.4
		if _hits_rock(spot + offset + Vector3(0.0, 6.0, 0.0), Vector3(0.0, -5.9, 0.0)):
			return false
	return true


func _hits_rock(from: Vector3, along: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from + along, 1)
	return not test.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The viewport is linear float data (HDR 2D): it is converted for the PNG.
func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		for y: int in image.get_height():
			for x: int in image.get_width():
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
		image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
