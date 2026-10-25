class_name AudioDirector
extends Node
## Plays the game's one-shot sounds by name. At start it reads every .wav in
## sound_dirs into a catalog: a file "player_move_2.wav" is the sound
## "player_move_2" and a variant of "player_move" (asking for "player_move"
## picks one variant at random). So a better recording dropped in with the same
## name (or an extra _4 variant) is used without code changes.
## Every play gets a little random pitch / volume (per-sound settings below).
## With a position, the sound is an AudioStreamPlayer2D (heard from the shared
## camera's AudioListener2D); without, a plain AudioStreamPlayer. The bus comes
## from the name's prefix (prefix_buses).
## Also: the world's underwater sound (low-pass + reverb on the SFX and
## Ambience buses, from the WorldConfig), music ducking under big sounds (the
## "Duck" amplify on the Music bus) and the finisher's hit-stop silence (the
## "Gate" amplify on the SFX / Ambience buses).
## Lives in game.tscn (group "audio_director"); find it with AudioDirector.find().

## Emitted on every play (debug, tests).
signal sound_played(sound_name: String, at: Vector2)

const NO_POSITION: Vector2 = Vector2.INF

@export var sound_dirs: PackedStringArray = PackedStringArray([
	"res://assets/audio/sfx", "res://assets/audio/music", "res://assets/audio/ambience"])
@export var positional_pool_size: int = 32
@export var flat_pool_size: int = 12

@export_group("Buses")
@export var sfx_bus: StringName = &"SFX"
@export var music_bus: StringName = &"Music"
@export var ambience_bus: StringName = &"Ambience"
## Name prefix -> bus (anything else goes to sfx_bus).
@export var prefix_buses: Dictionary = {"music": "Music", "sting": "Music", "amb": "Ambience"}

@export_group("Variation")
@export_range(0.0, 0.5) var default_pitch_variation: float = 0.06
@export var default_volume_variation_db: float = 1.5
@export var default_volume_db: float = -4.0
## Positional sounds: heard up to this far from the listener (pixels).
@export var default_max_distance: float = 1500.0
@export var default_attenuation: float = 1.2

## Per sound (or per variant group): any of "volume_db", "pitch_variation",
## "volume_variation_db", "max_distance", "bus". Missing = the defaults above.
@export var sound_settings: Dictionary = {
	"sword_whoosh": {"volume_db": -8.0, "pitch_variation": 0.05},
	"sword_impact": {"volume_db": -3.0},
	"sword_impact_heavy": {"volume_db": -1.0},
	"sword_finisher": {"volume_db": 0.0, "pitch_variation": 0.02, "max_distance": 3000.0},
	"pulse_distress": {"volume_db": -3.0},
	"creature_click": {"volume_db": -12.0, "pitch_variation": 0.12, "max_distance": 1100.0},
	"sentinel_click": {"volume_db": -11.0, "pitch_variation": 0.1, "max_distance": 1100.0},
	"boss_click": {"volume_db": -9.0, "pitch_variation": 0.08},
	"creature_investigate_chitter": {"volume_db": -6.0, "pitch_variation": 0.1},
	"creature_investigate_call": {"volume_db": -7.0, "pitch_variation": 0.08},
	"sentinel_investigate_creak": {"volume_db": -6.0},
	"boss_investigate": {"volume_db": -3.0, "max_distance": 2500.0},
	"creature_screech": {"volume_db": -5.0},
	"sentinel_screech": {"volume_db": -4.0},
	"boss_screech": {"volume_db": -2.0, "max_distance": 2500.0},
	"creature_hiss": {"volume_db": -4.0},
	"sentinel_hiss": {"volume_db": -3.0},
	"boss_hiss": {"volume_db": -2.0},
	"creature_death": {"volume_db": -4.0},
	"sentinel_death": {"volume_db": -3.0},
	"boss_death": {"volume_db": 0.0, "max_distance": 3000.0},
	"player_move": {"volume_db": -20.0, "pitch_variation": 0.12, "max_distance": 900.0},
	"player_hurt": {"volume_db": -3.0},
	"player_downed": {"volume_db": -2.0},
	"player_revive": {"volume_db": -4.0},
	"world_shard_pickup": {"volume_db": -4.0},
	"world_barrier_close": {"volume_db": 0.0, "max_distance": 2500.0},
	"world_barrier_open": {"volume_db": -2.0, "max_distance": 2500.0},
	"world_rock_fall": {"volume_db": -12.0, "pitch_variation": 0.15},
	"sting": {"volume_db": -5.0, "pitch_variation": 0.0, "volume_variation_db": 0.0},
	"amb_bubbles": {"pitch_variation": 0.2, "max_distance": 1200.0},
	"amb_whale": {"pitch_variation": 0.1, "volume_variation_db": 2.0},
}

