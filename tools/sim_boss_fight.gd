extends Node
## Headless fight simulation: the real game (game.tscn, stage 1 level 3, the
## Angler) with two bots playing it like a good pair, to measure how long the
## fight lasts and where the damage comes from:
##   godot --headless --path . --fixed-fps 60 res://tools/sim_boss_fight.tscn [-- calm|challenge|both] [log]
## - Guardian: stays at sword range and swings whenever the boss can be hurt
##   and is revealed (real SwordAbility input, real damage path);
## - Echo: stays by him (her light reveals it), pulses whenever the pulse is
##   ready (real sonar -> Exposed), and when the Lure is ready baits a charge
##   at a pillar (the decoy just in front of it, Lure cooldown respected);
## - both get out of the way during every telegraph / attack (out of the
##   charge's line, away from the jaws), so its attacks can still land.
## A downed bot is revived after revive_delay. Reports the fight time, the
## time and damage per phase, the damage by kind (armoured / Exposed /
## stunned), pillar stuns and the hits the players took (StageManager's
## "Hits taken"). Fails if a fight is shorter than MIN_FIGHT_SECONDS or the
## boss is still alive after MAX_FIGHT_SECONDS. "log" prints every damage event.

const GAME_SCENE: String = "res://scenes/game.tscn"
const PHYSICS_FPS: float = 60.0
const MIN_FIGHT_SECONDS: float = 90.0
const MAX_FIGHT_SECONDS: float = 600.0
## Skills the pair has by the boss (two picks each in stage 1).
const ECHO_SKILLS: Dictionary = {"lure_pulse": 1, "longer_exposure": 1}
const GUARDIAN_SKILLS: Dictionary = {"wide_swing": 1, "iron_lungs": 1}

## How far from its middle the Guardian fights / the Echo stays.
var guardian_distance: float = 100.0
var echo_side_offset: float = 60.0
## Dodging: how far out of the charge line / from the jaws they go.
var charge_dodge: float = 190.0
var bite_dodge: float = 320.0
var revive_delay: float = 3.0
## A pillar is used for a bait when it is this far from the boss.
var bait_min: float = 250.0
var bait_max: float = 800.0

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player
var _boss: AnglerBoss
var _failures: int = 0
var _attack_toggle: bool = false
var _downed_time: Dictionary = {}
var _phase_damage: Dictionary = {}
var _phase_start: Dictionary = {}
var _kind_damage: Dictionary = {}
var _hits_logged: int = 0
var _ignored: int = 0
var _duplicates: int = 0
var _baits: int = 0
var _revives: int = 0
## Both bots down at the same time (in the game: a defeat and a retry).
var _defeats: int = 0
var _time: float = 0.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "both"
	Boss.damage_log_enabled = args.has("log")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	_stage = _game.get_node("StageManager") as StageManager
	add_child(_game)
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	_echo = _game.get_node("Echo") as Player
	_guardian = _game.get_node("Guardian") as Player
	(_game.get_node("DepthAwareness") as DepthAwareness).decay_per_second = 0.0
	await _frames(10)
	# A defeat would restart the level: the bots get up and fight on instead
	# (counted as defeats in the report).
	for player: Player in [_echo, _guardian]:
		if player.health.downed.is_connected(_stage._on_player_downed):
			player.health.downed.disconnect(_stage._on_player_downed)
	var modes: Array[SaveData.Mode] = []
	if which != "challenge":
		modes.append(SaveData.Mode.CALM)
	if which != "calm":
		modes.append(SaveData.Mode.CHALLENGE)
	var lines: PackedStringArray = PackedStringArray()
	for mode: SaveData.Mode in modes:
		lines.append(await _fight(mode))
	print("\n".join(lines))
	print("RESULT: %s" % ("FIGHT LENGTH OK" if _failures == 0 else "%d PROBLEM(S)" % _failures))
	_game.queue_free()
	for i: int in 10:
		await get_tree().process_frame
		OS.delay_msec(30)
	get_tree().quit(0 if _failures == 0 else 1)


func _fight(mode: SaveData.Mode) -> String:
	var mode_name: String = "Calm" if mode == SaveData.Mode.CALM else "Challenge"
	print("== Fight (%s) ==" % mode_name)
	_stage.mode = mode
	_stage.stage_index = 0
	_stage._start_level(2)
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		if node != _builder.get_boss():
			node.remove_from_group("creatures")
			node.queue_free()
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	_boss = _builder.get_boss() as AnglerBoss
	_boss.killed.disconnect(_stage._on_boss_killed)
	_boss.damage_taken.connect(_on_damage)
	_echo.skills.set_skills(ECHO_SKILLS, Game.skill_catalog)
	_guardian.skills.set_skills(GUARDIAN_SKILLS, Game.skill_catalog)
	for player: Player in [_echo, _guardian]:
		player.health.refill()
		player.health._invulnerable_left = 0.0
	await _frames(15)
	_builder.open_exit()
	_phase_damage = {1: 0.0, 2: 0.0, 3: 0.0}
	_phase_start = {1: 0.0}
	_kind_damage = {"armor": 0.0, "exposed": 0.0, "stunned": 0.0}
	_hits_logged = 0
	_ignored = 0
	_duplicates = 0
	_baits = 0
	_revives = 0
	_defeats = 0
	_downed_time.clear()
	var hits_before: int = _stage.hits_taken
	_echo.global_position = _boss.global_position + Vector2(-60.0, -300.0)
	_guardian.global_position = _boss.global_position + Vector2(0.0, -300.0)
	_boss.start_fight()
	_time = 0.0
	var last_phase: int = 1
	while not _boss.is_dying() and _time < MAX_FIGHT_SECONDS:
		await get_tree().physics_frame
		var delta: float = 1.0 / PHYSICS_FPS
		_time += delta
		if _boss.phase != last_phase:
			last_phase = _boss.phase
			_phase_start[last_phase] = _time
		_play(delta)
	Input.action_release("p1_action")
	Input.action_release("p2_action")
	var hits: int = _stage.hits_taken - hits_before
	var killed: bool = _boss.is_dying()
	var phase_text: PackedStringArray = PackedStringArray()
	for p: int in [1, 2, 3]:
		var start: float = float(_phase_start.get(p, -1.0))
		var end: float = float(_phase_start.get(p + 1, _time))
		phase_text.append("phase %d: %s, %.1f dmg" % [p, "%.0f s" % (end - start) if start >= 0.0 else "-", float(_phase_damage[p])])
	var summary: String = "%s: %s in %d:%02d (%.0f s) | HP %.0f | %s | damage armoured %.1f / Exposed %.1f / stunned %.1f | %d hits, %d ignored, %d duplicate swings | %d pillar stuns, %d baits, %d pillars broken | hits taken by the players: %d, revives %d, defeats %d" % [
		mode_name, "killed" if killed else "NOT killed", int(_time) / 60, int(_time) % 60, _time, _boss.boss_max_health,
		" / ".join(phase_text), float(_kind_damage["armor"]), float(_kind_damage["exposed"]), float(_kind_damage["stunned"]),
		_hits_logged, _ignored, _duplicates, _boss.pillar_stuns, _baits, _broken_pillars(), hits, _revives, _defeats]
	print("  " + summary)
	if not killed:
		_failures += 1
		print("  [FAIL] the boss is still alive after %.0f s" % MAX_FIGHT_SECONDS)
	elif _time < MIN_FIGHT_SECONDS:
		_failures += 1
		print("  [FAIL] the fight lasted %.0f s (< %.0f s)" % [_time, MIN_FIGHT_SECONDS])
	else:
		print("  [ok] the fight lasted %.0f s (>= %.0f s)" % [_time, MIN_FIGHT_SECONDS])
	_boss.damage_taken.disconnect(_on_damage)
	_stage.mode = SaveData.Mode.CALM
	return summary


# --- The bots --------------------------------------------------------------------

func _play(delta: float) -> void:
	for player: Player in [_echo, _guardian]:
		player.pressure.refill()
		_handle_downed(player, delta)
	var danger: bool = _boss.mode == Boss.Mode.TELEGRAPH or _boss.mode == Boss.Mode.ACTIVE
	if danger:
		_dodge(_guardian, delta)
		_dodge(_echo, delta)
	else:
		_approach(delta)
	_guardian_attack(danger)
	_echo_pulse()
	_echo_bait()


func _approach(delta: float) -> void:
	var center: Vector2 = _boss.global_position
	var side: Vector2 = center.direction_to(_guardian.global_position)
	if side == Vector2.ZERO:
		side = Vector2.UP
	var guardian_spot: Vector2 = center + side * guardian_distance
	_move(_guardian, guardian_spot, delta)
	_move(_echo, guardian_spot + side.orthogonal() * echo_side_offset + side * 20.0, delta)
	_guardian.facing = _guardian.global_position.direction_to(center)


