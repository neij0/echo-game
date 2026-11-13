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
## - Each stage's level 2 (LevelDefinition.escape_event): the last shard starts
##   the collapse escape (EscapeEvent): reach the ancient light before the
##   timer (per mode) runs out, or every player is downed.
## - Lockdown waves (LockdownRoom) and Sentinels count as creatures for the stats.
## - Picking up an Echo Shard restores shard_heal_segments of health to every
##   player who is not downed. Health carries over between levels of a stage.
## - Every player downed at the same time: Calm restarts the current level,
##   Challenge restarts the stage from level 1. Every retry reshuffles the
##   creatures, corals and stations (new spawn seed).
## - Skills: after every level each player picks from an offer (SkillOffer,
##   SkillChoiceScreen); the picks go into the SkillLoadout, which every
##   player's PlayerSkills reads. A retry restores the skills owned at the start
##   of the level it restarts; the loadout is saved with the stage
##   (Game.complete_stage) and reset when a new world starts.
## - Pause (PauseMenu): only while playing (can_pause); restart_level() is its
##   "Restart level".

signal player_registered(player: Player)
signal level_started(level_index: int)
## Emitted between two levels, before the next one is built. The skill choice
## screen will hook in here (see _between_levels).
signal between_levels(next_level_index: int)
signal stage_completed(stage_index: int)
## Emitted when a level starts and whenever an Echo Shard is collected.
signal shards_changed(collected: int, total: int)

## Playtest start on a boss level (test_start_at, F6 only).
enum TestStart { LEVEL_START, ARENA_DOOR, IN_ARENA }
## Emitted the moment a level is won (the ancient light wakes or the boss
## falls), before the level-cleared screen (music stinger).
signal level_won
## Emitted after the skill choice: Player -> Array[SkillDefinition] picked.
signal skills_chosen(picks: Dictionary)
## Emitted when a faded level change (next level, retry, Restart) has faded
## back in and the game runs again.
signal transition_finished

## The world played. Started from the menus: the Game autoload's current
## world. On its own (F6): loaded from test_world_path when the scene starts
## (not a resource of the scene: a world still references scenes whose scripts
## are in legacy2d/, which would show as broken dependencies in the editor).
@export var world: WorldConfig
@export_file("*.tres") var test_world_path: String = "res://worlds/ocean.tres"
## Stage played when game.tscn runs on its own (0-based).
@export var test_stage_index: int = 0
## Mode used when game.tscn runs on its own.
@export var test_mode: SaveData.Mode = SaveData.Mode.CALM
## Level the stage starts at when game.tscn runs on its own (0-based; 2 = the
## boss level). A Challenge retry also goes back to it.
@export var test_level_index: int = 0
## Where a boss level starts when game.tscn runs on its own (with
## test_level_index on the boss level): LEVEL_START = its start room;
## ARENA_DOOR = every shard counted, the door open, the players just outside
## it; IN_ARENA = the same, the players already inside (the boss wakes).
@export var test_start_at: TestStart = TestStart.LEVEL_START
## How far from the arena door's middle the players are put (outside / inside;
## world units).
@export var test_door_outside_distance: float = 3.0
@export var test_door_inside_distance: float = 4.6
## Each player stands this far to one side of that spot.
@export var test_door_side_distance: float = 0.6
@export var level_builder: LevelBuilder
@export var awareness: DepthAwareness
@export var end_screen: EndScreen
@export var escape_event: EscapeEvent
@export var skill_choice_screen: SkillChoiceScreen
## Skills owned when game.tscn runs on its own (F6), for playtesting:
## "skill_id" or "skill_id:rank" (a shared skill goes to both players).
@export var test_skills: PackedStringArray = PackedStringArray()
## Seconds between activating the ancient light (or the boss falling) and the
## next screen.
@export var victory_delay: float = 3.0
## Seconds the "Level cleared" screen stays before the next level is built.
@export var level_cleared_time: float = 2.5
## The short fade through black round every level change (next level, retry,
## Restart): the level is built while the screen is black, so its build time
## (~0.5-1.2 s) never shows as a frozen frame. Seconds out / in; off = cut.
@export var level_fade_enabled: bool = true
@export var level_fade_out_time: float = 0.3
@export var level_fade_in_time: float = 0.45
## Frames drawn behind the black after a build (the hitch passes) before the fade in.
@export var level_fade_settle_frames: int = 2

