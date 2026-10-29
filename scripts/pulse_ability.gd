class_name PulseAbility
extends Node
## The Echo's sonar pulse: on the action button, spawns a PulseRing and emits
## the player's pulse_emitted signal (pressure cost, awareness, creatures, sound
## and camera shake all listen to that signal). Skills: "pulse_radius_mult".
## When the cooldown ends, ready_cue plays (ring on the Echo + chime).

## Emitted once when the cooldown has run out.
signal became_ready

@export var player: Player
@export var pulse_ring_scene: PackedScene
@export var pulse_cooldown: float = 3.0
## Ring + chime when the pulse is ready again (a ReadyCue on the UnlitLayer).
@export var ready_cue: ReadyCue

var cooldown_left: float = 0.0
## Set by the WorldConfig (the pulse can behave differently in each world).
var pulse_radius: float = 650.0
var pulse_expand_time: float = 0.8


func _ready() -> void:
	add_to_group("world_listeners")


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	pulse_radius = world.pulse_radius
	pulse_expand_time = world.pulse_expand_time


func _process(delta: float) -> void:
	var was_cooling: bool = cooldown_left > 0.0
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if was_cooling and cooldown_left <= 0.0:
		if ready_cue:
			ready_cue.play()
		became_ready.emit()
	if player and player.try_action_pressed() and is_ready():
		emit_pulse()


func is_ready() -> bool:
	return cooldown_left <= 0.0


## 0 = ready, 1 = just pulsed (HUD).
func get_cooldown_ratio() -> float:
	return clampf(cooldown_left / pulse_cooldown, 0.0, 1.0) if pulse_cooldown > 0.0 else 0.0


## The world's pulse radius with the Echo's skills.
func get_radius() -> float:
	var skills: PlayerSkills = PlayerSkills.of(player)
	return pulse_radius * (skills.get_multiplier("pulse_radius_mult") if skills else 1.0)


func emit_pulse() -> void:
	cooldown_left = pulse_cooldown
	if pulse_ring_scene:
		var ring := pulse_ring_scene.instantiate() as PulseRing
		ring.max_radius = get_radius()
		ring.expand_time = pulse_expand_time
		ring.position = player.position
		player.get_parent().add_child(ring)
	player.pulse_emitted.emit(player.global_position)