func _dodge(player: Player, delta: float) -> void:
	if player.health.is_downed or _boss.current_attack == null:
		return
	var spot: Vector2 = player.global_position
	if _boss.current_attack.id == &"charge":
		# Out of the line of the dash, to the nearer side.
		var aim: Vector2 = _boss.get_aim()
		var offset: Vector2 = player.global_position - _boss.global_position
		var across: Vector2 = aim.orthogonal()
		var side: float = signf(offset.dot(across)) if absf(offset.dot(across)) > 1.0 else 1.0
		spot = _boss.global_position + aim * maxf(offset.dot(aim), 0.0) + across * side * charge_dodge
	else:
		spot = _boss.global_position + _boss.global_position.direction_to(player.global_position) * bite_dodge
	_move(player, spot, delta)


func _move(player: Player, spot: Vector2, delta: float) -> void:
	if player.health.is_downed:
		return
	var offset: Vector2 = spot - player.global_position
	var step: float = minf(offset.length(), player.max_speed * delta)
	if step > 0.5:
		player.move_and_collide(offset.normalized() * step)


func _guardian_attack(danger: bool) -> void:
	var ready: bool = not danger and not _guardian.health.is_downed and _boss.can_be_hurt() and _boss.is_revealed() \
		and _guardian.global_position.distance_to(_boss.global_position) <= 150.0
	# Tap the button every other frame (a fresh press each time).
	_attack_toggle = not _attack_toggle
	if ready and _attack_toggle:
		Input.action_press("p2_action")
	else:
		Input.action_release("p2_action")


func _echo_pulse() -> void:
	var pulse: PulseAbility = _find_child_of(_echo, "PulseAbility") as PulseAbility
	if pulse and pulse.is_ready() and not _echo.health.is_downed and _boss.can_be_hurt():
		Input.action_press("p1_action")
	else:
		Input.action_release("p1_action")


func _echo_bait() -> void:
	var lure := _echo.skills.active as LurePulseSkill
	if lure == null or not lure.is_ready() or _boss.mode != Boss.Mode.IDLE or _echo.health.is_downed:
		return
	var best_point: Vector2 = Vector2.INF
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		var pillar := node as ArenaPillar
		if pillar == null or pillar.is_broken or not _builder._level.is_ancestor_of(pillar):
			continue
		var center: Vector2 = _center_of(pillar)
		var distance: float = center.distance_to(_boss.global_position)
		if distance < bait_min or distance > bait_max:
			continue
		var point: Vector2 = center - _boss.global_position.direction_to(center) * 95.0
		if best_point == Vector2.INF or point.distance_to(_boss.global_position) < best_point.distance_to(_boss.global_position):
			best_point = point
	if best_point == Vector2.INF:
		return
	# The Echo throws it (cooldown, cost); the boss hears it like a real ping.
	lure._mark_used()
	_baits += 1
	_boss.hear_decoy(best_point, 500.0)


func _handle_downed(player: Player, delta: float) -> void:
	if player == _echo and _echo.health.is_downed and _guardian.health.is_downed and not _downed_time.has(&"both"):
		_downed_time[&"both"] = true
		_defeats += 1
	elif not (_echo.health.is_downed and _guardian.health.is_downed):
		_downed_time.erase(&"both")
	if not player.health.is_downed:
		_downed_time.erase(player)
		return
	_downed_time[player] = float(_downed_time.get(player, 0.0)) + delta
	if float(_downed_time[player]) >= revive_delay:
		player.health.revive()
		_revives += 1


func _on_damage(info: Dictionary) -> void:
	var result: String = info["result"]
	if result.begins_with("ignored"):
		_ignored += 1
		return
	if result.begins_with("duplicate"):
		_duplicates += 1
		return
	_hits_logged += 1
	var dealt: float = float(info["dealt"])
	_phase_damage[int(info["phase"])] = float(_phase_damage.get(int(info["phase"]), 0.0)) + dealt
	var multipliers: Dictionary = info["multipliers"]
	var kind: String = "stunned" if info["mode"] == "STUNNED" else ("armor" if multipliers.has("armor") else "exposed")
	_kind_damage[kind] = float(_kind_damage[kind]) + dealt


# --- Helpers -----------------------------------------------------------------------

func _broken_pillars() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		if (node as ArenaPillar).is_broken:
			count += 1
	return count


func _center_of(pillar: ArenaPillar) -> Vector2:
	var center := Vector2.ZERO
	var outline: PackedVector2Array = pillar.get_global_outline()
	for point: Vector2 in outline:
		center += point / outline.size()
	return center


func _find_child_of(node: Node, type_name: String) -> Node:
	for child: Node in node.find_children("*", type_name, true, false):
		return child
	return null


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