@export_group("Modes")
## Calm mode: the pressure meter lasts this many times longer.
@export var calm_drain_multiplier: float = 1.25
## Calm retry: each player gets back the meter they had when the level
## started, but at least this share (0-1) of a full meter.
@export_range(0.0, 1.0) var retry_min_pressure: float = 0.5
## Calm retry: each player gets back the health they had when the level
## started, but at least this many segments.
@export var retry_min_health_segments: float = 2.0

@export_group("Health")
## Health segments every non-downed player gets back per Echo Shard.
@export var shard_heal_segments: float = 1.0

var players: Array[Player] = []
var stage_index: int = 0
var level_index: int = 0
var mode: SaveData.Mode = SaveData.Mode.CALM
var stage_time: float = 0.0
## Stage summary counts. Only what counts for the result: a retry rolls them
## back to the start of the level (Calm) / the stage (Challenge), so failed
## attempts are not added up. hits_taken = real damage events only
## (PlayerHealth.hit_taken: not blocked, not invulnerable, never a push).
var pulses_used: int = 0
var hits_taken: int = 0
var creatures_killed: int = 0
## [pulses_used, hits_taken, creatures_killed] when the current level started.
var _level_start_counts: Array[int] = [0, 0, 0]
var shards_collected: int = 0
var shards_total: int = 0
## Paused on a defeat / stage summary screen.
var is_over: bool = false
var _is_changing_level: bool = false
## True during a faded level change (until transition_finished).
var _transitioning: bool = false
## Each player's meter (0-1) when the current level started (Calm retries).
var _level_start_pressure: Dictionary = {}
## Each player's health (segments) when the current level started (Calm retries).
var _level_start_health: Dictionary = {}
## The skills owned right now, and copies for retries (level / stage start).
var loadout: SkillLoadout = SkillLoadout.new()
var _level_start_loadout: SkillLoadout = SkillLoadout.new()
var _stage_start_loadout: SkillLoadout = SkillLoadout.new()
var _skill_rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.started_from_menu and Game.get_current_world():
		world = Game.get_current_world()
		stage_index = Game.save.stage_index
		mode = Game.get_mode()
	else:
		stage_index = test_stage_index
		mode = test_mode
		if world == null and test_world_path != "":
			world = load(test_world_path) as WorldConfig
	if level_builder:
		level_builder.world = world
		level_builder.level_built.connect(_on_level_built)
	if end_screen:
		end_screen.restart_requested.connect(_retry_faded)
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
		player.health.set_challenge_mode(mode == SaveData.Mode.CHALLENGE)
	# DistressPulse, CloseSense, ReviveHelper: their values depend on the mode.
	get_tree().call_group("mode_listeners", "set_challenge_mode", mode == SaveData.Mode.CHALLENGE)
	_skill_rng.randomize()
	loadout = _initial_loadout()
	_stage_start_loadout = loadout.copy()
	_apply_loadout()
	_start_level(_first_level_index())


## The level a stage (or a Challenge retry) starts at: 0, or test_level_index
## when game.tscn runs on its own.
func _first_level_index() -> int:
	if Game.started_from_menu:
		return 0
	return clampi(test_level_index, 0, get_level_count() - 1)


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
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		if player.health.is_downed:
			player.health.revive()
		_level_start_pressure[player] = player.pressure.get_ratio()
		_level_start_health[player] = player.health.value
	_level_start_loadout = loadout.copy()
	_level_start_counts = [pulses_used, hits_taken, creatures_killed]
	if awareness:
		awareness.reset()
	if escape_event:
		escape_event.stop()
	_apply_test_start()
	var camera: SharedCamera = SharedCamera.find(get_tree())
	if camera:
		camera.snap_to_players()
	level_started.emit(index)


