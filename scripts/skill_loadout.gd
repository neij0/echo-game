class_name SkillLoadout
extends RefCounted
## The skills each character owns in the current world: character ("echo" /
## "guardian") -> {skill id: rank}. Shared skills are owned separately by each
## character (each has their own copy). Saved in save.json (SaveData.skills) at
## the end of every stage, cleared when a new world starts. The StageManager
## keeps copies for retries (the skills owned at the start of that level).

const CHARACTERS: PackedStringArray = ["echo", "guardian"]

## World the skills belong to (they reset when it changes).
var world_id: String = ""
var _ranks: Dictionary = {}


func _init(for_world: String = "") -> void:
	world_id = for_world
	clear()


func clear() -> void:
	_ranks = {}
	for character: String in CHARACTERS:
		_ranks[character] = {}


func is_empty() -> bool:
	for character: String in CHARACTERS:
		if not (_ranks[character] as Dictionary).is_empty():
			return false
	return true


func get_rank(character: String, skill_id: String) -> int:
	return int((_ranks.get(character, {}) as Dictionary).get(skill_id, 0))


## Adds one rank (a new skill starts at rank 1), up to max_rank.
func add_rank(character: String, definition: SkillDefinition) -> void:
	if not _ranks.has(character):
		return
	var rank: int = mini(get_rank(character, definition.id) + 1, definition.max_rank)
	(_ranks[character] as Dictionary)[definition.id] = rank


func set_rank(character: String, skill_id: String, rank: int) -> void:
	if not _ranks.has(character):
		return
	if rank <= 0:
		(_ranks[character] as Dictionary).erase(skill_id)
	else:
		(_ranks[character] as Dictionary)[skill_id] = rank


## A copy of one character's {skill id: rank}.
func get_entries(character: String) -> Dictionary:
	return (_ranks.get(character, {}) as Dictionary).duplicate()


## True when the character already owns an active skill (one slot each).
func has_active(character: String, catalog: SkillCatalog) -> bool:
	for skill_id: String in get_entries(character):
		var definition: SkillDefinition = catalog.find(skill_id) if catalog else null
		if definition and definition.is_active():
			return true
	return false


func copy() -> SkillLoadout:
	var result := SkillLoadout.new(world_id)
	for character: String in CHARACTERS:
		result._ranks[character] = get_entries(character)
	return result


func to_dict() -> Dictionary:
	var data: Dictionary = {"world": world_id}
	for character: String in CHARACTERS:
		data[character] = get_entries(character)
	return data


static func from_dict(data: Dictionary) -> SkillLoadout:
	var result := SkillLoadout.new(str(data.get("world", "")))
	for character: String in CHARACTERS:
		var entries: Variant = data.get(character, {})
		if not entries is Dictionary:
			continue
		for skill_id: Variant in entries as Dictionary:
			result.set_rank(character, str(skill_id), int((entries as Dictionary)[skill_id]))
	return result
