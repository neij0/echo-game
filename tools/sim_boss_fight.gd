extends Node
## Headless fight simulation: the real game (game.tscn, the boss level of each
## stage: 1 = the Angler, 2 / 3 = the placeholder boss) played by two bots that
## act like real players (not perfect ones), to measure how long the fights
## last, where the damage comes from and what hits the players:
##   godot --headless --path . --fixed-fps 60 res://tools/sim_boss_fight.tscn [-- calm|challenge] [1|2|3] [runs N] [log]
## (no mode = both, no stage = all three, runs = fights per stage and mode).
## Human-like bots:
## - they react to a telegraph after reaction (0.4-0.6 s), sometimes freeze
##   (freeze_chance: later still), and dodge imperfectly (a random share of
##   the safe distance);
## - the Guardian notices an opening (recovery, stun, Exposed) after a reaction
##   delay and misses miss_chance of them altogether; he keeps some distance
##   otherwise, swings at orbs coming at him (deflect_chance);
## - the Echo stays by him (her light reveals it), pulses when ready after a
##   human delay (sooner when orbs come close: the pulse pops them), and with
##   the Lure ready sometimes baits a charge at a pillar or a mine (bait_chance,
##   aim off by up to bait_error);
## - mines are only known once a pulse showed them or their warning ring shows;
## - no free oxygen: below vent_low they go to the nearest bubble vent and stay
##   until vent_full;
## - a downed bot is revived by the other (walk over, hold revive_time); both
##   down at once = a defeat (counted; the game would retry), both get up.
## Reports per run and averaged over the runs: the fight time (target window),
## time / damage per phase, damage by kind, hits taken per phase and by what,
## defeats, revives, the lowest oxygen. Fails if a fight is shorter than
## MIN_FIGHT_SECONDS or the boss still lives after MAX_FIGHT_SECONDS.

const GAME_SCENE: String = "res://scenes/game.tscn"
const PHYSICS_FPS: float = 60.0
const MIN_FIGHT_SECONDS: float = 90.0
const MAX_FIGHT_SECONDS: float = 900.0
## Game time per physics frame x this (Engine.time_scale, in the sim only).
const SIM_SPEED: float = 2.0
## Target fight length (seconds) per stage: [Calm, Challenge] windows
## (reported, not a failure; only MIN_FIGHT_SECONDS fails).
const TARGETS: Dictionary = {
	0: [Vector2(150.0, 225.0), Vector2(180.0, 240.0)],
	1: [Vector2(90.0, 150.0), Vector2(120.0, 180.0)],
	2: [Vector2(90.0, 150.0), Vector2(120.0, 180.0)],
}
## Skills the pair has by the boss (two picks each in stage 1).
const ECHO_SKILLS: Dictionary = {"lure_pulse": 1, "longer_exposure": 1}
const GUARDIAN_SKILLS: Dictionary = {"wide_swing": 1, "iron_lungs": 1}

