class_name ConfirmPanel
extends VBoxContainer
## A yes / no question in the "silhouette + glow" style, shown in place of a
## menu's button column (main menu: New Game over a save; pause menu: Restart,
## Quit): the question, an optional warning (WarningLabel) under a glowing wave
## line, then the No and Yes buttons (GlowButton). No takes the focus first, so
## a stray press never loses progress; ui_cancel answers No. Texts follow the
## parent's direction (Arabic: right-to-left). Works while the game is paused.

signal confirmed
signal cancelled

@export var width: float = 420.0
@export var spacing: int = 10
@export var question_font_size: int = 26
@export var rule_size: Vector2 = Vector2(160.0, 22.0)
## Left / right: where the texts and buttons line up (mirrored in Arabic).
@export var alignment_side: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
## Room before the texts, so they line up with the buttons' text (the theme's
## button margin; 0 when centred).
@export var text_indent: int = 34

var question_label: Label
var warning_label: Label
var yes_button: GlowButton
var no_button: GlowButton
var _rule: WaveRule
var _indented: Array[MarginContainer] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	add_theme_constant_override("separation", spacing)
	question_label = _label(&"Label")
	question_label.add_theme_font_size_override("font_size", question_font_size)
	_rule = WaveRule.new()
	_rule.custom_minimum_size = rule_size
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if alignment_side == HORIZONTAL_ALIGNMENT_CENTER \
		else Control.SIZE_SHRINK_BEGIN
	_indent(_rule)
	warning_label = _label(&"WarningLabel")
	no_button = _button(cancelled.emit)
	yes_button = _button(confirmed.emit)
	refresh()


## Sets the texts and takes the focus (on No).
func ask(question: String, warning: String = "") -> void:
	question_label.text = question
	warning_label.text = warning
	warning_label.visible = warning != ""
	refresh()
	no_button.focus_quietly()


func refresh() -> void:
	var game: Node = get_node_or_null("/root/Game")
	if game:
		yes_button.text = String(game.call("text", "yes"))
		no_button.text = String(game.call("text", "no"))
	var rtl: bool = is_layout_rtl()
	var indent: int = 0 if alignment_side == HORIZONTAL_ALIGNMENT_CENTER else text_indent
	for container: MarginContainer in _indented:
		container.add_theme_constant_override("margin_left", 0 if rtl else indent)
		container.add_theme_constant_override("margin_right", indent if rtl else 0)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		cancelled.emit()


func _label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = alignment_side
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width - text_indent
	_indent(label)
	return label


func _indent(control: Control) -> void:
	var container := MarginContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.add_child(control)
	_indented.append(container)


func _button(on_pressed: Callable) -> GlowButton:
	var button := GlowButton.new()
	button.alignment = alignment_side
	button.custom_minimum_size.x = width
	button.pressed.connect(on_pressed)
	add_child(button)
	return button
