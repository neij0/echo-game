class_name StageManager
extends Node
## Plays one stage of a world: its levels in order (3 per stage). Registers the
## players, gives every "world_listeners" node the WorldConfig, asks the
## LevelBuilder for each level, counts the stage stats, alerts creatures and
## awareness on every pulse.
## - Every level has Echo Shards: the exit stays locked until all of them are
##   collected (the ancient light, or the boss arena's door).
## - Activating the ancient light clears a level (short "Level cleared" screen,
##   the between-levels hook, then the next level).
## - The last level ends in a boss arena: beating the boss completes the stage,
##   saves the progress (Game autoload) and shows the summary. Its Continue
##   button starts the next stage, or the story screen after a world's last stage.
## - Every player downed at the same time: Calm restarts the current level,
##   Challenge restarts the stage from level 1. Every retry reshuffles the
##   creatures, corals and stations (new spawn seed).

signal player_registered(player: Player)
signal level_started(level_index: int)
## Emitted between two levels, before the next one is built. The skill choice
## screen will hook in here (see _between_levels).
signal between_levels(next_level_index: int)
signal stage_completed(stage_index: int)
## Emitted when a level starts and whenever an Echo Shard is collected.
signal shards_changed(collected: int, total: int)

## Used when game.tscn runs on its own (F6). Started from the menus, the Game
## autoload's current world and stage are used instead.
@export var world: WorldConfig
## Stage played when game.tscn runs on its own (0-based).
@export var test_stage_index: int = 0
## Mode used when game.tscn runs on its own.
@export var test_mode: SaveData.Mode = SaveData.Mode.CALM
@export var level_builder: LevelBuilder
@export var awareness: DepthAwareness
@export var end_screen: EndScreen
## Seconds between activating the ancient light (or the boss falling) and the
## next screen.
@export var victory_delay: float = 3.0
## Seconds the "Level cleared" screen stays before the next level is built.
@export var level_cleared_time: float = 2.5

@export_group("Modes")
## Calm mode: the pressure meter lasts this many times longer.
@export var calm_drain_multiplier: float = 1.25
## Calm retry: each player gets back the meter they had when the level
## started, but at least this share (0-1) of a full meter.
@export_range(0.0, 1.0) var retry_min_pressure: float = 0.5

var players: Array[Player] = []
var stage_index: int = 0
var level_index: int = 0
var mode: SaveData.Mode = SaveData.Mode.CALM
var stage_time: float = 0.0
var pulses_used: int = 0
var hits_taken: int = 0
var creatures_killed: int = 0
var shards_collected: int = 0
var shards_total: int = 0
## Paused on a defeat / stage summary screen.
var is_over: bool = false
var _is_changing_level: bool = false
## Each player's meter (0-1) when the current level started (Calm retries).
var _level_start_pressure: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.started_from_menu and Game.get_current_world():
		world = Game.get_current_world()
		stage_index = Game.save.stage_index
		mode = Game.get_mode()
	else:
		stage_index = test_stage_index
		mode = test_mode
	if level_builder:
		level_builder.world = world
		level_builder.level_built.connect(_on_level_built)
	if end_screen:
		end_screen.restart_requested.connect(_retry)
		end_screen.continue_requested.connect(_on_continue_pressed)
	# Deferred so every Player and listener in the scene has run _ready.
	_start_stage.call_deferred()


func _process(delta: float) -> void:
	if not is_over and not get_tree().paused:
		stage_time += delta


func _start_stage() -> void:
	if world:
		get_tree().call_group("world_listeners", "apply_world", world)
		# Per-stage values (lighting).
		get_tree().call_group("stage_listeners", "apply_stage", world.get_stage(stage_index))
	var scene_players: Array[Player] = Players.all(get_tree())
	scene_players.sort_custom(func(a: Player, b: Player) -> bool: return a.player_number < b.player_number)
	for player: Player in scene_players:
		register_player(player)
		player.pressure.drain_multiplier = calm_drain_multiplier if mode == SaveData.Mode.CALM else 1.0
	_start_level(0)


func register_player(player: Player) -> void:
	if player in players:
		return
	players.append(player)
	player.pulse_emitted.connect(_on_pulse_emitted.bind(player))
	player.health.hit_taken.connect(_on_hit_taken)
	player.health.downed.connect(_on_player_downed)
	player_registered.emit(player)


func get_level_count() -> int:
	return world.get_level_count(stage_index) if world else 1


func is_boss_level() -> bool:
	return world != null and world.get_level(stage_index, level_index).is_boss_level()


## Builds the level (new spawn seed every time) and puts the players at its
## start. The pressure meters are set by the caller before this.
func _start_level(index: int) -> void:
	level_index = index
	if level_builder:
		level_builder.build_level(world.get_level(stage_index, index), index, get_level_count(),
			world.get_global_level_index(stage_index, index))
	for player: Player in players:
		player.global_position = level_builder.get_spawn_position(player.player_number) if level_builder else player.global_position
		player.velocity = Vector2.ZERO
		if player.health.is_downed:
			player.health.revive()
		_level_start_pressure[player] = player.pressure.get_ratio()
	if awareness:
		awareness.reset()
	var camera := get_viewport().get_camera_2d() as SharedCamera
	if camera:
		camera.snap_to_players()
	level_started.emit(index)


