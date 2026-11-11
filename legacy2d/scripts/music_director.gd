class_name MusicDirector
extends Node
## Adaptive music. Every layer loops on the Music bus, all started together
## (they share one tempo, so they stay in step); the game state sets each
## layer's level and the layers crossfade over fade_time. States, from calm to
## most intense:
## - CALM: the ambience bed only (AmbiencePlayer);
## - TENSION: + a low pulse, while a creature INVESTIGATEs / SEARCHes near a player;
## - CHASE: + heartbeat percussion, while any creature is in CHASE (a stalking
##   light hunter only counts as TENSION: the music must not give it away);
## - INTENSE: the lockdown or the collapse escape;
## - BOSS: its own loop while the boss fight is on.
## A more intense state starts at once; a calmer one only after the calmer
## situation has lasted release_time (hysteresis: no flapping between layers).
## Stingers (one-shots on the Music bus): a creature spots you, an Echo Shard,
## the lockdown slam, doors opening, level complete, a player downed.

enum State { CALM, TENSION, CHASE, INTENSE, BOSS }

signal state_changed(state: State)
## Emitted for every stinger (debug, tests).
signal stinger_played(sound_name: String)

@export var audio_director: AudioDirector
@export var ambience: AmbiencePlayer
@export var stage_manager: StageManager
@export var level_builder: LevelBuilder
@export var escape_event: EscapeEvent

@export_group("Layers")
@export var tension_stream: AudioStream
@export var chase_stream: AudioStream
@export var intense_stream: AudioStream
@export var boss_stream: AudioStream
## Seconds of a crossfade between two states.
@export var fade_time: float = 2.0
## Seconds a calmer situation must last before the music calms down.
@export var release_time: float = 3.5
## Per state: the level (dB) of each layer that plays; missing = silent.
## "bed" is the ambience bed's offset.
@export var state_levels: Dictionary = {
	State.CALM: {"bed": 0.0},
	State.TENSION: {"bed": 0.0, "tension": -3.0},
	State.CHASE: {"bed": -2.0, "tension": -5.0, "chase": -1.0},
	State.INTENSE: {"bed": -8.0, "intense": -1.0},
	State.BOSS: {"bed": -10.0, "boss": -1.0},
}

@export_group("Situations")
## A creature INVESTIGATing / SEARCHing this close to a standing player = TENSION.
@export var tension_radius: float = 800.0
## The boss fight: the boss is awake (not wandering) or a player is this close.
@export var boss_radius: float = 900.0

@export_group("Stingers")
@export var spotted_stinger: String = "sting_spotted"
@export var shard_stinger: String = "sting_shard"
@export var lockdown_stinger: String = "sting_lockdown"
@export var doors_open_stinger: String = "sting_doors_open"
@export var level_complete_stinger: String = "sting_level_complete"
@export var downed_stinger: String = "sting_downed"
## The spotted stinger plays at most this often.
@export var spotted_cooldown: float = 6.0

var state: State = State.CALM
var _layers: Dictionary = {}
var _gain: Dictionary = {}
var _target: Dictionary = {}
var _calmer_for: float = 0.0
var _spotted_left: float = 0.0
var _last_chasers: int = 0
var _last_shards: int = 0
var _lockdown_was_locked: bool = false
var _door_was_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for layer: String in ["tension", "chase", "intense", "boss"]:
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		player.stream = get(layer + "_stream") as AudioStream
		player.volume_db = -80.0
		add_child(player)
		_layers[layer] = player
		_gain[layer] = 0.0
		_target[layer] = 0.0
	# Started in the same frame: one tempo, so they stay in step.
	for player: AudioStreamPlayer in _layers.values():
		if player.stream:
			player.play()
	if stage_manager:
		stage_manager.player_registered.connect(_on_player_registered)
		stage_manager.shards_changed.connect(_on_shards_changed)
		stage_manager.level_started.connect(_on_level_started)
		stage_manager.level_won.connect(_on_level_won)
	_apply_state()


func _on_player_registered(player: Player) -> void:
	player.health.downed.connect(func(_cause: PlayerHealth.Cause) -> void: _stinger(downed_stinger))


func _on_level_started(_index: int) -> void:
	_last_chasers = 0
	_last_shards = 0
	_lockdown_was_locked = false
	_door_was_open = false
	_calmer_for = 0.0
	_set_state(State.CALM)


