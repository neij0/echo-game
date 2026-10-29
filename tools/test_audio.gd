extends Node
## Headless audio test, run as a scene (loads the real game.tscn):
##   godot --headless --path . --fixed-fps 60 res://tools/test_audio.tscn
## Checks: the buses and their effects, the volume settings, the world's
## underwater low-pass / reverb, the AudioDirector's catalog (every name the
## game asks for exists; variants), bus by prefix, random pitch, the
## finisher's hit-stop silence and music ducking, the music states (Calm ->
## Tension -> Chase -> hysteresis -> Calm, Intense in a lockdown and the
## collapse, Boss) and their stingers, each creature type's voice, the
## players' sounds, the mending hum, the shard hum, the collapse sounds and
## the ambience one-shots.

const GAME_SCENE: String = "res://scenes/game.tscn"
const PHYSICS_FPS: float = 60.0
const REQUIRED_SOUNDS: Array[String] = [
	"sword_whoosh_1", "sword_whoosh_2", "sword_whoosh_3", "sword_impact", "sword_impact_heavy", "sword_finisher",
	"pulse_ping", "pulse_distress", "skill_ready",
	"creature_click", "creature_investigate_chitter", "creature_investigate_call", "creature_screech", "creature_hiss", "creature_death",
	"sentinel_click", "sentinel_investigate_creak", "sentinel_screech", "sentinel_hiss", "sentinel_death",
	"boss_click", "boss_investigate_chitter", "boss_investigate_creak", "boss_investigate_call", "boss_screech", "boss_hiss", "boss_death",
	"player_move", "player_hurt", "player_downed", "player_revive", "player_mending_hum", "player_low_oxygen", "player_low_health",
	"world_shard_hum", "world_shard_pickup", "world_barrier_close", "world_barrier_open", "world_collapse_rumble", "world_rock_fall",
	"sting_spotted", "sting_shard", "sting_lockdown", "sting_doors_open", "sting_level_complete", "sting_downed",
	"amb_bubbles", "amb_whale", "amb_ocean_bed",
]

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _audio: AudioDirector
var _music: MusicDirector
var _ambience: AmbiencePlayer
var _echo: Player
var _guardian: Player
var _failures: int = 0
var _heard: Array[String] = []
var _stingers: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	_stage = _game.get_node("StageManager") as StageManager
	_stage.test_mode = SaveData.Mode.CHALLENGE
	add_child(_game)
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	_audio = _game.get_node("AudioDirector") as AudioDirector
	_music = _game.get_node("MusicDirector") as MusicDirector
	_ambience = _game.get_node("AmbiencePlayer") as AmbiencePlayer
	_echo = _game.get_node("Echo") as Player
	_guardian = _game.get_node("Guardian") as Player
	(_game.get_node("DepthAwareness") as DepthAwareness).decay_per_second = 0.0
	_audio.sound_played.connect(func(sound_name: String, _at: Vector2) -> void: _heard.append(sound_name))
	_music.stinger_played.connect(func(sound_name: String) -> void: _stingers.append(sound_name))
	await _frames(10)

	_test_buses_and_settings()
	_test_catalog()
	await _test_hit_stop_and_duck()
	await _test_music_states()
	await _test_creature_voices()
	await _test_players()
	await _test_world()
	await _test_ambience()

	print("RESULT: %s" % ("ALL AUDIO CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures))
	# Free the game a moment before quitting: the audio server releases the
	# playbacks of freed players on its own thread (a stream still playing at
	# exit is reported as leaked).
	_game.queue_free()
	for i: int in 10:
		await get_tree().process_frame
		OS.delay_msec(30)
	get_tree().quit(0 if _failures == 0 else 1)


# --- Buses, settings, world ----------------------------------------------------

func _test_buses_and_settings() -> void:
	print("== Buses, volume settings, underwater sound ==")
	for bus: String in ["Master", "Music", "SFX", "Ambience", "UI"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	for bus: StringName in [&"SFX", &"Ambience"]:
		_check(_audio._bus_effect(bus, "AudioEffectLowPassFilter") != null and _audio._bus_effect(bus, "AudioEffectReverb") != null
			and _audio._bus_effect(bus, "AudioEffectAmplify") != null, "%s has the underwater low-pass, the reverb and the gate" % bus)
	_check(_audio._bus_effect(&"Music", "AudioEffectAmplify") != null, "Music has the duck")
	var before: float = Game.get_volume("Music")
	Game.set_volume("Music", 0.5)
	var music_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	_check(absf(music_db - linear_to_db(0.5)) < 0.1, "the Music slider sets the bus volume (50%% = %.1f dB)" % music_db)
	Game.set_volume("Music", before)
	var world: WorldConfig = _stage.world
	var lowpass := _audio._bus_effect(&"SFX", "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
	var reverb := _audio._bus_effect(&"Ambience", "AudioEffectReverb") as AudioEffectReverb
	print("  world %s: low-pass %.0f Hz, reverb room %.2f wet %.2f" % [world.world_name, lowpass.cutoff_hz, reverb.room_size, reverb.wet])
	_check(is_equal_approx(lowpass.cutoff_hz, world.audio_lowpass_hz) and is_equal_approx(reverb.wet, world.audio_reverb_wet),
		"the WorldConfig sets the underwater low-pass and reverb")
	var camera: Camera2D = get_viewport().get_camera_2d()
	var listener: AudioListener2D = null
	for child: Node in camera.get_children():
		if child is AudioListener2D:
			listener = child as AudioListener2D
	_check(listener != null and listener.is_current(), "the shared camera is the listener")


func _test_catalog() -> void:
	print("== Sound catalog ==")
	var missing: PackedStringArray = PackedStringArray()
	for sound_name: String in REQUIRED_SOUNDS:
		if not _audio.has_sound(sound_name):
			missing.append(sound_name)
	_check(missing.is_empty(), "every sound the game asks for exists%s" % ("" if missing.is_empty() else " (missing: %s)" % ", ".join(missing)))
	print("  variants: player_move %d, amb_bubbles %d, amb_whale %d, creature_click %d, world_rock_fall %d" % [
		_audio.get_variant_count("player_move"), _audio.get_variant_count("amb_bubbles"), _audio.get_variant_count("amb_whale"),
		_audio.get_variant_count("creature_click"), _audio.get_variant_count("world_rock_fall")])
	_check(_audio.get_variant_count("player_move") == 3 and _audio.get_variant_count("amb_whale") == 3, "numbered files are variants of one sound")
	_check(_audio.get_bus("sting_shard") == &"Music" and _audio.get_bus("amb_whale_1") == &"Ambience" and _audio.get_bus("sword_impact") == &"SFX",
		"the bus comes from the name (sting -> Music, amb -> Ambience, the rest -> SFX)")
	var pitches: Array[float] = []
	for i: int in 12:
		var player := _audio.play("player_move", Vector2.ZERO) as AudioStreamPlayer2D
		pitches.append(player.pitch_scale)
		player.stop()
	_check(pitches.max() - pitches.min() > 0.02, "repeats get a random pitch (%.2f - %.2f)" % [pitches.min(), pitches.max()])
	_check(_audio.play("player_move") is AudioStreamPlayer and _audio.play("player_move", Vector2(10, 10)) is AudioStreamPlayer2D,
		"with a position the sound is positional")


func _test_hit_stop_and_duck() -> void:
	print("== Finisher hit-stop + ducking ==")
	var gate := _audio._bus_effect(&"SFX", "AudioEffectAmplify") as AudioEffectAmplify
	_heard.clear()
	_audio.play_after_silence("sword_finisher", _echo.global_position, 0.12)
	await _frames(2)
	_check(gate.volume_db <= _audio.silence_db + 0.1 and not "sword_finisher" in _heard, "the hit-stop silences the SFX first")
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _frames(3)
	print("  after the silence: gate %.0f dB, finisher played %s, music duck %.1f dB" % [gate.volume_db, "sword_finisher" in _heard, _audio.get_duck_db()])
	_check(is_zero_approx(gate.volume_db) and "sword_finisher" in _heard, "then the finisher booms")
	_check(_audio.get_duck_db() < -1.0, "and the music ducks under it")
	await get_tree().create_timer(_audio.duck_hold_time + _audio.duck_release_time + 0.3, true, false, true).timeout
	_check(_audio.get_duck_db() > -0.5, "the music comes back after the duck")


# --- Music --------------------------------------------------------------------

func _test_music_states() -> void:
	print("== Music states and stingers ==")
	await _build(0, 0)
	await _frames(int((_music.release_time + 0.5) * PHYSICS_FPS))
	_check(_music.state == MusicDirector.State.CALM, "calm with nothing around")
	var creature: Creature = _spawn(load("res://scenes/creature.tscn") as PackedScene, _open_spot(_echo.global_position, 300.0))
	creature.hear_noise(_echo.global_position + Vector2(400.0, 0.0), 5000.0)
	await _frames(5)
	_check(_music.state == MusicDirector.State.TENSION, "an investigating creature near the players = Tension")
	_stingers.clear()
	creature._spot(_echo)
	await _frames(5)
	_check(_music.state == MusicDirector.State.CHASE, "a chase = Chase")
	_check("sting_spotted" in _stingers, "with the spotted stinger")
	await _frames(int(_music.fade_time * PHYSICS_FPS))
	print("  layer gains in Chase: tension %.2f, chase %.2f" % [_music.get_layer_gain("tension"), _music.get_layer_gain("chase")])
	_check(_music.get_layer_gain("chase") > 0.5 and _music.get_layer_gain("tension") > 0.3, "the chase layer comes in on top of the tension layer")
	creature.queue_free()
	await _frames(int(_music.release_time * 0.5 * PHYSICS_FPS))
	_check(_music.state == MusicDirector.State.CHASE, "the chase music holds for a moment (no flapping)")
	await _frames(int((_music.release_time * 0.6 + 0.2) * PHYSICS_FPS))
	_check(_music.state == MusicDirector.State.CALM, "then it calms down")

	var lockdown: LockdownRoom = _builder.get_lockdown()
	if lockdown:
		_stingers.clear()
		lockdown.enabled = true
		lockdown.lock()
		await _frames(3)
		_check(_music.state == MusicDirector.State.INTENSE and "sting_lockdown" in _stingers, "the lockdown = Intense, with its stinger")
		lockdown.unlock()
		await _frames(3)
		_check("sting_doors_open" in _stingers, "the doors opening have their stinger")
	var escape: EscapeEvent = _game.get_node("EnvironmentLayer/EscapeEvent") as EscapeEvent
	await _build(0, 1)
	escape.start(30.0)
	await _frames(3)
	_check(_music.state == MusicDirector.State.INTENSE, "the collapse escape = Intense")
	escape.stop()

	await _build(0, 2)
	var boss: Creature = _builder.get_boss()
	_builder.open_exit()
	await _frames(3)
	_echo.global_position = NavigationServer2D.map_get_closest_point(get_viewport().world_2d.navigation_map, boss.global_position + Vector2(300.0, 0.0))
	await _frames(3)
	_check(_music.state == MusicDirector.State.BOSS, "the boss fight = Boss")
	_stingers.clear()
	_stage.level_won.emit()
	_check("sting_level_complete" in _stingers, "winning a level has its stinger")


# --- Creatures ------------------------------------------------------------------

func _test_creature_voices() -> void:
	print("== Creature voices ==")
	await _build(0, 0)
	var types: Dictionary = {
		"res://scenes/creature.tscn": ["creature_investigate_chitter", "creature_death"],
		"res://scenes/sentinel.tscn": ["sentinel_investigate_creak", "sentinel_death"],
		"res://scenes/boss_placeholder.tscn": ["boss_investigate", "boss_death"],
	}
	for path: String in types:
		var creature: Creature = _spawn(load(path) as PackedScene, _open_spot(_echo.global_position, 260.0))
		await _frames(2)
		_heard.clear()
		creature._investigate(creature.global_position + Vector2(200.0, 0.0))
		await _frames(2)
		var expected: String = types[path][0]
		var investigate_ok: bool = _heard.any(func(n: String) -> bool: return n.begins_with(expected))
		creature._spot(_echo)
		await _frames(2)
		var screech_ok: bool = _heard.any(func(n: String) -> bool: return n.ends_with("_screech"))
		_heard.clear()
		creature.take_damage(9999, _guardian, 0.0, 0.0)
		await _frames(1)
		print("  %-22s investigate: %s | screech: %s | death: %s" % [path.get_file(), investigate_ok, screech_ok, types[path][1] in _heard])
		_check(investigate_ok, "%s investigates with %s" % [path.get_file().get_basename(), expected])
		_check(screech_ok, "%s screeches when it starts a chase" % path.get_file().get_basename())
		_check(types[path][1] in _heard, "%s has its death sound" % path.get_file().get_basename())
		await _frames(10)
	# The light hunter never investigates: it stalks the Echo in the dark.
	var hunter: Creature = _spawn(load("res://scenes/light_hunter.tscn") as PackedScene, _open_spot(_echo.global_position, 400.0))
	_heard.clear()
	await _frames(int(1.0 * PHYSICS_FPS))
	print("  light hunter: stalking %s, heard %s" % [hunter.is_stalking(), _heard.filter(func(n: String) -> bool: return n.begins_with("creature_"))])
	_check(hunter.is_stalking() and "creature_investigate_call" in _heard, "the light hunter stalks with its call (not a screech)")
	hunter.queue_free()


# --- Players, world, ambience -------------------------------------------------

func _test_players() -> void:
	print("== Player sounds ==")
	await _build(0, 0)
	_heard.clear()
	_echo.health._invulnerable_left = 0.0
	_echo.health.take_hit(_echo.global_position + Vector2(30.0, 0.0))
	await _frames(1)
	_check("player_hurt" in _heard, "a hit = hurt")
	_stingers.clear()
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	await _frames(1)
	_check("player_downed" in _heard and "sting_downed" in _stingers, "downed = downed sound + stinger")
	_echo.health.revive()
	await _frames(1)
	_check("player_revive" in _heard, "revived = revive sound")
	_heard.clear()
	Input.action_press("p1_move_right")
	await _frames(int(1.5 * PHYSICS_FPS))
	Input.action_release("p1_move_right")
	_check(_heard.has("player_move"), "swimming makes soft swishes")
	var mending: PartnerMending = _game.get_node("MendLayer/PartnerMending") as PartnerMending
	_echo.health.set_segments(1.0)
	_guardian.global_position = _echo.global_position + Vector2(40.0, 0.0)
	await _frames(int(0.6 * PHYSICS_FPS))
	_check(mending.is_mending and mending.is_humming(), "mending hums")
	_guardian.global_position = _echo.global_position + Vector2(700.0, 0.0)
	await _frames(int((mending.fade_time + 0.3) * PHYSICS_FPS))
	_check(not mending.is_humming(), "the hum stops when they part")
	var pressure: PlayerPressure = _echo.pressure
	_check(pressure.alarm_stream.resource_path.ends_with("player_low_oxygen.wav"), "the low-oxygen warning is the new beep")
	var vignette: HurtVignette = _game.get_node("Hud/HurtVignette") as HurtVignette
	_check(vignette.heartbeat_stream.resource_path.ends_with("player_low_health.wav"), "the low-health heartbeat is the new one")
	var sonar: SonarAudio = _game.get_node("SonarAudio") as SonarAudio
	_check(sonar.ping_stream.resource_path.ends_with("pulse_ping.wav"), "the pulse uses the new ping with echoes")
	_heard.clear()
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	var distress: DistressPulse = _echo.get_node("DistressPulse") as DistressPulse
	distress.emit_pulse()
	_check("pulse_distress" in _heard, "the distress pulse has its muffled ping")
	_echo.health.revive()
	_echo.health.refill()


func _test_world() -> void:
	print("== World sounds ==")
	await _build(0, 1)
	var shards: Array[EchoShard] = _builder.get_shards().duplicate()
	await _frames(3)
	_check(not shards.is_empty() and shards[0].is_humming(), "an Echo Shard hums")
	_stingers.clear()
	var first: EchoShard = shards[0]
	_echo.global_position = first.global_position
	_guardian.global_position = first.global_position
	await _frames(3)
	_check(not first.is_humming() and first.pickup_stream.resource_path.ends_with("world_shard_pickup.wav"), "picked up: the hum stops, the chime plays")
	_check("sting_shard" in _stingers, "with the shard stinger")
	var lockdown_scene := load("res://scenes/lockdown_room.tscn") as PackedScene
	var lockdown := lockdown_scene.instantiate() as LockdownRoom
	_check(lockdown.slam_stream.resource_path.ends_with("world_barrier_close.wav") and lockdown.clear_stream.resource_path.ends_with("world_barrier_open.wav"),
		"the lockdown barriers use the new rock sounds")
	lockdown.free()
	var escape: EscapeEvent = _game.get_node("EnvironmentLayer/EscapeEvent") as EscapeEvent
	_heard.clear()
	escape.start(30.0)
	await _frames(int(2.0 * PHYSICS_FPS))
	_check(escape._rumble.playing and escape.rumble_stream.resource_path.ends_with("world_collapse_rumble.wav"), "the collapse rumbles (loop)")
	_check(_heard.has("world_rock_fall"), "and rocks fall around the camera")
	escape.stop()
	_check(not escape._rumble.playing, "the rumble stops with the collapse")


func _test_ambience() -> void:
	print("== Ambience ==")
	_check(_ambience.is_bed_playing(), "the ocean bed plays")
	_heard.clear()
	_ambience._small_left = 0.0
	_ambience._rare_left = 0.0
	await _frames(2)
	_check(_heard.has("amb_bubbles") and _heard.has("amb_whale"), "bubbles and (rare) whale groans play as one-shots")
	var world: WorldConfig = _stage.world
	print("  bubbles every %.0f-%.0f s, whales every %.0f-%.0f s" % [world.ambience_small_interval_min, world.ambience_small_interval_max,
		world.ambience_rare_interval_min, world.ambience_rare_interval_max])
	_check(world.ambience_rare_interval_min >= 30.0, "whales stay rare")


# --- Helpers ------------------------------------------------------------------

func _build(stage_index: int, level_index: int) -> void:
	_stage.stage_index = stage_index
	_stage._start_level(level_index)
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		if node != _builder.get_boss():
			node.remove_from_group("creatures")
			node.queue_free()
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	await _frames(12)
	for player: Player in [_echo, _guardian]:
		player.health._invulnerable_left = 999.0
		player.pressure.refill()


func _spawn(scene: PackedScene, at: Vector2) -> Creature:
	var creature := scene.instantiate() as Creature
	creature.position = _builder.to_local(at)
	# The test decides when it spots someone.
	creature.spot_distance = 0.0
	creature.pulse_spot_distance = 0.0
	_builder._level.add_child(creature)
	(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)
	return creature


func _open_spot(center: Vector2, distance: float) -> Vector2:
	var map: RID = get_viewport().world_2d.navigation_map
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	for i: int in 16:
		var candidate: Vector2 = NavigationServer2D.map_get_closest_point(map, center + Vector2.from_angle(TAU * i / 16.0) * distance)
		var query := PhysicsRayQueryParameters2D.create(center, candidate, 1)
		if space.intersect_ray(query).is_empty() and candidate.distance_to(center) > distance * 0.7:
			return candidate
	return NavigationServer2D.map_get_closest_point(map, center + Vector2(distance, 0.0))


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("    [%s] %s" % ["ok" if ok else "FAIL", label])
