class_name GameState
extends Node
## Autoload "Game" (scenes/game_state.tscn): the progress (SaveData), the
## settings (language, preferred mode, brightness, the volume of each audio
## bus) and the moves between screens:
## main menu -> stage (game.tscn) -> ... -> story screen -> World Map.
## Structure: World (5) -> Stage (3 per world) -> Level (3 per stage).

signal language_changed

## Every world in play order (save file, World Map, story file names).
@export var world_ids: PackedStringArray = PackedStringArray(["ocean", "caves", "forest", "desert", "snow"])
## The WorldConfig of each world that exists so far. A world id without a
## config shows "coming soon" on the World Map.
@export var worlds: Array[WorldConfig] = []

@export_group("Scenes")
@export_file("*.tscn") var main_menu_scene: String = "res://scenes/main_menu.tscn"
@export_file("*.tscn") var game_scene: String = "res://scenes/game.tscn"
@export_file("*.tscn") var story_scene: String = "res://scenes/story_screen.tscn"
@export_file("*.tscn") var world_map_scene: String = "res://scenes/world_map.tscn"

@export_group("Files")
@export var save_path: String = "user://save.json"
@export var settings_path: String = "user://settings.json"
## Story text files: <story_folder>/<world id>_end_<language>.txt
@export var story_folder: String = "res://story"

@export_group("Defaults")
## "en" or "ar".
@export var default_language: String = "en"
@export var default_mode: SaveData.Mode = SaveData.Mode.CALM

@export_group("Brightness")
## Brightness setting: scales the ambient darkness and the players' lights a
## little (never the pulse or any other gameplay reveal). The range is kept
## narrow so even the maximum cannot make the far level readable. 1 = as designed.
@export var default_brightness: float = 1.0
@export var min_brightness: float = 0.7
@export var max_brightness: float = 1.3

@export_group("Volume")
## The audio buses with an Options slider (default_bus_layout.tres), and their
## default volume (0-1, linear).
@export var volume_buses: PackedStringArray = PackedStringArray(["Master", "Music", "SFX", "Ambience", "UI"])
@export_range(0.0, 1.0) var default_volume: float = 0.8

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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


func new_game() -> void:
	save = _fresh_save()
	write_save()
	play_current()


func continue_game() -> void:
	var loaded: SaveData = SaveData.read(save_path)
	if loaded:
		save = loaded
	play_current()


## Starts the saved stage, or opens the World Map if that world has no
## content yet (or the whole game is finished).
func play_current() -> void:
	var world: WorldConfig = get_current_world()
	if world and save.stage_index < world.get_stage_count():
		go_to_game()
	else:
		go_to_world_map()


## Called by the StageManager when a stage's boss is beaten. Moves the save to
## the next stage (or the next world) and writes it. Returns true when that was
## the world's last stage.
func complete_stage() -> bool:
	var world: WorldConfig = get_current_world()
	finished_world_id = ""
	save.stage_index += 1
	var world_finished: bool = world == null or save.stage_index >= world.get_stage_count()
	if world_finished:
		finished_world_id = save.world_id
		var next: int = world_ids.find(save.world_id) + 1
		if next < world_ids.size():
			save.world_id = world_ids[next]
			save.stage_index = 0
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
func get_story_path(world_id: String) -> String:
	var path: String = "%s/%s_end_%s.txt" % [story_folder, world_id, language]
	if not FileAccess.file_exists(path):
		path = "%s/%s_end_en.txt" % [story_folder, world_id]
	return path


# --- Screens ----------------------------------------------------------------

func go_to_main_menu() -> void:
	_change_scene(main_menu_scene)


func go_to_game() -> void:
	started_from_menu = true
	_change_scene(game_scene)


func go_to_story() -> void:
	_change_scene(story_scene)


func go_to_world_map() -> void:
	_change_scene(world_map_scene)


func _change_scene(path: String) -> void:
	get_tree().paused = false
	# In case a hit-stop (SwordAbility) was still running.
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(path)


# --- Settings file ----------------------------------------------------------

func _fresh_save() -> SaveData:
	var fresh := SaveData.new()
	fresh.world_id = world_ids[0]
	fresh.unlocked_worlds = PackedStringArray([world_ids[0]])
	fresh.mode = preferred_mode
	return fresh


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
	brightness = clampf(float(data.get("brightness", brightness)), min_brightness, max_brightness)
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
		"language": language,
		"mode": "challenge" if preferred_mode == SaveData.Mode.CHALLENGE else "calm",
		"brightness": brightness,
		"volumes": volumes,
	}
	file.store_string(JSON.stringify(data, "\t"))
