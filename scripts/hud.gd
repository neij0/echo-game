class_name Hud
extends CanvasLayer
## Awareness bar + debug label (awareness, pulse cooldown, creature state).

@export var awareness: DepthAwareness
@export var player: Player
@export var creature: Creature

@onready var _bar: ProgressBar = $AwarenessBar
@onready var _debug_label: Label = $DebugLabel


func _ready() -> void:
	_bar.max_value = awareness.max_value


func _process(_delta: float) -> void:
	_bar.value = awareness.value
	var cooldown_text: String = "READY" if player.is_pulse_ready() else "%.1fs" % player.pulse_cooldown_left
	_debug_label.text = "Awareness: %.1f / %.0f\nPulse cooldown: %s\nCreature: %s (speed %.0f)" % [
		awareness.value,
		awareness.max_value,
		cooldown_text,
		creature.get_state_name(),
		creature.get_current_speed(),
	]