## F6 playtests of a boss: every shard counted, the arena door open and the
## players at the door (outside) or already inside (test_start_at).
func _apply_test_start() -> void:
	if Game.started_from_menu or test_start_at == TestStart.LEVEL_START or level_builder == null:
		return
	if level_index != _first_level_index() or not is_boss_level():
		return
	var door: ShardDoor = level_builder.get_exit_door()
	# The boss, or the light standing in for it until the boss is ported.
	var inside: Node3D = level_builder.get_boss() if level_builder.get_boss() else level_builder.get_goal()
	if door == null or inside == null:
		return
	for shard: EchoShard in level_builder.get_shards():
		if is_instance_valid(shard):
			shard.queue_free()
	shards_collected = shards_total
	level_builder.open_exit()
	_update_exit_lock()
	var door_center: Vector3 = door.global_position + door.center
	# Straight through the door (across its long side), towards the arena.
	var inward: Vector3 = door.along.cross(Vector3.UP)
	if inward.dot(inside.global_position - door_center) < 0.0:
		inward = -inward
	var distance: float = test_door_inside_distance if test_start_at == TestStart.IN_ARENA else -test_door_outside_distance
	var spot: Vector3 = door_center + inward * distance
	for player: Player in players:
		var side: float = -1.0 if player.player_number == 1 else 1.0
		player.global_position = spot + door.along * side * test_door_side_distance
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()


func _on_level_built(_index: int) -> void:
	for creature: Creature in level_builder.get_creatures():
		creature.killed.connect(_on_creature_killed)
	get_tree().call_group("creatures", "set_challenge_mode", mode == SaveData.Mode.CHALLENGE)
	# The level's own mode listeners (LockdownRoom) exist only from now on.
	get_tree().call_group("mode_listeners", "set_challenge_mode", mode == SaveData.Mode.CHALLENGE)
	var lockdown: LockdownRoom = level_builder.get_lockdown()
	if lockdown:
		lockdown.wave_spawned.connect(func(creature: Creature) -> void: creature.killed.connect(_on_creature_killed))
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
	for player: Player in players:
		player.health.heal(shard_heal_segments + player.skills.get_bonus("shard_heal_add"))
	_update_exit_lock()
	if shards_collected >= shards_total:
		level_builder.open_exit()
		_start_escape_if_planned()


## The stage's level-2 twist: the collapse escape after the last shard.
func _start_escape_if_planned() -> void:
	var definition: LevelDefinition = world.get_level(stage_index, level_index) if world else null
	if escape_event and definition and definition.escape_event:
		escape_event.start(definition.get_escape_time(mode == SaveData.Mode.CHALLENGE))


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


func _on_pulse_emitted(origin: Vector3, player: Player) -> void:
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
			var start_health: float = float(_level_start_health.get(player, player.health.get_max_value()))
			player.health.set_segments(maxf(start_health, retry_min_health_segments))
		loadout = _level_start_loadout.copy()
		_apply_loadout()
		_restore_counts(_level_start_counts)
		_start_level(level_index)
	else:
		for player: Player in players:
			player.pressure.refill()
			player.health.refill()
		loadout = _stage_start_loadout.copy()
		_apply_loadout()
		_restore_counts([0, 0, 0])
		_start_level(_first_level_index())
	get_tree().paused = false


## The defeat screen's retry: the level (or stage) is rebuilt behind a fade
## through black.
func _retry_faded() -> void:
	_transitioning = true
	_is_changing_level = true
	await _fade_out()
	if end_screen:
		end_screen.hide_screen()
	_retry()
	await _settle_and_fade_in()
	_is_changing_level = false