## Human-like play.
var reaction: Vector2 = Vector2(0.4, 0.6)
var freeze_chance: float = 0.15
var freeze_extra: float = 0.4
## Share of the safe distance a dodge really covers.
var dodge_share: Vector2 = Vector2(0.55, 1.1)
var miss_chance: float = 0.3
var deflect_chance: float = 0.6
var bait_chance: float = 0.5
var bait_error: float = 60.0
## Seconds the Echo waits once her pulse is ready (when no orb is near).
var pulse_delay: Vector2 = Vector2(0.5, 1.5)
var vent_low: float = 0.35
var vent_full: float = 0.85
var revive_time: float = 3.0
## Positions.
var guardian_distance: float = 100.0
var guardian_wait_distance: float = 250.0
var echo_side_offset: float = 60.0
var charge_dodge: float = 190.0
var bite_dodge: float = 320.0
var sweep_dodge: float = 300.0
var slam_dodge_margin: float = 100.0
var mine_dodge_margin: float = 40.0
var bait_min: float = 250.0
var bait_max: float = 800.0

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player
var _boss: Boss
var _failures: int = 0
var _time: float = 0.0
var _attack_toggle: bool = false
# Per bot: reaction left for the current threat, the dodge share, the threat.
var _react_left: Dictionary = {}
var _dodge_scale: Dictionary = {}
var _last_threat: String = ""
var _opening_id: int = 0
var _opening_seen: int = -1
var _opening_left: float = 0.0
var _opening_missed: bool = false
var _was_exposed: bool = false
var _pulse_wait: float = -1.0
var _bait_rolled: bool = false
var _going_to_vent: Dictionary = {}
var _revive_progress: float = 0.0
var _known_mines: Dictionary = {}
# Per fight stats.
var _phase_damage: Dictionary = {}
var _phase_start: Dictionary = {}
var _phase_hits: Dictionary = {}
var _hit_sources: Dictionary = {}
var _kind_damage: Dictionary = {}
var _defeats: int = 0
var _revives: int = 0
var _baits: int = 0
var _deflect_tries: int = 0
var _min_oxygen: float = 1.0
var _oxygen_downs: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	Boss.damage_log_enabled = args.has("log")
	var runs: int = 1
	var stage_args: PackedStringArray = args.duplicate()
	if args.has("runs") and args.find("runs") + 1 < args.size():
		runs = maxi(int(args[args.find("runs") + 1]), 1)
		# The count after "runs" is not a stage number.
		stage_args.remove_at(args.find("runs") + 1)
	# Twice as fast (the sim only): physics steps of 1/30 s game time.
	Engine.time_scale = SIM_SPEED
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
		player.health.hit_taken.connect(_on_player_hit.bind(player))
		player.health.downed.connect(_on_player_downed)
	var modes: Array[SaveData.Mode] = []
	if not args.has("challenge"):
		modes.append(SaveData.Mode.CALM)
	if not args.has("calm"):
		modes.append(SaveData.Mode.CHALLENGE)
	var stages: Array[int] = []
	for stage: int in [0, 1, 2]:
		if stage_args.has(str(stage + 1)):
			stages.append(stage)
	if stages.is_empty():
		stages = [0, 1, 2]
	var report: PackedStringArray = PackedStringArray()
	for stage: int in stages:
		for mode: SaveData.Mode in modes:
			var results: Array[Dictionary] = []
			for run: int in runs:
				results.append(await _fight(stage, mode, run + 1, runs))
			report.append(_aggregate(stage, mode, results))
	print("\n".join(report))
	print("RESULT: %s" % ("FIGHT LENGTH OK" if _failures == 0 else "%d PROBLEM(S)" % _failures))
	Engine.time_scale = 1.0
	_game.queue_free()
	for i: int in 10:
		await get_tree().process_frame
		OS.delay_msec(30)
	get_tree().quit(0 if _failures == 0 else 1)


