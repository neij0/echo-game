class_name GameState
extends Node
## Autoload "Game" (scenes/game_state.tscn): the progress (SaveData), the
## settings (language, preferred mode, brightness, the volume of each audio
## bus), which gamepad each player uses, and the moves between screens:
## splash -> title ("press any button": that device becomes Player 1's) ->
## main menu -> New Game: intro story -> stage 1 / Continue: Journey -> stage
## (game.tscn) -> stage summary -> Journey (the island lights up one step) ->
## next stage; after the last stage of a world: its story -> Journey.
## Structure: World (5) -> Stage (3 per world) -> Level (3 per stage).

signal language_changed

## Every world in play order (save file, Journey, story file names).
@export var world_ids: PackedStringArray = PackedStringArray(["ocean", "caves", "forest", "desert", "snow"])
## The WorldConfig of each world that exists so far. A world id without a
## config shows "coming soon" on the Journey screen.
@export var worlds: Array[WorldConfig] = []
## Every skill of the game (offered between levels, see SkillOffer).
@export var skill_catalog: SkillCatalog

@export_group("Scenes")
@export_file("*.tscn") var title_scene: String = "res://scenes/title_screen.tscn"
@export_file("*.tscn") var main_menu_scene: String = "res://scenes/main_menu.tscn"
@export_file("*.tscn") var game_scene: String = "res://scenes/game.tscn"
@export_file("*.tscn") var story_scene: String = "res://scenes/story_screen.tscn"
@export_file("*.tscn") var journey_scene: String = "res://scenes/journey_screen.tscn"

@export_group("Files")
@export var save_path: String = "user://save.json"
@export var settings_path: String = "user://settings.json"
## Story text files: <story_folder>/<story id>_<language>.txt ("intro" before
## the first stage, "<world id>_end" after a world).
@export var story_folder: String = "res://story"

@export_group("Defaults")
## "en" or "ar".
@export var default_language: String = "en"
@export var default_mode: SaveData.Mode = SaveData.Mode.CALM

@export_group("Brightness")
## Brightness setting: scales the ambient darkness and the players' lights a
## little (never the pulse or any other gameplay reveal). The range is kept
## narrow so even the maximum cannot make the far level readable. 1 = as designed
## (the lights were tuned so that 1 is what the 3D play-tests liked best;
## older settings files are converted, OLD_BRIGHTNESS_BASES).
@export var default_brightness: float = 1.0
@export var min_brightness: float = 0.7
@export var max_brightness: float = 1.3

@export_group("Volume")
## The audio buses with an Options slider (default_bus_layout.tres), and their
## default volume (0-1, linear).
@export var volume_buses: PackedStringArray = PackedStringArray(["Master", "Music", "SFX", "Ambience", "UI"])
@export_range(0.0, 1.0) var default_volume: float = 0.8

@export_group("UI")
## The shared look of the screens (fonts, glowing buttons, panels, prompts).
@export var ui_theme: Theme = preload("res://assets/ui/echo_theme.tres")

## Current progress. Always set; has_save() tells if it is on disk.
var save: SaveData
var language: String = "en"
## See default_brightness.
var brightness: float = 1.0
## Bus name -> volume (0-1, linear). See volume_buses.
var volumes: Dictionary = {}
## Mode picked in the main menu (used by New Game, copied into the save).
var preferred_mode: SaveData.Mode = SaveData.Mode.CALM
## True when the stage was started from the menus. False when game.tscn is run
## on its own (F6): the StageManager then uses its own test values and never
## writes the save.
var started_from_menu: bool = false
## World whose story screen should show (set when a world is finished).
var finished_world_id: String = ""
## The story the story screen shows next: "intro" or "<world id>_end".
var story_id: String = "intro"
## Set by complete_stage: the progress before it (world index, stage index), so
## the Journey screen can play the island lighting up one step. Cleared there.
var journey_step_from: Vector2i = Vector2i(-1, -1)
## The gamepad of each player (InputMap device) and whether they started on it
## (the press on the title screen).
var player_gamepads: Dictionary = {1: 0, 2: 1}
var player_on_gamepad: Dictionary = {1: false, 2: false}
## Screens fade through black (see _change_scene).
var fader: ScreenFader
## The menus' focus / press sounds.
var ui_audio: UiAudio
var _changing_scene: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fader = ScreenFader.new()
	add_child(fader)
	ui_audio = UiAudio.new()
	add_child(ui_audio)
	_fade_in_new_scene.call_deferred()
	language = default_language
	preferred_mode = default_mode
	brightness = default_brightness
	for bus: String in volume_buses:
		volumes[bus] = default_volume
	_load_settings()
	apply_volumes()
	save = SaveData.read(save_path)
	if save == null:
		save = _fresh_save()


# --- Text and language ------------------------------------------------------

func text(key: String) -> String:
	return UiText.get_text(key, language)


func is_rtl() -> bool:
	return language == "ar"