func _on_level_built(_index: int) -> void:
	for creature: Creature in level_builder.get_creatures():
		creature.killed.connect(_on_creature_killed)
	get_tree().call_group("creatures", "set_challenge_mode", mode == SaveData.Mode.CHALLENGE)
	var goal: AncientLight = level_builder.get_goal()
	if goal:
		goal.activated.connect(_on_ancient_light_activated)
	var boss: Creature = level_builder.get_boss()
	if boss:
		boss.killed.connect(_on_boss_killed)
	var shards: Array[EchoShard] = level_builder.get_shards()
	for shard: EchoShard in shards:
		shard.collected.connect(_on_shard_collected)
	shards_collected = 0
	shards_total = shards.size()
	_update_exit_lock()


func _on_shard_collected(_shard: EchoShard) -> void:
	shards_collected += 1
	_update_exit_lock()
	if shards_collected >= shards_total:
		level_builder.open_exit()


## Shows the progress on the exit (sockets) and tells the HUD.
func _update_exit_lock() -> void:
	var goal: AncientLight = level_builder.get_goal()
	if goal:
		goal.set_shard_progress(shards_collected, shards_total)
	var door: ShardDoor = level_builder.get_exit_door()
	if door:
		door.set_shard_progress(shards_collected, shards_total)
		if shards_total == 0:
			level_builder.open_exit()
	shards_changed.emit(shards_collected, shards_total)


func _on_pulse_emitted(origin: Vector2, player: Player) -> void:
	pulses_used += 1
	if awareness:
		awareness.add_pulse()
	get_tree().call_group("creatures", "hear_pulse", origin, player)


func _on_hit_taken() -> void:
	hits_taken += 1


func _on_creature_killed() -> void:
	creatures_killed += 1


# --- Defeat and retries -----------------------------------------------------

func _on_player_downed(_cause: PlayerHealth.Cause) -> void:
	if is_over or _is_changing_level:
		return
	for player: Player in players:
		if not player.health.is_downed:
			return
	# Everyone is down at the same time.
	is_over = true
	get_tree().paused = true
	if end_screen:
		end_screen.show_defeat(players, stage_index + 1, level_index + 1, get_level_count(), mode)


## After a defeat. Calm: the same level again. Challenge: level 1 of the stage.
func _retry() -> void:
	is_over = false
	# In case a hit-stop (SwordAbility) was still running.
	Engine.time_scale = 1.0
	if mode == SaveData.Mode.CALM:
		for player: Player in players:
			var start_ratio: float = float(_level_start_pressure.get(player, 1.0))
			player.pressure.value = player.pressure.max_value * start_ratio
			player.pressure.ensure_ratio(retry_min_pressure)
		_start_level(level_index)
	else:
		for player: Player in players:
			player.pressure.refill()
		_start_level(0)
	get_tree().paused = false


# --- Clearing levels and the stage ------------------------------------------

func _on_ancient_light_activated() -> void:
	if is_over or _is_changing_level:
		return
	_is_changing_level = true
	await get_tree().create_timer(victory_delay).timeout
	if level_index + 1 >= get_level_count():
		# A stage without a boss level ends on its last ancient light.
		_complete_stage(false)
		return
	get_tree().paused = true
	if end_screen:
		end_screen.show_level_cleared(level_index + 1, get_level_count())
	await get_tree().create_timer(level_cleared_time, true).timeout
	if end_screen:
		end_screen.hide_screen()
	await _between_levels(level_index + 1)
	# The meter carries over between levels, topped up a little each time.
	for player: Player in players:
		player.pressure.add_ratio(player.pressure.level_refill_ratio)
	_start_level(level_index + 1)
	get_tree().paused = false
	_is_changing_level = false


func _on_boss_killed() -> void:
	if is_over or _is_changing_level:
		return
	_is_changing_level = true
	await get_tree().create_timer(victory_delay).timeout
	_complete_stage(true)


func _complete_stage(beat_boss: bool) -> void:
	is_over = true
	get_tree().paused = true
	var saved: bool = false
	if Game.started_from_menu:
		Game.complete_stage()
		saved = true
	stage_completed.emit(stage_index)
	if end_screen:
		end_screen.show_stage_cleared(stage_index + 1, beat_boss, saved, stage_time, pulses_used, hits_taken, creatures_killed, players)


## The stage summary's Continue button.
func _on_continue_pressed() -> void:
	if not Game.started_from_menu:
		# Started on its own (F6): just play the stage again.
		get_tree().paused = false
		get_tree().reload_current_scene()
	elif Game.finished_world_id != "":
		Game.go_to_story()
	else:
		Game.play_current()


## HOOK for the next step: the skill choice screen goes here. It should show the
## choice while the game is paused and return once both players picked, e.g.
## `await skill_screen.choose(players)`, then store the picks in
## Game.save.skills. Nothing to choose yet.
func _between_levels(next_level_index: int) -> void:
	between_levels.emit(next_level_index)
	await get_tree().process_frame