func _fight(stage: int, mode: SaveData.Mode, run: int, runs: int) -> Dictionary:
	var challenge: bool = mode == SaveData.Mode.CHALLENGE
	var label: String = "Stage %d %s" % [stage + 1, "Challenge" if challenge else "Calm"]
	_stage.mode = mode
	_stage.stage_index = stage
	_stage._start_level(2)
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		if node != _builder.get_boss():
			node.remove_from_group("creatures")
			node.queue_free()
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	_boss = _builder.get_boss() as Boss
	_boss.killed.disconnect(_stage._on_boss_killed)
	_boss.damage_taken.connect(_on_damage)
	_echo.skills.set_skills(ECHO_SKILLS, Game.skill_catalog)
	_guardian.skills.set_skills(GUARDIAN_SKILLS, Game.skill_catalog)
	for player: Player in [_echo, _guardian]:
		player.health.refill()
		player.pressure.refill()
		player.health._invulnerable_left = 0.0
	await _frames(15)
	_builder.open_exit()
	_reset_stats()
	_echo.global_position = _boss.global_position + Vector2(-60.0, -300.0)
	_guardian.global_position = _boss.global_position + Vector2(0.0, -300.0)
	_boss.start_fight()
	_time = 0.0
	var last_phase: int = 1
	while not _boss.is_dying() and _time < MAX_FIGHT_SECONDS:
		await get_tree().physics_frame
		var delta: float = SIM_SPEED / PHYSICS_FPS
		_time += delta
		if _boss.phase != last_phase:
			last_phase = _boss.phase
			_phase_start[last_phase] = _time
		_play(delta)
	for action: String in ["p1_action", "p2_action", "p2_skill", "p1_skill"]:
		Input.action_release(action)
	_boss.damage_taken.disconnect(_on_damage)
	var result: Dictionary = {
		"label": label, "killed": _boss.is_dying(), "time": _time, "hp": _boss.boss_max_health,
		"phase_time": _phase_times(), "phase_damage": _phase_damage.duplicate(), "phase_hits": _phase_hits.duplicate(),
		"sources": _hit_sources.duplicate(), "kinds": _kind_damage.duplicate(), "defeats": _defeats, "revives": _revives,
		"baits": _baits, "min_oxygen": _min_oxygen, "oxygen_downs": _oxygen_downs, "stage": stage, "challenge": challenge,
	}
	var angler := _boss as AnglerBoss
	if angler:
		result["angler"] = "pillar stuns %d, orb stuns %d, mine hits %d, sweeps %d, orbs %d, mines %d, vent charges %d" % [
			angler.pillar_stuns, angler.orb_stuns, angler.mine_hits, angler.sweeps_done, angler.orbs_fired, angler.mines_launched, angler.vent_charges]
	var phase_text: PackedStringArray = PackedStringArray()
	for p: int in [1, 2, 3]:
		phase_text.append("P%d %.0fs/%d hits" % [p, float((result["phase_time"] as Dictionary)[p]), int(_phase_hits[p])])
	print("  %s run %d/%d: %s %d:%02d | %s | defeats %d, revives %d, oxygen low %.0f%% (%d downs) | %s" % [
		label, run, runs, "killed" if result["killed"] else "NOT killed", int(_time) / 60, int(_time) % 60,
		", ".join(phase_text), _defeats, _revives, _min_oxygen * 100.0, _oxygen_downs, result.get("angler", "")])
	_stage.mode = SaveData.Mode.CALM
	return result


func _aggregate(stage: int, mode: SaveData.Mode, results: Array[Dictionary]) -> String:
	var challenge: bool = mode == SaveData.Mode.CHALLENGE
	var target: Vector2 = (TARGETS[stage] as Array)[1 if challenge else 0]
	var label: String = results[0]["label"]
	var times: Array[float] = []
	var phase_time: Dictionary = {1: 0.0, 2: 0.0, 3: 0.0}
	var phase_hits: Dictionary = {1: 0.0, 2: 0.0, 3: 0.0}
	var sources: Dictionary = {}
	var defeats: int = 0
	var revives: int = 0
	var oxygen_downs: int = 0
	var min_oxygen: float = 1.0
	var n: float = float(results.size())
	for result: Dictionary in results:
		var time: float = result["time"]
		times.append(time)
		if not result["killed"]:
			_failures += 1
			print("  [FAIL] %s: the boss is still alive after %.0f s" % [label, MAX_FIGHT_SECONDS])
		elif time < MIN_FIGHT_SECONDS:
			_failures += 1
			print("  [FAIL] %s: a fight lasted %.0f s (< %.0f s)" % [label, time, MIN_FIGHT_SECONDS])
		for p: int in [1, 2, 3]:
			phase_time[p] = float(phase_time[p]) + float((result["phase_time"] as Dictionary)[p]) / n
			phase_hits[p] = float(phase_hits[p]) + float((result["phase_hits"] as Dictionary)[p]) / n
		for key: String in result["sources"]:
			sources[key] = float(sources.get(key, 0.0)) + float((result["sources"] as Dictionary)[key]) / n
		defeats += int(result["defeats"])
		revives += int(result["revives"])
		oxygen_downs += int(result["oxygen_downs"])
		min_oxygen = minf(min_oxygen, float(result["min_oxygen"]))
	times.sort()
	var mean: float = 0.0
	for time: float in times:
		mean += time / n
	var source_text: PackedStringArray = PackedStringArray()
	for key: String in sources:
		source_text.append("%s %.1f" % [key, float(sources[key])])
	var inside: bool = mean >= target.x and mean <= target.y
	return "%s (%s, %d runs): mean %d:%02d, min %d:%02d, max %d:%02d (target %d:%02d-%d:%02d%s) | phases %.0f / %.0f / %.0f s | hits per fight: P1 %.1f, P2 %.1f, P3 %.1f (%s) | defeats %d, revives %d, oxygen downs %d, lowest oxygen %.0f%%" % [
		label, _boss_name(stage), results.size(), int(mean) / 60, int(mean) % 60, int(times[0]) / 60, int(times[0]) % 60,
		int(times[times.size() - 1]) / 60, int(times[times.size() - 1]) % 60, int(target.x) / 60, int(target.x) % 60,
		int(target.y) / 60, int(target.y) % 60, "" if inside else ", OUTSIDE", float(phase_time[1]), float(phase_time[2]), float(phase_time[3]),
		float(phase_hits[1]), float(phase_hits[2]), float(phase_hits[3]), ", ".join(source_text), defeats, revives, oxygen_downs, min_oxygen * 100.0]


