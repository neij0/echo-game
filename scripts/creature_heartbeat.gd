class_name CreatureHeartbeat
extends AudioStreamPlayer2D
## A low heartbeat that warns the player the hidden creature is near: it starts
## at start_distance and gets louder and faster as the creature gets closer.
## Positional (child of the creature), so the player hears which side it is on.

@export var creature: Creature

@export_group("Range")
## The heartbeat starts when the creature is this close to the player.
@export var start_distance: float = 500.0
## At this distance (or closer) the heartbeat is at its loudest and fastest.
@export var full_distance: float = 120.0

@export_group("Beat")
## Seconds between beats at start_distance.
@export var far_interval: float = 1.3
## Seconds between beats at full_distance.
@export var near_interval: float = 0.42
@export var far_volume_db: float = -30.0
@export var near_volume_db: float = -3.0
@export var far_pitch: float = 0.9
@export var near_pitch: float = 1.1
## Stereo panning strength (0 = no panning, 1 = Godot default, higher = wider).
@export var panning: float = 1.5

var _beat_timer: float = 0.0


func _ready() -> void:
	# Flat attenuation: volume is driven by closeness below, panning stays.
	attenuation = 0.0
	max_distance = start_distance * 3.0
	panning_strength = panning


func _process(delta: float) -> void:
	if creature == null:
		return
	var player: Player = creature.get_nearest_player()
	if player == null:
		return
	var distance: float = creature.global_position.distance_to(player.global_position)
	if distance > start_distance:
		_beat_timer = 0.0
		return
	var closeness: float = get_closeness(distance)
	volume_db = lerpf(far_volume_db, near_volume_db, closeness)
	pitch_scale = lerpf(far_pitch, near_pitch, closeness)
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		play()
		_beat_timer = lerpf(far_interval, near_interval, closeness)


## 0 at start_distance, 1 at full_distance or closer.
func get_closeness(distance: float) -> float:
	return clampf((start_distance - distance) / (start_distance - full_distance), 0.0, 1.0)