## Lays out a screen right-to-left in Arabic (containers mirror, text is RTL).
func apply_direction(control: Control) -> void:
	control.layout_direction = Control.LAYOUT_DIRECTION_RTL if is_rtl() else Control.LAYOUT_DIRECTION_LTR


func toggle_language() -> void:
	var index: int = UiText.LANGUAGES.find(language)
	language = UiText.LANGUAGES[(index + 1) % UiText.LANGUAGES.size()]
	_save_settings()
	language_changed.emit()


## Called by the Options slider; saved with the other settings.
func set_brightness(value: float) -> void:
	brightness = clampf(value, min_brightness, max_brightness)
	_save_settings()


## Called by the Options sliders; saved with the other settings.
func set_volume(bus: String, value: float) -> void:
	if not bus in volume_buses:
		return
	volumes[bus] = clampf(value, 0.0, 1.0)
	apply_volumes()
	_save_settings()


func get_volume(bus: String) -> float:
	return float(volumes.get(bus, default_volume))


## Sets every bus's volume on the AudioServer (0 = muted).
func apply_volumes() -> void:
	for bus: String in volume_buses:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var value: float = get_volume(bus)
		AudioServer.set_bus_mute(index, value <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func world_display_name(world_id: String) -> String:
	return text("world_" + world_id)


# --- Mode -------------------------------------------------------------------

func get_mode() -> SaveData.Mode:
	return save.mode


func mode_name(mode: SaveData.Mode) -> String:
	return text("mode_challenge" if mode == SaveData.Mode.CHALLENGE else "mode_calm")


## Switches Calm <-> Challenge. Also updates an existing save right away.
func toggle_mode() -> void:
	save.mode = SaveData.Mode.CHALLENGE if save.mode == SaveData.Mode.CALM else SaveData.Mode.CALM
	preferred_mode = save.mode
	_save_settings()
	if has_save():
		write_save()


# --- Progress ---------------------------------------------------------------

func has_save() -> bool:
	return SaveData.exists(save_path)


func write_save() -> void:
	var error: Error = save.write(save_path)
	if error != OK:
		push_error("Game: could not write the save (%s)" % error_string(error))


## A fresh save, then the intro story, then the first stage.
func new_game() -> void:
	save = _fresh_save()
	write_save()
	journey_step_from = Vector2i(-1, -1)
	story_id = "intro"
	go_to_story()


## The saved progress on the Journey screen (its Continue plays it).
func continue_game() -> void:
	var loaded: SaveData = SaveData.read(save_path)
	if loaded:
		save = loaded
	journey_step_from = Vector2i(-1, -1)
	go_to_journey()


## True if the saved stage can be played (its world has content).
func can_play_current() -> bool:
	var world: WorldConfig = get_current_world()
	return world != null and save.stage_index < world.get_stage_count()


## Starts the saved stage, or opens the Journey screen if that world has no
## content yet (or the whole game is finished).
func play_current() -> void:
	if can_play_current():
		go_to_game()
	else:
		go_to_journey()


## The story screen's Continue: the intro leads into the first stage, the
## ending of a world to the Journey.
func after_story() -> void:
	if story_id == "intro":
		play_current()
	else:
		go_to_journey()


## Called by the StageManager when a stage's boss is beaten. Moves the save to
## the next stage (or the next world) and writes it, with the skills owned now
## (null = keep the saved ones). A new world starts without skills. Returns
## true when that was the world's last stage.
func complete_stage(skills: SkillLoadout = null) -> bool:
	var world: WorldConfig = get_current_world()
	finished_world_id = ""
	journey_step_from = Vector2i(get_world_index(save.world_id), save.stage_index)
	if skills:
		save.skills = skills.copy()
	save.stage_index += 1
	var world_finished: bool = world == null or save.stage_index >= world.get_stage_count()
	if world_finished:
		finished_world_id = save.world_id
		story_id = save.world_id + "_end"
		var next: int = world_ids.find(save.world_id) + 1
		if next < world_ids.size():
			save.world_id = world_ids[next]
			save.stage_index = 0
			save.skills = SkillLoadout.new(save.world_id)
			if not save.world_id in save.unlocked_worlds:
				save.unlocked_worlds.append(save.world_id)
	write_save()
	return world_finished


func get_world_config(world_id: String) -> WorldConfig:
	for world: WorldConfig in worlds:
		if world and world.world_id == world_id:
			return world
	return null


func get_current_world() -> WorldConfig:
	return get_world_config(save.world_id)


## Position of a world in play order (0 = Ocean), for
## SkillDefinition.available_from_world.
func get_world_index(world_id: String) -> int:
	return maxi(world_ids.find(world_id), 0)


func is_world_unlocked(world_id: String) -> bool:
	return world_id in save.unlocked_worlds


## Every world before the current one is done; the current one is done only
## when all its stages are (the end of the last world).
func is_world_completed(world_id: String) -> bool:
	var index: int = world_ids.find(world_id)
	var current: int = world_ids.find(save.world_id)
	if index < current:
		return true
	if index == current:
		var world: WorldConfig = get_world_config(world_id)
		return world != null and save.stage_index >= world.get_stage_count()
	return false


func get_completed_world_count() -> int:
	var count: int = 0
	for world_id: String in world_ids:
		if is_world_completed(world_id):
			count += 1
	return count


## The story file for a world in the current language (English if missing).
## The story file for a story id in the current language (else English).
func get_story_path_for(id: String) -> String:
	var path: String = "%s/%s_%s.txt" % [story_folder, id, language]
	if not FileAccess.file_exists(path):
		path = "%s/%s_en.txt" % [story_folder, id]
	return path



# --- Screens ----------------------------------------------------------------

func go_to_title() -> void:
	_change_scene(title_scene)


func go_to_main_menu() -> void:
	_change_scene(main_menu_scene)


func go_to_game() -> void:
	started_from_menu = true
	_change_scene(game_scene)


func go_to_story() -> void:
	_change_scene(story_scene)


func go_to_journey() -> void:
	_change_scene(journey_scene)


# --- Players' devices ---------------------------------------------------------

## The device that pressed on the title screen becomes Player 1's (the Echo):
## gamepad_device = that gamepad, or -1 for the keyboard (Player 1 keeps the
## WASD keys and the first gamepad goes to Player 2). The gamepad events of
## each player's actions are moved to their device; the keys never change.
func assign_player_one(gamepad_device: int) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	var first: int
	var second: int
	if gamepad_device >= 0:
		first = gamepad_device
		second = _other_pad(pads, first)
	else:
		second = pads[0] if not pads.is_empty() else 0
		first = _other_pad(pads, second)
	player_gamepads = {1: first, 2: second}
	player_on_gamepad = {1: gamepad_device >= 0, 2: false}
	_bind_gamepad("p1_", first)
	_bind_gamepad("p2_", second)


func _other_pad(pads: Array[int], taken: int) -> int:
	for pad: int in pads:
		if pad != taken:
			return pad
	return 1 if taken == 0 else 0


func _bind_gamepad(prefix: String, device: int) -> void:
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with(prefix):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device != device:
				var moved: InputEvent = event.duplicate()
				moved.device = device
				InputMap.action_erase_event(action, event)
				InputMap.action_add_event(action, moved)


## Fades the screen to black (the old scene stays paused if it was), swaps the
## scene behind the black, then fades the new one in. A second request while
## one is under way is ignored (a double press).
func _change_scene(path: String) -> void:
	if _changing_scene:
		return
	_changing_scene = true
	await fader.fade_out()
	get_tree().paused = false
	# In case a hit-stop (SwordAbility) was still running.
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)
	_changing_scene = false
	_fade_in_new_scene()


