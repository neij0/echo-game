class_name SaveData
extends RefCounted
## The player's progress, written as a small JSON file in user:// after every
## completed stage (and when a new game starts or the mode changes).
## Worlds are stored by id ("ocean", "caves"...), see the Game autoload.

enum Mode { CALM, CHALLENGE }

## Bump when the format changes, so old files can be upgraded in from_dict.
const VERSION: int = 1

## World the players are in (or will start next).
var world_id: String = "ocean"
## Stage of that world to play next (0-based).
var stage_index: int = 0
var unlocked_worlds: PackedStringArray = PackedStringArray(["ocean"])
## Calm: both downed = restart the current level (and a bit more oxygen).
## Challenge: both downed = restart the current stage from level 1.
var mode: Mode = Mode.CALM
## Skills picked between levels (empty until the skill choice screen exists).
var skills: PackedStringArray = PackedStringArray()


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"world": world_id,
		"stage": stage_index,
		"unlocked_worlds": Array(unlocked_worlds),
		"mode": "challenge" if mode == Mode.CHALLENGE else "calm",
		"skills": Array(skills),
	}


static func from_dict(data: Dictionary) -> SaveData:
	var save := SaveData.new()
	save.world_id = str(data.get("world", save.world_id))
	save.stage_index = int(data.get("stage", 0))
	save.unlocked_worlds = _strings(data.get("unlocked_worlds", []))
	if not save.world_id in save.unlocked_worlds:
		save.unlocked_worlds.append(save.world_id)
	save.mode = Mode.CHALLENGE if str(data.get("mode", "calm")) == "challenge" else Mode.CALM
	save.skills = _strings(data.get("skills", []))
	return save


func write(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


## The save at path, or null if there is none or it cannot be read.
static func read(path: String) -> SaveData:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("SaveData: %s is not a valid save file" % path)
		return null
	return from_dict(parsed as Dictionary)


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func _strings(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is Array:
		for item: Variant in value as Array:
			result.append(str(item))
	return result
