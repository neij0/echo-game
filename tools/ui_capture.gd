extends Node
## Screenshots of the menu screens, run with a window (not headless):
##   godot --path . res://tools/ui_capture.tscn -- <folder>
## Saves: the splash, the title screen (EN / AR), the main menu (EN / AR, with
## Continue focused and with Mode focused: its help line), the Journey screen
## with the Ocean at stage 1, 2 and 3 (EN / AR), the camera on a locked world,
## the island halfway through lighting up one step, and the skill choice (EN /
## AR). The save and the language are only changed in memory (never written).

const SPLASH: String = "res://scenes/splash_screen.tscn"
const TITLE: String = "res://scenes/title_screen.tscn"
const MENU: String = "res://scenes/main_menu.tscn"
const JOURNEY: String = "res://scenes/journey_screen.tscn"

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
	Game.language = start_language
	print("screenshots in ", _folder)
	get_tree().quit()


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
