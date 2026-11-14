extends Node
## Headless: every screen with simulated keyboard, gamepad and mouse input.
## Walks the splash, the title ("press any button"), the main menu (buttons,
## Options with its sliders, the New Game question, back to the title), the
## Journey, a story screen and, in the real game.tscn, the pause menu (pages,
## questions), the skill choice (each player's own prompts), the defeat screen
## and the stage summary. Checks on every step that a visible control of the
## screen has the focus, that the D-pad, the left stick (one step per push,
## repeats while held, no flicker from drift) and the keys move it, that A /
## Cross confirms and B / Circle goes back, and that the prompts switch to the
## device last used (keyboard / mouse / gamepad past the deadzone; Xbox or
## PlayStation glyphs by the pad's name; each player's own side). Scene
## changes are only recorded (Game.block_scene_changes); the save and the
## settings go to test files.
## godot --headless --path . --fixed-fps 60 res://tools/test_menus.tscn
## Exits with 1 when a check fails.

const SPLASH_SCENE: String = "res://scenes/splash_screen.tscn"
const TITLE_SCENE: String = "res://scenes/title_screen.tscn"
const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const JOURNEY_SCENE: String = "res://scenes/journey_screen.tscn"
const STORY_SCENE: String = "res://scenes/story_screen.tscn"
const TEST_SAVE: String = "user://test_menus_save.json"
const TEST_SETTINGS: String = "user://test_menus_settings.json"

