@tool
extends EditorScript
## Editor tool: proposes a new random LevelDefinition from the world's chunk
## pools (LevelGenerator), checks it with the same BFS as the game, and saves it
## as a new .tres you can open, tweak and add to a StageDefinition in the
## world's .tres.
##
## How to use: open this script in the Godot Script editor, change the
## settings below if needed, then File > Run (Ctrl+Shift+X). The new file's
## path is printed in the Output panel.

## World whose chunk pools are used.
const WORLD_PATH: String = "res://worlds/ocean.tres"
## Spawns (creatures, corals, stations, boss health) are copied from this
## level. "" = LevelDefinition defaults.
const TEMPLATE_PATH: String = "res://worlds/ocean/level_2_1.tres"
const OUTPUT_FOLDER: String = "res://worlds/ocean"
const MIDDLE_CHUNKS_MIN: int = 5
const MIDDLE_CHUNKS_MAX: int = 7
## true = end in a boss arena with BOSS_SCENE.
const BOSS_LEVEL: bool = false
const BOSS_SCENE: String = "res://scenes/boss_placeholder.tscn"
## -1 = random. Any other value = the same proposal every time.
const PROPOSAL_SEED: int = -1
## Proposals tried before giving up.
const MAX_TRIES: int = 50


func _run() -> void:
	var world := load(WORLD_PATH) as WorldConfig
	var generator := LevelGenerator.new()
	generator.middle_min = MIDDLE_CHUNKS_MIN
	generator.middle_max = MIDDLE_CHUNKS_MAX
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
	print("propose_level: saved %s (%d chunks, %d pockets)" % [path, definition.chunks.size(), definition.pockets.size()])
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource(load(path))
