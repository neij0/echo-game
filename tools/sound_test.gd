extends Control
## Sound Test (dev tool, run tools/sound_test.tscn with F6): a button for every
## .wav in sound_dirs, grouped by name prefix (amb_, music_, sting_, sword_,
## pulse_, creature_, sentinel_, boss_, player_, world_). One-shots play with a
## random pitch / volume (like they will in the game, can be switched off);
## loops (files with a WAV loop chunk) toggle on and off. The music section
## plays every layer in sync and crossfades between the game states; the demo
## button runs Calm -> Tension -> Chase -> Calm. "Ambience" plays the ocean bed
## with random bubbles and whale groans. Files are found by name, so a better
## recording with the same name replaces a sound without code changes.

@export var sound_dirs: PackedStringArray = PackedStringArray([
	"res://assets/audio/sfx", "res://assets/audio/music", "res://assets/audio/ambience"])

@export_group("Variation")
## One-shots: random pitch within +- this share, volume within +- these dB.
@export_range(0.0, 0.5) var pitch_variation: float = 0.08
@export var volume_variation_db: float = 2.0

@export_group("Music")
## Seconds of every crossfade between music states.
@export var fade_time: float = 2.0
## Seconds each state holds during the demo.
@export var demo_hold_time: float = 7.0
## File (without .wav) of each music layer.
@export var layer_files: Dictionary = {
	"calm": "amb_ocean_bed",
	"tension": "music_tension",
	"chase": "music_chase",
	"intense": "music_intense",
	"boss": "music_boss",
}
## Per state: the level (dB) of each layer that plays. Missing = silent.
@export var states: Dictionary = {
	"Calm": {"calm": 0.0},
	"Tension": {"calm": 0.0, "tension": -2.0},
	"Chase": {"calm": -2.0, "tension": -4.0, "chase": 0.0},
	"Lockdown / Escape": {"calm": -8.0, "intense": 0.0},
	"Boss": {"calm": -10.0, "boss": 0.0},
}

@export_group("Ambience One-Shots")
@export var bubble_interval_min: float = 1.5
@export var bubble_interval_max: float = 5.0
@export var whale_interval_min: float = 10.0
@export var whale_interval_max: float = 22.0
@export var ambience_pitch_min: float = 0.8
@export var ambience_pitch_max: float = 1.2
@export var ambience_volume_min_db: float = -10.0
@export var ambience_volume_max_db: float = -2.0

@export_group("Look")
@export var button_min_size: Vector2 = Vector2(190.0, 34.0)
@export var section_font_size: int = 20

const SECTIONS: Array[String] = ["amb", "music", "sting", "sword", "pulse", "creature", "sentinel", "boss", "player", "world"]
const SECTION_TITLES: Dictionary = {
	"amb": "Ocean ambience", "music": "Music layers (single, looped)", "sting": "Stingers",
	"sword": "Sword", "pulse": "Pulse", "creature": "Creature", "sentinel": "Sentinel (deeper)",
	"boss": "Boss (deepest)", "player": "Players", "world": "World",
}
const POOL_SIZE: int = 12

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_next: int = 0
var _loop_players: Dictionary = {}
var _layers: Dictionary = {}
var _layer_gain: Dictionary = {}
var _layer_target: Dictionary = {}
var _music_on: bool = false
var _state_label: Label
var _vary: CheckBox
var _ambience_on: bool = false
var _bubble_left: float = 0.0
var _whale_left: float = 0.0
var _demo_running: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_streams()
	for i: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	_build_ui()


func _load_streams() -> void:
	for folder: String in sound_dirs:
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension() != "wav":
				continue
			var stream := load(folder.path_join(file)) as AudioStream
			if stream:
				_streams[file.get_basename()] = stream
	print("Sound Test: %d sounds, %d loops" % [_streams.size(), _streams.keys().filter(_is_loop).size()])


func _is_loop(sound_name: String) -> bool:
	var wav := _streams.get(sound_name) as AudioStreamWAV
	return wav != null and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.04, 0.06, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 20.0
	scroll.offset_top = 16.0
	scroll.offset_right = -20.0
	scroll.offset_bottom = -16.0
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "Sound Test — %d sounds" % _streams.size()
	title.add_theme_font_size_override("font_size", section_font_size + 4)
	column.add_child(title)
	var top := HFlowContainer.new()
	column.add_child(top)
	_vary = CheckBox.new()
	_vary.text = "Random pitch / volume on one-shots"
	_vary.button_pressed = true
	top.add_child(_vary)
	_add_button(top, "Stop everything", _stop_all)

	_add_title(column, "Adaptive music (all layers in sync, %.1f s crossfades)" % fade_time)
	var music := HFlowContainer.new()
	column.add_child(music)
	for state: String in states:
		_add_button(music, state, _set_state.bind(state))
	_add_button(music, "Demo: Calm → Tension → Chase → Calm", _run_demo)
	_add_button(music, "Music off", _music_off)
	_state_label = Label.new()
	_state_label.text = "Music: off"
	column.add_child(_state_label)
	var ambience := HFlowContainer.new()
	column.add_child(ambience)
	_add_button(ambience, "Ambience with random bubbles + whales (toggle)", _toggle_ambience)
	_add_button(ambience, "Combo: hit 1, hit 2, hit 3, hit-stop, finisher", _play_combo)

	for section: String in SECTIONS:
		var names: Array = _streams.keys().filter(func(n: String) -> bool: return n.begins_with(section + "_"))
		if names.is_empty():
			continue
		names.sort()
		_add_title(column, SECTION_TITLES.get(section, section))
		var flow := HFlowContainer.new()
		column.add_child(flow)
		for sound_name: String in names:
			var label: String = sound_name.trim_prefix(section + "_")
			if _is_loop(sound_name):
				_add_button(flow, "⟳ " + label, _toggle_loop.bind(sound_name))
			else:
				_add_button(flow, label, play.bind(sound_name))