var _failures: int = 0
var _checks: int = 0
var _screen: Node
var _save_path: String
var _settings_path: String
var _language: String


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("TEST MENUS (keyboard + gamepad)")
	_save_path = Game.save_path
	_settings_path = Game.settings_path
	_language = Game.language
	Game.save_path = TEST_SAVE
	Game.settings_path = TEST_SETTINGS
	for path: String in [TEST_SAVE, TEST_SETTINGS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Game.save = SaveData.new()
	Game.block_scene_changes = true
	Game.language = "en"
	await _frames(2)

	await _test_device_rules()
	await _test_splash_and_title()
	await _test_main_menu()
	await _test_journey()
	await _test_story()
	await _test_game_screens()

	await _close_screen()
	Game.block_scene_changes = false
	Game.save_path = _save_path
	Game.settings_path = _settings_path
	Game.language = _language
	InputDevices.name_overrides.clear()
	print("")
	print("%d checks, %d failed" % [_checks, _failures])
	print("RESULT: ", "MENUS OK" if _failures == 0 else "MENUS FAIL")
	get_tree().quit(0 if _failures == 0 else 1)


# --- Devices and glyphs -------------------------------------------------------------

func _test_device_rules() -> void:
	print("- which device is in use, which glyphs")
	var bound: Callable = func(action: StringName, kind: String) -> bool:
		for event: InputEvent in InputMap.action_get_events(action):
			if event.get_class() == kind:
				return true
		return false
	_check(bound.call(&"ui_accept", "InputEventJoypadButton") and bound.call(&"ui_cancel", "InputEventJoypadButton"),
		"A / Cross confirms and B / Circle goes back in every menu (ui_accept, ui_cancel)")
	_check(not bound.call(&"ui_up", "InputEventJoypadMotion") and not bound.call(&"ui_left", "InputEventJoypadMotion")
		and bound.call(&"ui_up", "InputEventJoypadButton"), "the stick steps through the navigator, the D-pad stays bound")
	await _key(KEY_A)
	_check(InputDevices.menu_device == InputGlyph.Device.KEYBOARD, "a key = the keyboard")
	await _stick(0, JOY_AXIS_LEFT_X, 0.3)
	await _stick(0, JOY_AXIS_LEFT_X, 0.0)
	_check(InputDevices.menu_device == InputGlyph.Device.KEYBOARD, "stick drift under the deadzone does not switch")
	await _stick(0, JOY_AXIS_TRIGGER_RIGHT, 0.9)
	await _stick(0, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(InputDevices.menu_device == InputGlyph.Device.GAMEPAD, "a trigger pulled = the gamepad")
	await _mouse_move(Vector2(4.0, 3.0))
	_check(InputDevices.menu_device == InputGlyph.Device.GAMEPAD, "a tiny mouse nudge does not switch")
	await _mouse_move(Vector2(30.0, 10.0))
	_check(InputDevices.menu_device == InputGlyph.Device.KEYBOARD, "moving the mouse = the keyboard")
	await _pad(0, JOY_BUTTON_A)
	_check(InputDevices.menu_device == InputGlyph.Device.GAMEPAD, "a gamepad button = the gamepad")
	await _mouse_click()
	_check(InputDevices.menu_device == InputGlyph.Device.KEYBOARD, "a mouse click = the keyboard")

	var names: Dictionary = {
		"Xbox Wireless Controller": InputDevices.PadStyle.XBOX, "XInput Gamepad": InputDevices.PadStyle.XBOX,
		"PS4 Controller": InputDevices.PadStyle.PLAYSTATION, "PS5 Controller": InputDevices.PadStyle.PLAYSTATION,
		"DualSense Wireless Controller": InputDevices.PadStyle.PLAYSTATION, "Sony Interactive Entertainment Wireless Controller": InputDevices.PadStyle.PLAYSTATION,
		"Wireless Controller": InputDevices.PadStyle.PLAYSTATION, "Logitech Dual Action": InputDevices.PadStyle.XBOX, "": InputDevices.PadStyle.XBOX,
	}
	var all_right: bool = true
	for pad_name: String in names:
		if InputDevices.style_for(pad_name) != names[pad_name]:
			all_right = false
			print("        wrong style for '%s'" % pad_name)
	_check(all_right, "PlayStation glyphs for PlayStation pads (by name), Xbox glyphs otherwise")
	_check(InputDevices.style_for("Generic Gamepad", InputDevices.SONY_VENDOR_ID) == InputDevices.PadStyle.PLAYSTATION, "Sony's vendor id = PlayStation")

	var prompt := InputPrompt.new()
	add_child(prompt)
	prompt.setup([{"actions": [&"ui_accept"], "text": "ok"}, {"actions": [&"ui_up", &"ui_down"], "text": "move"}], InputDevices.menu_device, true)
	InputDevices.name_overrides[0] = "Xbox Wireless Controller"
	await _pad(0, JOY_BUTTON_B)
	await _frames(1)
	var specs: Array[Dictionary] = prompt.get_shown_specs()
	_check(specs.size() == 2 and specs[0].get("label", "") == "A" and specs[1].shape == InputGlyph.Shape.DPAD,
		"menu prompt on an Xbox pad: (A), the D-pad")
	InputDevices.name_overrides[1] = "DualSense Wireless Controller"
	await _pad(1, JOY_BUTTON_B)
	await _frames(1)
	specs = prompt.get_shown_specs()
	_check(specs[0].get("symbol", InputGlyph.Symbol.NONE) == InputGlyph.Symbol.CROSS, "a PlayStation pad pressed: the same prompt shows Cross at once")
	await _key(KEY_DOWN)
	await _frames(1)
	specs = prompt.get_shown_specs()
	_check(specs[0].shape == InputGlyph.Shape.KEY and specs[1].shape == InputGlyph.Shape.ARROW_KEY, "a key: back to key caps at once")
	var start_spec: Dictionary = InputGlyph.spec_for(&"pause", InputGlyph.Device.GAMEPAD, InputDevices.PadStyle.PLAYSTATION)
	_check(start_spec.get("label", "") == "Options" and InputGlyph.spec_for(&"pause", InputGlyph.Device.GAMEPAD).get("label", "") == "Menu",
		"Start reads Options on a PlayStation pad, Menu on an Xbox pad")
	prompt.queue_free()


# --- Splash and title ---------------------------------------------------------------

func _test_splash_and_title() -> void:
	print("- splash and title")
	await _open(SPLASH_SCENE)
	await _seconds(0.4)
	Game.last_scene_request = ""
	await _pad(0, JOY_BUTTON_Y)
	_check(Game.last_scene_request == Game.title_scene, "the splash: any gamepad button skips it")

	await _open(TITLE_SCENE)
	await _seconds(0.7)
	Game.last_scene_request = ""
	await _pad(1, JOY_BUTTON_X)
	_check(Game.last_scene_request == Game.main_menu_scene, "the title: any gamepad button (X on pad 2) goes on")
	_check(InputDevices.player_pad(1) == 1 and InputDevices.player_device[1] == InputGlyph.Device.GAMEPAD
		and InputDevices.menu_device == InputGlyph.Device.GAMEPAD, "that pad is Player 1's, and the menus show gamepad glyphs")
	await _open(TITLE_SCENE)
	await _seconds(0.7)
	Game.last_scene_request = ""
	await _key(KEY_K)
	_check(Game.last_scene_request == Game.main_menu_scene and InputDevices.player_device[1] == InputGlyph.Device.KEYBOARD,
		"any key goes on too (Player 1 on the keyboard)")
	# Back to the usual binding: pad 0 = Player 1, pad 1 = Player 2.
	Game.assign_player_one(0)


# --- Main menu ----------------------------------------------------------------------

func _test_main_menu() -> void:
	print("- main menu")
	var menu := await _open(MENU_SCENE) as MainMenu
	_expect_focus("it opens with a button focused")
	var first: Control = _focus()
	await _pad(0, JOY_BUTTON_DPAD_DOWN)
	_check(_focus() != first and _focus() is GlowButton, "D-pad down moves the focus")
	_expect_focus("still focused")
	await _key(KEY_UP)
	_check(_focus() == first, "the Up key moves it back")
	var steps: int = Game.input_devices.steps_sent
	await _stick(0, JOY_AXIS_LEFT_Y, 0.9)
	await _frames(2)
	_check(Game.input_devices.steps_sent == steps + 1 and _focus() != first, "pushing the stick down = one step")
	await _seconds(0.3)
	_check(Game.input_devices.steps_sent == steps + 1, "no second step before the repeat delay")
	await _stick(0, JOY_AXIS_LEFT_Y, 0.5)
	await _seconds(0.45)
	_check(Game.input_devices.steps_sent >= steps + 2, "held down, it repeats (%d steps)" % (Game.input_devices.steps_sent - steps))
	await _stick(0, JOY_AXIS_LEFT_Y, 0.0)
	var settled: int = Game.input_devices.steps_sent
	await _seconds(0.4)
	_check(Game.input_devices.steps_sent == settled, "let go, it stops")
	for wobble: float in [0.4, 0.55, 0.42, 0.58, 0.3]:
		await _stick(0, JOY_AXIS_LEFT_Y, wobble)
	await _stick(0, JOY_AXIS_LEFT_Y, 0.0)
	_check(Game.input_devices.steps_sent == settled, "a stick wobbling near the middle never steps")
	_expect_focus("still focused after the stick")

	# The Mode toggle with left / right.
	_focus_on(menu._mode_button)
	var mode: SaveData.Mode = Game.get_mode()
	await _pad(0, JOY_BUTTON_DPAD_RIGHT)
	_check(Game.get_mode() != mode and _focus() == menu._mode_button, "right on Mode switches it (the focus stays)")
	await _key(KEY_LEFT)
	_check(Game.get_mode() == mode, "left switches it back")

	# Options: sliders with left / right, B back.
	_focus_on(menu._options_button)
	await _pad(0, JOY_BUTTON_A)
	_check(menu._options.visible and _focus() is HSlider, "A on Options opens it with the first slider focused")
	var slider := _focus() as HSlider
	var value: float = slider.value
	await _pad(0, JOY_BUTTON_DPAD_LEFT)
	_check(slider.value < value, "D-pad left lowers the slider (%.2f -> %.2f)" % [value, slider.value])
	await _stick(0, JOY_AXIS_LEFT_X, 0.9)
	await _frames(2)
	await _stick(0, JOY_AXIS_LEFT_X, 0.0)
	_check(is_equal_approx(slider.value, value), "the stick right raises it back")
	await _pad(0, JOY_BUTTON_DPAD_DOWN)
	_check(_focus() is HSlider and _focus() != slider, "D-pad down: the next slider")
	await _pad(0, JOY_BUTTON_B)
	_check(not menu._options.visible and _focus() == menu._options_button, "B closes Options, back on its button")

	# Focus lost (a click on empty space): it comes back.
	_focus().release_focus()
	await _frames(2)
	_expect_focus("focus lost: the screen's button is focused again")

	# The New Game question: No first, B = No.
	menu._show_confirm(true)
	await _frames(1)
	_check(_focus() == menu._confirm.no_button, "the New Game question opens on No")
	await _pad(0, JOY_BUTTON_DPAD_UP)
	_expect_focus("navigating in the question keeps a button focused")
	await _pad(0, JOY_BUTTON_B)
	_check(not menu._confirm.visible and _focus() == menu._new_game_button, "B answers No (back on New Game)")
	await _key(KEY_ESCAPE)
	_check(Game.last_scene_request == Game.title_scene, "Esc / B on the buttons goes back to the title")
	Game.last_scene_request = ""
	_check(_prompt_device(menu._prompt) == InputGlyph.Device.KEYBOARD, "the prompt follows the key just pressed")
	await _pad(0, JOY_BUTTON_DPAD_UP)
	_check(_prompt_device(menu._prompt) == InputGlyph.Device.GAMEPAD, "and switches to the pad when it is used")
	await _pad(0, JOY_BUTTON_B)
	_check(Game.last_scene_request == Game.title_scene, "B on the buttons goes back to the title too")


# --- Journey ------------------------------------------------------------------------

func _test_journey() -> void:
	print("- Journey")
	var journey := await _open(JOURNEY_SCENE) as JourneyScreen
	await _frames(2)
	_expect_focus("it opens with Continue focused")
	var selected: int = journey._selected
	await _stick(0, JOY_AXIS_LEFT_Y, -0.9)
	await _frames(2)
	await _stick(0, JOY_AXIS_LEFT_Y, 0.0)
	_check(journey._selected == selected + 1, "the stick up looks at the next world")
	await _pad(0, JOY_BUTTON_DPAD_DOWN)
	_check(journey._selected == selected, "D-pad down looks back")
	await _pad(0, JOY_BUTTON_DPAD_LEFT)
	_expect_focus("left / right move between the two buttons")
	Game.last_scene_request = ""
	await _pad(0, JOY_BUTTON_B)
	_check(Game.last_scene_request == Game.main_menu_scene, "B goes back to the main menu")


# --- Story --------------------------------------------------------------------------

func _test_story() -> void:
	print("- story")
	var story := await _open(STORY_SCENE) as StoryScreen
	await _frames(2)
	await _pad(0, JOY_BUTTON_A)
	await _frames(2)
	_check(not story._button.disabled, "A shows every line at once")
	_expect_focus("then Continue is focused")
	_focus().release_focus()
	await _frames(2)
	_expect_focus("and stays focused (restored)")
	Game.last_scene_request = ""
	await _pad(0, JOY_BUTTON_A)
	await _frames(2)
	_check(Game.last_scene_request != "", "A continues")


# --- The game's screens -------------------------------------------------------------

func _test_game_screens() -> void:
	print("- in the game: pause, skill choice, defeat, summary")
	await _close_screen()
	Game.started_from_menu = false
	var game: Node3D = GameSceneLoader.instantiate(SaveData.Mode.CALM)
	add_child(game)
	_screen = game
	await _frames(4)
	var stage := game.get_node("StageManager") as StageManager
	var pause := game.get_node("PauseMenu") as PauseMenu
	var end_screen := game.get_node("EndScreen") as EndScreen
	var choice := game.get_node("SkillChoiceScreen") as SkillChoiceScreen
	for player: Player in stage.players:
		player.health.make_invulnerable(600.0)
	_check(get_viewport().gui_get_focus_owner() == null, "while playing nothing in the menus is focused")

	await _pad(0, JOY_BUTTON_START)
	_check(pause.is_open and _focus() == pause._resume_button, "Start pauses, Resume focused")
	await _pad(1, JOY_BUTTON_DPAD_DOWN)
	_check(_focus() == pause._options_button, "the other pad's D-pad moves it too")
	await _pad(1, JOY_BUTTON_A)
	_check(pause._options.visible and _focus() is HSlider, "A opens Options (first slider)")
	await _pad(1, JOY_BUTTON_B)
	_check(pause._main_page.visible and _focus() == pause._options_button, "B: back to the pause page")
	await _pad(0, JOY_BUTTON_DPAD_DOWN)
	_check(_focus() == pause._restart_button, "down to Restart")
	await _pad(0, JOY_BUTTON_A)
	_check(pause._confirm.visible and _focus() == pause._confirm.no_button, "A asks first (No focused)")
	await _pad(0, JOY_BUTTON_B)
	_check(pause._main_page.visible and _focus() == pause._restart_button, "B = No, back on Restart")
	await _pad(0, JOY_BUTTON_B)
	_check(not pause.is_open and not get_tree().paused, "B on the pause page resumes")
	await _key(KEY_ESCAPE)
	_check(pause.is_open and _focus() == pause._resume_button, "Esc pauses too")
	await _pad(0, JOY_BUTTON_START)
	_check(not pause.is_open, "Start resumes")

	# Skill choice: each player's own glyphs on their side.
	InputDevices.name_overrides[0] = "Xbox Wireless Controller"
	InputDevices.name_overrides[1] = "PS5 Controller"
	get_tree().paused = true
	stage._offer_skills()
	await _seconds(choice.input_delay + 0.2)
	var echo_side: SkillChoiceScreen.ChoiceSide = choice._sides[0]
	var guardian_side: SkillChoiceScreen.ChoiceSide = choice._sides[1]
	await _key(KEY_S)
	await _pad(1, JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	_check(echo_side.prompt.device == InputGlyph.Device.KEYBOARD and guardian_side.prompt.device == InputGlyph.Device.GAMEPAD,
		"the Echo's side shows keys (she used them), the Guardian's his pad's glyphs")
	var guardian_specs: Array[Dictionary] = guardian_side.prompt.get_shown_specs()
	_check(guardian_specs.size() == 2 and guardian_specs[1].get("symbol", InputGlyph.Symbol.NONE) == InputGlyph.Symbol.CROSS,
		"his PlayStation pad: Cross to pick")
	_check(echo_side.cursor == 1 and guardian_side.cursor == 1, "each moved their own cursor")
	await _pad(0, JOY_BUTTON_DPAD_UP)
	await _frames(1)
	_check(echo_side.prompt.device == InputGlyph.Device.GAMEPAD and echo_side.prompt.get_shown_specs()[1].get("label", "") == "A",
		"the Echo picks up her Xbox pad: her side switches to (A) at once")
	_check(guardian_side.prompt.device == InputGlyph.Device.GAMEPAD, "the Guardian's side stays as it was")
	await _pad(0, JOY_BUTTON_B)
	_check(not echo_side.done, "B does nothing on the choice (no stray pick)")
	for player: Player in stage.players:
		choice.press_pick(player)
	await _seconds(choice.summary_time + 0.4)
	_check(not choice.is_open, "both picked: the choice closes")
	get_tree().paused = false
	var status_prompts: Array[Node] = game.get_node("Hud").find_children("*", "InputPrompt", true, false)
	var follows_players: bool = not status_prompts.is_empty()
	for node: Node in status_prompts:
		follows_players = follows_players and (node as InputPrompt).follow == InputPrompt.Follow.PLAYER
	_check(follows_players, "the HUD's skill buttons follow each player's own device (%d prompts)" % status_prompts.size())

	# The downed Echo's distress hint shows her own button.
	var echo: Player = stage.players[0]
	echo.health.make_invulnerable(0.0)
	echo.health.down(PlayerHealth.Cause.CREATURE)
	await _pad(0, JOY_BUTTON_X)
	var echo_status: PlayerStatus = null
	for node: Node in game.get_node("Hud").find_children("*", "PlayerStatus", true, false):
		if (node as PlayerStatus).player == echo:
			echo_status = node as PlayerStatus
	_check(echo_status != null and echo_status._distress_row.visible, "the downed Echo's distress hint shows")
	var distress_prompt := echo_status._distress_row.get_child(0) as InputPrompt
	_check(distress_prompt.follow == InputPrompt.Follow.PLAYER and distress_prompt.device == InputGlyph.Device.GAMEPAD
		and distress_prompt.get_shown_specs()[0].get("label", "") == "A", "with her own pad's button (A)")
	await _key(KEY_W)
	await _frames(1)
	_check(distress_prompt.device == InputGlyph.Device.KEYBOARD and distress_prompt.get_shown_specs()[0].get("label", "") == "Space",
		"her keys used: Space")
	echo.health.revive()
	await _frames(2)

	# Defeat: Retry focused, A on it (B does nothing: there is nowhere to go back to).
	stage.level_fade_enabled = false
	for player: Player in stage.players:
		player.health.make_invulnerable(0.0)
		player.health.down(PlayerHealth.Cause.CREATURE)
	await _frames(3)
	_check(end_screen.is_showing() and _focus() == end_screen._button, "defeat: Retry focused")
	await _pad(1, JOY_BUTTON_B)
	_check(end_screen.is_showing() and _focus() == end_screen._button, "B keeps the defeat screen (and its focus)")
	var retried: Array[bool] = [false]
	end_screen.restart_requested.connect(func() -> void: retried[0] = true, CONNECT_ONE_SHOT)
	await _pad(1, JOY_BUTTON_A)
	_check(retried[0], "A retries")
	await _frames(4)
	end_screen.hide_screen()
	stage.is_over = false
	get_tree().paused = false

	# Stage summary: Continue focused.
	end_screen.show_stage_cleared(1, true, false, 120.0, 10, 2, 5, stage.players)
	await _frames(2)
	_check(_focus() == end_screen._button, "stage summary: Continue focused")
	_focus().release_focus()
	await _frames(2)
	_check(_focus() == end_screen._button, "and kept focused")
	var continued: Array[bool] = [false]
	# Run on its own, the game would reload the scene (here: this test).
	end_screen.continue_requested.disconnect(stage._on_continue_pressed)
	end_screen.continue_requested.connect(func() -> void: continued[0] = true, CONNECT_ONE_SHOT)
	await _key(KEY_ENTER)
	_check(continued[0], "Enter continues")
	end_screen.hide_screen()
	get_tree().paused = false


# --- Helpers ------------------------------------------------------------------------

func _open(path: String) -> Node:
	await _close_screen()
	_screen = (load(path) as PackedScene).instantiate()
	add_child(_screen)
	await _frames(3)
	return _screen


func _close_screen() -> void:
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
	get_tree().paused = false
	await _frames(2)


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _focus_on(control: Control) -> void:
	if control is GlowButton:
		(control as GlowButton).focus_quietly()
	else:
		control.grab_focus()


## A visible, usable control of the open screen has the focus.
func _expect_focus(label: String) -> void:
	var owner_control: Control = _focus()
	var ok: bool = owner_control != null and owner_control.is_visible_in_tree() and _screen.is_ancestor_of(owner_control)
	_check(ok, label + (" (%s)" % owner_control.name if owner_control else " (nothing focused)"))


func _prompt_device(prompt: InputPrompt) -> InputGlyph.Device:
	return prompt.device


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)
	await _frames(1)


func _pad(device: int, button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)
	await _frames(1)


func _stick(device: int, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await _frames(1)


func _mouse_move(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(-50.0, -50.0)
	Input.parse_input_event(event)
	await _frames(1)


## A click outside the window's controls (it only counts for the device).
func _mouse_click() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = Vector2(-50.0, -50.0)
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["ok  " if ok else "FAIL", label])


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout
