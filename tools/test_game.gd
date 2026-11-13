extends Node
## Headless checks of the real game.tscn in 3D (through GameSceneLoader): the
## stage starts (world, players, the full HUD), the level flow (shards unlock
## the light, Level cleared, the fade, the skill choice, the next level with
## the picks owned), defeat and retries (Calm: the level again; Challenge: the
## stage from level 1), the lockdown (doorways close, the wave, the oxygen
## rules, the navigation rebake, clearing it), the collapse escape (frenzy,
## timer, timing out), a boss level (arena door, vents, the stand-in light
## ends the stage, the summary), the three active skills (Lure Pulse, Shield,
## Dash) and the pause menu.
## godot --headless --path . --fixed-fps 60 res://tools/test_game.tscn
## Exits with 1 when a check fails.

var _failures: int = 0
var _checks: int = 0
var _game: Node3D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("TEST GAME (3D)")
	await _test_start_and_hud()
	await _test_level_flow_and_skills()
	await _test_defeat_and_retry()
	await _test_lockdown()
	await _test_escape()
	await _test_boss_level()
	await _test_active_skills()
	await _test_pause()
	await _test_from_menu()
	await _close_game()
	print("")
	print("%d checks, %d failed" % [_checks, _failures])
	print("RESULT: ", "GAME OK" if _failures == 0 else "GAME FAIL")
	get_tree().quit(0 if _failures == 0 else 1)


# --- Checks -----------------------------------------------------------------------

func _test_start_and_hud() -> void:
	print("- the stage starts, the HUD is complete")
	await _open_game(SaveData.Mode.CALM)
	_check(_stage.world != null and _stage.world.world_id == "ocean", "the Ocean is loaded")
	_check(_stage.players.size() == 2 and _echo != null and _guardian != null, "both players are registered")
	_check(_stage.level_index == 0 and _builder.get_shards().size() == _stage.shards_total and _stage.shards_total > 0,
		"level 1 is built with its %d shards" % _stage.shards_total)
	_check(Creature._flat_distance(_echo.global_position, _builder.get_spawn_position(1)) < 0.5
		and absf(_echo.global_position.y) < 0.01, "the players stand on the level's start")
	var hud := _game.get_node("Hud") as Hud
	_check(hud.get_node("PlayerStatuses").get_child_count() == 2, "a status block per player")
	_check(hud._shard_pips != null and hud._awareness_meter != null and hud._shard_label.text != "",
		"the shard counter (\"%s\") and the awareness meter show" % hud._shard_label.text)
	var pulse := _echo.get_node("Pulse") as PulseAbility
	await get_tree().physics_frame
	pulse.emit_pulse()
	await _frames(3)
	_check(_stage.pulses_used == 1 and _stage.awareness.get_ratio() > 0.0, "a pulse counts and raises the awareness")
	_check(Game.skill_catalog != null and Game.skill_catalog.skills.size() > 5, "the skill catalog is back on the Game autoload")
	_check(Game.get_world_config("ocean") == _stage.world or Game.get_world_config("ocean") != null,
		"the Game autoload finds the Ocean (the menus' way into the game)")


func _test_level_flow_and_skills() -> void:
	print("- level flow: shards, the light, Level cleared, the skill choice, the next level")
	await _open_game(SaveData.Mode.CALM)
	var goal: AncientLight = _builder.get_goal()
	_check(goal != null and goal.is_locked(), "the ancient light starts locked")
	_echo.health.set_segments(2.0)
	for shard: EchoShard in _builder.get_shards().duplicate():
		shard.collect()
	await _frames(2)
	_check(_stage.shards_collected == _stage.shards_total and not goal.is_locked(), "every shard collected unlocks it")
	_check(_echo.health.value > 2.0, "a shard heals (%.1f segments)" % _echo.health.value)
	var hud := _game.get_node("Hud") as Hud
	_check(hud._shard_label.text == Game.text("exit_open"), "the HUD says the exit is open")
	_place(_echo, goal.global_position + Vector3(1.0, 0.0, 0.0))
	_place(_guardian, goal.global_position + Vector3(-1.0, 0.0, 0.0))
	var won: Array[bool] = [false]
	_stage.level_won.connect(func() -> void: won[0] = true)
	await _seconds(goal.activation_time + 0.5)
	_check(won[0], "waking the light wins the level")
	var screen := _game.get_node("SkillChoiceScreen") as SkillChoiceScreen
	var end_screen := _game.get_node("EndScreen") as EndScreen
	await _seconds(_stage.victory_delay + 0.3)
	_check(end_screen.is_showing() and get_tree().paused, "the Level cleared card shows (the game is paused)")
	await _wait_until(func() -> bool: return screen.is_open, 8.0)
	_check(screen.is_open, "then the skill choice opens")
	await _seconds(screen.input_delay + 0.2)
	for player: Player in _stage.players:
		screen.press_pick(player)
	await _wait_until(func() -> bool: return not _stage.is_transitioning(), 10.0)
	_check(_stage.level_index == 1 and not get_tree().paused, "after both picked, level 2 starts")
	var owned: int = _stage.loadout.get_entries("echo").size() + _stage.loadout.get_entries("guardian").size()
	_check(owned >= 1, "the picks are owned (%d skill(s))" % owned)
	_check(Creature._flat_distance(_echo.global_position, _builder.get_spawn_position(1)) < 0.5, "the players stand on level 2's start")
	_check(Game.fader.get_cover() < 0.05, "the black has lifted")


func _test_defeat_and_retry() -> void:
	print("- defeat and retries")
	await _open_game(SaveData.Mode.CALM)
	_stage.apply_picks({_echo: [Game.skill_catalog.find("far_echo")]})
	var seed_before: int = _builder.spawn_seed
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	_check(not _stage.is_over, "one player down: the level goes on")
	_guardian.health.down(PlayerHealth.Cause.CREATURE)
	await _frames(2)
	var end_screen := _game.get_node("EndScreen") as EndScreen
	_check(_stage.is_over and end_screen.is_showing(), "both down: the defeat screen")
	end_screen.restart_requested.emit()
	await _wait_until(func() -> bool: return not _stage.is_transitioning() and not _stage.is_over, 8.0)
	_check(_stage.level_index == 0 and not _echo.health.is_downed and _builder.spawn_seed != seed_before,
		"Calm: the same level again, both up, new spawns")
	_check(_stage.loadout.get_entries("echo").is_empty(), "the skills are those of the level's start")

	await _open_game(SaveData.Mode.CHALLENGE)
	_stage.level_fade_enabled = false
	_stage._start_level(1)
	await _frames(3)
	for player: Player in _stage.players:
		player.health.down(PlayerHealth.Cause.CREATURE)
	await _frames(2)
	_stage._retry()
	await _frames(3)
	_check(_stage.level_index == 0, "Challenge: the stage starts again from level 1")


func _test_lockdown() -> void:
	print("- lockdown")
	await _open_game(SaveData.Mode.CALM)
	var lockdown: LockdownRoom = _builder.get_lockdown()
	_check(lockdown != null and lockdown._barriers.size() >= 1, "level 1 has a lockdown room with %d doorway(s)" % (lockdown._barriers.size() if lockdown else 0))
	if lockdown == null:
		return
	_protect_players()
	var barrier: LockdownBarrier = lockdown._barriers[0]
	_check(not _blocked_across(barrier), "its doorways are open at first")
	var inside: Vector3 = _builder.to_world(_builder.get_layout().lockdown_point)
	for player: Player in _stage.players:
		player.pressure.value = player.pressure.max_value * 0.5
	_place(_echo, inside + Vector3(-0.5, 0.0, 0.0))
	_place(_guardian, inside + Vector3(0.5, 0.0, 0.0))
	await _frames(3)
	_check(lockdown.is_locked() and barrier.is_closed, "both players deep inside: the doorways close")
	_check(_blocked_across(barrier), "a closed doorway is solid rock (bodies, the pulse, sight)")
	_check(_echo.pressure.drain_scale == 0.0, "Calm: the oxygen drain is paused while locked")
	await _wait_until(func() -> bool: return not _builder.is_rebaking(), 5.0)
	await _frames(3)
	var outside: Vector3 = barrier.center + _outward(barrier, inside) * 4.0
	_check(not _reachable(inside, outside), "the creatures' navigation is closed too (rebaked on a thread)")
	await _seconds(lockdown.wake_delay + 0.3)
	var wave: Array[Creature] = lockdown.get_wave()
	_check(wave.size() == _stage.world.get_level(0, 0).lockdown_wave_calm and wave.size() > 0, "the wave wakes (%d creatures, Calm)" % wave.size())
	var hunting: bool = not wave.is_empty()
	for creature: Creature in wave:
		hunting = hunting and creature.state == Creature.State.CHASE
	_check(hunting, "every wave creature hunts a player")
	var kills_before: int = _stage.creatures_killed
	for creature: Creature in wave:
		creature.take_damage(creature.health + 10, _guardian, 0.0, 0.0)
	await _frames(3)
	_check(lockdown.phase == LockdownRoom.Phase.CLEARED and not barrier.is_closed, "the wave dead: the doorways open")
	_check(_stage.creatures_killed == kills_before + wave.size(), "wave kills count for the summary")
	_check(is_equal_approx(_echo.pressure.get_ratio(), 0.5 + lockdown.clear_pressure_ratio) or _echo.pressure.get_ratio() > 0.7,
		"clearing it gives oxygen back (%.0f %%)" % (_echo.pressure.get_ratio() * 100.0))
	_check(_echo.pressure.drain_scale == 1.0, "and the drain is back to normal")
	await _wait_until(func() -> bool: return not _builder.is_rebaking(), 5.0)
	await _frames(3)
	_check(not _blocked_across(barrier) and _reachable(inside, outside), "the doorway is open again, for bodies and for navigation")


func _test_escape() -> void:
	print("- collapse escape")
	await _open_game(SaveData.Mode.CALM)
	_stage.level_fade_enabled = false
	_stage._start_level(1)
	await _frames(3)
	_protect_players()
	var escape := _game.get_node("EscapeEvent") as EscapeEvent
	var definition: LevelDefinition = _stage.world.get_level(0, 1)
	_check(definition.escape_event, "level 2 of the stage has the collapse escape")
	for shard: EchoShard in _builder.get_shards().duplicate():
		shard.collect()
	await _frames(3)
	_check(escape.is_active and is_equal_approx(escape.total_time, definition.get_escape_time(false)),
		"the last shard starts it (%.0f s in Calm)" % escape.total_time)
	var frenzied: int = 0
	for creature: Creature in _builder.get_creatures():
		if creature.is_frenzied:
			frenzied += 1
	_check(frenzied == _builder.get_creatures().size() and frenzied > 0, "every creature is in frenzy (%d)" % frenzied)
	var hud := _game.get_node("Hud") as Hud
	await _frames(3)
	_check(hud._escape_label.visible, "the HUD shows the timer")
	var arrow := _echo.find_child("GoalEcho", true, false) as GoalEcho
	_check(arrow != null and arrow.is_showing(), "the Echo's arrow stays on")
	escape.time_left = 0.05
	_echo.health.make_invulnerable(0.0)
	await _seconds(0.3)
	_check(not escape.is_active and _echo.health.is_downed and _guardian.health.is_downed and _stage.is_over,
		"the timer at zero downs both players (defeat)")


func _test_boss_level() -> void:
	print("- boss level: the arena door, the vents, the end of the stage")
	await _open_game(SaveData.Mode.CALM)
	_stage.level_fade_enabled = false
	_stage._start_level(2)
	await _frames(3)
	_protect_players()
	var door: ShardDoor = _builder.get_exit_door()
	_check(_stage.is_boss_level() and door != null and door.is_solid, "level 3 is a boss level with a closed arena door")
	if door == null:
		return
	var goal: AncientLight = _builder.get_goal()
	var start: Vector3 = _builder.get_spawn_position(1)
	_check(_blocked_across(door) and not _reachable(start, goal.global_position), "the arena is sealed (bodies and navigation)")
	_check(door.shards_needed == _stage.shards_total and door.shards_have == 0, "the door has a socket per shard (%d)" % door.shards_needed)
	var vents: Array[Node] = get_tree().get_nodes_in_group("bubble_vents")
	_check(vents.size() == 2, "the arena has its bubble vents (%d)" % vents.size())
	var shards: Array[EchoShard] = _builder.get_shards().duplicate()
	shards[0].collect()
	await _frames(2)
	_check(door.shards_have == 1 and not door.is_open, "a shard lights a socket")
	for i: int in range(1, shards.size()):
		shards[i].collect()
	await _frames(2)
	_check(door.is_open and not door.is_solid, "every shard: the door opens")
	await _wait_until(func() -> bool: return not _builder.is_rebaking(), 5.0)
	await _seconds(door.open_time + 0.2)
	_check(not _blocked_across(door) and _reachable(start, goal.global_position), "the arena can be entered (bodies and navigation)")
	if not vents.is_empty():
		var vent := vents[0] as BubbleVent
		_echo.pressure.value = _echo.pressure.max_value * 0.3
		_place(_echo, vent.global_position)
		_place(_guardian, vent.global_position + Vector3(4.0, 0.0, 0.0))
		await _seconds(1.0)
		_check(_echo.pressure.get_ratio() > 0.45 and vent.is_busy(), "standing at a vent refills oxygen (30 %% -> %.0f %%)" % (_echo.pressure.get_ratio() * 100.0))
		_check(_guardian.pressure.get_ratio() <= 1.0 and not vent.is_player_at(_guardian), "only for a player standing in it")
	# Until the boss is ported the stage ends at a light on the Boss marker.
	_place(_echo, goal.global_position + Vector3(1.0, 0.0, 0.0))
	_place(_guardian, goal.global_position + Vector3(-1.0, 0.0, 0.0))
	var completed: Array[int] = [-1]
	_stage.stage_completed.connect(func(index: int) -> void: completed[0] = index)
	await _seconds(goal.activation_time + _stage.victory_delay + 0.6)
	var screen := _game.get_node("SkillChoiceScreen") as SkillChoiceScreen
	await _wait_until(func() -> bool: return screen.is_open or completed[0] >= 0, 6.0)
	if screen.is_open:
		await _seconds(screen.input_delay + 0.2)
		for i: int in 3:
			for player: Player in _stage.players:
				screen.press_pick(player)
			await _frames(2)
	await _wait_until(func() -> bool: return completed[0] >= 0, 8.0)
	var end_screen := _game.get_node("EndScreen") as EndScreen
	_check(completed[0] == 0 and _stage.is_over and end_screen.is_showing(), "the light in the arena completes the stage (summary)")


func _test_active_skills() -> void:
	print("- active skills in 3D")
	await _open_game(SaveData.Mode.CALM)
	_protect_players()
	# Lure Pulse.
	_stage.apply_picks({_echo: [Game.skill_catalog.find("lure_pulse")], _guardian: [Game.skill_catalog.find("shield")]})
	await _frames(2)
	var lure := _echo.skills.active as LurePulseSkill
	var shield := _guardian.skills.active as ShieldSkill
	_check(lure != null and shield != null, "the Echo owns Lure Pulse, the Guardian the Shield")
	if lure == null or shield == null:
		return
	# Too far to see her, close enough to the decoy to hear it.
	var creature: Creature = _calm_creature_near(_echo.global_position + Vector3(lure.value("range") + lure.value("noise_radius") * 0.7, 0.0, 0.0))
	var oxygen: float = _echo.pressure.get_ratio()
	lure.throw_decoy(Vector3.RIGHT)
	_check(Creature._flat_distance(lure.decoy_position, _echo.global_position) <= lure.value("range") + 0.01 and not lure.is_ready(),
		"the decoy lands within %.0f units and the cooldown starts" % lure.value("range"))
	_check(_echo.pressure.get_ratio() < oxygen, "it costs a little oxygen")
	await _seconds(lure.value("travel_time") + 0.2)
	_check(creature.state == Creature.State.INVESTIGATE, "a creature within its noise comes to investigate (%s)" % creature.get_state_name())
	var blocked_point: Vector3 = lure.get_landing_point(Vector3.LEFT)
	_check(Creature._flat_distance(blocked_point, _echo.global_position) <= lure.value("range") + 0.01, "rock stops the throw")

	# Shield.
	Input.action_press("p2_skill")
	await _frames(3)
	_check(shield.is_raised and _guardian.speed_scale < 1.0, "holding the skill button raises the shield (slower)")
	var front: Vector3 = _guardian.global_position + shield.shield_direction * 1.0
	var health_before: float = _guardian.health.value
	_guardian.health.make_invulnerable(0.0)
	await _frames(1)
	_guardian.health._invulnerable_left = 0.0
	_guardian.health.take_hit(front)
	_check(_guardian.health.value == health_before and shield.blocks == 1, "a hit from the front is blocked")
	_guardian.health.take_hit(_guardian.global_position - shield.shield_direction * 1.0)
	_check(_guardian.health.value < health_before, "a hit from behind is not")
	Input.action_release("p2_skill")
	await _frames(3)
	_check(not shield.is_raised and _guardian.speed_scale == 1.0, "letting go lowers it")

	# Dash.
	_stage.loadout = SkillLoadout.new(_stage.world.world_id)
	_stage.apply_picks({_guardian: [Game.skill_catalog.find("dash")]})
	await _frames(2)
	var dash := _guardian.skills.active as DashSkill
	_check(dash != null, "the Guardian owns the Dash")
	if dash == null:
		return
	_guardian.health._invulnerable_left = 0.0
	var from: Vector3 = _guardian.global_position
	dash.dash()
	await _seconds(0.25)
	var moved: float = Creature._flat_distance(from, _guardian.global_position)
	_check(moved > 1.0 and absf(_guardian.global_position.y) < 0.01, "the dash bursts him forward (%.1f units), still on the floor" % moved)
	_check(not dash.is_ready() and _guardian.health.is_invulnerable(), "it has a cooldown and a short invulnerability")


func _test_pause() -> void:
	print("- pause menu")
	await _open_game(SaveData.Mode.CALM)
	var pause := _game.get_node("PauseMenu") as PauseMenu
	_check(_stage.can_pause(), "a level being played can be paused")
	pause.open()
	await get_tree().process_frame
	_check(pause.is_open and get_tree().paused, "the menu pauses the whole game")
	var oxygen: float = _echo.pressure.value
	await _seconds(0.5)
	_check(_echo.pressure.value == oxygen, "the oxygen stands still while paused")
	pause.close()
	await get_tree().process_frame
	_check(not pause.is_open and not get_tree().paused, "Resume continues")
	_stage.apply_picks({_echo: [Game.skill_catalog.find("far_echo")]})
	var seed_before: int = _builder.spawn_seed
	_stage.restart_level()
	await _frames(3)
	_check(_stage.level_index == 0 and _builder.spawn_seed != seed_before and _stage.loadout.get_entries("echo").is_empty(),
		"Restart level: the level again with the skills of its start")


## The way the menus start it: the world and stage of the save (changed in
## memory only: nothing is written).
func _test_from_menu() -> void:
	print("- started from the menus")
	await _close_game()
	var world_before: String = Game.save.world_id
	var stage_before: int = Game.save.stage_index
	Game.save.world_id = "ocean"
	Game.save.stage_index = 1
	Game.started_from_menu = true
	_game = (load(GameSceneLoader.GAME_SCENE) as PackedScene).instantiate() as Node3D
	add_child(_game)
	_stage = _game.get_node("StageManager") as StageManager
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	await _frames(4)
	_check(_stage.world == Game.get_current_world() and _stage.world != null, "the stage plays the save's world (loaded by the Game autoload)")
	_check(_stage.stage_index == 1 and _stage.level_index == 0 and _builder.get_shards().size() > 0, "the save's stage starts at its level 1")
	Game.started_from_menu = false
	Game.save.world_id = world_before
	Game.save.stage_index = stage_before


# --- Helpers ----------------------------------------------------------------------

func _open_game(mode: SaveData.Mode) -> void:
	await _close_game()
	Game.started_from_menu = false
	_game = GameSceneLoader.instantiate(mode)
	add_child(_game)
	_stage = _game.get_node("StageManager") as StageManager
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	await _frames(4)
	_echo = null
	_guardian = null
	for player: Player in _stage.players:
		if player.player_number == 1:
			_echo = player
		else:
			_guardian = player


func _close_game() -> void:
	if _game == null:
		return
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.action_release("p2_skill")
	Input.action_release("p1_skill")
	_game.queue_free()
	_game = null
	await _frames(2)
	if Game.fader:
		Game.fader.fade_in(0.0)


## Nothing hurts the players for the rest of this check.
func _protect_players() -> void:
	for player: Player in _stage.players:
		player.health.make_invulnerable(600.0)


## True when rock stands across this gate (a ray through it, at body height).
func _blocked_across(gate: RockGate) -> bool:
	var across: Vector3 = gate.along.cross(Vector3.UP)
	var middle: Vector3 = gate.global_position + gate.center + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(middle - across * 4.0, middle + across * 4.0, 1)
	return not _game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The direction from a gate away from a point (out of the room).
func _outward(gate: RockGate, from_inside: Vector3) -> Vector3:
	var across: Vector3 = gate.along.cross(Vector3.UP)
	return across if across.dot(gate.center - from_inside) > 0.0 else -across


func _reachable(from: Vector3, to: Vector3) -> bool:
	var map: RID = _game.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	return not path.is_empty() and Creature._flat_distance(path[path.size() - 1], to) < 1.0


## A creature of the level put at a spot, wandering (not chasing).
func _calm_creature_near(at: Vector3) -> Creature:
	var creature: Creature = _builder.get_creatures()[0]
	for candidate: Creature in _builder.get_creatures():
		if not candidate is Sentinel and not candidate is LightHunter:
			creature = candidate
			break
	creature.forget_players()
	_place(creature, at)
	return creature


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = Vector3(at.x, 0.0, at.z)
	node.reset_physics_interpolation()
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["ok  " if ok else "FAIL", label])


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## Real seconds of the tree, also while the game is paused.
func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _wait_until(condition: Callable, timeout: float) -> void:
	var left: float = timeout
	while left > 0.0 and not condition.call():
		await get_tree().process_frame
		left -= get_process_delta_time()
