extends Node
## Screenshots of the menu screens, run with a window (not headless):
##   godot --path . res://tools/ui_capture.tscn -- <folder>
## Saves: the splash, the title screen (EN / AR), the main menu (EN / AR, with
## Continue focused and with Mode focused: its help line), the Journey screen
## with the Ocean at stage 1, 2 and 3 (EN / AR), the camera on a locked world
## (the Caves, then the Snow at the top),
## the island halfway through lighting up one step, and the skill choice (EN /
## AR). Then the PART 2b screens, each EN / AR: the main menu's Options page
## and its New Game confirmation, the intro story, and in a level: the HUD
## (calm, and under alert: low oxygen, the Echo downed with her distress hint,
## the escape timer), the pause menu (main list, Options, the Restart
## confirmation), the Level cleared card, the defeat screen, the stage summary
## and a boss fight (the Angler's title card and health bar).
## The save and the language are only changed in memory (never written).

const SPLASH: String = "res://scenes/splash_screen.tscn"
const TITLE: String = "res://scenes/title_screen.tscn"
const MENU: String = "res://scenes/main_menu.tscn"
const JOURNEY: String = "res://scenes/journey_screen.tscn"
const STORY: String = "res://scenes/story_screen.tscn"

var _folder: String


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_folder = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("ui_capture")
	DirAccess.make_dir_recursive_absolute(_folder)
	var start_language: String = Game.language
	var start_save: SaveData = Game.save
	Game.save = _save_at(1)
	# The window's very first frames read back black.
	await _wait(1.0)

	_set_language("en")
	var splash: Node = await _open(SPLASH, 1.4)
	await _shot("splash")
	await _close(splash)

	for language: String in ["en", "ar"]:
		_set_language(language)
		var title: Node = await _open(TITLE, 2.2)
		await _shot("title_" + language)
		await _close(title)

	for language: String in ["en", "ar"]:
		_set_language(language)
		var menu := await _open(MENU, 2.0) as MainMenu
		await _shot("menu_" + language)
		menu._mode_button.grab_focus()
		await _wait(0.25)
		await _shot("menu_mode_" + language)
		await _close(menu)

	for language: String in ["en", "ar"]:
		_set_language(language)
		for stage: int in 3:
			Game.save = _save_at(stage)
			var journey: Node = await _open(JOURNEY, 1.6)
			await _shot("journey_ocean_%d_%s" % [stage + 1, language])
			if stage == 1 and language == "en":
				(journey as JourneyScreen)._select(1, true)
				await _wait(1.6)
				await _shot("journey_locked_caves_en")
				(journey as JourneyScreen)._select(4, true)
				await _wait(2.4)
				await _shot("journey_locked_snow_en")
			await _close(journey)

	# The island lighting up one step (Ocean stage 1 -> 2).
	_set_language("en")
	Game.save = _save_at(1)
	Game.journey_step_from = Vector2i(0, 0)
	var stepping: Node = await _open(JOURNEY, 1.8)
	await _shot("journey_step_en")
	await _close(stepping)

	# The skill choice (stage 2 boss level: 3 cards, 2 picks each).
	Game.save = start_save
	for language: String in ["en", "ar"]:
		_set_language(language)
		var game: Node2D = GameSceneLoader.instantiate(SaveData.Mode.CALM)
		add_child(game)
		await _wait(1.0)
		var stage := game.get_node("StageManager") as StageManager
		var screen := game.get_node("SkillChoiceScreen") as SkillChoiceScreen
		var echo := game.get_node("Echo") as Player
		var guardian := game.get_node("Guardian") as Player
		stage.loadout = SkillLoadout.new("ocean")
		stage._apply_loadout()
		stage.stage_index = 1
		stage.level_index = 2
		get_tree().paused = true
		stage._offer_skills()
		await _wait(1.2)
		screen.move_cursor(echo, 1)
		screen.press_pick(guardian)
		screen.move_cursor(guardian, 1)
		await _wait(0.25)
		await _shot("skills_" + language)
		get_tree().paused = false
		await _close(game)

	Game.save = start_save
	await _capture_part_2b()
	Game.save = start_save
	Game.language = start_language
	print("screenshots in ", _folder)
	get_tree().quit()


func _capture_part_2b() -> void:
	Game.save = _save_at(1)
	for language: String in ["en", "ar"]:
		_set_language(language)
		var menu := await _open(MENU, 1.6) as MainMenu
		menu._show_options(true)
		await _wait(1.0)
		await _shot("options_" + language)
		menu._show_options(false)
		menu._show_confirm(true)
		await _wait(1.0)
		await _shot("confirm_new_game_" + language)
		await _close(menu)

		Game.story_id = "intro"
		var story := await _open(STORY, 0.5) as StoryScreen
		story._show_all()
		await _wait(1.6)
		await _shot("story_" + language)
		await _close(story)
		Game.story_id = ""

		await _capture_level(language)