func _boss_name(stage: int) -> String:
	return "Angler" if stage == 0 else "placeholder"


func _reset_stats() -> void:
	_phase_damage = {1: 0.0, 2: 0.0, 3: 0.0}
	_phase_start = {1: 0.0}
	_phase_hits = {1: 0, 2: 0, 3: 0}
	_hit_sources = {}
	_kind_damage = {"armor": 0.0, "exposed": 0.0, "stunned": 0.0, "mine": 0.0}
	_defeats = 0
	_revives = 0
	_baits = 0
	_deflect_tries = 0
	_min_oxygen = 1.0
	_oxygen_downs = 0
	_react_left.clear()
	_dodge_scale.clear()
	_last_threat = ""
	_opening_id = 0
	_opening_seen = -1
	_opening_left = 0.0
	_opening_missed = false
	_was_exposed = false
	_pulse_wait = -1.0
	_bait_rolled = false
	_going_to_vent.clear()
	_revive_progress = 0.0
	_known_mines.clear()


func _phase_times() -> Dictionary:
	var result: Dictionary = {}
	for p: int in [1, 2, 3]:
		var start: float = float(_phase_start.get(p, -1.0))
		var end: float = float(_phase_start.get(p + 1, _time))
		result[p] = end - start if start >= 0.0 else 0.0
	return result


# --- The bots --------------------------------------------------------------------

func _play(delta: float) -> void:
	for player: Player in [_echo, _guardian]:
		_min_oxygen = minf(_min_oxygen, player.pressure.get_ratio())
	_track_threat()
	_track_openings(delta)
	_learn_mines()
	if _handle_downed(delta):
		return
	var guardian_busy: bool = _move_bot(_guardian, delta)
	_move_bot(_echo, delta)
	_guardian_attack(guardian_busy)
	_echo_pulse(delta)
	_echo_bait()


## A new telegraph: each bot reacts after its own delay, with its own dodge.
func _track_threat() -> void:
	var threat: String = ""
	if _boss.mode == Boss.Mode.TELEGRAPH or _boss.mode == Boss.Mode.ACTIVE:
		threat = String(_boss.current_attack.id) if _boss.current_attack else ""
	if threat != "" and threat != _last_threat:
		for player: Player in [_echo, _guardian]:
			var delay: float = randf_range(reaction.x, reaction.y)
			if randf() < freeze_chance:
				delay += freeze_extra
			_react_left[player] = delay
			_dodge_scale[player] = randf_range(dodge_share.x, dodge_share.y)
	_last_threat = threat


## Openings: a recovery, a stun or a fresh Exposed. The Guardian notices it
## after a reaction delay, or misses it.
func _track_openings(delta: float) -> void:
	var open: bool = _boss.mode == Boss.Mode.RECOVERY or _boss.mode == Boss.Mode.STUNNED or _boss.is_exposed()
	var exposed: bool = _boss.is_exposed()
	if (open and _opening_seen != _opening_id) or (exposed and not _was_exposed):
		_opening_id += 1
		_opening_seen = _opening_id
		_opening_left = randf_range(reaction.x, reaction.y)
		_opening_missed = randf() < miss_chance
	if not open:
		_opening_seen = -1
	_was_exposed = exposed
	_opening_left = maxf(_opening_left - delta, 0.0)
	for player: Player in [_echo, _guardian]:
		_react_left[player] = maxf(float(_react_left.get(player, 0.0)) - delta, 0.0)


