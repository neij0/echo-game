class_name CharacterTestShots
extends Node
## Pictures of every blockout variant (needs a window):
## godot --path . res://tools/character_test.tscn -- pictures <folder>
## - sheet_echo / sheet_guardian: the three variants side by side with the
##   lights up and the camera close (the game camera's angle), each seen from
##   the front, the side and the back.
## - game_<a|b|c>_...: the real players wearing that variant (the Echo and
##   the Guardian side by side) at the game's camera distance: in the dark,
##   as the pulse's front passes, in its afterglow and while they swim. These
##   are cut out of the 1080p frame at its real pixels (the players and what
##   is round them), plus the whole frame of the pulse.

@export var test: CharacterTest
@export var folder: String = ""
@export var settle_time: float = 1.2
## Where the sheets are set up (clear of the rooms), and their floor's size.
@export var sheet_spot: Vector3 = Vector3(-60.0, 0.0, -60.0)
@export var sheet_floor: float = 40.0
## Sheets: units between two variants / two rows, and the view height.
@export var echo_spacing: Vector2 = Vector2(2.1, 2.7)
@export var echo_view: float = 6.6
@export var guardian_spacing: Vector2 = Vector2(3.0, 3.3)
@export var guardian_view: float = 8.8
## Units between the front row and the names under it (Echo sheet; scaled for the Guardian).
@export var label_gap: float = 0.75
## Size in pixels of the cut-out round the players in the game pictures.
@export var crop_size: Vector2i = Vector2i(960, 600)
## Units between the two players in the game pictures.
@export var pair_distance: float = 1.7
## Seconds the players swim before the "moving" picture.
@export var swim_time: float = 0.55
@export_range(0.1, 1.0) var jpg_quality: float = 0.92


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1920, 1080)
	test._info.visible = false
	test.set_creatures_frozen(true)
	await _wait(0.5)
	await _sheets()
	await _game_pictures()
	get_tree().quit()


## Both characters' variants, lights up, close, from three sides.
func _sheets() -> void:
	var start: Array[Vector3] = [test.echo.global_position, test.guardian.global_position]
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(sheet_floor, sheet_floor)
	ground.mesh = plane
	ground.material_override = test._surface_material(test.floor_color)
	ground.position = sheet_spot
	test.add_child(ground)
	for player: Player in [test.echo, test.guardian]:
		player.visible = false
		player.global_position = sheet_spot
		player.reset_physics_interpolation()
	test.set_studio_light(true)
	for character: String in ["echo", "guardian"]:
		var is_echo: bool = character == "echo"
		test.set_close_view(true, echo_view if is_echo else guardian_view)
		test.camera.snap_to_players()
		await _wait(0.2)
		var right: Vector3 = _flat(test.camera.global_basis.x)
		var away: Vector3 = _flat(-test.camera.global_basis.z)
		var spacing: Vector2 = echo_spacing if is_echo else guardian_spacing
		var names: Array[String] = CharacterTest.ECHO_NAMES if is_echo else CharacterTest.GUARDIAN_NAMES
		var holder := Node3D.new()
		test.add_child(holder)
		var facings: Array[Vector3] = [-away, right, away]
		for variant: int in 3:
			for row: int in 3:
				var model := (CharacterTest.ECHO_BLOCKOUT if is_echo else CharacterTest.GUARDIAN_BLOCKOUT).instantiate() as CharacterModel
				model.model = CharacterTest.model_of(character, variant)
				holder.add_child(model)
				model.global_position = sheet_spot + right * (variant - 1) * spacing.x + away * (row - 1) * spacing.y
				model.rotation.y = atan2(facings[row].x, facings[row].z)
			var label := Label3D.new()
			label.text = "%s  %s" % [CharacterTest.VARIANTS[variant].to_upper(), names[variant]]
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.font_size = 64
			label.pixel_size = 0.0035 * (1.0 if is_echo else 1.6)
			label.modulate = Color(0.85, 0.95, 1.0)
			holder.add_child(label)
			label.global_position = sheet_spot + right * (variant - 1) * spacing.x - away * (spacing.y + label_gap * label.pixel_size / 0.0035) + Vector3(0.0, 0.05, 0.0)
		await _wait(settle_time)
		await _save("sheet_%s" % character)
		holder.queue_free()
	test.set_studio_light(false)
	test.set_close_view(false)
	ground.queue_free()
	test.echo.visible = true
	test.guardian.visible = true
	test.echo.global_position = start[0]
	test.guardian.global_position = start[1]
	for player: Player in [test.echo, test.guardian]:
		player.reset_physics_interpolation()
	test.camera.snap_to_players()
	await _wait(0.5)


## The real players wearing each variant, at the game's camera distance.
func _game_pictures() -> void:
	var pulse := test.echo.get_node("Pulse") as PulseAbility
	var start: Vector3 = test.echo.global_position
	for variant: int in 3:
		var letter: String = CharacterTest.VARIANTS[variant]
		test.set_variants(variant, variant)
		var right: Vector3 = _flat(test.camera.global_basis.x)
		var away: Vector3 = _flat(-test.camera.global_basis.z)
		test.echo.global_position = start
		test.guardian.global_position = start + right * pair_distance
		test.echo.facing = (-away + right * 0.45).normalized()
		test.guardian.facing = (-away - right * 0.45).normalized()
		for player: Player in [test.echo, test.guardian]:
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
		test.camera.snap_to_players()
		await _wait(settle_time + maxf(pulse.cooldown_left, 0.0))
		await _save("game_%s_1_dark" % letter, true)
		await get_tree().physics_frame
		pulse.emit_pulse()
		await _wait(pulse.pulse_expand_time * 0.3)
		await _save("game_%s_2_pulse" % letter, true)
		await _save("game_%s_2_pulse_whole_frame" % letter)
		await _wait(pulse.pulse_expand_time * 0.7 + 1.0)
		await _save("game_%s_3_afterglow" % letter, true)
		await _wait(test.sonar.get_lifetime(pulse.pulse_expand_time))
		for action: String in ["p1_move_right", "p2_move_right"]:
			Input.action_press(action)
		await _wait(swim_time)
		await _save("game_%s_4_swimming" % letter, true)
		for action: String in ["p1_move_right", "p2_move_right"]:
			Input.action_release(action)
		await _wait(0.6)


func _flat(direction: Vector3) -> Vector3:
	return Vector3(direction.x, 0.0, direction.z).normalized()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The viewport is linear float data (HDR): converted for the picture.
## cut_out: only the part round the two players, at its real pixels.
func _save(file_name: String, cut_out: bool = false) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if cut_out:
		var middle: Vector3 = (test.echo.global_position + test.guardian.global_position) * 0.5 + Vector3(0.0, 0.8, 0.0)
		var scale: Vector2 = Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var at: Vector2i = Vector2i(test.camera.unproject_position(middle) * scale) - crop_size / 2
		at = at.clamp(Vector2i.ZERO, image.get_size() - crop_size)
		image = image.get_region(Rect2i(at, crop_size))
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		for y: int in image.get_height():
			for x: int in image.get_width():
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
		image.convert(Image.FORMAT_RGB8)
	image.save_jpg(folder.path_join(file_name + ".jpg"), jpg_quality)
	print("saved ", file_name)
