class_name CreatureVoice
extends Node
## A creature's sounds, all positional (AudioDirector): idle clicks now and
## then while it wanders near the players, its investigate voice when it starts
## to INVESTIGATE, a screech when it starts a CHASE, a hiss on the lunge
## wind-up, its death. Names are "<voice_prefix>_click" etc.; the investigate
## voice is picked from investigate_sounds (one per type: basic = chitter,
## light hunter = call, Sentinel = creak, boss = its three layered voices).
## A creature that stalks instead of chasing (Creature.is_stalking: the light
## hunter creeping up in the dark) uses its investigate voice, not a screech.

@export var creature: Creature
## "creature", "sentinel" or "boss": the deeper versions use their own files.
@export var voice_prefix: String = "creature"
@export var investigate_sounds: PackedStringArray = PackedStringArray(["creature_investigate_chitter"])

@export_group("Idle")
@export var idle_interval_min: float = 4.0
@export var idle_interval_max: float = 10.0
## Idle clicks only while a player is within this distance (pixels).
@export var idle_max_distance: float = 1100.0

@export_group("Cooldowns")
## Seconds before the same kind of sound can come again from this creature.
@export var investigate_cooldown: float = 3.0
@export var screech_cooldown: float = 4.0
## Every creature together: at most one screech this often (the collapse
## escape wakes them all at once).
@export var global_screech_gap: float = 0.25

## Physics frame of the last screech of any creature (game time, not wall time).
static var _last_global_screech_frame: int = -100000

var _idle_left: float = 0.0
var _investigate_left: float = 0.0
var _screech_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_idle_left = _rng.randf_range(idle_interval_min, idle_interval_max)
	if creature:
		creature.state_changed.connect(_on_state_changed)
		creature.lunge_started.connect(_on_lunge_started)
		creature.killed.connect(_on_killed)


func _process(delta: float) -> void:
	_investigate_left = maxf(_investigate_left - delta, 0.0)
	_screech_left = maxf(_screech_left - delta, 0.0)
	if creature == null or creature.state != Creature.State.WANDER:
		return
	_idle_left -= delta
	if _idle_left > 0.0:
		return
	_idle_left = _rng.randf_range(idle_interval_min, idle_interval_max)
	if _player_near():
		_play(voice_prefix + "_click")


func _on_state_changed(_old_state: Creature.State, new_state: Creature.State) -> void:
	match new_state:
		Creature.State.INVESTIGATE:
			_play_investigate()
		Creature.State.CHASE:
			if creature.is_stalking():
				_play_investigate()
				return
			var now: int = Engine.get_physics_frames()
			var gap_frames: int = ceili(global_screech_gap * Engine.physics_ticks_per_second)
			if _screech_left <= 0.0 and now - _last_global_screech_frame >= gap_frames:
				_screech_left = screech_cooldown
				_last_global_screech_frame = now
				_play(voice_prefix + "_screech")


func _play_investigate() -> void:
	if _investigate_left <= 0.0 and not investigate_sounds.is_empty():
		_investigate_left = investigate_cooldown
		_play(investigate_sounds[_rng.randi_range(0, investigate_sounds.size() - 1)])


func _on_lunge_started() -> void:
	_play(voice_prefix + "_hiss")


func _on_killed() -> void:
	_play(voice_prefix + "_death")


func _player_near() -> bool:
	for player: Player in Players.all(get_tree()):
		if player.global_position.distance_to(creature.global_position) <= idle_max_distance:
			return true
	return false


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and creature:
		audio.play(sound_name, creature.global_position)