func _learn_mines() -> void:
	for node: Node in get_tree().get_nodes_in_group("angler_mines"):
		var mine := node as AnglerMine
		if mine.is_revealed() or mine.get_fuse_left() <= mine.warning_time:
			_known_mines[mine] = true


## Moves one bot; returns true while it is busy (dodging, at a vent, avoiding).
func _move_bot(player: Player, delta: float) -> bool:
	if player.health.is_downed:
		return true
	var danger: bool = _boss.mode == Boss.Mode.TELEGRAPH or _boss.mode == Boss.Mode.ACTIVE
	if danger and float(_react_left.get(player, 0.0)) <= 0.0:
		_move(player, _dodge_spot(player), delta)
		return true
	var mine_spot: Vector2 = _mine_escape(player)
	if mine_spot != Vector2.INF:
		_move(player, mine_spot, delta)
		return true
	# Oxygen: to the nearest vent below vent_low, stay until vent_full.
	var ratio: float = player.pressure.get_ratio()
	if ratio < vent_low:
		_going_to_vent[player] = true
	elif ratio >= vent_full:
		_going_to_vent.erase(player)
	var vent: BubbleVent = _nearest_vent(player.global_position)
	if _going_to_vent.has(player) and vent and not danger:
		_move(player, vent.global_position, delta)
		return true
	if danger:
		# Not reacted yet: keeps doing what it did.
		return false
	var center: Vector2 = _boss.global_position
	var side: Vector2 = center.direction_to(_guardian.global_position)
	if side == Vector2.ZERO:
		side = Vector2.UP
	var attacking: bool = _opening_ready()
	var guardian_spot: Vector2 = center + side * (minf(guardian_distance, _boss.body_radius + 50.0) if attacking else guardian_wait_distance)
	if player == _guardian:
		# A summon chasing her (or him): he steps in to cut it down.
		var pest: Creature = _nearest_small_creature(_echo.global_position, 220.0)
		if pest == null:
			pest = _nearest_small_creature(_guardian.global_position, 220.0)
		if pest:
			_move(player, pest.global_position + pest.global_position.direction_to(_guardian.global_position) * 50.0, delta)
		else:
			_move(player, guardian_spot, delta)
			_guardian.facing = _guardian.global_position.direction_to(center)
	else:
		_move(player, guardian_spot + side.orthogonal() * echo_side_offset + side * 20.0, delta)
	return false


func _opening_ready() -> bool:
	var open: bool = _boss.mode == Boss.Mode.RECOVERY or _boss.mode == Boss.Mode.STUNNED or _boss.is_exposed()
	return open and _boss.can_be_hurt() and _opening_left <= 0.0 and not _opening_missed


func _dodge_spot(player: Player) -> Vector2:
	var attack: StringName = _boss.current_attack.id if _boss.current_attack else &""
	var share: float = float(_dodge_scale.get(player, 1.0))
	var away: Vector2 = _boss.global_position.direction_to(player.global_position)
	if away == Vector2.ZERO:
		away = Vector2.UP
	match attack:
		&"charge", &"lunge":
			var aim: Vector2 = _boss.call("get_aim")
			var offset: Vector2 = player.global_position - _boss.global_position
			var across: Vector2 = aim.orthogonal()
			var side: float = signf(offset.dot(across)) if absf(offset.dot(across)) > 1.0 else 1.0
			return _boss.global_position + aim * maxf(offset.dot(aim), 0.0) + across * side * charge_dodge * share
		&"slam":
			return _boss.global_position + away * (float(_boss.get("slam_radius")) + slam_dodge_margin) * share
		&"sweep":
			return _boss.global_position + away * sweep_dodge * share
		&"orbs", &"mines":
			# Not aimed at a spot yet: keep some room.
			return _boss.global_position + away * maxf(_boss.global_position.distance_to(player.global_position), 260.0)
	return _boss.global_position + away * bite_dodge * share


