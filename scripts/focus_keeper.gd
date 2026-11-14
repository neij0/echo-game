class_name FocusKeeper
extends Node
## Makes sure a menu screen always has a focused control, so a gamepad or the
## keyboard can never get stuck with nothing selected (a mouse click on empty
## space, a page that was hidden, a button that was disabled...). Lives in the
## Game autoload. Every screen that has controls joins the "focus_screens"
## group and answers get_default_focus(): the control to focus while it is
## active (the focused page's first button, No in a question...), or null
## while it is not (closed, hidden, nothing to choose yet). Whenever the
## viewport has no focus owner, or it is hidden or disabled, the first
## screen's default takes the focus again (quietly: no focus ping).

const GROUP: StringName = &"focus_screens"

## Focus restored (tests).
var restores: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var owner_control: Control = get_viewport().gui_get_focus_owner()
	if owner_control and _usable(owner_control):
		return
	var target: Control = default_focus(get_tree())
	if target == null or target == owner_control:
		return
	restores += 1
	if target is GlowButton:
		(target as GlowButton).focus_quietly()
	else:
		target.grab_focus()


## The control the active screen wants focused (null if no screen is active).
static func default_focus(tree: SceneTree) -> Control:
	for node: Node in tree.get_nodes_in_group(GROUP):
		if not node.has_method("get_default_focus"):
			continue
		var control := node.call("get_default_focus") as Control
		if control and _usable(control):
			return control
	return null


static func _usable(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return false
	var button := control as BaseButton
	return button == null or not button.disabled
