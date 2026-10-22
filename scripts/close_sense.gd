class_name CloseSense
extends Node
## The Guardian's close sense: any creature within radius of him is always
## shown at least as a dark silhouette with clearly glowing eyes (Creature
## sense_ratio, CreatureEyes), even without the Echo's light, so he is never hit
## by something he could not see at melee range. Beyond it the normal
## visibility rules apply. It does not make creatures hittable: only the Echo
## (her light or a pulse) does. Values per mode ("mode_listeners" group).

@export var player: Player
@export var calm_radius: float = 90.0
@export var challenge_radius: float = 90.0
## The sense fades in over this many pixels outside the radius.
@export var fade_band: float = 30.0

var challenge_mode: bool = false


func _ready() -> void:
	add_to_group("close_senses")
	add_to_group("mode_listeners")


## Called (via the "mode_listeners" group) by StageManager.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled


func get_radius() -> float:
	return challenge_radius if challenge_mode else calm_radius


## 1 inside the radius (measured to the creature's edge), fading to 0 over
## fade_band outside it. 0 while this player is downed.
func get_sense_ratio(creature_position: Vector2, creature_radius: float) -> float:
	if player == null or player.health.is_downed:
		return 0.0
	var distance: float = player.global_position.distance_to(creature_position) - creature_radius
	var radius: float = get_radius()
	if distance <= radius:
		return 1.0
	if fade_band <= 0.0:
		return 0.0
	return clampf(1.0 - (distance - radius) / fade_band, 0.0, 1.0)