## A known mine about to blow (or right under it): step out of its ring.
func _mine_escape(player: Player) -> Vector2:
	for node: Node in get_tree().get_nodes_in_group("angler_mines"):
		var mine := node as AnglerMine
		if not _known_mines.has(mine):
			continue
		var gap: float = player.global_position.distance_to(mine.global_position)
		var ring: float = mine.blast_radius + mine_dodge_margin
		if gap < ring and mine.get_fuse_left() < 2.0:
			var away: Vector2 = mine.global_position.direction_to(player.global_position)
			return mine.global_position + (away if away != Vector2.ZERO else Vector2.UP) * (ring + 20.0)
	return Vector2.INF


func _move(player: Player, spot: Vector2, delta: float) -> void:
	if player.health.is_downed:
		return
	var offset: Vector2 = spot - player.global_position
	var step: float = minf(offset.length(), player.max_speed * delta)
	if step > 0.5:
		player.move_and_collide(offset.normalized() * step)


func _guardian_attack(busy: bool) -> void:
	_attack_toggle = not _attack_toggle
	var swing: bool = false
	if not _guardian.health.is_downed:
		# An orb coming at him: he tries to bat it back.
		var orb: AnglerOrb = _nearest_orb(_guardian.global_position, 85.0)
		if orb and float(_react_left.get(_guardian, 0.0)) <= 0.0:
			if not orb.has_meta("tried"):
				orb.set_meta("tried", randf() < deflect_chance)
				_deflect_tries += 1
			if bool(orb.get_meta("tried")):
				_guardian.facing = _guardian.global_position.direction_to(orb.global_position)
				swing = true
		elif not busy and _opening_ready() and _boss.is_revealed() \
				and _guardian.global_position.distance_to(_boss.global_position) <= 150.0:
			swing = true
		else:
			# A small creature (the summons) close by: he cuts it down.
			var creature: Creature = _nearest_small_creature(_guardian.global_position, 110.0)
			if creature and creature.is_revealed():
				_guardian.facing = _guardian.global_position.direction_to(creature.global_position)
				swing = true
	if swing and _attack_toggle:
		Input.action_press("p2_action")
	else:
		Input.action_release("p2_action")


func _echo_pulse(delta: float) -> void:
	var pulse: PulseAbility = _find_child_of(_echo, "PulseAbility") as PulseAbility
	if pulse == null or _echo.health.is_downed or not pulse.is_ready():
		Input.action_release("p1_action")
		_pulse_wait = -1.0
		return
	var orb_near: bool = _nearest_orb(_echo.global_position, 260.0) != null or _nearest_orb(_guardian.global_position, 260.0) != null
	if _pulse_wait < 0.0:
		_pulse_wait = randf_range(reaction.x, reaction.y) if orb_near else randf_range(pulse_delay.x, pulse_delay.y)
	_pulse_wait -= delta
	if _pulse_wait <= 0.0 and (_boss.can_be_hurt() or orb_near):
		Input.action_press("p1_action")
		_pulse_wait = -1.0
	else:
		Input.action_release("p1_action")


## With the Lure ready, now and then a decoy just past a pillar or a mine, so
## the charge runs into it (aim off by up to bait_error).
func _echo_bait() -> void:
	var angler := _boss as AnglerBoss
	var lure := _echo.skills.active as LurePulseSkill
	if angler == null or lure == null or _echo.health.is_downed:
		return
	if not lure.is_ready() or _boss.mode != Boss.Mode.IDLE:
		_bait_rolled = false if lure.is_ready() else _bait_rolled
		return
	if _bait_rolled:
		return
	_bait_rolled = true
	if randf() >= bait_chance:
		return
	var targets: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		var pillar := node as ArenaPillar
		if pillar and not pillar.is_broken and _builder._level.is_ancestor_of(pillar):
			targets.append(_center_of(pillar))
	for node: Node in get_tree().get_nodes_in_group("angler_mines"):
		if _known_mines.has(node):
			targets.append((node as Node2D).global_position)
	var best: Vector2 = Vector2.INF
	for point: Vector2 in targets:
		var distance: float = point.distance_to(_boss.global_position)
		if distance < bait_min or distance > bait_max:
			continue
		if best == Vector2.INF or distance < best.distance_to(_boss.global_position):
			best = point
	if best == Vector2.INF:
		return
	var direction: Vector2 = _boss.global_position.direction_to(best)
	var decoy: Vector2 = best - direction * 95.0 + direction.orthogonal() * randf_range(-bait_error, bait_error)
	lure._mark_used()
	_baits += 1
	angler.hear_decoy(decoy, 500.0)


