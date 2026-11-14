class_name InputPrompt
extends HBoxContainer
## A row of button prompts: for each entry its drawn glyphs (InputGlyph) and a
## short label, e.g. "[W][S] choose   [Space] pick" or "(L↕) choose   (A) pick".
## It follows the device in use (InputDevices) and changes the moment it
## changes, without the screen being opened again:
## - menu prompts (setup with any_device): the device last used in any way,
##   and on a gamepad that pad's kind (Xbox letters / PlayStation symbols);
## - a player's prompts (setup_for_player): only that player's own device
##   (their keys or their own gamepad), so two players each see their own.
## On a gamepad the stick / D-pad parts of one entry merge into one glyph (up +
## down = one stick with both arrows). Mirrors in Arabic like any HBoxContainer.

enum Follow { MENU, PLAYER, FIXED }

## Space between two entries.
@export var entry_gap: int = 28
## Space between the glyphs of one entry and its label.
@export var glyph_gap: int = 5

var follow: Follow = Follow.MENU
## The player followed (Follow.PLAYER).
var player_number: int = 1
## What is shown right now.
var device: InputGlyph.Device = InputGlyph.Device.KEYBOARD
var style: InputDevices.PadStyle = InputDevices.PadStyle.XBOX
## [{"actions": Array[StringName], "text": String}]
var _entries: Array[Dictionary] = []
var _shown: String = ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## entries: [{"actions": [&"ui_up", &"ui_down"], "text": "choose"}, ...].
## any_device: follow the menus' device (true), else stay on start_device.
func setup(entries: Array[Dictionary], start_device: InputGlyph.Device, any_device: bool = false) -> void:
	follow = Follow.MENU if any_device else Follow.FIXED
	device = start_device
	_set_entries(entries)


## Follows one player's own device (their keys or their own gamepad).
func setup_for_player(entries: Array[Dictionary], number: int) -> void:
	follow = Follow.PLAYER
	player_number = number
	_set_entries(entries)


func _set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries
	_shown = ""
	_update()


func _process(_delta: float) -> void:
	_update()


## Rebuilds when the followed device or pad kind changed.
func _update() -> void:
	match follow:
		Follow.MENU:
			device = InputDevices.menu_device
			style = InputDevices.menu_style()
		Follow.PLAYER:
			device = InputDevices.player_device.get(player_number, InputGlyph.Device.KEYBOARD)
			style = InputDevices.player_style(player_number)
	var key: String = "%d:%d" % [device, style if device == InputGlyph.Device.GAMEPAD else 0]
	if key == _shown:
		return
	_shown = key
	_rebuild()


## The pad whose names are shown (PS5 "Create" or PS4 "Share" for Back).
func _pad() -> int:
	return InputDevices.player_pad(player_number) if follow == Follow.PLAYER else InputDevices.menu_pad


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", entry_gap)
	for entry: Dictionary in _entries:
		var group := HBoxContainer.new()
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_theme_constant_override("separation", glyph_gap)
		for spec: Dictionary in _specs(entry.get("actions", [])):
			var glyph := InputGlyph.new()
			glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			group.add_child(glyph)
			glyph.setup(spec)
		var label := Label.new()
		label.theme_type_variation = &"PromptLabel"
		label.text = entry.get("text", "")
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.visible = label.text != ""
		group.add_child(label)
		add_child(group)


## The glyphs shown right now (tests): one spec per glyph.
func get_shown_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append_array(_specs(entry.get("actions", [])))
	return result


## The glyphs of one entry on the current device; on a gamepad the D-pad and
## stick parts of the same stick / pad merge into one glyph.
func _specs(actions: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var newer: bool = InputDevices.is_newer_playstation(_pad())
	for action: StringName in actions:
		var spec: Dictionary = InputGlyph.spec_for(action, device, style, newer)
		if spec.is_empty():
			continue
		var merged: bool = false
		if spec.shape in [InputGlyph.Shape.DPAD, InputGlyph.Shape.STICK]:
			for existing: Dictionary in result:
				if existing.shape == spec.shape and existing.get("label", "") == spec.get("label", ""):
					for direction: Vector2 in spec.get("directions", []):
						if not (existing.directions as Array).has(direction):
							(existing.directions as Array).append(direction)
					merged = true
					break
		if not merged:
			spec["directions"] = (spec.get("directions", []) as Array).duplicate()
			result.append(spec)
	return result
