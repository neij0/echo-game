class_name CharacterTestShots
extends Node
## Pictures of the blockouts (needs a window):
## godot --path . res://tools/character_test.tscn -- pictures <folder> [variants]
## - sheet_echo / sheet_guardian: the final blockout from the front, the side
##   and the back, lights up, camera close (the game camera's angle). With
##   the Guardian on a Mixamo body made, he is the second row.
## - game_...: the real players in their final blockouts at the game's camera
##   distance, cut out of the 1080p frame at its real pixels: in the dark, the
##   pulse (the Echo's pulse pose) and its afterglow, swimming / walking, the
##   Guardian's sword swing; game_guardian_options: both Guardian options
##   side by side (only with the Mixamo one made).
## - "variants": also the sheets of the first three variants of each.

@export var test: CharacterTest
@export var folder: String = ""
## Also the sheets of the first variants (A, B, C).
@export var with_variants: bool = false
@export var settle_time: float = 1.2
## Where the sheets are set up (clear of the rooms), and their floor's size.
@export var sheet_spot: Vector3 = Vector3(-60.0, 0.0, -60.0)
@export var sheet_floor: float = 40.0
## Sheets: units between two views (front, side, back) and between two rows,
## and the view height per row.
@export var echo_spacing: Vector2 = Vector2(1.55, 2.8)
@export var echo_view: float = 2.9
@export var guardian_spacing: Vector2 = Vector2(2.0, 4.4)
@export var guardian_view: float = 3.6
## Size in pixels of the cut-out round the players in the game pictures.
@export var crop_size: Vector2i = Vector2i(960, 600)
## Units between the two players in the game pictures.
@export var pair_distance: float = 1.8
## Seconds the players move before the "moving" picture, and into the
## Guardian's swing / the Echo's pulse pose before theirs.
@export var move_time: float = 0.7
@export var swing_wait: float = 0.1
@export var pulse_pose_wait: float = 0.12
## The sheet of the moves: units between two figures, and the view height.
@export var moves_spacing: float = 2.0
@export var moves_view: float = 7.0
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
	var guardians: Array[int] = [CharacterTest.FINAL]
	if CharacterTest.has_model("guardian", CharacterTest.MIXAMO):
		guardians.append(CharacterTest.MIXAMO)
	await _sheet("sheet_echo", "echo", [CharacterTest.FINAL])
	await _sheet("sheet_guardian", "guardian", guardians)
	await _moves_sheet()
	if with_variants:
		await _sheet("sheet_echo_variants", "echo", [0, 1, 2])
		await _sheet("sheet_guardian_variants", "guardian", [0, 1, 2])
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


## One row per variant: front, side and back, lights up, camera close.
func _sheet(file_name: String, character: String, variants: Array[int]) -> void:
	var is_echo: bool = character == "echo"
	var spacing: Vector2 = echo_spacing if is_echo else guardian_spacing
	var rows: int = variants.size()
	test.set_close_view(true, (echo_view if is_echo else guardian_view) + spacing.y * 0.72 * (rows - 1))
	test.camera.snap_to_players()
	await _wait(0.2)
	var right: Vector3 = _flat(test.camera.global_basis.x)
	var away: Vector3 = _flat(-test.camera.global_basis.z)
	var facings: Array[Vector3] = [-away, right, away]
	var names: Array[String] = CharacterTest.ECHO_NAMES if is_echo else CharacterTest.GUARDIAN_NAMES
	var holder := Node3D.new()
	test.add_child(holder)
	for row: int in rows:
		var variant: int = variants[row]
		var depth: Vector3 = away * ((rows - 1) * 0.5 - row) * spacing.y
		for view: int in 3:
			var model := (CharacterTest.ECHO_BLOCKOUT if is_echo else CharacterTest.GUARDIAN_BLOCKOUT).instantiate() as CharacterModel
			model.model = CharacterTest.model_of(character, variant)
			holder.add_child(model)
			model.global_position = sheet_spot + right * (view - 1) * spacing.x + depth
			model.rotation.y = atan2(facings[view].x, facings[view].z)
		var label := Label3D.new()
		label.text = "%s %s" % [["A", "B", "C", "Final", "On a"][variant], names[variant]]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 64
		label.pixel_size = 0.0016 * (1.0 if is_echo else 1.6) * (1.0 + 0.6 * (rows - 1))
		label.modulate = Color(0.85, 0.95, 1.0)
		holder.add_child(label)
		label.global_position = sheet_spot - right * spacing.x * 0.5 + depth + Vector3(0.0, 1.75 if is_echo else 2.75, 0.0)
	await _wait(settle_time)
	await _save(file_name)
	holder.free()