func _add_title(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", section_font_size)
	label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	parent.add_child(label)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = button_min_size
	button.pressed.connect(action)
	parent.add_child(button)


# --- Playing ----------------------------------------------------------------

## Plays a one-shot (random pitch / volume when switched on).
func play(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	var player: AudioStreamPlayer = _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	player.stream = stream
	var vary: bool = _vary == null or _vary.button_pressed
	player.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_variation, pitch_variation) if vary else 1.0)
	player.volume_db = volume_db + (_rng.randf_range(-volume_variation_db, volume_variation_db) if vary else 0.0)
	player.play()


func _toggle_loop(sound_name: String) -> void:
	var player: AudioStreamPlayer = _loop_players.get(sound_name)
	if player and player.playing:
		player.stop()
		return
	if player == null:
		player = AudioStreamPlayer.new()
		player.stream = _streams[sound_name]
		add_child(player)
		_loop_players[sound_name] = player
	player.play()


func _stop_all() -> void:
	_demo_running = false
	_ambience_on = false
	_music_off()
	for player: AudioStreamPlayer in _pool:
		player.stop()
	for player: AudioStreamPlayer in _loop_players.values():
		player.stop()


# --- Music --------------------------------------------------------------------

func _start_music() -> void:
	if _music_on:
		return
	_music_on = true
	for layer: String in layer_files:
		var player: AudioStreamPlayer = _layers.get(layer)
		if player == null:
			player = AudioStreamPlayer.new()
			player.stream = _streams.get(layer_files[layer])
			add_child(player)
			_layers[layer] = player
		_layer_gain[layer] = 0.0
		_layer_target[layer] = 0.0
		player.volume_db = -80.0
	# Started in the same frame: the layers share the tempo and stay in step.
	for player: AudioStreamPlayer in _layers.values():
		if player.stream:
			player.play()


func _set_state(state: String) -> void:
	_start_music()
	var levels: Dictionary = states.get(state, {})
	for layer: String in layer_files:
		_layer_target[layer] = db_to_linear(float(levels[layer])) if levels.has(layer) else 0.0
	_state_label.text = "Music: %s" % state


func _music_off() -> void:
	for layer: String in _layer_target:
		_layer_target[layer] = 0.0
	if _state_label:
		_state_label.text = "Music: fading out"


func _run_demo() -> void:
	if _demo_running:
		return
	_demo_running = true
	for state: String in ["Calm", "Tension", "Chase", "Calm"]:
		if not _demo_running:
			return
		_set_state(state)
		_state_label.text = "Music: %s (demo)" % state
		await get_tree().create_timer(demo_hold_time).timeout
	_demo_running = false
	_state_label.text = "Music: Calm (demo done)"


func _process(delta: float) -> void:
	var step: float = delta / maxf(fade_time, 0.01)
	for layer: String in _layer_gain:
		_layer_gain[layer] = move_toward(float(_layer_gain[layer]), float(_layer_target[layer]), step)
		var player: AudioStreamPlayer = _layers[layer]
		player.volume_db = linear_to_db(maxf(float(_layer_gain[layer]), 0.0001))
	_update_ambience(delta)


# --- Ambience one-shots, combo ------------------------------------------------

func _toggle_ambience() -> void:
	_ambience_on = not _ambience_on
	if _ambience_on:
		_set_state("Calm")
		_bubble_left = _rng.randf_range(0.5, bubble_interval_min)
		_whale_left = _rng.randf_range(whale_interval_min * 0.5, whale_interval_min)


func _update_ambience(delta: float) -> void:
	if not _ambience_on:
		return
	_bubble_left -= delta
	_whale_left -= delta
	if _bubble_left <= 0.0:
		_bubble_left = _rng.randf_range(bubble_interval_min, bubble_interval_max)
		_play_ambient("amb_bubbles_%d" % _rng.randi_range(1, 4))
	if _whale_left <= 0.0:
		_whale_left = _rng.randf_range(whale_interval_min, whale_interval_max)
		_play_ambient("amb_whale_%d" % _rng.randi_range(1, 3))


func _play_ambient(sound_name: String) -> void:
	play(sound_name, _rng.randf_range(ambience_pitch_min, ambience_pitch_max) / (1.0 + pitch_variation),
		_rng.randf_range(ambience_volume_min_db, ambience_volume_max_db))


## The Guardian's combo as it will sound: two quick hits, the heavier third,
## a short hit-stop silence, then the Exposed finisher.
func _play_combo() -> void:
	for i: int in 3:
		play("sword_whoosh_%d" % (i + 1))
		await get_tree().create_timer(0.08).timeout
		play("sword_impact_heavy" if i == 2 else "sword_impact")
		await get_tree().create_timer(0.32).timeout
	play("sword_whoosh_3")
	await get_tree().create_timer(0.1).timeout
	play("sword_impact_heavy")
	# Hit-stop: a short silence before the boom.
	await get_tree().create_timer(0.09).timeout
	for player: AudioStreamPlayer in _pool:
		player.stop()
	await get_tree().create_timer(0.12).timeout
	play("sword_finisher")
