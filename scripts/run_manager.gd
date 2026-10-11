class_name RunManager
extends Node
## The run's core loop. A run = the world's stages in order (3 in the Ocean).
## Registers the players, gives every "world_listeners" node the WorldConfig,
## asks the StageBuilder for each stage, counts run stats, alerts creatures and
## awareness on every pulse. Activating the ancient light clears the stage (a
## short "Stage cleared" screen, then the next stage); clearing the last stage
## wins the run. When every player is downed at the same time, the run is over
## and restarts from stage 1 with a new seed.

signal player_registered(player: Player)
signal stage_started(stage_index: int)
## Emitted between two stages, before the next one is built. The skill choice
## screen will hook in here (see _between_stages).
signal between_stages(next_stage_index: int)

@export var world: WorldConfig
@export var stage_builder: StageBuilder
@export var awareness: DepthAwareness
@export var end_screen: EndScreen
## Seconds between activating the ancient light and the next screen.
@export var victory_delay: float = 3.0
## Seconds the "Stage cleared" screen stays before the next stage is built.
@export var stage_cleared_time: float = 2.5

var players: Array[Player] = []
var stage_index: int = 0
var stages_cleared: int = 0
var run_time: float = 0.0
var pulses_used: int = 0
var hits_taken: int = 0
var creatures_killed: int = 0
var is_over: bool = false
var _is_changing_stage: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if end_screen:
		end_screen.restart_requested.connect(restart)
	if stage_builder:
		stage_builder.stage_built.connect(_on_stage_built)
	# Deferred so every Player and listener in the scene has run _ready.
	_start_run.call_deferred()


func _process(delta: float) -> void:
	if not is_over and not get_tree().paused:
		run_time += delta


func _start_run() -> void:
	if world:
		get_tree().call_group("world_listeners", "apply_world", world)
	var scene_players: Array[Player] = Players.all(get_tree())
	scene_players.sort_custom(func(a: Player, b: Player) -> bool: return a.player_number < b.player_number)
	for player: Player in scene_players:
		register_player(player)
	_start_stage(0)


func register_player(player: Player) -> void:
	if player in players:
		return
	players.append(player)
	player.pulse_emitted.connect(_on_pulse_emitted.bind(player))
	player.health.hit_taken.connect(_on_hit_taken)
	player.health.downed.connect(_on_player_downed)
	player_registered.emit(player)


func get_stage_count() -> int:
	return world.get_stage_count() if world else 1


func restart() -> void:
	get_tree().paused = false
	# In case a hit-stop (SwordAbility) was still running.
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _start_stage(index: int) -> void:
	stage_index = index
	if stage_builder:
		stage_builder.build_stage(index)
	for player: Player in players:
		player.global_position = stage_builder.get_spawn_position(player.player_number) if stage_builder else player.global_position
		player.velocity = Vector2.ZERO
		if player.health.is_downed:
			player.health.revive()
		# The meter carries over between stages, topped up a little each time.
		if index > 0:
			player.pressure.add_ratio(player.pressure.stage_refill_ratio)
	if awareness:
		awareness.reset()
	var camera := get_viewport().get_camera_2d() as SharedCamera
	if camera:
		camera.snap_to_players()
	stage_started.emit(index)


func _on_stage_built(_index: int) -> void:
	for creature: Creature in stage_builder.get_creatures():
		creature.killed.connect(_on_creature_killed)
	var goal: AncientLight = stage_builder.get_goal()
	if goal:
		goal.activated.connect(_on_ancient_light_activated)


func _on_pulse_emitted(origin: Vector2, player: Player) -> void:
	pulses_used += 1
	if awareness:
		awareness.add_pulse()
	get_tree().call_group("creatures", "hear_pulse", origin, player)


func _on_hit_taken() -> void:
	hits_taken += 1


func _on_creature_killed() -> void:
	creatures_killed += 1


func _on_player_downed(_cause: PlayerHealth.Cause) -> void:
	if is_over or _is_changing_stage:
		return
	for player: Player in players:
		if not player.health.is_downed:
			return
	# Everyone is down at the same time: the run is over (back to stage 1).
	is_over = true
	get_tree().paused = true
	if end_screen:
		end_screen.show_defeat(players, stage_index + 1, get_stage_count())


func _on_ancient_light_activated() -> void:
	if is_over or _is_changing_stage:
		return
	stages_cleared = stage_index + 1
	if stages_cleared >= get_stage_count():
		is_over = true
		await get_tree().create_timer(victory_delay).timeout
		get_tree().paused = true
		if end_screen:
			end_screen.show_victory(run_time, pulses_used, hits_taken, creatures_killed, stages_cleared, get_stage_count(), players)
		return

	_is_changing_stage = true
	await get_tree().create_timer(victory_delay).timeout
	get_tree().paused = true
	if end_screen:
		end_screen.show_stage_cleared(stages_cleared, get_stage_count())
	await get_tree().create_timer(stage_cleared_time, true).timeout
	if end_screen:
		end_screen.hide_screen()
	await _between_stages(stage_index + 1)
	_start_stage(stage_index + 1)
	get_tree().paused = false
	_is_changing_stage = false


## HOOK for the next step: the skill choice screen goes here. It should show the
## choice while the game is paused and return once both players picked, e.g.
## `await skill_screen.choose(players)`. Nothing to choose yet.
func _between_stages(next_stage_index: int) -> void:
	between_stages.emit(next_stage_index)
	await get_tree().process_frame
