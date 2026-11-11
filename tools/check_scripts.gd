extends Node
## Loads every GDScript in the project and lists the ones that do not parse,
## so the editor's Output stays clean (and, during the 3D conversion, so it is
## clear which scripts are still unported). Folders with a .gdignore are
## skipped, like the editor does. Run as a scene (the Game autoload must
## exist, many scripts use it):
## godot --headless --path . res://tools/check_scripts.tscn
## Exits with 1 when a script fails.

## Folders not checked (besides any folder with a .gdignore).
@export var skip_folders: PackedStringArray = PackedStringArray(["res://.godot", "res://addons"])


func _ready() -> void:
	var scripts: PackedStringArray = PackedStringArray()
	_collect("res://", scripts)
	var failed: PackedStringArray = PackedStringArray()
	for path: String in scripts:
		var script := ResourceLoader.load(path, "GDScript") as GDScript
		if script == null or not script.can_instantiate():
			failed.append(path)
	print("")
	print("CHECK SCRIPTS: %d scripts, %d fail to parse" % [scripts.size(), failed.size()])
	for path: String in failed:
		print("  FAIL ", path)
	print("RESULT: ", "SCRIPTS OK" if failed.is_empty() else "SCRIPTS FAIL")
	get_tree().quit(0 if failed.is_empty() else 1)


func _collect(folder: String, into: PackedStringArray) -> void:
	if folder in skip_folders or FileAccess.file_exists(folder.path_join(".gdignore")):
		return
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if file_name.get_extension() == "gd":
			into.append(folder.path_join(file_name))
	for sub: String in dir.get_directories():
		_collect(folder.path_join(sub), into)