func _on_shards_changed(collected: int, _total: int) -> void:
	if collected > _last_shards:
		_stinger(shard_stinger)
	_last_shards = collected


func _on_level_won() -> void:
	_stinger(level_complete_stinger, true)


func _process(delta: float) -> void:
	_spotted_left = maxf(_spotted_left - delta, 0.0)
	var step: float = delta / maxf(fade_time, 0.01)
	for layer: String in _layers:
		_gain[layer] = move_toward(float(_gain[layer]), float(_target[layer]), step)
		(_layers[layer] as AudioStreamPlayer).volume_db = linear_to_db(maxf(float(_gain[layer]), 0.0001))
	if get_tree().paused:
		return
	_watch_events()
	var wanted: State = get_wanted_state()
	if wanted > state:
		_set_state(wanted)
	elif wanted < state:
		_calmer_for += delta
		if _calmer_for >= release_time:
			_set_state(wanted)
	else:
		_calmer_for = 0.0


## What the situation calls for right now (before the hysteresis).
func get_wanted_state() -> State:
	if _boss_fight():
		return State.BOSS
	if (escape_event and escape_event.is_active) or _lockdown_locked():
		return State.INTENSE
	var players: Array[Player] = Players.all(get_tree())
	var wanted: State = State.CALM
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature == null or creature.is_dying():
			continue
		if creature.state == Creature.State.CHASE and not creature.is_stalking():
			return State.CHASE
		if creature.state == Creature.State.INVESTIGATE or creature.state == Creature.State.SEARCH or creature.is_stalking():
			for player: Player in players:
				if not player.health.is_downed and player.global_position.distance_to(creature.global_position) <= tension_radius:
					wanted = State.TENSION
	return wanted


func _boss_fight() -> bool:
	var boss: Creature = level_builder.get_boss() if level_builder else null
	if boss == null or not is_instance_valid(boss) or boss.is_dying():
		return false
	var door: ShardDoor = level_builder.get_exit_door()
	if door and not door.is_open:
		return false
	if boss.state != Creature.State.WANDER:
		return true
	for player: Player in Players.all(get_tree()):
		if player.global_position.distance_to(boss.global_position) <= boss_radius:
			return true
	return false


func _lockdown_locked() -> bool:
	var lockdown: LockdownRoom = level_builder.get_lockdown() if level_builder else null
	return lockdown != null and lockdown.is_locked()


## Stingers for things that are easiest to see by watching the level.
func _watch_events() -> void:
	var chasers: int = 0
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature and creature.state == Creature.State.CHASE and not creature.is_stalking():
			chasers += 1
	if chasers > _last_chasers and _spotted_left <= 0.0:
		_spotted_left = spotted_cooldown
		_stinger(spotted_stinger)
	_last_chasers = chasers
	var locked: bool = _lockdown_locked()
	if locked and not _lockdown_was_locked:
		_stinger(lockdown_stinger, true)
	elif not locked and _lockdown_was_locked:
		_stinger(doors_open_stinger)
	_lockdown_was_locked = locked
	var door: ShardDoor = level_builder.get_exit_door() if level_builder else null
	var open: bool = door != null and door.is_open
	if open and not _door_was_open:
		_stinger(doors_open_stinger)
	_door_was_open = open


func _stinger(sound_name: String, big: bool = false) -> void:
	if audio_director == null:
		return
	if big:
		audio_director.duck()
	audio_director.play(sound_name)
	stinger_played.emit(sound_name)


func _set_state(new_state: State) -> void:
	_calmer_for = 0.0
	if new_state == state:
		return
	state = new_state
	_apply_state()
	state_changed.emit(state)


func _apply_state() -> void:
	var levels: Dictionary = state_levels.get(state, {})
	for layer: String in _layers:
		_target[layer] = db_to_linear(float(levels[layer])) if levels.has(layer) else 0.0
	if ambience:
		ambience.set_bed_offset_db(float(levels.get("bed", 0.0)))


## Stopped playbacks are freed with the scene (a playing one would outlive it).
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _layers.values():
		player.stop()


func get_layer_gain(layer: String) -> float:
	return float(_gain.get(layer, 0.0))
