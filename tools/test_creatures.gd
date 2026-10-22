extends Node
## Headless test of the creature chase and the Echo Shards, run as a scene so
## the Game autoload exists (it loads the real game.tscn):
##   godot --headless --path . --fixed-fps 60 res://tools/test_creatures.tscn
## --fixed-fps makes the simulation run as fast as possible (no real time).
## Checks and reports:
## - chase speed vs player speed per mode, at Depth Awareness 0 / 50 / 100
##   (computed and measured), and that awareness really changes the speeds;
## - the lunge timeline (wind-up, burst, recovery) and the eye flare;
## - alerting (a creature entering CHASE makes nearby ones INVESTIGATE);
## - persistence (CHASE -> SEARCH at the last seen spot -> WANDER);
## - pathing: creatures reaching a far room through doorways, with and without
##   the navigation mesh, on every level;
## - downed Echo: creatures ignore downed players, the distress pulse (reveal,
##   Exposed, no oxygen), the Guardian's close sense (silhouette, eyes, lunge
##   flare) and revive progress that pauses and decays instead of resetting;
## - Sentinels: placement next to shards, health, leash, guard area, return
##   to the post, frenzy ignoring the leash;
## - the lockdown room: doorways close (collision + navigation), the wave per
##   mode, revive / distress pulse / close sense inside, reopening once the
##   wave is dead;
## - the collapse escape: starts on the last shard of a level-2, timer per mode,
##   every creature hunts without losing track, the exit arrow stays on, the
##   timer running out downs both players, a new level stops it;
## - shards: locked ancient light, collection, unlock, the Echo's arrow, and the
##   boss arena door blocking (collision + navigation) until all are collected.

