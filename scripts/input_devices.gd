class_name InputDevices
extends Node
## Which input device is in use, for the button prompts and the menus. Lives
## in the Game autoload (created by GameState) and sees every event before any
## screen can consume it (the root window's window_input signal).
## - The menus' device (menu_device): the last one used. Any key, a mouse click
##   or the mouse moved more than mouse_switch_distance = the keyboard; any
##   gamepad button, or a stick / trigger beyond axis_deadzone = a gamepad
##   (that pad, menu_pad). The deadzone keeps stick drift from flipping it.
## - Each player's device (player_device): the same rules, but only their own
##   input: their keys (the actions starting with "p1_" / "p2_") or their own
##   gamepad (the device their gamepad actions are bound to).
## - The kind of gamepad (pad_style): PlayStation glyphs (Cross, Circle,
##   Square, Triangle) for a Sony pad (by name or vendor), Xbox glyphs
##   otherwise.
## - Menu navigation with the left stick: the stick is not bound to ui_up /
##   ui_down / ui_left / ui_right (an analog stick sends an event on every
##   tiny change, which moved the focus many times); instead a stick pushed
##   past stick_press (and back under stick_release) sends one ui_* action,
##   repeated while held (first after repeat_delay, then every
##   repeat_interval), only while a control has the focus. A held D-pad
##   repeats the same way. setup_menu_actions() adds A / Cross to ui_accept
##   and B / Circle to ui_cancel (Godot's defaults have no gamepad there).
## Everything readable is static, so scripts that run without the autoload
## still work (they see the defaults). Prompts poll revision to update.

enum PadStyle { XBOX, PLAYSTATION }

## Words in a gamepad's name that mean a PlayStation pad (lower case).
const PLAYSTATION_NAMES: Array[String] = ["playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense", "sony"]
## Names a PlayStation pad reports on some systems (the whole name, lower case).
const PLAYSTATION_EXACT_NAMES: Array[String] = ["wireless controller"]
## Sony's USB vendor id (0x054C).
const SONY_VENDOR_ID: int = 1356
const DIRECTIONS: Dictionary = {
	&"ui_up": Vector2.UP, &"ui_down": Vector2.DOWN, &"ui_left": Vector2.LEFT, &"ui_right": Vector2.RIGHT,
}
const DPAD_ACTIONS: Dictionary = {
	JOY_BUTTON_DPAD_UP: &"ui_up", JOY_BUTTON_DPAD_DOWN: &"ui_down",
	JOY_BUTTON_DPAD_LEFT: &"ui_left", JOY_BUTTON_DPAD_RIGHT: &"ui_right",
}

## The menus' device and, on a gamepad, which pad (its style).
static var menu_device: InputGlyph.Device = InputGlyph.Device.KEYBOARD
static var menu_pad: int = 0
## Player number -> InputGlyph.Device.
static var player_device: Dictionary = {1: InputGlyph.Device.KEYBOARD, 2: InputGlyph.Device.KEYBOARD}
## Goes up on every change (prompts compare it to rebuild).
static var revision: int = 0
## Tests: gamepad device -> the name it pretends to have.
static var name_overrides: Dictionary = {}

## A stick or trigger moved further than this counts as using the gamepad.
@export var axis_deadzone: float = 0.5
## The mouse must move this far (pixels, added up) to count as the keyboard.
@export var mouse_switch_distance: float = 16.0
## Left stick menu navigation: pushed past stick_press = one step; it must
## come back under stick_release before the next (no flicker).
@export var stick_press: float = 0.6
@export var stick_release: float = 0.35
## Held stick / D-pad: first repeat after repeat_delay, then every repeat_interval.
@export var repeat_delay: float = 0.42
@export var repeat_interval: float = 0.12

var _mouse_travel: float = 0.0
## "device:action" -> seconds until the next repeat (held stick / D-pad).
var _held: Dictionary = {}
## "device:dpad:action" of the D-pad buttons held right now.
var _held_dpad: Dictionary = {}
## Navigation actions sent (tests).
var steps_sent: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_menu_actions()
	get_tree().root.window_input.connect(note)


## Gamepad buttons on the menu actions; the stick off them (see the header).
static func setup_menu_actions() -> void:
	_add_button(&"ui_accept", JOY_BUTTON_A)
	_add_button(&"ui_cancel", JOY_BUTTON_B)
	for action: StringName in DIRECTIONS:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)


static func _add_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	InputMap.action_add_event(action, event)


## Every event, before the scene sees it.
func note(event: InputEvent) -> void:
	var used: int = _device_of(event)
	if event is InputEventJoypadButton:
		_note_dpad(event as InputEventJoypadButton)
	if used < 0:
		return
	var pad: int = event.device if used == InputGlyph.Device.GAMEPAD else menu_pad
	if used == InputGlyph.Device.GAMEPAD:
		_mouse_travel = 0.0
	set_menu_device(used as InputGlyph.Device, pad)
	if event is InputEventMouse:
		return
	for number: int in player_device:
		if _belongs_to(event, number):
			set_player_device(number, used as InputGlyph.Device)


