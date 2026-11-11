extends Node3D
## Headless checks of the 3D core (Phase A): the creature's senses, chase
## speeds, lunge, alerting, search and navigation; the sword's reveal rules and
## the Exposed kill; close sense, distress pulse, revive decay, partner mending,
## sonar occlusion and the goal arrow. Each check builds a small arena of its
## own (floor, rock walls, a navigation mesh baked from the plan).
## godot --headless --path . --fixed-fps 60 res://tools/test_core.tscn
## Exits with 1 when a check fails.

const ECHO_SCENE: PackedScene = preload("res://scenes/echo.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://scenes/guardian.tscn")
const CREATURE_SCENE: PackedScene = preload("res://scenes/creature.tscn")

## The arena: a 24 x 16 floor with a wall across its middle (a gap at one end)
## and a pillar.
const FLOOR_SIZE: Vector2 = Vector2(24.0, 16.0)
const WALL: Array[Vector2] = [Vector2(11.5, 0.0), Vector2(12.5, 0.0), Vector2(12.5, 12.0), Vector2(11.5, 12.0)]
const PILLAR: Array[Vector2] = [Vector2(5.0, 11.0), Vector2(7.0, 11.0), Vector2(7.0, 13.0), Vector2(5.0, 13.0)]
const ROCK_HEIGHT: float = 1.0

var _failures: int = 0
var _checks: int = 0
var _arena: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("TEST CORE (3D)")
	await _test_chase_speeds()
	await _test_spot_and_alert()
	await _test_lunge_hits_once()
	await _test_downed_ignored()
	await _test_search_after_losing_sight()
	await _test_navigation_round_the_wall()
	await _test_sword_reveal_rules()
	await _test_close_sense()
	await _test_distress_pulse()
	await _test_sonar_blocked_by_rock()
	await _test_revive_decay()
	await _test_mending()
	await _test_goal_arrow()
	print("")
	print("%d checks, %d failed" % [_checks, _failures])
	print("RESULT: ", "CORE OK" if _failures == 0 else "CORE FAIL")
	get_tree().quit(0 if _failures == 0 else 1)


# --- Checks -----------------------------------------------------------------------

func _test_chase_speeds() -> void:
	print("- chase speeds")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 3.0))
	var creature: Creature = _add_creature(Vector3(6.0, 0.0, 3.0))
	await _frames(2)
	creature.hunt(echo)
	var awareness: DepthAwareness = _arena.get_node("DepthAwareness")
	awareness.value = 0.0
	_check_near(creature.get_chase_speed() / echo.max_speed, 0.82, 0.001, "Calm, no awareness: 0.82 of the player's speed")
	awareness.value = awareness.max_value
	_check_near(creature.get_chase_speed() / echo.max_speed, 0.88, 0.001, "Calm, full awareness: 0.88")
	creature.set_challenge_mode(true)
	_check_near(creature.get_chase_speed() / echo.max_speed, 1.0, 0.001, "Challenge, full awareness: 1.0 (never clearly faster)")
	awareness.value = 0.0
	_check_near(creature.get_chase_speed() / echo.max_speed, 0.95, 0.001, "Challenge, no awareness: 0.95")


func _test_spot_and_alert() -> void:
	print("- spotting and alerting")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 3.0))
	var spotter: Creature = _add_creature(Vector3(6.5, 0.0, 3.0))
	var listener: Creature = _add_creature(Vector3(9.0, 0.0, 8.0))
	# Far away and behind the wall: hears the alert, cannot see the player.
	var too_far: Creature = _add_creature(Vector3(20.0, 0.0, 14.5))
	await _seconds(0.5)
	_check(spotter.state == Creature.State.CHASE, "a creature 3.5 units away with a clear view chases (spot distance 4.4)")
	_check(listener.state == Creature.State.INVESTIGATE, "a creature within the alert radius investigates")
	_check(too_far.state == Creature.State.WANDER, "a creature beyond the alert radius keeps wandering")
	_check(echo.health.value == echo.health.get_max_value() or spotter.lunges_started > 0, "nothing else hurt the player")


func _test_lunge_hits_once() -> void:
	print("- lunge")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 3.0))
	var creature: Creature = _add_creature(Vector3(5.0, 0.0, 3.0))
	await _frames(2)
	creature.hunt(echo)
	var lunged: bool = false
	for i: int in 90:
		await get_tree().physics_frame
		lunged = lunged or creature.lunge_phase != Creature.Lunge.NONE
	_check(lunged, "a chasing creature within lunge range lunges")
	_check_near(echo.health.value, echo.health.get_max_value() - echo.health.calm_hit_damage, 0.01,
		"the lunge costs one segment (Calm), the invulnerability stops a second hit")