## The HUD, the pause menu and the in-game screens of one language.
func _capture_level(language: String) -> void:
	var game: Node2D = GameSceneLoader.instantiate(SaveData.Mode.CALM)
	add_child(game)
	await _wait(1.5)
	var stage := game.get_node("StageManager") as StageManager
	var hud := game.get_node("Hud") as Hud
	var pause := game.get_node("PauseMenu") as PauseMenu
	var end := game.get_node("EndScreen") as EndScreen
	var echo := game.get_node("Echo") as Player
	var guardian := game.get_node("Guardian") as Player
	var awareness := game.get_node("DepthAwareness") as DepthAwareness
	hud.set_debug_visible(false)
	stage.loadout = SkillLoadout.new("ocean")
	stage.loadout.set_rank("echo", "far_echo", 2)
	stage.loadout.set_rank("echo", "lure_pulse", 1)
	stage.loadout.set_rank("guardian", "shield", 1)
	stage._apply_loadout()
	for player: Player in [echo, guardian]:
		player.health._invulnerable_left = 999.0
	# Calm: a pulse, one shard, some awareness, a little damage.
	(echo.get_node("Pulse") as PulseAbility).emit_pulse()
	awareness.add_pulse()
	stage._on_shard_collected(null)
	guardian.health.set_segments(2.6)
	await _wait(1.2)
	await _shot("hud_%s" % language)

	# Under alert: low oxygen, the Echo down (distress hint), the escape timer.
	echo.pressure.value = echo.pressure.max_value * 0.12
	guardian.pressure.value = guardian.pressure.max_value * 0.4
	guardian.health.set_segments(1.0)
	for i: int in 3:
		awareness.add_pulse()
	echo.health.down(PlayerHealth.Cause.CREATURE)
	(game.get_node("EnvironmentLayer/EscapeEvent") as EscapeEvent).start(42.0)
	await _wait(0.8)
	await _shot("hud_alert_%s" % language)
	echo.health.revive()
	(game.get_node("EnvironmentLayer/EscapeEvent") as EscapeEvent).stop()
	echo.pressure.refill()
	guardian.health.refill()
	await _wait(0.5)

	pause.open()
	await _wait(1.0)
	await _shot("pause_%s" % language)
	pause._show_page("options")
	await _wait(1.0)
	await _shot("pause_options_%s" % language)
	pause._show_page("main")
	pause._ask(PauseMenu.Confirm.RESTART)
	await _wait(1.0)
	await _shot("pause_confirm_%s" % language)
	pause.close()
	await _wait(0.3)

	get_tree().paused = true
	end.show_level_cleared(1, 3)
	await _wait(1.0)
	await _shot("level_cleared_%s" % language)
	end.hide_screen()
	# The defeat screen retries on its own: long enough for the picture.
	end.death_restart_delay = 30.0
	end.restart_requested.disconnect(stage._retry_faded)
	end.show_defeat(stage.players, 1, 2, 3, SaveData.Mode.CALM)
	await _wait(6.0)
	await _shot("defeat_%s" % language)
	end.hide_screen()
	end.show_stage_cleared(1, true, true, 263.0, 41, 7, 12, stage.players)
	await _wait(1.8)
	await _shot("stage_summary_%s" % language)
	end.hide_screen()
	get_tree().paused = false

	# The boss: the players step into the Angler's arena (it wakes: title + bar).
	stage.test_level_index = 2
	stage.test_start_at = StageManager.TestStart.IN_ARENA
	stage._start_level(2)
	for player: Player in [echo, guardian]:
		player.health._invulnerable_left = 999.0
	await _until_boss_title(game)
	await _shot("boss_title_%s" % language)
	await _wait(3.5)
	await _shot("boss_fight_%s" % language)
	await _close(game)


## Waits until the boss shows its name card (it wakes, then its intro), at most 12 s.
func _until_boss_title(game: Node) -> void:
	var stage := game.get_node("StageManager") as StageManager
	var boss: Boss = stage.level_builder.get_boss() as Boss
	for i: int in 120:
		if boss and boss._title and boss._title.is_showing() and boss._title._age > 0.8:
			return
		await _wait(0.1)


## A save in memory: the Ocean at stage (0-based).
func _save_at(stage: int) -> SaveData:
	var save: SaveData = Game._fresh_save()
	save.stage_index = stage
	return save


func _open(path: String, wait: float) -> Node:
	var screen: Node = (load(path) as PackedScene).instantiate()
	add_child(screen)
	await _wait(wait)
	return screen


func _close(screen: Node) -> void:
	screen.queue_free()
	await _wait(0.3)


func _set_language(language: String) -> void:
	Game.language = language
	Game.language_changed.emit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Saves the screen as an 8-bit sRGB PNG (the viewport holds linear HDR values).
func _shot(file_name: String) -> void:
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
	srgb.save_png(_folder.path_join(file_name + ".png"))
	print("saved ", file_name)
