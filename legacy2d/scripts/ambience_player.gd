class_name AmbiencePlayer
extends Node
## The world's ambience (from the WorldConfig): its bed loop on the Ambience
## bus (the "Calm" music layer: the MusicDirector can lower it a little under
## the more intense layers) plus random one-shots at random times, pitches and
## volumes, so it never sounds like a loop: small ones often (bubbles, placed
## around the camera so they come from the sides) and a rare, distant one
## (whale groans, not positional: felt more than heard).

@export var audio_director: AudioDirector
## Small one-shots play this far around the camera (pixels).
@export var small_spread: float = 700.0
## Seconds for the bed to follow a new level (set_bed_offset_db).
@export var bed_fade_time: float = 2.0

var _world: WorldConfig
var _bed: AudioStreamPlayer
var _bed_offset_db: float = 0.0
var _bed_current_db: float = -80.0
var _small_left: float = 0.0
var _rare_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("world_listeners")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_bed = AudioStreamPlayer.new()
	_bed.bus = &"Ambience"
	_bed.volume_db = -80.0
	add_child(_bed)


## Called (via the "world_listeners" group) by StageManager.
func apply_world(world: WorldConfig) -> void:
	_world = world
	_bed.stream = world.ambience_bed
	if _bed.stream and not _bed.playing:
		_bed.play()
	_small_left = _rng.randf_range(world.ambience_small_interval_min, world.ambience_small_interval_max)
	_rare_left = _rng.randf_range(world.ambience_rare_interval_min * 0.3, world.ambience_rare_interval_min)


## The MusicDirector lowers the bed a little under the intense layers.
func set_bed_offset_db(offset_db: float) -> void:
	_bed_offset_db = offset_db


## Stopped playbacks are freed with the scene (a playing one would outlive it).
func _exit_tree() -> void:
	_bed.stop()


func is_bed_playing() -> bool:
	return _bed.playing


func _process(delta: float) -> void:
	if _world == null:
		return
	var target: float = _world.ambience_bed_volume_db + _bed_offset_db
	_bed_current_db = move_toward(_bed_current_db, target, 40.0 * delta / maxf(bed_fade_time, 0.01))
	_bed.volume_db = _bed_current_db
	if get_tree().paused:
		return
	_small_left -= delta
	_rare_left -= delta
	if _small_left <= 0.0:
		_small_left = _rng.randf_range(_world.ambience_small_interval_min, _world.ambience_small_interval_max)
		_play_small()
	if _rare_left <= 0.0:
		_rare_left = _rng.randf_range(_world.ambience_rare_interval_min, _world.ambience_rare_interval_max)
		if audio_director:
			audio_director.play(_world.ambience_rare_one_shot, AudioDirector.NO_POSITION,
				_rng.randf_range(_world.ambience_rare_volume_min_db, _world.ambience_rare_volume_max_db))


func _play_small() -> void:
	if audio_director == null:
		return
	var camera: Camera2D = get_viewport().get_camera_2d()
	var center: Vector2 = camera.get_screen_center_position() if camera else Vector2.ZERO
	var at: Vector2 = center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 1.0) * small_spread
	audio_director.play(_world.ambience_small_one_shot, at,
		_rng.randf_range(_world.ambience_small_volume_min_db, _world.ambience_small_volume_max_db))