func _test_downed_ignored() -> void:
	print("- a downed player is ignored")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 3.0))
	var creature: Creature = _add_creature(Vector3(5.0, 0.0, 3.0))
	await _frames(2)
	creature.hunt(echo)
	echo.health.down(PlayerHealth.Cause.CREATURE)
	await _seconds(0.3)
	_check(creature.state != Creature.State.CHASE, "the chase ends when the player goes down")
	await _seconds(1.5)
	_check(creature.state != Creature.State.CHASE, "it does not spot the downed player again")


func _test_search_after_losing_sight() -> void:
	print("- search after losing sight")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(10.0, 0.0, 6.0))
	var creature: Creature = _add_creature(Vector3(7.0, 0.0, 6.0))
	await _frames(2)
	creature.hunt(echo)
	# Behind the wall, far round its end.
	echo.global_position = Vector3(16.0, 0.0, 2.0)
	echo.reset_physics_interpolation()
	await _seconds(1.0)
	_check(creature.state == Creature.State.SEARCH, "losing sight (the wall in between) starts a SEARCH")


func _test_navigation_round_the_wall() -> void:
	print("- navigation round the wall")
	await _build_arena()
	var creature: Creature = _add_creature(Vector3(6.0, 0.0, 4.0))
	# Full awareness: it swims at max_speed (3.8) instead of min_speed (0.9).
	var awareness: DepthAwareness = _arena.get_node("DepthAwareness")
	awareness.decay_per_second = 0.0
	awareness.value = awareness.max_value
	await _frames(3)
	var goal := Vector3(18.0, 0.0, 4.0)
	creature.hear_noise(goal, 100.0)
	var reached: bool = false
	for i: int in 60 * 12:
		await get_tree().physics_frame
		if Creature._flat_distance(creature.global_position, goal) < 1.5 or creature.state == Creature.State.WANDER:
			reached = Creature._flat_distance(creature.global_position, goal) < 3.5
			break
	_check(creature.path_requests > 0 and creature.get_path_size() != 1, "it asked the navigation mesh for a path")
	_check(reached, "it went round the wall's end (through the gap) to a point straight behind the wall (ended at %s, %s)" % [
		creature.global_position.snappedf(0.1), creature.get_state_name()])
	var watch: CreatureStuckWatch = creature.get_node("StuckWatch")
	_check(watch.nudges_done == 0, "it never needed the stuck nudge (nudges: %d)" % watch.nudges_done)


func _test_sword_reveal_rules() -> void:
	print("- the sword: only revealed creatures, the Exposed kill")
	await _build_arena()
	var guardian: Player = _add_player(GUARDIAN_SCENE, Vector3(3.0, 0.0, 6.0))
	var creature: Creature = _add_creature(Vector3(5.4, 0.0, 6.0))
	creature.set_physics_process(false)
	guardian.facing = Vector3.RIGHT
	# The close sense would reveal it at 1.8: keep it just outside.
	(guardian.get_node("CloseSense") as CloseSense).calm_radius = 0.5
	await _frames(2)
	var sword: SwordAbility = guardian.get_node("Sword")
	var sword_ranges: float = sword.quick_range
	guardian.global_position = creature.global_position - Vector3(sword_ranges * 0.8 + creature.body_radius, 0.0, 0.0)
	guardian.reset_physics_interpolation()
	await _frames(2)
	await _press("p2_action")
	await _seconds(0.3)
	_check(creature.health == creature.max_health, "an unrevealed creature takes no damage")
	creature.on_sonar_hit(guardian.global_position)
	await _seconds(0.5)
	for hit: int in 3:
		await _press("p2_action")
		await _seconds(0.3)
	_check(not is_instance_valid(creature) or creature.is_dying(), "quick, quick, finisher on an Exposed creature kills it")


func _test_close_sense() -> void:
	print("- the Guardian's close sense")
	await _build_arena()
	var guardian: Player = _add_player(GUARDIAN_SCENE, Vector3(3.0, 0.0, 6.0))
	var creature: Creature = _add_creature(Vector3(4.6, 0.0, 6.0))
	creature.set_physics_process(false)
	await _frames(2)
	creature._update_reveal(0.016)
	_check(creature.sense_ratio >= 1.0, "a creature within 1.8 units of him is fully sensed")
	_check(creature.is_revealed(), "a fully sensed creature can be hit")
	_check(not creature.is_exposed(), "but it is not Exposed (only a pulse does that)")