## Downed bots: the other walks over and revives (holding revive_time); both
## down = a defeat, both get up after revive_time. Returns true while reviving.
func _handle_downed(delta: float) -> bool:
	var down_echo: bool = _echo.health.is_downed
	var down_guardian: bool = _guardian.health.is_downed
	if not down_echo and not down_guardian:
		_revive_progress = 0.0
		return false
	if down_echo and down_guardian:
		_revive_progress += delta
		if _revive_progress >= revive_time:
			_echo.health.revive()
			_guardian.health.revive()
			_revives += 2
			_revive_progress = 0.0
		return true
	var downed: Player = _echo if down_echo else _guardian
	var helper: Player = _guardian if down_echo else _echo
	if helper.global_position.distance_to(downed.global_position) > 45.0:
		_move(helper, downed.global_position, delta)
		_revive_progress = 0.0
		return true
	_revive_progress += delta
	if _revive_progress >= revive_time:
		downed.health.revive()
		_revives += 1
		_revive_progress = 0.0
	return true


func _on_player_downed(cause: PlayerHealth.Cause) -> void:
	if cause == PlayerHealth.Cause.PRESSURE:
		_oxygen_downs += 1
	if _echo.health.is_downed and _guardian.health.is_downed:
		_defeats += 1


func _on_player_hit(player: Player) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_phase_hits[_boss.phase] = int(_phase_hits.get(_boss.phase, 0)) + 1
	var source: Node2D = player.health.last_hit_source
	var key: String = "other"
	if source is AnglerOrb:
		key = "orb"
	elif source is AnglerMine:
		key = "mine"
	elif source == _boss:
		key = String(_boss.current_attack.id) if _boss.current_attack else "boss"
	elif source is Creature:
		key = "summon"
	_hit_sources[key] = int(_hit_sources.get(key, 0)) + 1


func _on_damage(info: Dictionary) -> void:
	var result: String = info["result"]
	if result.begins_with("ignored") or result.begins_with("duplicate"):
		return
	var dealt: float = float(info["dealt"])
	_phase_damage[int(info["phase"])] = float(_phase_damage.get(int(info["phase"]), 0.0)) + dealt
	var multipliers: Dictionary = info["multipliers"]
	var kind: String = "mine" if info["source"] == "mine" else ("stunned" if info["mode"] == "STUNNED" else ("armor" if multipliers.has("armor") else "exposed"))
	_kind_damage[kind] = float(_kind_damage.get(kind, 0.0)) + dealt


# --- Helpers -----------------------------------------------------------------------

func _nearest_orb(from: Vector2, within: float) -> AnglerOrb:
	var best: AnglerOrb = null
	for node: Node in get_tree().get_nodes_in_group("deflectables"):
		var orb := node as AnglerOrb
		if orb and orb.is_homing() and orb.global_position.distance_to(from) <= within:
			if best == null or orb.global_position.distance_to(from) < best.global_position.distance_to(from):
				best = orb
	return best


func _nearest_small_creature(from: Vector2, within: float) -> Creature:
	var best: Creature = null
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature == null or creature == _boss or creature.is_dying():
			continue
		if creature.global_position.distance_to(from) <= within:
			if best == null or creature.global_position.distance_to(from) < best.global_position.distance_to(from):
				best = creature
	return best


func _nearest_vent(from: Vector2) -> BubbleVent:
	var best: BubbleVent = null
	for node: Node in get_tree().get_nodes_in_group("bubble_vents"):
		var vent := node as BubbleVent
		if best == null or vent.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = vent
	return best


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