const GAME_SCENE: String = "res://scenes/game.tscn"
const CREATURE_SCENE: String = "res://scenes/creature.tscn"
const PHYSICS_FPS: float = 60.0
## Pathing runs per level (navigation on) and baseline runs (navigation off).
const PATH_RUNS_PER_LEVEL: int = 3
const BASELINE_RUNS_PER_LEVEL: int = 2
## A walk counts as arrived this close to the target.
const ARRIVE_RADIUS: float = 200.0

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _awareness: DepthAwareness
var _echo: Player
var _guardian: Player
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	_stage = _game.get_node("StageManager") as StageManager
	_stage.test_mode = SaveData.Mode.CHALLENGE
	add_child(_game)
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	_awareness = _game.get_node("DepthAwareness") as DepthAwareness
	_echo = _game.get_node("Echo") as Player
	_guardian = _game.get_node("Guardian") as Player
	# No decay: the tests set the awareness themselves.
	_awareness.decay_per_second = 0.0
	await _frames(10)

	await _test_player_speeds()
	await _test_chase_speeds()
	await _test_lunge()
	await _test_alert()
	await _test_search()
	await _test_downed_ignored()
	await _test_distress_pulse()
	await _test_close_sense()
	await _test_revive_decay()
	await _test_sentinel()
	await _test_lockdown()
	await _test_escape()
	await _test_shards()
	await _test_pathing()

	print("RESULT: %s" % ("ALL CREATURE CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures))
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


# --- Downed Echo -------------------------------------------------------------

func _test_downed_ignored() -> void:
	print("== Creatures ignore downed players ==")
	await _build(0, 0)
	_guardian.global_position = _far_spot(_echo.global_position, 750.0)
	var creature: Creature = _spawn_creature(_open_spot(_echo.global_position, 150.0))
	creature._spot(_echo)
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	await _frames(3)
	_check(creature.state != Creature.State.CHASE, "a chase on a player who goes down ends")
	creature._end_search()
	creature._respot_left = 0.0
	await _frames(10)
	_check(creature.state != Creature.State.CHASE, "a downed player is never spotted")
	creature.hear_pulse(_echo.global_position, _echo)
	_check(creature.state != Creature.State.CHASE, "a downed player's pulse does not give them away")
	var before: float = _echo.health.value
	_echo.health._invulnerable_left = 0.0
	_echo.health.take_hit(creature.global_position)
	_check(_echo.health.value == before and _echo.health.is_downed, "a downed player takes no damage")
	creature.queue_free()
	_protect_players()


func _test_distress_pulse() -> void:
	print("== Distress pulse (downed Echo) ==")
	await _build(0, 0)
	var distress: DistressPulse = _echo.get_node("DistressPulse") as DistressPulse
	_guardian.global_position = _far_spot(_echo.global_position, 750.0)
	var near: Creature = _spawn_creature(_open_spot(_echo.global_position, distress.get_radius() * 0.6))
	var far: Creature = _spawn_creature(_far_spot(_echo.global_position, distress.get_radius() * 2.5))
	for creature: Creature in [near, far]:
		creature.set_physics_process(false)
	await _frames(2)
	# Not downed: the button is the normal pulse, the distress pulse stays unused.
	Input.action_press("p1_action")
	await _frames(2)
	Input.action_release("p1_action")
	_check(distress.is_ready(), "no distress pulse while the Echo is up")
	# Clear the normal pulse's reveal (their physics is off, so it does not run out).
	await _frames(int(3.5 * PHYSICS_FPS))
	for creature: Creature in [near, far]:
		creature._exposed_left = 0.0
		creature._revealed_left = 0.0
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	var oxygen: float = _echo.pressure.value
	var pulses: int = _stage.pulses_used
	Input.action_press("p1_action")
	await _frames(2)
	Input.action_release("p1_action")
	_check(not distress.is_ready() and absf(distress.cooldown_left - distress.get_cooldown()) < 0.1,
		"a downed Echo's button sends the distress pulse (cooldown %.1f s)" % distress.get_cooldown())
	await _frames(int((distress.expand_time + 0.15) * PHYSICS_FPS))
	print("  radius %.0f px | near creature %.0f px: revealed %s, exposed %s | far creature %.0f px: exposed %s" % [
		distress.get_radius(), near.global_position.distance_to(_echo.global_position), near.is_revealed(), near.is_exposed(),
		far.global_position.distance_to(_echo.global_position), far.is_exposed()])
	_check(near.is_revealed() and near.is_exposed(), "it reveals and Exposes a creature inside its radius")
	_check(not far.is_exposed(), "a creature outside its radius is not Exposed")
	_check(is_equal_approx(_echo.pressure.value, oxygen), "it costs no oxygen")
	_check(_stage.pulses_used == pulses, "it is not a normal pulse (no Depth Awareness, no spotting)")
	Input.action_press("p1_action")
	await _frames(2)
	Input.action_release("p1_action")
	_check(distress.cooldown_left < distress.get_cooldown() - 0.3, "the cooldown blocks a second pulse")
	near.queue_free()
	far.queue_free()
	_protect_players()


func _test_close_sense() -> void:
	print("== Guardian close sense ==")
	await _build(0, 0)
	var sense: CloseSense = _guardian.get_node("CloseSense") as CloseSense
	# The Echo is downed far away: no light of hers reveals anything near him.
	_echo.global_position = _far_spot(_guardian.global_position, 750.0)
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	var close: Creature = _spawn_creature(_open_spot(_guardian.global_position, sense.get_radius() * 0.8))
	var outside: Creature = _spawn_creature(_open_spot(_guardian.global_position, sense.get_radius() + sense.fade_band + 80.0))
	var close_spot: Vector2 = close.global_position
	var outside_spot: Vector2 = outside.global_position
	for i: int in 20:
		await get_tree().physics_frame
		close.global_position = close_spot
		outside.global_position = outside_spot
		close.velocity = Vector2.ZERO
		outside.velocity = Vector2.ZERO
	var close_eyes: CreatureEyes = close.get_node("EchoLayer/Eyes") as CreatureEyes
	print("  radius %.0f px | close creature: sense %.2f, silhouette %.2f, eyes %.2f, hittable %s | outside: sense %.2f" % [
		sense.get_radius(), close.sense_ratio, close.silhouette_ratio, close_eyes._alpha, close.is_revealed(), outside.sense_ratio])
	_check(close.sense_ratio >= 1.0 and close.silhouette_ratio >= 1.0, "a creature within the radius is shown as a silhouette")
	_check(close_eyes._alpha >= close_eyes.sensed_eye_share * 0.99, "its eyes glow clearly")
	_check(close.is_revealed() and not close.is_exposed(), "a sensed creature is hittable but not Exposed")
	var sword: SwordAbility = _guardian.get_node("UnlitLayer/Sword") as SwordAbility
	var health_before: int = close.health
	var killed: bool = close.take_damage(sword.finisher_damage, _guardian, 0.0, 0.0, true)
	_check(not killed and close.health == health_before - sword.finisher_damage, "a finisher on it deals normal damage (no instant kill)")
	_check(sword.finisher_range <= sense.get_radius(), "the sword's reach is inside the close sense")
	_check(not outside.is_revealed(), "a creature beyond it is not hittable")
	_check(outside.sense_ratio == 0.0, "beyond the radius the normal rules apply")
	close.queue_free()
	outside.queue_free()
	await _frames(2)
	# The lunge wind-up flare is visible to him even outside the sense radius.
	var lunger: Creature = _spawn_creature(_open_spot(_guardian.global_position, 260.0))
	var lunger_eyes: CreatureEyes = lunger.get_node("EchoLayer/Eyes") as CreatureEyes
	lunger._spot(_guardian)
	var flare_alpha: float = -1.0
	for i: int in int(4.0 * PHYSICS_FPS):
		await get_tree().physics_frame
		_guardian.health._invulnerable_left = 999.0
		if lunger.lunge_phase == Creature.Lunge.WIND_UP:
			await get_tree().process_frame
			flare_alpha = lunger_eyes._alpha
			break
	print("  lunge wind-up: eye alpha %.2f at %.0f px from the Guardian" % [flare_alpha, lunger.global_position.distance_to(_guardian.global_position)])
	_check(flare_alpha > 0.0, "the lunge wind-up flare shows without the Echo")
	lunger.queue_free()
	_protect_players()


func _test_revive_decay() -> void:
	print("== Revive progress (interrupted) ==")
	await _build(0, 0)
	var helper: ReviveHelper = _guardian.get_node("Revive") as ReviveHelper
	var delay: float = helper.challenge_decay_delay if helper.challenge_mode else helper.calm_decay_delay
	var decay: float = helper.challenge_decay_per_second if helper.challenge_mode else helper.calm_decay_per_second
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	_guardian.global_position = _echo.global_position + Vector2(30.0, 0.0)
	await _frames(2)
	Input.action_press("p2_action")
	await _frames(int(helper.revive_time * 0.5 * PHYSICS_FPS))
	Input.action_release("p2_action")
	var held: float = helper.get_progress_ratio()
	await _frames(int(delay * 0.8 * PHYSICS_FPS))
	var paused: float = helper.get_progress_ratio()
	await _frames(int((delay * 0.2 + 1.0) * PHYSICS_FPS))
	var decayed: float = helper.get_progress_ratio()
	print("  held %.2f -> paused %.2f -> after 1 s of decay %.2f (expected %.2f)" % [held, paused, decayed, held - decay])
	_check(held > 0.4, "holding fills the progress")
	_check(is_equal_approx(paused, held), "letting go pauses the progress (decay delay %.1f s)" % delay)
	_check(absf(decayed - (held - decay)) < 0.05, "then it decays %.0f%% per second" % (decay * 100.0))
	# Stepping away keeps the progress too.
	var kept: float = helper.get_progress_ratio()
	_guardian.global_position = _echo.global_position + Vector2(helper.revive_distance * 2.0, 0.0)
	await _frames(5)
	_check(helper.get_progress_ratio() > 0.0 and helper.get_progress_ratio() >= kept - 0.02, "stepping away does not reset it")
	_guardian.global_position = _echo.global_position + Vector2(30.0, 0.0)
	Input.action_press("p2_action")
	await _frames(int(helper.revive_time * PHYSICS_FPS))
	Input.action_release("p2_action")
	_check(not _echo.health.is_downed and helper.progress == 0.0, "finishing revives and resets the progress")
	_protect_players()


# --- Phase 3: Sentinels, lockdown, collapse escape ----------------------------

func _test_sentinel() -> void:
	print("== Sentinels ==")
	var world: WorldConfig = _stage.world
	var placed_ok: bool = true
	for stage_index: int in world.get_stage_count():
		for level_index: int in world.get_level_count(stage_index):
			var definition: LevelDefinition = world.get_level(stage_index, level_index)
			_stage.stage_index = stage_index
			_stage._start_level(level_index)
			var sentinels: int = 0
			for creature: Creature in _builder.get_creatures():
				var sentinel := creature as Sentinel
				if sentinel == null:
					continue
				sentinels += 1
				var nearest: float = INF
				for shard: EchoShard in _builder.get_shards():
					nearest = minf(nearest, shard.global_position.distance_to(sentinel.post))
				if nearest > _builder.sentinel_post_offset + 1.0:
					placed_ok = false
			if sentinels != mini(definition.sentinels, definition.shard_count):
				placed_ok = false
	_check(placed_ok, "every level has its Sentinels, each posted next to a shard")

	await _build(0, 0)
	_guardian.global_position = _far_spot(_echo.global_position, 750.0)
	var post_spot: Vector2 = _open_spot(_echo.global_position, 160.0)
	var sentinel: Sentinel = _spawn_creature(post_spot, world.sentinel_scene) as Sentinel
	await _frames(2)
	sentinel.set_challenge_mode(true)
	var basic: Creature = _spawn_creature(_far_spot(post_spot, 900.0))
	print("  health %d (basic creature %d) | guard %.0f px, leash %.0f px" % [
		sentinel.health, basic.max_health, sentinel.get_guard_radius(), sentinel.get_leash_radius()])
	basic.queue_free()
	_check(sentinel.health > basic.max_health, "a Sentinel is tougher than a basic creature")
	# Spots and chases a player near its post.
	for i: int in int(1.0 * PHYSICS_FPS):
		await get_tree().physics_frame
		_protect_players()
		if sentinel.state == Creature.State.CHASE:
			break
	_check(sentinel.state == Creature.State.CHASE, "it chases a player near its post")
	# The player leaves the leash: it gives up and swims back to its post.
	_echo.global_position = _far_spot(sentinel.post, sentinel.get_leash_radius() + 350.0)
	var gave_up: bool = false
	var back_at: float = -1.0
	for i: int in int(14.0 * PHYSICS_FPS):
		await get_tree().physics_frame
		_protect_players()
		if sentinel.state != Creature.State.CHASE:
			gave_up = true
		if gave_up and sentinel.state == Creature.State.WANDER and sentinel.global_position.distance_to(sentinel.post) <= sentinel.get_guard_radius() + 20.0:
			back_at = (i + 1) / PHYSICS_FPS
			break
	print("  player beyond the leash: gave up %s, back inside its guard area after %.1f s" % [gave_up, back_at])
	_check(gave_up, "it stops chasing beyond its leash")
	_check(back_at > 0.0, "it returns to its post")
	# A far noise: it investigates only up to the edge of its guard area.
	sentinel.hear_noise(sentinel.post + Vector2(900.0, 0.0), 2000.0)
	_check(sentinel.state == Creature.State.INVESTIGATE and sentinel.target.distance_to(sentinel.post) <= sentinel.get_guard_radius() + 0.5,
		"it investigates noises, but only inside its guard area")
	# The collapse escape: the leash no longer holds it.
	sentinel.set_frenzy(true)
	await _frames(3)
	_check(sentinel.state == Creature.State.CHASE, "in a frenzy it hunts beyond its leash")
	sentinel.queue_free()
	_protect_players()


func _test_lockdown() -> void:
	print("== Lockdown room ==")
	await _build(0, 0)
	var lockdown: LockdownRoom = _builder.get_lockdown()
	_check(lockdown != null, "the level has a lockdown room")
	if lockdown == null:
		return
	var definition: LevelDefinition = _builder._definition
	_check(definition.get_lockdown_wave(false) < definition.get_lockdown_wave(true), "fewer wave creatures in Calm (%d) than in Challenge (%d)" % [
		definition.get_lockdown_wave(false), definition.get_lockdown_wave(true)])
	lockdown.enabled = true
	var map: RID = get_viewport().world_2d.navigation_map
	var center: Vector2 = NavigationServer2D.map_get_closest_point(map, _builder.to_global(lockdown.room_rect.get_center()))
	var outside: Vector2 = _builder.get_spawn_position(1)
	# One player inside is not enough.
	_echo.global_position = center
	await _frames(5)
	_check(not lockdown.is_locked(), "one player inside does not lock it")
	_teleport_players(center)
	await _frames(3)
	_check(lockdown.is_locked(), "both players inside lock the doorways")
	var barriers_blocked: bool = true
	for polygon: PackedVector2Array in lockdown.get_obstacles():
		var middle := Vector2.ZERO
		for point: Vector2 in polygon:
			middle += point
		if not _point_blocked(_builder.to_global(middle / polygon.size())):
			barriers_blocked = false
	_check(not lockdown.get_obstacles().is_empty() and barriers_blocked, "every doorway is sealed (%d)" % lockdown.get_obstacles().size())
	await _frames(int((lockdown.wake_delay + 0.3) * PHYSICS_FPS))
	var closed_path: PackedVector2Array = NavigationServer2D.map_get_path(map, center, outside, true)
	var closed_gap: float = closed_path[closed_path.size() - 1].distance_to(outside) if closed_path.size() > 0 else INF
	_check(closed_gap > 200.0, "the navigation no longer leads out")
	print("  wave: %d creatures (Challenge) | path out ends %.0f px from the target while locked" % [lockdown.get_wave().size(), closed_gap])
	_check(lockdown.get_wave().size() == lockdown.get_wave_size(), "the wave wakes")
	for creature: Creature in lockdown.get_wave():
		(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)

	# Downed inside: the distress pulse, the close sense and the revive all work.
	_protect_players()
	_echo.health.down(PlayerHealth.Cause.CREATURE)
	var distress: DistressPulse = _echo.get_node("DistressPulse") as DistressPulse
	distress.cooldown_left = 0.0
	Input.action_press("p1_action")
	await _frames(2)
	Input.action_release("p1_action")
	_check(not distress.is_ready(), "a downed Echo can send the distress pulse inside")
	var near_wave: Creature = lockdown.get_wave()[0]
	near_wave.set_physics_process(false)
	near_wave.global_position = _open_spot(_guardian.global_position, 60.0)
	near_wave.set_physics_process(true)
	await _frames(2)
	near_wave.global_position = _open_spot(_guardian.global_position, 60.0)
	await _frames(1)
	_check(near_wave.sense_ratio >= 1.0 and near_wave.is_revealed(), "the Guardian senses (and can hit) a wave creature next to him")
	_guardian.global_position = _echo.global_position + Vector2(30.0, 0.0)
	var helper: ReviveHelper = _guardian.get_node("Revive") as ReviveHelper
	Input.action_press("p2_action")
	await _frames(int((helper.revive_time + 0.2) * PHYSICS_FPS))
	Input.action_release("p2_action")
	_check(not _echo.health.is_downed, "the Guardian can revive the Echo inside")

	# The wave dies: the doorways open again.
	for creature: Creature in lockdown.get_wave():
		if is_instance_valid(creature):
			creature.take_damage(999, _guardian, 0.0, 0.0)
	await _frames(20)
	var open_path: PackedVector2Array = NavigationServer2D.map_get_path(map, center, outside, true)
	var open_gap: float = open_path[open_path.size() - 1].distance_to(outside) if open_path.size() > 0 else INF
	_check(lockdown.phase == LockdownRoom.Phase.CLEARED and lockdown.get_obstacles().is_empty(), "with the wave dead the doorways open")
	_check(open_gap < 60.0, "the navigation leads out again")
	_teleport_players(outside)
	await _frames(5)
	_teleport_players(center)
	await _frames(5)
	_check(not lockdown.is_locked(), "it happens only once per attempt")
	_protect_players()


func _test_escape() -> void:
	print("== Collapse escape (stage 1 level 2) ==")
	await _build(0, 1)
	var escape: EscapeEvent = _game.get_node("EnvironmentLayer/EscapeEvent") as EscapeEvent
	var definition: LevelDefinition = _builder._definition
	var goal: AncientLight = _builder.get_goal()
	_check(definition.escape_event, "level 2 of the stage has the collapse escape")
	_check(definition.get_escape_time(false) > definition.get_escape_time(true), "the Calm timer is longer (%.0f s vs %.0f s)" % [
		definition.get_escape_time(false), definition.get_escape_time(true)])
	var hunters: Array[Creature] = []
	for i: int in 2:
		var hunter: Creature = _spawn_creature(_far_spot(goal.global_position, 500.0 + i * 200.0))
		hunter.safe_zone_push = 0.0
		hunters.append(hunter)
	var shards: Array[EchoShard] = _builder.get_shards().duplicate()
	for i: int in shards.size():
		if i == shards.size() - 1:
			_check(not escape.is_active, "no collapse before the last shard")
		_teleport_players(shards[i].global_position)
		await _frames(3)
	_check(escape.is_active and absf(escape.time_left - definition.get_escape_time(true)) < 0.5, "the last shard starts it (%.0f s, Challenge)" % escape.time_left)
	_teleport_players(_builder.get_spawn_position(1))
	var arrow: GoalEcho = _echo.get_node("UnlitLayer/GoalEcho") as GoalEcho
	await _frames(int(3.0 * PHYSICS_FPS))
	var all_hunting: bool = true
	for hunter: Creature in hunters:
		if not is_instance_valid(hunter) or hunter.state != Creature.State.CHASE or not hunter.is_frenzied:
			all_hunting = false
	_check(all_hunting, "every creature hunts the players (still after 3 s, without sight)")
	_check(arrow.is_showing() and arrow._find_target() == goal, "the Echo's arrow points to the exit and stays on")
	# Time runs out: both players are downed by the collapse.
	_stage.is_over = true
	escape.time_left = 0.05
	await _frames(5)
	_check(_echo.health.is_downed and _guardian.health.is_downed and _echo.health.last_cause == PlayerHealth.Cause.COLLAPSE,
		"the timer running out downs both players (collapse)")
	_check(not escape.is_active, "then it stops")
	_stage.is_over = false
	_protect_players()
	# A new level never starts in a collapse.
	escape.start(10.0)
	await _build(0, 1)
	_check(not escape.is_active, "a new attempt starts without the collapse")
	for hunter: Creature in hunters:
		if is_instance_valid(hunter):
			hunter.queue_free()


# --- Speeds -------------------------------------------------------------------

func _test_player_speeds() -> void:
	print("== Player top speed (measured, holding a direction for 1.5 s) ==")
	for player: Player in [_echo, _guardian]:
		await _build(0, 0)
		var action: String = player.input_prefix + "move_right"
		var best: float = 0.0
		Input.action_press(action)
		for i: int in int(1.5 * PHYSICS_FPS):
			await get_tree().physics_frame
			best = maxf(best, player.velocity.length())
		Input.action_release(action)
		print("  %-8s max_speed %.0f, measured %.0f px/s" % [player.display_name, player.max_speed, best])


func _test_chase_speeds() -> void:
	print("== Chase speed vs player speed (ratio of the chased player's max_speed) ==")
	await _build(0, 0)
	var creature: Creature = _spawn_creature(_open_spot(_echo.global_position, 300.0))
	var awareness_steps: Array[float] = [0.0, 50.0, 100.0]
	for challenge: bool in [false, true]:
		creature.challenge_mode = challenge
		for value: float in awareness_steps:
			_awareness.value = value
			var ratio: float = creature.get_chase_ratio()
			print("  %-9s awareness %3.0f: ratio %.2f -> vs Echo %.0f / %.0f px/s, vs Guardian %.0f / %.0f px/s | wander/investigate %.0f px/s" % [
				"Challenge" if challenge else "Calm", value, ratio,
				_echo.max_speed * ratio, _echo.max_speed, _guardian.max_speed * ratio, _guardian.max_speed,
				lerpf(creature.min_speed, creature.max_speed, _awareness.get_ratio())])
			_check(ratio <= 1.0 + 0.001, "chase ratio never above 1.0")
		_awareness.value = 0.0
		var low: float = creature.get_chase_ratio()
		_awareness.value = 100.0
		var high: float = creature.get_chase_ratio()
		_check(high > low, "Depth Awareness raises the chase speed (%s)" % ("Challenge" if challenge else "Calm"))
	_awareness.value = 0.0
	creature.queue_free()

	print("== Measured chase speed (creature chasing the Echo, lunges off) ==")
	for challenge: bool in [false, true]:
		for value: float in [0.0, 100.0]:
			await _build(0, 0)
			_awareness.value = value
			# The Guardian waits far away, so the creature only chases the Echo.
			_guardian.global_position = _far_spot(_echo.global_position, 750.0)
			var chaser: Creature = _spawn_creature(_open_spot(_echo.global_position, 450.0))
			chaser.challenge_mode = challenge
			chaser.lunge_enabled = false
			chaser.safe_zone_push = 0.0
			chaser._spot(_echo)
			var total: float = 0.0
			var samples: int = 0
			for i: int in int(2.0 * PHYSICS_FPS):
				await get_tree().physics_frame
				_protect_players()
				if i > 30 and chaser.state == Creature.State.CHASE and chaser._chased == _echo 						and chaser.global_position.distance_to(_echo.global_position) > 120.0:
					total += chaser.velocity.length()
					samples += 1
			var measured: float = total / maxf(samples, 1)
			var expected: float = _echo.max_speed * chaser.get_chase_ratio()
			print("  %-9s awareness %3.0f: expected %.0f, measured %.0f px/s over %d frames (Echo %.0f)" % [
				"Challenge" if challenge else "Calm", value, expected, measured, samples, _echo.max_speed])
			_check(samples > 0 and measured <= _echo.max_speed + 1.0, "measured chase speed not faster than the Echo")
			chaser.queue_free()
	_awareness.value = 0.0


# --- Lunge, alert, search -----------------------------------------------------

func _test_lunge() -> void:
	print("== Lunge ==")
	await _build(0, 0)
	var creature: Creature = _spawn_creature(_open_spot(_echo.global_position, 260.0))
	creature._spot(_echo)
	var eyes: CreatureEyes = creature.get_node("EchoLayer/Eyes") as CreatureEyes
	var timeline: Array[String] = []
	var phase: Creature.Lunge = Creature.Lunge.NONE
	var phase_start: float = 0.0
	var flare_at_burst: float = 0.0
	var sound_played: bool = false
	var max_speed: float = 0.0
	var completed: bool = false
	for i: int in int(5.0 * PHYSICS_FPS):
		await get_tree().physics_frame
		_protect_players()
		var t: float = (i + 1) / PHYSICS_FPS
		if creature.lunge_phase != phase:
			if phase != Creature.Lunge.NONE:
				timeline.append("%s %.2fs" % [Creature.Lunge.keys()[phase], t - phase_start])
			if creature.lunge_phase == Creature.Lunge.BURST:
				flare_at_burst = eyes._flare
			if creature.lunge_phase == Creature.Lunge.WIND_UP:
				sound_played = creature._lunge_sound.playing
			if phase == Creature.Lunge.RECOVER:
				completed = true
				break
			phase = creature.lunge_phase
			phase_start = t
		if phase == Creature.Lunge.BURST:
			max_speed = maxf(max_speed, creature.velocity.length())
	print("  timeline: %s | burst speed %.0f px/s | eye flare at burst %.2f | sound %s" % [
		", ".join(timeline), max_speed, flare_at_burst, "yes" if sound_played else "no"])
	_check(completed, "lunge runs WIND_UP -> BURST -> RECOVER -> done")
	_check(timeline.size() >= 1 and absf(float(timeline[0].split(" ")[1].trim_suffix("s")) - creature.lunge_wind_up) < 0.05, "wind-up lasts lunge_wind_up")
	_check(flare_at_burst > 0.9, "eyes flare during the wind-up")
	_check(sound_played, "lunge sound plays at the wind-up")
	creature.queue_free()


func _test_alert() -> void:
	print("== Alerting ==")
	await _build(0, 0)
	var spotter: Creature = _spawn_creature(_open_spot(_echo.global_position, 260.0))
	var near: Creature = _spawn_creature(_far_spot(spotter.global_position, 450.0))
	var far: Creature = _spawn_creature(_far_spot(spotter.global_position, 1300.0))
	for other: Creature in [near, far]:
		other.spot_distance = 0.0
		other.pulse_spot_distance = 0.0
	await _frames(2)
	var near_distance: float = near.global_position.distance_to(spotter.global_position)
	var far_distance: float = far.global_position.distance_to(spotter.global_position)
	spotter._spot(_echo)
	await _frames(1)
	print("  creature %.0f px away: %s | creature %.0f px away: %s (alert_radius %.0f)" % [
		near_distance, near.get_state_name(), far_distance, far.get_state_name(), spotter.alert_radius])
	_check(near_distance > spotter.alert_radius or near.state == Creature.State.INVESTIGATE, "a creature inside alert_radius investigates")
	_check(far_distance <= spotter.alert_radius or far.state == Creature.State.WANDER, "a creature outside alert_radius keeps wandering")
	for creature: Creature in [spotter, near, far]:
		creature.queue_free()


func _test_search() -> void:
	print("== Persistence (lose sight -> SEARCH -> WANDER) ==")
	await _build(0, 0)
	var creature: Creature = _spawn_creature(_open_spot(_echo.global_position, 300.0))
	creature.lunge_enabled = false
	creature._spot(_echo)
	await _frames(10)
	# The players vanish far away (another room): the creature loses sight.
	var away: Vector2 = _builder.to_global(_builder._nav_bounds.end - Vector2(300.0, 300.0))
	_echo.global_position = away
	_guardian.global_position = away + Vector2(40.0, 0.0)
	var lost_at: float = -1.0
	var arrived_at: float = -1.0
	var wander_at: float = -1.0
	for i: int in int(20.0 * PHYSICS_FPS):
		await get_tree().physics_frame
		_protect_players()
		var t: float = (i + 1) / PHYSICS_FPS
		if lost_at < 0.0 and creature.state == Creature.State.SEARCH:
			lost_at = t
		if arrived_at < 0.0 and creature.state == Creature.State.SEARCH and creature._search_arrived:
			arrived_at = t
		if lost_at >= 0.0 and creature.state == Creature.State.WANDER:
			wander_at = t
			break
	print("  SEARCH after %.2fs (chase_memory %.1f), at the last seen spot after %.2fs, WANDER after %.2fs (search_time %.1f)" % [
		lost_at, creature.chase_memory, arrived_at, wander_at, creature.search_time])
	_check(lost_at > 0.0 and lost_at < creature.chase_memory + 0.3, "loses sight after about chase_memory")
	_check(arrived_at > 0.0, "reaches the last seen spot")
	_check(wander_at > 0.0 and wander_at - arrived_at >= creature.search_time - 0.1, "searches search_time seconds before wandering")
	creature.queue_free()


# --- Shards -------------------------------------------------------------------

func _test_shards() -> void:
	print("== Echo Shards + locked ancient light (stage 1 level 1) ==")
	await _build(0, 0)
	var goal: AncientLight = _builder.get_goal()
	goal.activated.disconnect(_stage._on_ancient_light_activated)
	var shards: Array[EchoShard] = _builder.get_shards().duplicate()
	_check(shards.size() == _builder._definition.shard_count, "every planned shard is spawned (%d)" % shards.size())
	_check(goal.is_locked(), "the ancient light starts locked")
	_teleport_players(goal.global_position + Vector2(30.0, 0.0))
	await _frames(int(goal.activation_time * PHYSICS_FPS) + 20)
	_check(not goal.is_active and goal.charge == 0.0, "a locked ancient light does not charge")
	var arrow: GoalEcho = _echo.get_node("UnlitLayer/GoalEcho") as GoalEcho
	for i: int in shards.size():
		var target: Node2D = arrow._find_target()
		var nearest: EchoShard = _nearest_shard(shards)
		_check(target == nearest, "the Echo's arrow points to the nearest shard")
		_teleport_players(nearest.global_position)
		await _frames(3)
		shards.erase(nearest)
		print("  collected %d / %d (exit %s)" % [_stage.shards_collected, _stage.shards_total, "locked" if goal.is_locked() else "open"])
	_check(not goal.is_locked(), "all shards unlock the ancient light")
	_check(arrow._find_target() == goal, "then the arrow points to the ancient light")
	_teleport_players(goal.global_position + Vector2(30.0, 0.0))
	await _frames(int(goal.activation_time * PHYSICS_FPS) + 20)
	_check(goal.is_active, "the unlocked ancient light activates")

	print("== Boss arena door (stage 1 level 3) ==")
	await _build(0, 2)
	var door: ShardDoor = _builder.get_exit_door()
	var boss: Creature = _builder.get_boss()
	_check(door != null, "the boss level has an arena door")
	if door == null or boss == null:
		return
	boss.set_physics_process(false)
	var map: RID = get_viewport().world_2d.navigation_map
	var door_center: Vector2 = door.to_global(door._center)
	_check(_point_blocked(door_center), "the closed door blocks (collision)")
	var start: Vector2 = _builder.get_spawn_position(1)
	var closed_path: PackedVector2Array = NavigationServer2D.map_get_path(map, start, boss.global_position, true)
	var closed_gap: float = closed_path[closed_path.size() - 1].distance_to(boss.global_position) if closed_path.size() > 0 else INF
	for shard: EchoShard in _builder.get_shards().duplicate():
		_teleport_players(shard.global_position)
		await _frames(3)
	_check(door.is_open, "all shards open the arena door")
	_teleport_players(start)
	await _frames(20)
	var open_path: PackedVector2Array = NavigationServer2D.map_get_path(map, start, boss.global_position, true)
	var open_gap: float = open_path[open_path.size() - 1].distance_to(boss.global_position) if open_path.size() > 0 else INF
	print("  navigation path start -> boss ends %.0f px from the boss with the door closed, %.0f px when open" % [closed_gap, open_gap])
	_check(closed_gap > 100.0, "creatures cannot path through the closed door")
	_check(open_gap < 60.0, "creatures can path through the open door")
	_check(not _point_blocked(door_center), "the open door no longer blocks")


# --- Pathing ------------------------------------------------------------------

func _test_pathing() -> void:
	print("== Pathing: a creature walks from a far creature spot to the start (awareness 100 -> %0.f px/s) ==" % 190.0)
	var totals: Dictionary = {true: [0, 0], false: [0, 0]}
	var world: WorldConfig = _stage.world
	for stage_index: int in world.get_stage_count():
		for level_index: int in world.get_level_count(stage_index):
			await _build(stage_index, level_index)
			var start: Vector2 = _builder.get_spawn_position(1)
			var spots: Array[Vector2] = _builder.creature_spots.duplicate()
			spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(start) > b.distance_to(start))
			var line: String = "  Stage %d level %d:" % [stage_index + 1, level_index + 1]
			for navigation: bool in [true, false]:
				var runs: int = PATH_RUNS_PER_LEVEL if navigation else BASELINE_RUNS_PER_LEVEL
				var arrived: int = 0
				var times: PackedStringArray = PackedStringArray()
				for run: int in mini(runs, spots.size()):
					var result: float = await _walk(spots[run], start, navigation)
					arrived += 1 if result >= 0.0 else 0
					times.append(("%.0fs" % result if result >= 0.0 else "stuck") + " (ideal %.0fs)" % _last_ideal_time)
				(totals[navigation] as Array)[0] += arrived
				(totals[navigation] as Array)[1] += mini(runs, spots.size())
				line += " %s %s" % ["nav" if navigation else "| no nav", " ".join(times)]
			print(line)
	var on: Array = totals[true]
	var off: Array = totals[false]
	print("  arrived with navigation %d / %d, without %d / %d" % [on[0], on[1], off[0], off[1]])
	_check(on[0] == on[1], "with navigation every walk arrives")


## Walks a fresh creature from `from` to `to` (INVESTIGATE). Returns the time in
## seconds, or -1 if it did not arrive within the time limit. _last_ideal_time
## is the time along the shortest path at full speed.
var _last_ideal_time: float = 0.0


func _walk(from: Vector2, to: Vector2, navigation: bool) -> float:
	var map: RID = get_viewport().world_2d.navigation_map
	var path: PackedVector2Array = NavigationServer2D.map_get_path(map, from, to, true)
	var length: float = 0.0
	for i: int in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	_awareness.value = _awareness.max_value
	var creature: Creature = _spawn_creature(from)
	creature.use_navigation = navigation
	creature.spot_distance = 0.0
	creature.pulse_spot_distance = 0.0
	creature.responds_to_alerts = false
	await _frames(1)
	creature.hear_noise(to, INF)
	_last_ideal_time = maxf(length - ARRIVE_RADIUS, 0.0) / creature.max_speed
	var limit: float = length / creature.max_speed * 1.6 + 4.0
	var result: float = -1.0
	for i: int in int(limit * PHYSICS_FPS):
		await get_tree().physics_frame
		_protect_players()
		if creature.global_position.distance_to(to) <= ARRIVE_RADIUS:
			result = (i + 1) / PHYSICS_FPS
			break
	creature.queue_free()
	_awareness.value = 0.0
	await _frames(1)
	return result


# --- Helpers ------------------------------------------------------------------

## Builds a level (stage, level) like the StageManager does, without other
## creatures, and puts the players at its start.
func _build(stage_index: int, level_index: int) -> void:
	_stage.stage_index = stage_index
	_stage._start_level(level_index)
	_clear_creatures()
	if _builder.get_boss():
		_builder.get_boss().set_physics_process(false)
	# The lockdown only runs in its own test (players are teleported around).
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	_awareness.value = 0.0
	# The navigation map syncs a few physics frames after the level is built.
	await _frames(12)
	_protect_players()


func _clear_creatures() -> void:
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature and creature != _builder.get_boss():
			creature.remove_from_group("creatures")
			creature.queue_free()


func _spawn_creature(at: Vector2, scene: PackedScene = null) -> Creature:
	var source: PackedScene = scene if scene else load(CREATURE_SCENE) as PackedScene
	var creature := source.instantiate() as Creature
	creature.position = _builder.to_local(at)
	_builder._level.add_child(creature)
	creature.challenge_mode = _stage.mode == SaveData.Mode.CHALLENGE
	# Never hurts the players during the tests.
	(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)
	return creature


## Keeps both players alive and full during the tests.
func _protect_players() -> void:
	for player: Player in [_echo, _guardian]:
		if player.health.is_downed:
			player.health.revive()
		player.health._invulnerable_left = 999.0
		player.pressure.refill()


func _teleport_players(at: Vector2) -> void:
	_echo.global_position = at
	_guardian.global_position = at + Vector2(10.0, 0.0)
	_echo.velocity = Vector2.ZERO
	_guardian.velocity = Vector2.ZERO


## A walkable point about `distance` away from `center`, in line of sight.
func _open_spot(center: Vector2, distance: float) -> Vector2:
	var map: RID = get_viewport().world_2d.navigation_map
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	for i: int in 16:
		var candidate: Vector2 = NavigationServer2D.map_get_closest_point(map, center + Vector2.from_angle(TAU * i / 16.0) * distance)
		var query := PhysicsRayQueryParameters2D.create(center, candidate, 1)
		if space.intersect_ray(query).is_empty() and candidate.distance_to(center) > distance * 0.7:
			return candidate
	return NavigationServer2D.map_get_closest_point(map, center + Vector2(distance, 0.0))


## A walkable point roughly `distance` away (line of sight not needed).
func _far_spot(center: Vector2, distance: float) -> Vector2:
	var map: RID = get_viewport().world_2d.navigation_map
	var best: Vector2 = center
	var best_error: float = INF
	for i: int in 24:
		var candidate: Vector2 = NavigationServer2D.map_get_closest_point(map, center + Vector2.from_angle(TAU * i / 24.0) * distance)
		var error: float = absf(candidate.distance_to(center) - distance)
		if error < best_error:
			best_error = error
			best = candidate
	return best


func _nearest_shard(shards: Array[EchoShard]) -> EchoShard:
	var best: EchoShard = null
	var best_distance: float = INF
	for shard: EchoShard in shards:
		var distance: float = _echo.global_position.distance_to(shard.global_position)
		if distance < best_distance:
			best_distance = distance
			best = shard
	return best


func _point_blocked(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not get_viewport().world_2d.direct_space_state.intersect_point(query).is_empty()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("    [%s] %s" % ["ok" if ok else "FAIL", label])