## Rolls the summary counts back (retries: failed attempts do not count).
func _restore_counts(counts: Array[int]) -> void:
	pulses_used = counts[0]
	hits_taken = counts[1]
	creatures_killed = counts[2]


## The pause menu's "Restart level". Calm: the current level again, with the
## meters, health and skills every player had when it started. Challenge: the
## whole stage from level 1, the same as both players downed (full meters and
## health, the skills of the stage start).
func restart_level() -> void:
	is_over = false
	_is_changing_level = false
	Engine.time_scale = 1.0
	if mode == SaveData.Mode.CHALLENGE:
		_retry()
		return
	for player: Player in players:
		player.pressure.value = player.pressure.max_value * float(_level_start_pressure.get(player, 1.0))
		player.pressure.ensure_ratio(0.0)
		player.health.set_segments(float(_level_start_health.get(player, player.health.get_max_value())))
	loadout = _level_start_loadout.copy()
	_apply_loadout()
	_restore_counts(_level_start_counts)
	_start_level(level_index)
	get_tree().paused = false


## restart_level behind a fade through black (the pause menu's Restart):
## when_covered runs once the screen is black (the menu hides then).
func restart_level_faded(when_covered: Callable = Callable()) -> void:
	_transitioning = true
	_is_changing_level = true
	await _fade_out()
	if when_covered.is_valid():
		when_covered.call()
	restart_level()
	_is_changing_level = true
	await _settle_and_fade_in()
	_is_changing_level = false


## True while a level is being played (no defeat / summary / level change).
func can_pause() -> bool:
	return not is_over and not _is_changing_level and not get_tree().paused


## True during a faded level change (tests wait for transition_finished).
func is_transitioning() -> bool:
	return _transitioning


func _fade_out() -> void:
	if level_fade_enabled and Game.fader:
		await Game.fader.fade_out(level_fade_out_time)


func _fade_in() -> void:
	if level_fade_enabled and Game.fader:
		await Game.fader.fade_in(level_fade_in_time)


## After a level was built behind the black: a few frames for the hitch (still
## paused), then the game runs again while the black lifts.
func _settle_and_fade_in() -> void:
	get_tree().paused = true
	for i: int in level_fade_settle_frames:
		await get_tree().process_frame
	get_tree().paused = false
	await _fade_in()
	_transitioning = false
	transition_finished.emit()


## True when a skill choice comes after the current level.
func _has_skill_offer() -> bool:
	var size: Vector2i = SkillOffer.get_offer_size(world, stage_index, level_index)
	return Game.skill_catalog != null and skill_choice_screen != null and size.x > 0 and size.y > 0


# --- Clearing levels and the stage ------------------------------------------

func _on_ancient_light_activated() -> void:
	if is_over or _is_changing_level:
		return
	_is_changing_level = true
	if escape_event:
		escape_event.stop()
	level_won.emit()
	await get_tree().create_timer(victory_delay).timeout
	if level_index + 1 >= get_level_count():
		# A stage without a boss level ends on its last ancient light.
		get_tree().paused = true
		await _offer_skills()
		_complete_stage(false)
		return
	get_tree().paused = true
	_transitioning = true
	if end_screen:
		end_screen.show_level_cleared(level_index + 1, get_level_count())
	await get_tree().create_timer(level_cleared_time, true).timeout
	await _fade_out()
	if end_screen:
		end_screen.hide_screen()
	if _has_skill_offer():
		# The skill choice opens (pulse wipe) while the black lifts, and the
		# screen goes black again once both picked.
		_fade_in()
		await _between_levels(level_index + 1)
		await _fade_out()
	else:
		await _between_levels(level_index + 1)
	# The meter carries over between levels, topped up a little each time.
	for player: Player in players:
		player.pressure.add_ratio(player.pressure.level_refill_ratio)
	_start_level(level_index + 1)
	await _settle_and_fade_in()
	_is_changing_level = false


