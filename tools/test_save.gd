extends SceneTree
## Headless save/load test: writes a SaveData to a test file, reads it back,
## checks defaults for old/broken files, and walks the Game progress through a
## whole world (3 completed stages -> next world unlocked). Uses its own files
## in user://, so the real save is never touched.
##
## Run from the project folder:
##   godot --headless --path . -s res://tools/test_save.gd

const TEST_SAVE: String = "user://test_save.json"
const TEST_SETTINGS: String = "user://test_settings.json"
const WORLD_PATH: String = "res://worlds/ocean.tres"

var _failures: int = 0


func _initialize() -> void:
	_test_round_trip()
	_test_defaults_and_broken_files()
	_test_world_progress()
	for path: String in [TEST_SAVE, TEST_SETTINGS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT: %s" % ("SAVE/LOAD OK" if _failures == 0 else "%d CHECKS FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_round_trip() -> void:
	var save := SaveData.new()
	save.world_id = "caves"
	save.stage_index = 2
	save.unlocked_worlds = PackedStringArray(["ocean", "caves"])
	save.mode = SaveData.Mode.CHALLENGE
	save.skills = PackedStringArray(["lure_pulse"])
	_expect(save.write(TEST_SAVE) == OK, "write the save file")
	var loaded: SaveData = SaveData.read(TEST_SAVE)
	_expect(loaded != null, "read the save file back")
	if loaded == null:
		return
	_expect(loaded.world_id == "caves", "world survives the round trip")
	_expect(loaded.stage_index == 2, "stage survives the round trip")
	_expect(loaded.unlocked_worlds == PackedStringArray(["ocean", "caves"]), "unlocked worlds survive the round trip")
	_expect(loaded.mode == SaveData.Mode.CHALLENGE, "mode survives the round trip")
	_expect(loaded.skills == PackedStringArray(["lure_pulse"]), "skills survive the round trip")
	print("  file content: " + FileAccess.get_file_as_string(TEST_SAVE).replace("\n", " ").replace("\t", ""))


func _test_defaults_and_broken_files() -> void:
	var partial: SaveData = SaveData.from_dict({"world": "ocean"})
	_expect(partial.stage_index == 0 and partial.mode == SaveData.Mode.CALM and partial.skills.is_empty(), "missing fields get defaults")
	_expect("ocean" in partial.unlocked_worlds, "the current world is always unlocked")
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	_expect(SaveData.read(TEST_SAVE) == null, "a broken file reads as no save")
	_expect(SaveData.read("user://does_not_exist.json") == null, "a missing file reads as no save")


func _test_world_progress() -> void:
	var game := GameState.new()
	game.save_path = TEST_SAVE
	game.settings_path = TEST_SETTINGS
	var worlds: Array[WorldConfig] = [load(WORLD_PATH) as WorldConfig]
	game.worlds = worlds
	game.preferred_mode = SaveData.Mode.CALM
	game.save = game._fresh_save()
	_expect(game.get_current_world() != null, "the Ocean config is found by id")

	_expect(not game.complete_stage(), "stage 1 done: the world goes on")
	_expect(game.save.world_id == "ocean" and game.save.stage_index == 1, "saved at Ocean stage 2")
	_expect(not game.complete_stage(), "stage 2 done: the world goes on")
	_expect(game.complete_stage(), "stage 3 done: the world is finished")
	_expect(game.finished_world_id == "ocean", "story screen will be the Ocean's")
	_expect(game.save.world_id == "caves" and game.save.stage_index == 0, "moved to Caves stage 1")
	_expect(game.is_world_unlocked("caves") and not game.is_world_unlocked("forest"), "Caves unlocked, Forest still locked")
	_expect(game.is_world_completed("ocean") and not game.is_world_completed("caves"), "Ocean completed, Caves not")
	_expect(game.get_completed_world_count() == 1, "one star on the World Map")

	var loaded: SaveData = SaveData.read(TEST_SAVE)
	_expect(loaded != null and loaded.world_id == "caves" and "caves" in loaded.unlocked_worlds, "the progress was written to disk")
	game.toggle_mode()
	var after_toggle: SaveData = SaveData.read(TEST_SAVE)
	_expect(after_toggle != null and after_toggle.mode == SaveData.Mode.CHALLENGE, "changing the mode updates the save")

	game.set_brightness(1.4)
	game.brightness = game.default_brightness
	game._load_settings()
	_expect(is_equal_approx(game.brightness, 1.4), "the brightness setting is saved and loaded")
	game.set_brightness(99.0)
	_expect(is_equal_approx(game.brightness, game.max_brightness), "the brightness is clamped to its range")
	game.free()


func _expect(condition: bool, description: String) -> void:
	print("  %s %s" % ["ok  " if condition else "FAIL", description])
	if not condition:
		_failures += 1
