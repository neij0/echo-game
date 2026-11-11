class_name DistressPulse
extends Node
## The downed Echo's weak pulse: while she is downed, the action button sends a
## small sonar pulse (no oxygen cost, short radius, its own cooldown) so the
## Guardian can see and fight the creatures around her. It is a normal sonar
## pulse (Sonar.add_pulse, "sonar" group): creatures it reaches are revealed
## and Exposed. It does not emit pulse_emitted (no oxygen, no Depth Awareness,
## no spotting), but its noise makes creatures within noise_radius INVESTIGATE
## (0 = silent). Values per mode ("mode_listeners" group).

## Emitted on every distress pulse (tests, the HUD hint).
signal emitted

@export var player: Player

@export_group("Calm")
## World units (the 2D game's 200 px).
@export var calm_radius: float = 4.0
@export var calm_cooldown: float = 4.0
@export var calm_noise_radius: float = 0.0

@export_group("Challenge")
@export var challenge_radius: float = 4.0
@export var challenge_cooldown: float = 4.0
@export var challenge_noise_radius: float = 4.0

@export_group("Look")
## AudioDirector sound name (a weaker, muffled ping).
@export var sound: String = "pulse_distress"
@export var expand_time: float = 0.45

var challenge_mode: bool = false
var cooldown_left: float = 0.0


func _ready() -> void:
	add_to_group("mode_listeners")


## Called (via the "mode_listeners" group) by StageManager.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


## In the physics step: starting a pulse casts the sonar's rays.
func _physics_process(delta: float) -> void:
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
	get_tree().call_group("sonar", "add_pulse", player.global_position, get_radius(), expand_time)
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio:
		audio.play(sound, player.global_position)
	var noise: float = challenge_noise_radius if challenge_mode else calm_noise_radius
	if noise > 0.0:
		get_tree().call_group("creatures", "hear_noise", player.global_position, noise)
	emitted.emit()