func _on_boss_killed() -> void:
	if is_over or _is_changing_level:
		return
	_is_changing_level = true
	level_won.emit()
	await get_tree().create_timer(victory_delay).timeout
	get_tree().paused = true
	await _offer_skills()
	_complete_stage(true)


func _complete_stage(beat_boss: bool) -> void:
	is_over = true
	get_tree().paused = true
	var saved: bool = false
	if Game.started_from_menu:
		Game.complete_stage(loadout)
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
		# The Journey screen lights the island up one step; its Continue plays on.
		Game.go_to_journey()


## Runs between two levels (paused): the skill choice.
func _between_levels(next_level_index: int) -> void:
	between_levels.emit(next_level_index)
	await _offer_skills()
	await get_tree().process_frame


# --- Skills -----------------------------------------------------------------

## The skill choice after the current level (paused). Nothing after the world's
## final level, or without a catalog / screen.
func _offer_skills() -> void:
	var catalog: SkillCatalog = Game.skill_catalog
	var size: Vector2i = SkillOffer.get_offer_size(world, stage_index, level_index)
	if catalog == null or skill_choice_screen == null or size.x <= 0 or size.y <= 0:
		return
	var world_index: int = Game.get_world_index(world.world_id)
	var offers: Dictionary = {}
	var pick_counts: Dictionary = {}
	for player: Player in players:
		var offer: Array[SkillDefinition] = SkillOffer.build(catalog, loadout, player.get_character_key(), world_index, size.x, _skill_rng)
		offers[player] = offer
		pick_counts[player] = mini(size.y, offer.size())
	# The HUD hides behind the choice (its texts would show through the cards).
	var huds: Array[Node] = get_tree().get_nodes_in_group("hud")
	var shown: Array[CanvasLayer] = []
	for node: Node in huds:
		var hud := node as CanvasLayer
		if hud and hud.visible:
			hud.visible = false
			shown.append(hud)
	var picks: Dictionary = await skill_choice_screen.choose(players, offers, pick_counts, world)
	for hud: CanvasLayer in shown:
		if is_instance_valid(hud):
			hud.visible = true
	apply_picks(picks)


## Adds the picked skills to the loadout (fallbacks are applied once instead).
func apply_picks(picks: Dictionary) -> void:
	for player: Player in picks:
		for definition: SkillDefinition in picks[player]:
			if definition.is_fallback:
				_apply_fallback(player, definition)
			else:
				loadout.add_rank(player.get_character_key(), definition)
	_apply_loadout()
	skills_chosen.emit(picks)


## A fallback's values: "pressure_refill" (share of a full meter), "heal_add"
## (health segments).
func _apply_fallback(player: Player, definition: SkillDefinition) -> void:
	player.pressure.add_ratio(definition.get_value("pressure_refill", 1))
	player.health.heal(definition.get_value("heal_add", 1))


## Gives every player the skills of the current loadout.
func _apply_loadout() -> void:
	for player: Player in players:
		player.skills.set_skills(loadout.get_entries(player.get_character_key()), Game.skill_catalog)


## Started from the menus: the saved skills (if they belong to this world).
## Run on its own (F6): test_skills.
func _initial_loadout() -> SkillLoadout:
	var world_id: String = world.world_id if world else ""
	if Game.started_from_menu:
		var saved: SkillLoadout = Game.save.skills
		return saved.copy() if saved and saved.world_id == world_id else SkillLoadout.new(world_id)
	var result := SkillLoadout.new(world_id)
	for entry: String in test_skills:
		var parts: PackedStringArray = entry.split(":")
		var definition: SkillDefinition = Game.skill_catalog.find(parts[0].strip_edges()) if Game.skill_catalog else null
		if definition == null:
			push_warning("StageManager: unknown test skill " + entry)
			continue
		var rank: int = clampi(int(parts[1]) if parts.size() > 1 else 1, 1, definition.max_rank)
		for character: String in SkillLoadout.CHARACTERS:
			if definition.is_for(character):
				result.set_rank(character, definition.id, rank)
	return result
