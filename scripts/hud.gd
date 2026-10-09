class_name Hud
extends CanvasLayer
## Awareness bar + debug label (awareness, pulse cooldown, creature state).

@export var awareness: DepthAwareness
@export var player: Player
@export var creature: Creature

@export_group("Awareness Bar")
@export var calm_color: Color = Color(0.2, 0.55, 1.0)
@export var warning_color: Color = Color(1.0, 0.15, 0.15)
@export var background_color: Color = Color(0.1, 0.12, 0.18, 0.85)

@onready var _bar: ProgressBar = $AwarenessBar
@onready var _debug_label: Label = $DebugLabel

var _fill_style: StyleBoxFlat


func _ready() -> void:
	_bar.max_value = awareness.max_value

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = calm_color
	_bar.add_theme_stylebox_override("fill", _fill_style)

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = background_color
	_bar.add_theme_stylebox_override("background", background_style)


func _process(_delta: float) -> void:
	_bar.value = awareness.value
	_fill_style.bg_color = calm_color.lerp(warning_color, awareness.get_ratio())

	var cooldown_text: String = "READY" if player.is_pulse_ready() else "%.1fs" % player.pulse_cooldown_left
	_debug_label.text = "Awareness: %.1f / %.0f\nPulse cooldown: %s\nCreature: %s (speed %.0f)" % [
		awareness.value,
		awareness.max_value,
		cooldown_text,
		creature.get_state_name(),
		creature.get_current_speed(),
	]
