class_name UiAudio
extends Node
## The menus' sounds on the UI bus, found by file name in sound_dir (like the
## AudioDirector): "ui_focus" (a soft ping when a button or card gets the
## focus), "ui_press" (a brighter one when it is pressed). A sound that does
## not exist there (e.g. still waiting for approval in assets/audio/preview/)
## stays silent. Created by the Game autoload; works while the game is paused.

const GROUP: StringName = &"ui_audio"

@export var sound_dir: String = "res://assets/audio/sfx"
@export var bus: StringName = &"UI"
@export var volume_db: float = -8.0
@export_range(0.0, 0.5) var pitch_variation: float = 0.03
## The same sound never plays twice within this many seconds (focus jumping
## over several buttons at once).
@export var min_interval: float = 0.05
@export var pool_size: int = 4

var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


## The UiAudio of this tree (the Game autoload's), or null.
static func find(tree: SceneTree) -> UiAudio:
	return tree.get_first_node_in_group(GROUP) as UiAudio if tree else null


## Plays sound_name if a UiAudio exists (any screen can call it).
static func play_in(tree: SceneTree, sound_name: StringName) -> void:
	var audio: UiAudio = find(tree)
	if audio:
		audio.play(sound_name)


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in pool_size:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		_players.append(player)


func has_sound(sound_name: StringName) -> bool:
	return _stream(sound_name) != null


func play(sound_name: StringName) -> void:
	var stream: AudioStream = _stream(sound_name)
	if stream == null or _players.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound_name, -INF)) < min_interval:
		return
	_last_played[sound_name] = now
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func _stream(sound_name: StringName) -> AudioStream:
	if not _streams.has(sound_name):
		var path: String = sound_dir.path_join(String(sound_name) + ".wav")
		_streams[sound_name] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[sound_name] as AudioStream