## The device an event counts for, or -1 (a release, a small stick move, a
## little mouse movement, an action sent by code).
func _device_of(event: InputEvent) -> int:
	if event is InputEventKey:
		return InputGlyph.Device.KEYBOARD if (event as InputEventKey).pressed and not event.is_echo() else -1
	if event is InputEventMouseButton:
		return InputGlyph.Device.KEYBOARD if (event as InputEventMouseButton).pressed else -1
	if event is InputEventMouseMotion:
		_mouse_travel += (event as InputEventMouseMotion).relative.length()
		if _mouse_travel >= mouse_switch_distance:
			_mouse_travel = 0.0
			return InputGlyph.Device.KEYBOARD
		return -1
	if event is InputEventJoypadButton:
		return InputGlyph.Device.GAMEPAD if (event as InputEventJoypadButton).pressed else -1
	if event is InputEventJoypadMotion:
		return InputGlyph.Device.GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) >= axis_deadzone else -1
	return -1


static func set_menu_device(device: InputGlyph.Device, pad: int = menu_pad) -> void:
	if device == menu_device and (device == InputGlyph.Device.KEYBOARD or pad == menu_pad):
		return
	menu_device = device
	if device == InputGlyph.Device.GAMEPAD:
		menu_pad = pad
	revision += 1


static func set_player_device(number: int, device: InputGlyph.Device) -> void:
	if player_device.get(number, -1) == device:
		return
	player_device[number] = device
	revision += 1


## True if the event is this player's own: one of their keys, or their gamepad.
static func _belongs_to(event: InputEvent, number: int) -> bool:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device == player_pad(number)
	if event is InputEventKey:
		var prefix: String = "p%d_" % number
		for action: StringName in InputMap.get_actions():
			if String(action).begins_with(prefix) and event.is_action(action, true):
				return true
	return false


## The gamepad a player's actions are bound to (Game.assign_player_one moves them).
static func player_pad(number: int) -> int:
	var action: StringName = StringName("p%d_move_left" % number)
	if InputMap.has_action(action):
		for event: InputEvent in InputMap.action_get_events(action):
			if (event is InputEventJoypadMotion or event is InputEventJoypadButton) and event.device >= 0:
				return event.device
	return number - 1


static func menu_style() -> PadStyle:
	return pad_style(menu_pad)


static func player_style(number: int) -> PadStyle:
	return pad_style(player_pad(number))


## PlayStation or Xbox, from the pad's name (or Sony's vendor id).
static func pad_style(device: int) -> PadStyle:
	var name: String = String(name_overrides[device]) if name_overrides.has(device) else Input.get_joy_name(device)
	var vendor: int = int(Input.get_joy_info(device).get("vendor_id", 0)) if not name_overrides.has(device) else 0
	return style_for(name, vendor)


static func style_for(pad_name: String, vendor_id: int = 0) -> PadStyle:
	var lower: String = pad_name.to_lower().strip_edges()
	if lower.contains("xbox") or lower.contains("xinput"):
		return PadStyle.XBOX
	if vendor_id == SONY_VENDOR_ID or lower in PLAYSTATION_EXACT_NAMES:
		return PadStyle.PLAYSTATION
	for word: String in PLAYSTATION_NAMES:
		if lower.contains(word):
			return PadStyle.PLAYSTATION
	return PadStyle.XBOX


## PS5 pads call Back "Create", older ones "Share".
static func is_newer_playstation(device: int) -> bool:
	var name: String = String(name_overrides[device]) if name_overrides.has(device) else Input.get_joy_name(device)
	var lower: String = name.to_lower()
	return lower.contains("ps5") or lower.contains("dualsense")


# --- Menu navigation with the stick, repeats while held ---------------------------

func _process(delta: float) -> void:
	var focused: bool = get_viewport().gui_get_focus_owner() != null
	for device: int in _pads():
		for action: StringName in DIRECTIONS:
			var key: String = "%d:%s" % [device, action]
			var stick: float = _stick_toward(device, DIRECTIONS[action])
			var dpad: bool = _dpad_held(device, action)
			if not _held.has(key):
				if stick >= stick_press:
					_held[key] = repeat_delay
					if focused:
						_send(action)
				elif dpad:
					# The D-pad's first step comes from the InputMap itself.
					_held[key] = repeat_delay
				continue
			if stick < stick_release and not dpad:
				_held.erase(key)
				continue
			_held[key] = float(_held[key]) - delta
			if float(_held[key]) <= 0.0:
				_held[key] = repeat_interval
				if focused:
					_send(action)


func _note_dpad(event: InputEventJoypadButton) -> void:
	if not DPAD_ACTIONS.has(event.button_index):
		return
	var key: String = "%d:dpad:%s" % [event.device, DPAD_ACTIONS[event.button_index]]
	if event.pressed:
		_held_dpad[key] = true
	else:
		_held_dpad.erase(key)



func _dpad_held(device: int, action: StringName) -> bool:
	return _held_dpad.has("%d:dpad:%s" % [device, action])


func _stick_toward(device: int, direction: Vector2) -> float:
	var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	return stick.dot(direction)


## Pads to watch: the connected ones and any that sent an event (tests).
func _pads() -> Array[int]:
	var pads: Array[int] = []
	pads.assign(Input.get_connected_joypads())
	for device: int in [0, 1, 2, 3]:
		if not device in pads and (absf(Input.get_joy_axis(device, JOY_AXIS_LEFT_X)) > 0.0 or absf(Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)) > 0.0):
			pads.append(device)
	# Also every pad still marked as held, so a released one is cleared.
	for key: String in _held_dpad.keys() + _held.keys():
		var device: int = int(key.get_slice(":", 0))
		if not device in pads:
			pads.append(device)
	return pads


## One navigation step, as if the action's key was pressed and released.
func _send(action: StringName) -> void:
	steps_sent += 1
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_tree().root.push_input(event)
