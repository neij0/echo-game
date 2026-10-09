extends Node2D
## Wires the level together: a pulse raises awareness and alerts the creature.

@export var player: Player
@export var awareness: DepthAwareness
@export var creature: Creature


func _ready() -> void:
	player.pulse_emitted.connect(_on_player_pulse_emitted)


func _on_player_pulse_emitted(origin: Vector2) -> void:
	awareness.add_pulse()
	creature.hear_pulse(origin)
