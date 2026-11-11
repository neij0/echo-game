@tool
extends EditorScript
## Editor tool: proposes a new random room-grid LevelDefinition from the
## world's room pool (LevelGenerator), checks it with the same BFS as the game,
## and saves it as a new .tres you can open, tweak and add to a
## StageDefinition in the world's .tres.
##
## How to use: open this script in the Godot Script editor, change the
## settings below if needed, then File > Run (Ctrl+Shift+X). The new file's
## path and its room map are printed in the Output panel.

## World whose room pool is used.
const WORLD_PATH: String = "res://worlds/ocean.tres"
## Spawns (creatures, corals, stations, shards, boss health) are copied from
## this level. "" = LevelDefinition defaults.
const TEMPLATE_PATH: String = "res://worlds/ocean/level_2_1.tres"
const OUTPUT_FOLDER: String = "res://worlds/ocean"
const GRID_SIZE: Vector2i = Vector2i(4, 4)
const ROOM_COUNT_MIN: int = 8
const ROOM_COUNT_MAX: int = 11
## Extra links on top of the tree (each one makes a loop).
const EXTRA_LINKS: int = 1
## true = the exit is a boss arena with BOSS_SCENE.
const BOSS_LEVEL: bool = false
const BOSS_SCENE: String = "res://scenes/boss_placeholder.tscn"
## -1 = random. Any other value = the same proposal every time.
const PROPOSAL_SEED: int = -1
## Proposals tried before giving up.
const MAX_TRIES: int = 50


func _run() -> void:
	var world := load(WORLD_PATH) as WorldConfig
	var generator := LevelGenerator.new()
	generator.grid_size = GRID_SIZE
	generator.room_count_min = ROOM_COUNT_MIN
	generator.room_count_max = ROOM_COUNT_MAX
	generator.extra_links = EXTRA_LINKS
	if TEMPLATE_PATH != "":
		generator.template = load(TEMPLATE_PATH) as LevelDefinition
	if BOSS_LEVEL:
		generator.boss_scene = load(BOSS_SCENE) as PackedScene

	var builder := LevelBuilder.new()
	builder.world = world
	var base_seed: int = PROPOSAL_SEED if PROPOSAL_SEED >= 0 else randi() % 1000000
	var definition: LevelDefinition = generator.propose_valid(world, base_seed, MAX_TRIES, builder)
	builder.free()
	if definition == null:
		push_error("propose_level: no valid level in %d tries (seed %d)" % [MAX_TRIES, base_seed])
		return

	var path: String = "%s/proposed_%d.tres" % [OUTPUT_FOLDER, base_seed]
	var error: Error = ResourceSaver.save(definition, path)
	if error != OK:
		push_error("propose_level: could not save %s (%s)" % [path, error_string(error)])
		return
	print("propose_level: saved %s (%d rooms, start %s, exit %s, lockdown %s)" % [
		path, definition.rooms.size(), definition.start_cell, definition.exit_cell, definition.lockdown_cell])
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource(load(path))