## The basic animations, lights up: the Echo idle, swimming and in her pulse
## pose; the Guardian idle, walking and in a sword swing.
func _moves_sheet() -> void:
	test.set_close_view(true, moves_view)
	test.camera.snap_to_players()
	await _wait(0.2)
	var right: Vector3 = _flat(test.camera.global_basis.x)
	var away: Vector3 = _flat(-test.camera.global_basis.z)
	var facing: Vector3 = (-away + right * 0.8).normalized()
	var holder := Node3D.new()
	test.add_child(holder)
	var models: Array[CharacterModel] = []
	for i: int in 6:
		var is_echo: bool = i < 3
		var model := (CharacterTest.ECHO_BLOCKOUT if is_echo else CharacterTest.GUARDIAN_BLOCKOUT).instantiate() as CharacterModel
		holder.add_child(model)
		model.global_position = sheet_spot + right * (i - 2.5) * moves_spacing
		model.rotation.y = atan2(facing.x, facing.z)
		models.append(model)
	models[1].preview_speed = models[1].preview_max_speed
	models[4].preview_speed = models[4].preview_max_speed
	models[5].preview_swing = Vector3(0.45, 0.0, 0.9)
	await _wait(settle_time + 0.37)
	models[2].flare()
	await _wait(pulse_pose_wait)
	await _save("sheet_moves")
	holder.free()


## The real players in their final blockouts, at the game distance.
func _game_pictures() -> void:
	var pulse := test.echo.get_node("Pulse") as PulseAbility
	var start: Vector3 = test.echo.global_position
	test.set_variants(CharacterTest.FINAL, CharacterTest.FINAL)
	var right: Vector3 = _flat(test.camera.global_basis.x)
	var away: Vector3 = _flat(-test.camera.global_basis.z)
	_place_pair(start, right, away)
	await _wait(settle_time + maxf(pulse.cooldown_left, 0.0))
	await _save("game_1_dark", true)
	if CharacterTest.has_model("guardian", CharacterTest.MIXAMO):
		var other := CharacterTest.GUARDIAN_BLOCKOUT.instantiate() as CharacterModel
		other.model = CharacterTest.model_of("guardian", CharacterTest.MIXAMO)
		test.add_child(other)
		other.global_position = test.guardian.global_position + right * pair_distance
		other.rotation.y = atan2(test.guardian.facing.x, test.guardian.facing.z)
		await _wait(settle_time)
		await _save("game_guardian_options", true)
		other.free()
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _wait(pulse.pulse_expand_time * 0.3)
	await _save("game_3_pulse", true)
	await _save("game_3_pulse_whole_frame")
	await _wait(pulse.pulse_expand_time * 0.7 + 1.0)
	await _save("game_4_afterglow", true)
	await _wait(test.sonar.get_lifetime(pulse.pulse_expand_time))
	# The sword swing (the first hit of the combo, then the finisher).
	_send("p2_action", true)
	await _wait(swing_wait)
	_send("p2_action", false)
	await _save("game_5_swing", true)
	await _wait(1.2)
	for action: String in ["p1_move_right", "p2_move_right"]:
		Input.action_press(action)
	await _wait(move_time)
	await _save("game_6_moving", true)
	await _wait(0.13)
	await _save("game_6_moving_next_step", true)
	for action: String in ["p1_move_right", "p2_move_right"]:
		Input.action_release(action)
	await _wait(0.6)


func _place_pair(start: Vector3, right: Vector3, away: Vector3) -> void:
	test.echo.global_position = start
	test.guardian.global_position = start + right * pair_distance
	test.echo.facing = (-away + right * 0.45).normalized()
	test.guardian.facing = (-away - right * 0.45).normalized()
	for player: Player in [test.echo, test.guardian]:
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
	test.camera.snap_to_players()


func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


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
