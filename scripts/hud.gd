class_name Hud
extends CanvasLayer
## Awareness bar, a debug label, and one PlayerStatus (depth + oxygen) per
## registered player. Never holds a single fixed player.

@export var run_manager: RunManager
@export var awareness: DepthAwareness
@export var level: DescentLevel

@export_group("Awareness Bar")
@export var calm_color: Color = Color(0.2, 0.55, 1.0)
@export var warning_color: Color = Color(1.0, 0.15, 0.15)
@export var background_color: Color = Color(0.1, 0.12, 0.18, 0.85)

@onready var _bar: ProgressBar = $AwarenessBar
@onready var _debug_label: Label = $DebugLabel
@onready var _statuses: VBoxContainer = $PlayerStatuses

var _fill_style: StyleBoxFlat


func _ready() -> void:
	_bar.max_value = awareness.max_value

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = calm_color
	_bar.add_theme_stylebox_override("fill", _fill_style)

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = background_color
	_bar.add_theme_stylebox_override("background", background_style)

	if run_manager:
		run_manager.player_registered.connect(_on_player_registered)


func _on_player_registered(player: Player) -> void:
	var status := PlayerStatus.new()
	status.setup(player, level)
	_statuses.add_child(status)


func _process(_delta: float) -> void:
	_bar.value = awareness.value
	_fill_style.bg_color = calm_color.lerp(warning_color, awareness.get_ratio())

	var hunting: int = 0
	var creatures: Array[Node] = get_tree().get_nodes_in_group("creatures")
	for node: Node in creatures:
		var creature := node as Creature
		if creature and creature.state == Creature.State.INVESTIGATE:
			hunting += 1

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Awareness: %.1f / %.0f" % [awareness.value, awareness.max_value])
	if run_manager:
		for player: Player in run_manager.players:
			var cooldown: String = "READY" if player.is_pulse_ready() else "%.1fs" % player.pulse_cooldown_left
			lines.append("P%d pulse: %s" % [player.player_number, cooldown])
	lines.append("Creatures investigating: %d / %d" % [hunting, creatures.size()])
	_debug_label.text = "\n".join(lines)