@export_group("Ducking")
## How far the music drops under a big sound, and how fast it moves.
@export var duck_depth_db: float = -9.0
@export var duck_hold_time: float = 0.6
@export var duck_attack_time: float = 0.05
@export var duck_release_time: float = 1.2

@export_group("Hit-Stop")
## The SFX / Ambience buses drop to this during the finisher's hit-stop silence.
@export var silence_db: float = -60.0

var _catalog: Dictionary = {}
var _positional: Array[AudioStreamPlayer2D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next_positional: int = 0
var _next_flat: int = 0
var _rng := RandomNumberGenerator.new()
var _duck_left: float = 0.0
var _duck_target_db: float = 0.0
var _duck_db: float = 0.0
var _silence_left: float = 0.0


static func find(tree: SceneTree) -> AudioDirector:
	return tree.get_first_node_in_group("audio_director") as AudioDirector if tree else null


func _ready() -> void:
	add_to_group("audio_director")
	add_to_group("world_listeners")
	# Keeps playing (and ducking) while the game is paused on a screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_load_catalog()
	for i: int in positional_pool_size:
		var player := AudioStreamPlayer2D.new()
		add_child(player)
		_positional.append(player)
	for i: int in flat_pool_size:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_flat.append(player)


# --- Catalog ----------------------------------------------------------------

func _load_catalog() -> void:
	for folder: String in sound_dirs:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file: String in DirAccess.get_files_at(folder):
			# Exported games list "x.wav.import" / "x.wav.remap" instead of "x.wav".
			var source: String = file.trim_suffix(".import").trim_suffix(".remap")
			if source.get_extension() != "wav":
				continue
			var stream := load(folder.path_join(source)) as AudioStream
			if stream == null:
				continue
			var sound_name: String = source.get_basename()
			_add(sound_name, stream)
			var group: String = _variant_group(sound_name)
			if group != sound_name:
				_add(group, stream)


func _add(sound_name: String, stream: AudioStream) -> void:
	if not _catalog.has(sound_name):
		_catalog[sound_name] = []
	var streams: Array = _catalog[sound_name]
	if not stream in streams:
		streams.append(stream)


## "player_move_2" -> "player_move"; names without a number stay as they are.
static func _variant_group(sound_name: String) -> String:
	var cut: int = sound_name.rfind("_")
	if cut > 0 and sound_name.substr(cut + 1).is_valid_int():
		return sound_name.substr(0, cut)
	return sound_name


func has_sound(sound_name: String) -> bool:
	return _catalog.has(sound_name)


func get_variant_count(sound_name: String) -> int:
	return (_catalog.get(sound_name, []) as Array).size()


## One of the sound's variants (null if there is no such sound).
func pick_stream(sound_name: String) -> AudioStream:
	var streams: Array = _catalog.get(sound_name, [])
	if streams.is_empty():
		return null
	return streams[_rng.randi_range(0, streams.size() - 1)] as AudioStream


## A setting of the sound: its own entry, else its variant group's, else the
## first matching prefix ("sting"), else the default.
func get_setting(sound_name: String, key: String, default_value: Variant) -> Variant:
	for candidate: String in [sound_name, _variant_group(sound_name), sound_name.get_slice("_", 0)]:
		var entry: Dictionary = sound_settings.get(candidate, {})
		if entry.has(key):
			return entry[key]
	# Longest matching group prefix, e.g. "boss_investigate" for "boss_investigate_call".
	for candidate: String in sound_settings:
		if sound_name.begins_with(candidate + "_") and (sound_settings[candidate] as Dictionary).has(key):
			return sound_settings[candidate][key]
	return default_value


func get_bus(sound_name: String) -> StringName:
	var bus: Variant = get_setting(sound_name, "bus", null)
	if bus != null:
		return StringName(str(bus))
	return StringName(str(prefix_buses.get(sound_name.get_slice("_", 0), sfx_bus)))


# --- Playing ----------------------------------------------------------------

## Plays a sound once (a random variant, with a little random pitch and
## volume). at = world position for a positional sound. Returns the player.
func play(sound_name: String, at: Vector2 = NO_POSITION, volume_offset_db: float = 0.0, pitch: float = 1.0) -> Node:
	var stream: AudioStream = pick_stream(sound_name)
	if stream == null:
		return null
	var pitch_variation: float = float(get_setting(sound_name, "pitch_variation", default_pitch_variation))
	var volume_variation: float = float(get_setting(sound_name, "volume_variation_db", default_volume_variation_db))
	var volume: float = float(get_setting(sound_name, "volume_db", default_volume_db)) + volume_offset_db \
		+ _rng.randf_range(-volume_variation, volume_variation)
	var pitch_scale: float = pitch * (1.0 + _rng.randf_range(-pitch_variation, pitch_variation))
	var player: Node
	if at == NO_POSITION:
		var flat: AudioStreamPlayer = _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
		_setup(flat, stream, sound_name, volume, pitch_scale)
		flat.play()
		player = flat
	else:
		var positional: AudioStreamPlayer2D = _positional[_next_positional]
		_next_positional = (_next_positional + 1) % _positional.size()
		_setup(positional, stream, sound_name, volume, pitch_scale)
		positional.global_position = at
		positional.max_distance = float(get_setting(sound_name, "max_distance", default_max_distance))
		positional.attenuation = default_attenuation
		positional.play()
		player = positional
	sound_played.emit(sound_name, at)
	return player


func _setup(player: Node, stream: AudioStream, sound_name: String, volume_db: float, pitch_scale: float) -> void:
	player.set("stream", stream)
	player.set("bus", get_bus(sound_name))
	player.set("volume_db", volume_db)
	player.set("pitch_scale", maxf(pitch_scale, 0.05))


## A player of its own for a looping sound (a shard's hum, the mending link):
## a child of parent, positional when parent is a Node2D. The caller plays
## and stops it. Null if the sound does not exist.
func make_loop_player(sound_name: String, parent: Node) -> Node:
	var stream: AudioStream = pick_stream(sound_name)
	if stream == null or parent == null:
		return null
	var player: Node
	if parent is Node2D:
		var positional := AudioStreamPlayer2D.new()
		positional.max_distance = float(get_setting(sound_name, "max_distance", default_max_distance))
		positional.attenuation = default_attenuation
		player = positional
	else:
		player = AudioStreamPlayer.new()
	_setup(player, stream, sound_name, float(get_setting(sound_name, "volume_db", default_volume_db)), 1.0)
	parent.add_child(player)
	return player


## Lowers the music for a moment (under a big sound).
func duck(depth_db: float = NAN, hold: float = NAN) -> void:
	_duck_target_db = minf(_duck_target_db, depth_db if not is_nan(depth_db) else duck_depth_db)
	_duck_left = maxf(_duck_left, hold if not is_nan(hold) else duck_hold_time)


## The finisher: every SFX and the ambience go silent for `silence` real
## seconds (the hit-stop), then the sound plays with the music ducked.
func play_after_silence(sound_name: String, at: Vector2, silence: float) -> void:
	_silence_left = silence
	_set_gate(silence_db)
	await get_tree().create_timer(silence, true, false, true).timeout
	_silence_left = 0.0
	_set_gate(0.0)
	duck()
	play(sound_name, at)


func is_silenced() -> bool:
	return _silence_left > 0.0


func _process(delta: float) -> void:
	# Unscaled time: the hit-stop slows Engine.time_scale, ducking must not slow down.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	if _duck_left > 0.0:
		_duck_left -= real_delta
		_duck_db = move_toward(_duck_db, _duck_target_db, absf(duck_depth_db) * real_delta / maxf(duck_attack_time, 0.001))
	else:
		_duck_target_db = 0.0
		_duck_db = move_toward(_duck_db, 0.0, absf(duck_depth_db) * real_delta / maxf(duck_release_time, 0.001))
	var effect := _bus_effect(music_bus, "AudioEffectAmplify")
	if effect:
		effect.set("volume_db", _duck_db)


func get_duck_db() -> float:
	return _duck_db


# --- Buses ------------------------------------------------------------------

## Called (via the "world_listeners" group) by StageManager: the world's
## underwater low-pass and reverb on the SFX and Ambience buses.
func apply_world(world: WorldConfig) -> void:
	for bus: StringName in [sfx_bus, ambience_bus]:
		var lowpass := _bus_effect(bus, "AudioEffectLowPassFilter")
		if lowpass:
			lowpass.set("cutoff_hz", world.audio_lowpass_hz)
		var reverb := _bus_effect(bus, "AudioEffectReverb")
		if reverb:
			reverb.set("room_size", world.audio_reverb_room_size)
			reverb.set("damping", world.audio_reverb_damping)
			reverb.set("wet", world.audio_reverb_wet)
			reverb.set("dry", world.audio_reverb_dry)


func _set_gate(volume_db: float) -> void:
	for bus: StringName in [sfx_bus, ambience_bus]:
		var gate := _bus_effect(bus, "AudioEffectAmplify")
		if gate:
			gate.set("volume_db", volume_db)


## The first effect of that class on the bus (null if none).
func _bus_effect(bus: StringName, effect_class: String) -> AudioEffect:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return null
	for i: int in AudioServer.get_bus_effect_count(index):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, i)
		if effect.is_class(effect_class):
			return effect
	return null


func _exit_tree() -> void:
	# Stopped playbacks are freed with the scene (a playing one would outlive it).
	for player: AudioStreamPlayer2D in _positional:
		player.stop()
	for player: AudioStreamPlayer in _flat:
		player.stop()
	# Never leave the buses silenced or ducked for the next scene.
	_set_gate(0.0)
	var effect := _bus_effect(music_bus, "AudioEffectAmplify")
	if effect:
		effect.set("volume_db", 0.0)