func _test_distress_pulse() -> void:
	print("- the downed Echo's distress pulse")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 6.0))
	var creature: Creature = _add_creature(Vector3(6.0, 0.0, 6.0))
	creature.set_physics_process(false)
	await _frames(2)
	echo.health.down(PlayerHealth.Cause.CREATURE)
	var oxygen: float = echo.pressure.value
	var distress: DistressPulse = echo.get_node("DistressPulse")
	await _press("p1_action")
	await _seconds(0.6)
	_check(distress.cooldown_left > 0.0, "the action button sends it while downed")
	_check(creature.is_exposed(), "a creature 3 units away (radius 4) is Exposed by it")
	_check(is_equal_approx(echo.pressure.value, oxygen), "it costs no oxygen")


func _test_sonar_blocked_by_rock() -> void:
	print("- the sonar is blocked by rock")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(10.0, 0.0, 6.0))
	var behind: Creature = _add_creature(Vector3(14.5, 0.0, 6.0))
	var open: Creature = _add_creature(Vector3(7.0, 0.0, 6.0))
	for creature: Creature in [behind, open]:
		creature.set_physics_process(false)
	await _frames(2)
	await get_tree().physics_frame
	(echo.get_node("Pulse") as PulseAbility).emit_pulse()
	await _seconds(0.8)
	_check(open.is_exposed(), "a creature in the open is Exposed by the pulse")
	_check(not behind.is_exposed(), "a creature behind the wall is not")


func _test_revive_decay() -> void:
	print("- revive: interrupted progress pauses, then decays")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 6.0))
	var guardian: Player = _add_player(GUARDIAN_SCENE, Vector3(3.8, 0.0, 6.0))
	await _frames(2)
	# Down the way a creature does it: no health left.
	guardian.health.set_segments(0.0)
	guardian.health.down(PlayerHealth.Cause.CREATURE)
	var reviver: ReviveHelper = echo.get_node("Revive")
	_send("p1_action", true)
	await _seconds(1.0)
	_send("p1_action", false)
	await _frames(2)
	var held: float = reviver.progress
	_check(held > 0.7, "holding the button builds progress (%.2f s)" % held)
	await _seconds(0.5)
	_check_near(reviver.progress, held, 0.02, "letting go pauses the progress")
	await _seconds(1.5)
	_check(reviver.progress < held - 0.1, "then it decays")
	# Read at the moment of the revive: mending heals him right after.
	var at_revive: Array[float] = [-1.0]
	guardian.health.revived.connect(func() -> void: at_revive[0] = guardian.health.value)
	_send("p1_action", true)
	await _seconds(2.5)
	_send("p1_action", false)
	_check(not guardian.health.is_downed, "holding long enough revives")
	_check_near(at_revive[0], guardian.health.revive_segments, 0.01, "with one segment")
	var overlay: PlayerOverlay = guardian.get_node("Overlay")
	_check(not overlay.is_showing_revive(), "the revive ring is gone once he is up")


func _test_mending() -> void:
	print("- partner mending")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 6.0))
	var guardian: Player = _add_player(GUARDIAN_SCENE, Vector3(5.0, 0.0, 6.0))
	var mending: PartnerMending = _arena.get_node("PartnerMending")
	await _frames(2)
	echo.health.set_segments(2.0)
	guardian.health.set_segments(3.0)
	await _seconds(3.0)
	_check(mending.is_mending, "close together and hurt: they mend")
	_check(echo.health.value > 2.4 and guardian.health.value > 3.4, "both gain health (one segment per 6 s, Calm)")
	guardian.global_position = Vector3(10.0, 0.0, 6.0)
	guardian.reset_physics_interpolation()
	await _seconds(0.3)
	_check(not mending.is_mending, "too far apart: no mending")
	guardian.global_position = Vector3(5.0, 0.0, 6.0)
	var creature: Creature = _add_creature(Vector3(20.0, 0.0, 14.0))
	creature.set_physics_process(false)
	await _frames(2)
	creature.hunt(echo)
	await _seconds(0.2)
	_check(not mending.is_mending, "no mending while a creature chases one of them")


