class_name DistressPulse
extends Node
## The downed Echo's weak pulse: while she is downed, the action button sends a
## small sonar pulse (no oxygen cost, short radius, its own cooldown) so the
## Guardian can see and fight the creatures around her. It works like a normal
## pulse front (SonarOverlay): creatures it reaches are revealed and Exposed.
## It does not emit pulse_emitted (no oxygen, no Depth Awareness, no spotting),
## but its noise makes creatures within noise_radius INVESTIGATE.
## Values per mode; the StageManager sets the mode ("mode_listeners" group).

@export var player: Player
@export var pulse_ring_scene: PackedScene

@export_group("Calm")
@export var calm_radius: float = 200.0
@export var calm_cooldown: float = 4.0
@export var calm_noise_radius: float = 350.0

@export_group("Challenge")
@export var challenge_radius: float = 200.0
@export var challenge_cooldown: float = 4.0
@export var challenge_noise_radius: float = 450.0

@export_group("Look")
@export var expand_time: float = 0.45
## The ring's own faint light (kept lower than a normal pulse).
@export var light_energy: float = 0.1

var challenge_mode: bool = false
var cooldown_left: float = 0.0


func _ready() -> void:
	add_to_group("mode_listeners")


## Called (via the "mode_listeners" group) by StageManager.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


func _process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if player == null or not player.health.is_downed:
		return
	if Input.is_action_just_pressed(player.input_prefix + "action") and is_ready():
		emit_pulse()


func is_ready() -> bool:
	return cooldown_left <= 0.0


func get_radius() -> float:
	return challenge_radius if challenge_mode else calm_radius


func get_cooldown() -> float:
	return challenge_cooldown if challenge_mode else calm_cooldown


func emit_pulse() -> void:
	cooldown_left = get_cooldown()
	if pulse_ring_scene:
		var ring := pulse_ring_scene.instantiate() as PulseRing
		ring.max_radius = get_radius()
		ring.expand_time = expand_time
		ring.light_energy = light_energy
		ring.position = player.position
		player.get_parent().add_child(ring)
	var noise: float = challenge_noise_radius if challenge_mode else calm_noise_radius
	get_tree().call_group("creatures", "hear_noise", player.global_position, noise)
