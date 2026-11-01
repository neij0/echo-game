extends Node
## Headless test of the boss framework and the Angler fight, run as a scene so
## the Game autoload exists (it loads the real game.tscn, stage 1 level 3):
##   godot --headless --path . --fixed-fps 60 res://tools/test_boss.tscn
## Checks:
## - waking: asleep behind the closed door, wakes when a player comes in, the
##   intro (cannot be hurt), then the fight with the name + health bar;
## - no contact damage: a player inside its body is only pushed out;
## - armour: the sword barely hurts it, Exposed (pulse, Longer Exposure)
##   hurts, the Exposed finisher is big but no instant kill;
## - the charge into a pillar stuns it (Exposed) and the pillar takes the
##   blow; cracks after 2 blows, breaks after 3 (no collision, navigation);
## - the Guardian's Shield blocks the charge;
## - a Lure Pulse decoy baits the charge towards it;
## - no chained hits: the 2-snap bite hits a player once;
## - phases at 66 % / 33 % (transition, no skipping), faster charges and the
##   fake lure in phase 2, summons per mode and a darker arena in phase 3,
##   death; Challenge has more health than Calm.

const GAME_SCENE: String = "res://scenes/game.tscn"
const PHYSICS_FPS: float = 60.0

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player
var _boss: AnglerBoss
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	_stage = _game.get_node("StageManager") as StageManager
	_stage.test_mode = SaveData.Mode.CHALLENGE
	add_child(_game)
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	_echo = _game.get_node("Echo") as Player
	_guardian = _game.get_node("Guardian") as Player
	(_game.get_node("DepthAwareness") as DepthAwareness).decay_per_second = 0.0
	await _frames(10)

	await _test_wake()
	await _test_no_contact_damage()
	await _test_armor()
	await _test_pillar_stun()
	await _test_shield_block()
	await _test_lure_bait()
	await _test_no_chained_hits()
	await _test_phases(SaveData.Mode.CHALLENGE)
	await _test_phases(SaveData.Mode.CALM)

	print("RESULT: %s" % ("ALL BOSS CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures))
	_game.queue_free()
	for i: int in 10:
		await get_tree().process_frame
		OS.delay_msec(30)
	get_tree().quit(0 if _failures == 0 else 1)


# --- Tests -----------------------------------------------------------------------

func _test_wake() -> void:
	print("== Waking, intro, health bar ==")
	await _build()
	_check(_boss.mode == Boss.Mode.DORMANT, "asleep while the players are outside the arena")
	await _frames(30)
	_check(_boss.mode == Boss.Mode.DORMANT, "the closed door hides the players (still asleep)")
	_builder.open_exit()
	await _frames(5)
	_teleport(_echo, _boss.global_position + Vector2(0.0, -560.0))
	_teleport(_guardian, _boss.global_position + Vector2(60.0, -560.0))
	await _frames(5)
	_check(_boss.mode == Boss.Mode.INTRO, "a player in sight wakes it (intro)")
	var before: float = _boss.boss_health
	_boss.on_sonar_hit(_echo.global_position)
	_boss.take_damage(2, _guardian, 0.0, 0.0, true)
	_check(_boss.boss_health == before, "it cannot be hurt during the intro")
	await _frames(int((_boss.intro_time + 0.2) * PHYSICS_FPS))
	_check(_boss.mode == Boss.Mode.IDLE, "the fight starts after the intro")
	_check(_boss._health_bar.is_shown(), "the health bar with its name shows")
	_check(not _boss.visual.is_hidden_for_intro, "the body is revealed")
	_check(_boss.state == Creature.State.CHASE, "the music sees a fight (state CHASE)")


func _test_no_contact_damage() -> void:
	print("== No contact damage (soft push only) ==")
	await _build_fighting()
	_freeze(_boss)
	_teleport(_guardian, _entrance())
	var full: float = _echo.health.value
	_teleport(_echo, _boss.global_position)
	_echo.health._invulnerable_left = 0.0
	var inside: float = _boss._contact_distance(_echo.global_position)
	await _frames(int(2.0 * PHYSICS_FPS))
	_check(_echo.health.value == full, "2 s inside its body: no damage")
	var gap: float = _boss._contact_distance(_echo.global_position)
	print("  contact distance %.0f -> %.0f px" % [inside, gap])
	_check(gap > inside + 20.0, "the player is pushed out of the body")
	_check(_boss.strikes_landed == 0, "no strike while idle")


func _test_armor() -> void:
	print("== Armour, Exposed, Longer Exposure ==")
	await _build_fighting()
	_freeze(_boss)
	var start: float = _boss.boss_health
	_boss.take_damage(1, _guardian, 0.0, 0.0, false)
	var armored: float = start - _boss.boss_health
	_check(is_equal_approx(armored, _boss.armored_damage_scale), "unexposed: a sword hit deals only %.2f" % armored)
	_boss.on_sonar_hit(_echo.global_position)
	_check(_boss.is_exposed() and is_equal_approx(_boss._exposed_total, _boss.exposed_time), "a pulse makes it Exposed (%.1f s)" % _boss._exposed_total)
	var before: float = _boss.boss_health
	var big: bool = _boss.take_damage(2, _guardian, 0.0, 0.0, true)
	var dealt: float = before - _boss.boss_health
	_check(is_equal_approx(dealt, 2.0 * _boss.exposed_finisher_scale) and big, "the Exposed finisher deals %.0f (big hit)" % dealt)
	_check(not _boss.is_dying(), "and does not kill it outright")
	_boss._exposed_left = 0.0
	_give(_echo, "longer_exposure", 1)
	_boss.on_sonar_hit(_echo.global_position)
	_check(_boss._exposed_total > _boss.exposed_time + 0.1, "Longer Exposure: Exposed for %.1f s" % _boss._exposed_total)
	_give(_echo, "", 0)


func _test_pillar_stun() -> void:
	print("== Charge into a pillar: stun, cracks, break ==")
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	var pillar: ArenaPillar = _nearest_pillar(_boss.global_position)
	var center: Vector2 = _center_of(pillar)
	var direction: Vector2 = _boss.global_position.direction_to(center)
	_teleport(_echo, center + direction * 140.0)
	_teleport(_guardian, _entrance())
	_boss.target_player = _echo
	_boss.start_attack(_boss.get_attack(&"charge"))
	var stunned: bool = false
	for i: int in int(4.0 * PHYSICS_FPS):
		await _frames(1)
		if _boss.mode == Boss.Mode.STUNNED:
			stunned = true
			break
	_check(stunned, "running into the pillar stuns it")
	_check(pillar.blows == 1 and not pillar.is_cracked, "the pillar took one blow (no cracks yet)")
	_check(_boss.is_exposed(), "stunned counts as Exposed")
	await _frames(int((_boss.pillar_stun_time + 0.2) * PHYSICS_FPS))
	_check(_boss.mode != Boss.Mode.STUNNED, "the stun ends after %.0f s" % _boss.pillar_stun_time)
	pillar.take_blow()
	_check(pillar.is_cracked and not pillar.is_broken, "2 blows: cracked")
	pillar.take_blow()
	_check(pillar.is_broken, "3 blows: broken")
	await _frames(20)
	_check(not _point_blocked(center), "a broken pillar no longer blocks")
	var map: RID = get_viewport().world_2d.navigation_map
	_check(NavigationServer2D.map_get_closest_point(map, center).distance_to(center) < 8.0, "the navigation is rebaked through it")


func _test_shield_block() -> void:
	print("== The Shield blocks the charge ==")
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	_give(_guardian, "shield", 1)
	var shield := _guardian.skills.active as ShieldSkill
	var direction: Vector2 = Vector2(1.0, -1.0).normalized()
	_teleport(_guardian, _boss.global_position + direction * 260.0)
	_teleport(_echo, _entrance())
	_guardian.facing = -direction
	Input.action_press("p2_skill")
	await _frames(3)
	shield.shield_direction = -direction
	_guardian.health._invulnerable_left = 0.0
	var full: float = _guardian.health.value
	_boss.target_player = _guardian
	_boss.start_attack(_boss.get_attack(&"charge"))
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		shield.shield_direction = _guardian.global_position.direction_to(_boss.global_position)
		if _boss.mode == Boss.Mode.RECOVERY or _boss.mode == Boss.Mode.IDLE:
			break
	Input.action_release("p2_skill")
	_check(shield.blocks >= 1 and _boss.charges_blocked == 1, "the charge is blocked")
	_check(_guardian.health.value == full, "the Guardian takes no damage")
	_check(_boss.mode == Boss.Mode.RECOVERY, "it recoils into a recovery (an opening)")
	_give(_guardian, "", 0)


func _test_lure_bait() -> void:
	print("== A Lure Pulse decoy baits the charge ==")
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	_give(_echo, "lure_pulse", 1)
	var lure := _echo.skills.active as LurePulseSkill
	_teleport(_echo, _boss.global_position + Vector2(200.0, -180.0))
	_teleport(_guardian, _entrance())
	await _frames(2)
	lure.throw_decoy(Vector2.DOWN)
	var baited: bool = false
	for i: int in int(1.5 * PHYSICS_FPS):
		await _frames(1)
		if _boss.mode == Boss.Mode.TELEGRAPH:
			baited = true
			break
	await _frames(5)
	var to_decoy: Vector2 = _boss.global_position.direction_to(lure.decoy_position)
	var to_echo: Vector2 = _boss.global_position.direction_to(_echo.global_position)
	print("  decoy %.0f px from the boss, aim vs decoy %.0f°, vs Echo %.0f°" % [_boss.global_position.distance_to(lure.decoy_position),
		rad_to_deg(absf(_boss.get_aim().angle_to(to_decoy))), rad_to_deg(absf(_boss.get_aim().angle_to(to_echo)))])
	_check(baited and _boss.current_attack and _boss.current_attack.id == &"charge", "the decoy starts a charge at once (charge on cooldown before)")
	_check(_boss.get_aim().dot(to_decoy) > 0.96, "it aims at the decoy")
	_check(_boss.get_aim().dot(to_echo) < 0.7, "not at the Echo")
	_give(_echo, "", 0)


func _test_no_chained_hits() -> void:
	print("== The bite combo hits a player once ==")
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	_teleport(_guardian, _entrance())
	_teleport(_echo, _boss.get_bite_point())
	_echo.health._invulnerable_left = 0.0
	var full: float = _echo.health.value
	_boss.target_player = _echo
	var bite: BossAttack = _boss.get_attack(&"bite")
	_boss.start_attack(bite)
	var hit_speed: float = 0.0
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		if hit_speed == 0.0 and _echo.health.value < full:
			hit_speed = _echo.velocity.length()
		if _boss.mode == Boss.Mode.IDLE:
			break
	var lost: float = full - _echo.health.value
	print("  lost %.1f segments, knockback %.0f px/s" % [lost, hit_speed])
	_check(is_equal_approx(lost, bite.get_damage(true)), "2 snaps, one hit (%.1f segments)" % lost)
	_check(_boss.strikes_landed == 1, "one strike landed")
	_check(hit_speed > 0.0 and hit_speed <= bite.knockback_speed + 1.0, "a short knockback")


func _test_phases(mode: SaveData.Mode) -> void:
	var challenge: bool = mode == SaveData.Mode.CHALLENGE
	print("== Phases (%s) ==" % ("Challenge" if challenge else "Calm"))
	_stage.mode = mode
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	var expected_health: float = float(_boss.max_health) * (_boss.challenge_health_scale if challenge else 1.0)
	_check(is_equal_approx(_boss.boss_max_health, expected_health), "health %.0f" % _boss.boss_max_health)
	var calm_speed: float = _boss.get_charge_speed()
	_boss.expose(5.0)
	_boss.take_damage(100, _guardian, 0.0, 0.0, true)
	_check(_boss.phase == 2 and _boss.mode == Boss.Mode.TRANSITION, "66 %: phase 2 starts with a transition")
	_check(is_equal_approx(_boss.get_health_ratio(), _boss.phase_thresholds[0]), "one hit never skips past the threshold")
	var during: float = _boss.boss_health
	_boss.take_damage(2, _guardian, 0.0, 0.0, true)
	_check(_boss.boss_health == during, "it cannot be hurt during the transition")
	await _frames(int((_boss.transition_time + 0.2) * PHYSICS_FPS))
	_check(_boss.mode == Boss.Mode.IDLE, "then it fights on")
	_check(_boss.get_charge_speed() > calm_speed * 1.2, "phase 2 charges are faster (%.0f -> %.0f px/s)" % [calm_speed, _boss.get_charge_speed()])
	var faked: bool = false
	for i: int in int((_boss.fake_lure_interval + 1.0) * PHYSICS_FPS):
		await _frames(1)
		if _boss.is_faking_lure() and _boss.visual.lure.light_offset.length() > 10.0:
			faked = true
			break
	_check(faked, "phase 2: the lure fakes its position (its light moves)")
	_boss.expose(5.0)
	_boss.take_damage(100, _guardian, 0.0, 0.0, true)
	_check(_boss.phase == 3, "33 %: phase 3")
	var wanted: int = _boss.challenge_summon_count if challenge else _boss.calm_summon_count
	_check(_boss.summoned.size() == wanted, "it calls %d small creature(s)" % _boss.summoned.size())
	var darkness: Darkness = _game.get_node("Darkness") as Darkness
	_check(is_equal_approx(darkness.extra_darkness, _boss.phase3_darkness), "the arena gets darker")
	await _frames(int((_boss.transition_time + 0.2) * PHYSICS_FPS))
	var killed: Array[bool] = [false]
	_boss.killed.connect(func() -> void: killed[0] = true)
	_boss.expose(5.0)
	for i: int in 10:
		if _boss.is_dying():
			break
		_boss.take_damage(100, _guardian, 0.0, 0.0, true)
	_check(killed[0] and _boss.mode == Boss.Mode.DEAD, "it dies at 0 health")
	_check(darkness.extra_darkness == 0.0, "the darkness lifts when it dies")
	for creature: Creature in _boss.summoned:
		if is_instance_valid(creature):
			creature.queue_free()
	_stage.mode = SaveData.Mode.CHALLENGE


# --- Helpers -----------------------------------------------------------------------

## Builds stage 1 level 3 (the Angler) with the players at the start.
func _build() -> void:
	_stage.stage_index = 0
	_stage._start_level(2)
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature and creature != _builder.get_boss():
			creature.remove_from_group("creatures")
			creature.queue_free()
	_boss = _builder.get_boss() as AnglerBoss
	# The tests check the boss alone (no stage summary when it dies).
	if _boss.killed.is_connected(_stage._on_boss_killed):
		_boss.killed.disconnect(_stage._on_boss_killed)
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	await _frames(15)
	_protect_players()


## Built, door open, intro skipped: fighting in IDLE.
func _build_fighting() -> void:
	await _build()
	_builder.open_exit()
	_boss.start_fight()
	await _frames(15)
	_protect_players()


## No attack of its own during a test (they are started by hand).
func _freeze(boss: Boss) -> void:
	for attack: BossAttack in boss.attacks:
		boss._cooldowns[attack.id] = 999.0


func _protect_players() -> void:
	for player: Player in [_echo, _guardian]:
		if player.health.is_downed:
			player.health.revive()
		player.health.refill()
		player.health._invulnerable_left = 999.0
		player.pressure.refill()


func _give(player: Player, skill_id: String, rank: int) -> void:
	var entries: Dictionary = {}
	if skill_id != "":
		entries[skill_id] = rank
	player.skills.set_skills(entries, Game.skill_catalog)


func _teleport(player: Player, at: Vector2) -> void:
	player.global_position = at
	player.velocity = Vector2.ZERO


## Inside the arena, just past its doorway (far from the boss).
func _entrance() -> Vector2:
	var door: ShardDoor = _builder.get_exit_door()
	var door_center: Vector2 = door.to_global(door._center)
	return door_center + door_center.direction_to(_boss.global_position) * 160.0


func _nearest_pillar(from: Vector2) -> ArenaPillar:
	var best: ArenaPillar = null
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		var pillar := node as ArenaPillar
		if pillar == null or not _builder._level.is_ancestor_of(pillar):
			continue
		if best == null or _center_of(pillar).distance_to(from) < _center_of(best).distance_to(from):
			best = pillar
	return best


func _center_of(pillar: ArenaPillar) -> Vector2:
	var center := Vector2.ZERO
	var outline: PackedVector2Array = pillar.get_global_outline()
	for point: Vector2 in outline:
		center += point / outline.size()
	return center


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
