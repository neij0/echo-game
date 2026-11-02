class_name InputPrompt
extends HBoxContainer
## A row of button prompts: for each entry its drawn glyphs (InputGlyph) and a
## short label, e.g. "[W][S] choose   [Space] pick" or "(L↕) choose   (A) pick".
## It follows the device in use: a player's own (their keys or their own
## gamepad: any event of the entries' actions) or, for the menus (follow_any),
## whatever was used last; menu_device keeps that between screens. On a gamepad
## the stick / D-pad parts of one entry merge into one glyph (up + down = one
## stick with both arrows). Mirrors in Arabic like any HBoxContainer.

## The device the menus' prompts show (the last one used in a menu).
static var menu_device: InputGlyph.Device = InputGlyph.Device.KEYBOARD

## Space between two entries.
@export var entry_gap: int = 28
## Space between the glyphs of one entry and its label.
@export var glyph_gap: int = 5
## A stick moved further than this counts as using the gamepad.
@export var axis_threshold: float = 0.5

var device: InputGlyph.Device = InputGlyph.Device.KEYBOARD
var follow_any: bool = false
## [{"actions": Array[StringName], "text": String}]
var _entries: Array[Dictionary] = []
var _actions: Array[StringName] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## entries: [{"actions": [&"p1_move_up", &"p1_move_down"], "text": "choose"}, ...].
## any_device: follow whatever device is used (menus), starting at menu_device.
func setup(entries: Array[Dictionary], start_device: InputGlyph.Device, any_device: bool = false) -> void:
	_entries = entries
	follow_any = any_device
	device = menu_device if any_device else start_device
	_actions.clear()
	for entry: Dictionary in entries:
		for action: StringName in entry.get("actions", []):
			_actions.append(action)
	_rebuild()


func set_device(value: InputGlyph.Device) -> void:
	if follow_any:
		menu_device = value
	if value != device:
		device = value
		_rebuild()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _entries.is_empty():
		return
	var used: int = _device_of(event)
	if used < 0:
		return
	if follow_any or _is_own(event):
		set_device(used as InputGlyph.Device)


## The device an event comes from, or -1 if it does not count (a release, a
## stick barely moved, the mouse).
func _device_of(event: InputEvent) -> int:
	if event is InputEventKey:
		return InputGlyph.Device.KEYBOARD if (event as InputEventKey).pressed else -1
	if event is InputEventJoypadButton:
		return InputGlyph.Device.GAMEPAD if (event as InputEventJoypadButton).pressed else -1
	if event is InputEventJoypadMotion:
		return InputGlyph.Device.GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) >= axis_threshold else -1
	return -1


func _is_own(event: InputEvent) -> bool:
	for action: StringName in _actions:
		if InputMap.has_action(action) and event.is_action(action):
			return true
	return false


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
		group.add_child(label)
		add_child(group)


## The glyphs of one entry on the current device; on a gamepad the D-pad and
## stick parts of the same stick / pad merge into one glyph.
func _specs(actions: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: StringName in actions:
		var spec: Dictionary = InputGlyph.spec_for(action, device)
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