## Waits until the new scene has drawn a couple of frames (its build hidden
## behind the black), then fades it in.
func _fade_in_new_scene() -> void:
	for i: int in 2:
		await get_tree().process_frame
	await fader.fade_in()


# --- Settings file ----------------------------------------------------------

func _fresh_save() -> SaveData:
	var fresh := SaveData.new()
	fresh.world_id = world_ids[0]
	fresh.unlocked_worlds = PackedStringArray([world_ids[0]])
	fresh.mode = preferred_mode
	fresh.skills = SkillLoadout.new(fresh.world_id)
	return fresh


## Settings saved before this version kept the brightness on the old scale
## Settings saved before this version kept the brightness on an older scale:
## per old version, the value that looks like today's 1 (the 3D play-tests
## twice chose the 70 % look as the new 100 %).
const SETTINGS_VERSION: int = 3
const OLD_BRIGHTNESS_BASES: Dictionary = {1: 0.49, 2: 0.7}


func _load_settings() -> void:
	if not FileAccess.file_exists(settings_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if not parsed is Dictionary:
		return
	var data := parsed as Dictionary
	var saved_language: String = str(data.get("language", language))
	if saved_language in UiText.LANGUAGES:
		language = saved_language
	preferred_mode = SaveData.Mode.CHALLENGE if str(data.get("mode", "calm")) == "challenge" else SaveData.Mode.CALM
	var saved_brightness: float = float(data.get("brightness", brightness))
	var saved_version: int = int(data.get("version", 1))
	if data.has("brightness") and OLD_BRIGHTNESS_BASES.has(saved_version):
		saved_brightness /= float(OLD_BRIGHTNESS_BASES[saved_version])
	brightness = clampf(saved_brightness, min_brightness, max_brightness)
	var saved_volumes: Variant = data.get("volumes", {})
	if saved_volumes is Dictionary:
		for bus: String in volume_buses:
			if (saved_volumes as Dictionary).has(bus):
				volumes[bus] = clampf(float(saved_volumes[bus]), 0.0, 1.0)


func _save_settings() -> void:
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		return
	var data: Dictionary = {
		"version": SETTINGS_VERSION,
		"language": language,
		"mode": "challenge" if preferred_mode == SaveData.Mode.CHALLENGE else "calm",
		"brightness": brightness,
		"volumes": volumes,
	}
	file.store_string(JSON.stringify(data, "\t"))
