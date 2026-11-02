class_name JourneyMusic
extends Node
## The Journey screen's music: each world's theme (WorldConfig.map_theme, else
## the file music_map_<world id>.wav in music_dir, found by name). play_world()
## crossfades to it over fade_time; a locked world's theme plays muffled, as if
## heard from far away (a low-pass and quieter). Two players, each on a bus of
## its own (created here, sent to Music, removed on exit), so the muffle can
## glide on the theme that keeps playing. A theme that does not exist yet is
## silence. Both buses fade in and out with the screen (Game.fader).

@export var music_dir: String = "res://assets/audio/music"
@export var volume_db: float = -5.0
@export var fade_time: float = 1.5
## Locked worlds: the low-pass cutoff and how much quieter.
@export var muffled_cutoff_hz: float = 650.0
@export var muffled_volume_db: float = -9.0
@export var open_cutoff_hz: float = 20000.0
@export var send_bus: StringName = &"Music"

var current_world: String = ""
var current_muffled: bool = false
var _players: Array[AudioStreamPlayer] = []
var _filters: Array[AudioEffectLowPassFilter] = []
var _bus_names: Array[StringName] = [&"JourneyA", &"JourneyB"]
var _active: int = 0
var _tween: Tween


func _ready() -> void:
	for bus_name: StringName in _bus_names:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index < 0:
			index = AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, send_bus)
			AudioServer.add_bus_effect(index, AudioEffectLowPassFilter.new())
		var filter := AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
		filter.cutoff_hz = open_cutoff_hz
		_filters.append(filter)
		var player := AudioStreamPlayer.new()
		player.bus = bus_name
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


func _process(_delta: float) -> void:
	# Fades in and out with the screen (Game's fader).
	var cover: float = Game.fader.get_cover() if Game.fader else 0.0
	for bus_name: StringName in _bus_names:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(1.0 - cover, 0.001)))


func _exit_tree() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
	for bus_name: StringName in _bus_names:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.remove_bus(index)


## The theme of a world, or null if there is none yet.
func find_theme(world_id: String) -> AudioStream:
	var world: WorldConfig = Game.get_world_config(world_id)
	if world and world.map_theme:
		return world.map_theme
	var path: String = music_dir.path_join("music_map_%s.wav" % world_id)
	return load(path) as AudioStream if ResourceLoader.exists(path) else null


func play_world(world_id: String, muffled: bool) -> void:
	if world_id == current_world and muffled == current_muffled:
		return
	var same_theme: bool = world_id == current_world
	current_world = world_id
	current_muffled = muffled
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var target_db: float = volume_db + (muffled_volume_db if muffled else 0.0)
	var cutoff: float = muffled_cutoff_hz if muffled else open_cutoff_hz
	if same_theme:
		# Only the muffle changes: glide it on the theme that keeps playing.
		_tween.tween_property(_players[_active], "volume_db", target_db, fade_time)
		_tween.tween_property(_filters[_active], "cutoff_hz", cutoff, fade_time).set_trans(Tween.TRANS_EXPO)
		return
	var old: AudioStreamPlayer = _players[_active]
	_tween.tween_property(old, "volume_db", -80.0, fade_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_active = 1 - _active
	var player: AudioStreamPlayer = _players[_active]
	var stream: AudioStream = find_theme(world_id)
	player.stop()
	if stream == null:
		return
	player.stream = stream
	_filters[_active].cutoff_hz = cutoff
	player.volume_db = -60.0
	player.play()
	_tween.tween_property(player, "volume_db", target_db, fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The theme playing now (null = silence).
func get_playing_stream() -> AudioStream:
	return _players[_active].stream if _players[_active].playing else null