func _test_goal_arrow() -> void:
	print("- the goal arrow")
	await _build_arena()
	var echo: Player = _add_player(ECHO_SCENE, Vector3(3.0, 0.0, 3.0))
	var shard := Node3D.new()
	shard.position = Vector3(8.0, 0.0, 3.0)
	_arena.add_child(shard)
	shard.add_to_group("echo_shards")
	var exit := Node3D.new()
	exit.position = Vector3(3.0, 0.0, 14.0)
	_arena.add_child(exit)
	exit.add_to_group("level_exit")
	await _frames(2)
	var goal: GoalEcho = echo.get_node("GoalEcho")
	_check(not goal.is_showing(), "hidden before a pulse")
	await get_tree().physics_frame
	(echo.get_node("Pulse") as PulseAbility).emit_pulse()
	await _seconds(0.6)
	_check(goal.is_showing(), "shows shortly after a pulse")
	_check(goal.get_target() == shard, "points to the shard while one is left")
	shard.remove_from_group("echo_shards")
	_check(goal.get_target() == exit, "then to the exit")


# --- Arena ------------------------------------------------------------------------

func _build_arena() -> void:
	if _arena:
		_arena.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_arena = Node3D.new()
	_arena.name = "Arena"
	add_child(_arena)
	var awareness := DepthAwareness.new()
	awareness.name = "DepthAwareness"
	_arena.add_child(awareness)
	var sonar := Sonar.new()
	sonar.name = "Sonar"
	_arena.add_child(sonar)
	var mending := PartnerMending.new()
	mending.name = "PartnerMending"
	_arena.add_child(mending)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FLOOR_SIZE.x, 0.2, FLOOR_SIZE.y)
	floor_shape.shape = box
	floor_shape.position = Vector3(FLOOR_SIZE.x * 0.5, -0.1, FLOOR_SIZE.y * 0.5)
	floor_body.add_child(floor_shape)
	floor_body.collision_layer = 0
	_arena.add_child(floor_body)
	var rocks: Array[Dictionary] = []
	var material := StandardMaterial3D.new()
	for outline: PackedVector2Array in _rock_outlines():
		_arena.add_child(RockMesher.rock_body(outline, ROCK_HEIGHT, 40.0, material))
		rocks.append({"outline": outline, "height": ROCK_HEIGHT})
	var floors: Array[PackedVector2Array] = [PackedVector2Array([Vector2.ZERO, Vector2(FLOOR_SIZE.x, 0.0), FLOOR_SIZE, Vector2(0.0, FLOOR_SIZE.y)])]
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavigationBaker.bake(floors, rocks, 0.5, 0.125, 0.125)
	NavigationBaker.apply_to_map(get_world_3d().navigation_map, 0.125, 0.125)
	_arena.add_child(region)
	# Navigation maps update on the next physics frames.
	await _frames(3)


## The wall, the pillar and the arena's four sides.
func _rock_outlines() -> Array[PackedVector2Array]:
	var w: float = FLOOR_SIZE.x
	var h: float = FLOOR_SIZE.y
	return [
		PackedVector2Array(WALL), PackedVector2Array(PILLAR),
		PackedVector2Array([Vector2(-1.0, -1.0), Vector2(w + 1.0, -1.0), Vector2(w + 1.0, 0.0), Vector2(-1.0, 0.0)]),
		PackedVector2Array([Vector2(-1.0, h), Vector2(w + 1.0, h), Vector2(w + 1.0, h + 1.0), Vector2(-1.0, h + 1.0)]),
		PackedVector2Array([Vector2(-1.0, 0.0), Vector2(0.0, 0.0), Vector2(0.0, h), Vector2(-1.0, h)]),
		PackedVector2Array([Vector2(w, 0.0), Vector2(w + 1.0, 0.0), Vector2(w + 1.0, h), Vector2(w, h)]),
	]


func _add_player(scene: PackedScene, at: Vector3) -> Player:
	var player := scene.instantiate() as Player
	player.position = at
	_arena.add_child(player)
	player.pressure.drain_scale = 0.0
	return player


func _add_creature(at: Vector3) -> Creature:
	var creature := CREATURE_SCENE.instantiate() as Creature
	creature.position = at
	_arena.add_child(creature)
	return creature


# --- Helpers ----------------------------------------------------------------------

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["ok  " if ok else "FAIL", label])


func _check_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(value - expected) <= tolerance, "%s (got %.3f)" % [label, value])


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second))


## A real input event (handled at the start of the next frame, like a key).
func _press(action: String) -> void:
	_send(action, true)
	await _frames(2)
	_send(action, false)
	await _frames(1)


func _send(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
