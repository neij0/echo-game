class_name PulseAbility
extends Node
## The Echo's sonar pulse: on the action button, spawns a PulseRing and emits
## the player's pulse_emitted signal (pressure cost, awareness, creatures, sound
## and camera shake all listen to that signal).

@export var player: Player
@export var pulse_ring_scene: PackedScene
@export var pulse_cooldown: float = 3.0

var cooldown_left: float = 0.0
## Set by the WorldConfig (the pulse can behave differently in each world).
var pulse_radius: float = 650.0
var pulse_expand_time: float = 0.8


func _ready() -> void:
	add_to_group("world_listeners")


## Called (via the "world_listeners" group) by RunManager.
func apply_world(world: WorldConfig) -> void:
	pulse_radius = world.pulse_radius
	pulse_expand_time = world.pulse_expand_time


func _process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if player and player.try_action_pressed() and is_ready():
		emit_pulse()


func is_ready() -> bool:
	return cooldown_left <= 0.0


func emit_pulse() -> void:
	cooldown_left = pulse_cooldown
	if pulse_ring_scene:
		var ring := pulse_ring_scene.instantiate() as PulseRing
		ring.max_radius = pulse_radius
		ring.expand_time = pulse_expand_time
		ring.position = player.position
		player.get_parent().add_child(ring)
	player.pulse_emitted.emit(player.global_position)
