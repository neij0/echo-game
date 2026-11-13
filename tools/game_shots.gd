extends Node
## Pictures of the real game.tscn in 3D (needs a window): the HUD at a level's
## start and after a pulse, the lockdown (doorways closed, the wave), the
## collapse escape, a boss level's arena door (closed, open) and vents, the
## Lure Pulse aim and the Shield, the skill choice and the pause menu.
## godot --path . res://tools/game_shots.tscn -- <folder>

var _folder: String = ""
var _game: Node3D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	_folder = arguments[0] if arguments.size() > 0 else "user://game_shots"
	DirAccess.make_dir_recursive_absolute(_folder)
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1920, 1080)
	await _open_game()
	await _wait(1.0)
	await _save("01_start_hud")
	var pulse := _echo.get_node("Pulse") as PulseAbility
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _wait(0.7)
	await _save("02_pulse_hud")

	# Lockdown.
	var lockdown: LockdownRoom = _builder.get_lockdown()
	if lockdown:
		var inside: Vector3 = _builder.to_world(_builder.get_layout().lockdown_point)
		var barrier: LockdownBarrier = lockdown._barriers[0]
		var near: Vector3 = barrier.center + (inside - barrier.center).normalized() * 6.0
		# Deep enough inside to trigger it, as near the doorway as that allows.
		var spot: Vector3 = near if lockdown.contains(near) else inside
		_place(_echo, spot + Vector3(-0.5, 0.0, 0.0))
		_place(_guardian, spot + Vector3(0.5, 0.0, 0.0))
		await _wait(0.6)
		await get_tree().physics_frame
		pulse.cooldown_left = 0.0
		pulse.emit_pulse()
		await _wait(0.9)
		await _save("03_lockdown_closed")
		await _wait(lockdown.wake_delay + 0.6)
		await _save("04_lockdown_wave")
		for creature: Creature in lockdown.get_wave():
			creature.take_damage(creature.health + 10, _guardian, 0.0, 0.0)
		await _wait(0.5)
		await _save("05_lockdown_open")

	# Collapse escape (level 2).
	_stage.level_fade_enabled = false
	_stage._start_level(1)
	await _wait(0.8)
	_protect()
	for shard: EchoShard in _builder.get_shards().duplicate():
		shard.collect()
	await _wait(1.6)
	await _save("06_escape")

	# Boss level: the door, the arena, a vent.
	_stage._start_level(2)
	await _wait(0.5)
	_protect()
	var door: ShardDoor = _builder.get_exit_door()
	var goal: AncientLight = _builder.get_goal()
	if door and goal:
		var door_center: Vector3 = door.global_position + door.center
		var inward: Vector3 = door.along.cross(Vector3.UP)
		if inward.dot(goal.global_position - door_center) < 0.0:
			inward = -inward
		_place(_echo, door_center - inward * 3.0 - door.along * 0.6)
		_place(_guardian, door_center - inward * 3.0 + door.along * 0.6)
		var shards: Array[EchoShard] = _builder.get_shards().duplicate()
		shards[0].collect()
		await _wait(1.0)
		await _save("07_arena_door_closed")
		await get_tree().physics_frame
		pulse.cooldown_left = 0.0
		pulse.emit_pulse()
		await _wait(0.9)
		await _save("08_arena_door_pulse")
		for i: int in range(1, shards.size()):
			shards[i].collect()
		await _wait(door.open_time + 0.4)
		await _save("09_arena_door_open")
		var vents: Array[Node] = get_tree().get_nodes_in_group("bubble_vents")
		if not vents.is_empty():
			var vent := vents[0] as BubbleVent
			_place(_echo, vent.global_position + Vector3(0.4, 0.0, 0.0))
			_place(_guardian, vent.global_position + Vector3(2.5, 0.0, 1.0))
			_echo.pressure.value = _echo.pressure.max_value * 0.3
			await _wait(2.5)
			await _save("10_vent")

	# Skills: the Lure aim (keyboard hold) and the Shield.
	_stage.apply_picks({_echo: [Game.skill_catalog.find("lure_pulse")], _guardian: [Game.skill_catalog.find("shield")]})
	await _wait(0.3)
	# At the start of a frame, so the skills see the button "just pressed".
	await get_tree().process_frame
	Input.action_press("p1_skill")
	Input.action_press("p2_skill")
	await _wait(0.5)
	await _save("11_lure_aim_and_shield")
	Input.action_release("p1_skill")
	Input.action_release("p2_skill")
	await _wait(0.6)
	await _save("12_lure_decoy")

	# The pause menu and the skill choice.
	var pause := _game.get_node("PauseMenu") as PauseMenu
	pause.open()
	await _wait(1.2)
	await _save("13_pause")
	pause.close()
	await _wait(0.3)
	var screen := _game.get_node("SkillChoiceScreen") as SkillChoiceScreen
	_stage.loadout = SkillLoadout.new(_stage.world.world_id)
	_stage._apply_loadout()
	get_tree().paused = true
	_stage._offer_skills()
	await _wait(1.6)
	await _save("14_skill_choice")
	get_tree().paused = false
	get_tree().quit()


func _open_game() -> void:
	Game.started_from_menu = false
	_game = GameSceneLoader.instantiate(SaveData.Mode.CALM)
	add_child(_game)
	_stage = _game.get_node("StageManager") as StageManager
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	await _wait(0.2)
	for player: Player in _stage.players:
		if player.player_number == 1:
			_echo = player
		else:
			_guardian = player
	_protect()


func _protect() -> void:
	for player: Player in _stage.players:
		player.health.make_invulnerable(600.0)


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = Vector3(at.x, 0.0, at.z)
	node.reset_physics_interpolation()
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


## The viewport is linear float data (HDR): converted for the PNG.
func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		for y: int in image.get_height():
			for x: int in image.get_width():
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
		image.convert(Image.FORMAT_RGB8)
	image.save_png(_folder.path_join(file_name + ".png"))
	print("saved ", file_name)
