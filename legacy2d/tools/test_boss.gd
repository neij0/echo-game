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
##   death; Challenge has more health than Calm;
## - the placeholder bosses (stages 2-3) on the framework: no contact damage,
##   telegraphed lunge and slam, one hit each, Shield block, a phase change;
## - partner mending in a boss fight: open while it is stunned / recovering /
##   far, closed during a telegraph or an attack and while it is close;
## - the HUD: F1 shows / hides the debug lines, the boss bar never overlaps
##   a HUD part (debug lines shown or hidden);
## - the F6 playtest start (StageManager.test_level_index / test_start_at):
##   at the arena door (door open, boss asleep), inside the arena (it wakes),
##   and a Calm retry back to the same spot;
## - the tail sweep (staying close), homing orbs (pulse pops, sword / Shield
##   send them back, a stun), lure mines (count, dim, pulse reveal, touch,
##   fuse, a charge over one), the bubble vents (refill, vent prey).

const PHYSICS_FPS: float = 60.0
## Fuse of the mine in the "fuse runs out" check (fixed, so it never depends on the lob).
const MINE_TEST_FUSE: float = 1.0

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
	_game = GameSceneLoader.instantiate(SaveData.Mode.CHALLENGE)
	_stage = _game.get_node("StageManager") as StageManager
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
	await _test_mending()
	await _test_hud()
	await _test_placeholder()
	await _test_hit_count()
	await _test_playtest_start()
	await _test_hitboxes()
	await _test_sweep()
	await _test_orbs()
	await _test_mines()
	await _test_vents()

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
	await _frames(1)
	_check(is_equal_approx(armored, _boss.armored_damage_scale), "unexposed: a sword hit deals only %.2f" % armored)
	_boss.on_sonar_hit(_echo.global_position)
	_check(_boss.is_exposed() and is_equal_approx(_boss._exposed_total, _boss.exposed_time), "a pulse makes it Exposed (%.1f s)" % _boss._exposed_total)
	await _frames(1)
	var before: float = _boss.boss_health
	var big: bool = _boss.take_damage(2, _guardian, 0.0, 0.0, true)
	var dealt: float = before - _boss.boss_health
	_check(is_equal_approx(dealt, 2.0 * _boss.exposed_finisher_scale) and big, "the Exposed finisher deals %.0f (big hit)" % dealt)
	_check(not _boss.is_dying(), "and does not kill it outright")
	await _frames(1)
	_boss.stun(2.0)
	before = _boss.boss_health
	_boss.take_damage(2, _guardian, 0.0, 0.0, true)
	var stunned_hit: float = before - _boss.boss_health
	_check(is_equal_approx(stunned_hit, 2.0 * _boss.exposed_finisher_scale * _boss.stunned_damage_scale), "stunned: the finisher deals %.1f (the big opening)" % stunned_hit)
	_boss.take_damage(2, _guardian, 0.0, 0.0, true)
	_check(_boss.boss_health == before - stunned_hit, "a second hit from the same swing (same frame) is ignored")
	await _frames(int(2.2 * PHYSICS_FPS))
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
	_boss.take_damage(1000, _guardian, 0.0, 0.0, true)
	_check(_boss.phase == 2 and _boss.mode == Boss.Mode.TRANSITION, "66 %: phase 2 starts with a transition")
	_check(is_equal_approx(_boss.get_health_ratio(), _boss.phase_thresholds[0]), "one hit never skips past the threshold")
	var during: float = _boss.boss_health
	await _frames(1)
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
	_boss.take_damage(1000, _guardian, 0.0, 0.0, true)
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
		await _frames(1)
		_boss.take_damage(1000, _guardian, 0.0, 0.0, true)
	_check(killed[0] and _boss.mode == Boss.Mode.DEAD, "it dies at 0 health")
	_check(darkness.extra_darkness == 0.0, "the darkness lifts when it dies")
	for creature: Creature in _boss.summoned:
		if is_instance_valid(creature):
			creature.queue_free()
	_stage.mode = SaveData.Mode.CHALLENGE


func _test_mending() -> void:
	print("== Partner mending in a boss fight ==")
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	var mending: PartnerMending = _game.get_node("MendLayer/PartnerMending") as PartnerMending
	var near: Vector2 = _boss.global_position + Vector2(0.0, -220.0)
	_teleport(_echo, near)
	_teleport(_guardian, near + Vector2(40.0, 0.0))
	_echo.health.set_segments(2.0)
	await _frames(2)
	_check(not mending._can_mend(), "idle and close (%.0f px): no mending" % near.distance_to(_boss.global_position))
	_boss.target_player = _echo
	_boss.start_attack(_boss.get_attack(&"bite"))
	await _frames(2)
	_check(_boss.mode == Boss.Mode.TELEGRAPH and not mending._can_mend(), "during a telegraph: no mending")
	_boss.stun(2.0)
	await _frames(2)
	_check(_boss.mode == Boss.Mode.STUNNED and mending._can_mend(), "while it is stunned: mending")
	await _frames(int(2.2 * PHYSICS_FPS))
	_freeze(_boss)
	_boss.target_player = _echo
	_boss.start_attack(_boss.get_attack(&"bite"))
	_boss.end_active()
	await _frames(2)
	_check(_boss.mode == Boss.Mode.RECOVERY and mending._can_mend(), "during its recovery: mending")
	await _frames(int(2.0 * PHYSICS_FPS))
	_check(_boss.mode == Boss.Mode.IDLE, "(back to idle)")
	var far: Vector2 = _boss.global_position + Vector2(0.0, -(_boss.mend_safe_distance + 120.0))
	_teleport(_echo, far)
	_teleport(_guardian, far + Vector2(40.0, 0.0))
	await _frames(2)
	_echo.health.set_segments(2.0)
	_check(mending._can_mend(), "idle and farther than %.0f px from both: mending" % _boss.mend_safe_distance)
	_boss.start_attack(_boss.get_attack(&"charge"))
	await _frames(2)
	_check(not mending._can_mend(), "a telegraph blocks it even from far away")
	_protect_players()


func _test_hud() -> void:
	print("== HUD: F1 debug lines, the boss bar stays clear ==")
	await _build_fighting()
	_freeze(_boss)
	var hud: Hud = _game.get_node("Hud") as Hud
	var bar: BossHealthBar = _boss._health_bar
	# Headless windows are tiny: lay it out for the game's 1280 x 720.
	bar.screen_size_override = Vector2(1280.0, 720.0)
	for shown: bool in [true, false]:
		hud.set_debug_visible(shown)
		await get_tree().process_frame
		await get_tree().process_frame
		var overlap: bool = false
		for rect: Rect2 in hud.get_occupied_rects():
			if rect.intersects(bar.get_screen_rect()):
				overlap = true
		_check(not overlap, "debug lines %s: the bar %s overlaps no HUD part" % ["shown" if shown else "hidden", bar.get_screen_rect()])
	var before: bool = hud.is_debug_visible()
	var key := InputEventKey.new()
	key.keycode = hud.debug_toggle_key
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud.is_debug_visible() != before, "F1 toggles the debug lines")
	var release := InputEventKey.new()
	release.keycode = hud.debug_toggle_key
	release.pressed = false
	Input.parse_input_event(release)
	hud.set_debug_visible(OS.has_feature("editor"))


func _test_placeholder() -> void:
	print("== Placeholder boss (stage 2) on the framework ==")
	await _build(1)
	var boss := _builder.get_boss() as PlaceholderBoss
	_check(boss != null, "the stage 2 boss is a PlaceholderBoss")
	if boss == null:
		return
	_builder.open_exit()
	boss.start_fight()
	await _frames(10)
	_protect_players()
	_freeze(boss)
	boss.move_speed = 0.0
	_check(boss._health_bar.is_shown() and boss.name_key != "", "name + health bar")
	_teleport(_guardian, _entrance())
	var full: float = _echo.health.value
	_teleport(_echo, boss.global_position)
	_echo.health._invulnerable_left = 0.0
	await _frames(int(1.5 * PHYSICS_FPS))
	_check(_echo.health.value == full, "no contact damage")
	# Lunge: telegraphed, one hit.
	var lunge: BossAttack = boss.get_attack(&"lunge")
	_protect_players()
	_teleport(_echo, boss.global_position + Vector2(-260.0, 0.0))
	_echo.health._invulnerable_left = 0.0
	full = _echo.health.value
	boss.target_player = _echo
	boss.start_attack(lunge)
	var telegraph_frames: int = 0
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		if boss.mode == Boss.Mode.TELEGRAPH:
			telegraph_frames += 1
		if boss.mode == Boss.Mode.RECOVERY or boss.mode == Boss.Mode.IDLE:
			break
	_check(telegraph_frames >= int(0.75 * PHYSICS_FPS), "the lunge is telegraphed (%.2f s)" % (telegraph_frames / PHYSICS_FPS))
	_check(is_equal_approx(full - _echo.health.value, lunge.get_damage(true)) and boss.strikes_landed == 1, "the lunge hits once")
	_check(boss.mode == Boss.Mode.RECOVERY, "then it recovers (an opening)")
	await _frames(int(2.0 * PHYSICS_FPS))
	_freeze(boss)
	# Slam: both players inside the ring, each hit once.
	_protect_players()
	for player: Player in [_echo, _guardian]:
		player.health._invulnerable_left = 0.0
	_teleport(_echo, boss.global_position + Vector2(-90.0, 0.0))
	_teleport(_guardian, boss.global_position + Vector2(90.0, 0.0))
	var strikes: int = boss.strikes_landed
	boss.start_attack(boss.get_attack(&"slam"))
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		if boss.mode == Boss.Mode.RECOVERY:
			break
	_check(boss.strikes_landed - strikes == 2, "the slam hits each player inside once")
	await _frames(int(2.0 * PHYSICS_FPS))
	_freeze(boss)
	# Shield block.
	_protect_players()
	_give(_guardian, "shield", 1)
	var shield := _guardian.skills.active as ShieldSkill
	_teleport(_echo, _entrance())
	_teleport(_guardian, boss.global_position + Vector2(0.0, -260.0))
	Input.action_press("p2_skill")
	await _frames(3)
	_guardian.health._invulnerable_left = 0.0
	var guardian_full: float = _guardian.health.value
	boss.target_player = _guardian
	boss.start_attack(lunge)
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		shield.shield_direction = _guardian.global_position.direction_to(boss.global_position)
		if boss.mode == Boss.Mode.RECOVERY or boss.mode == Boss.Mode.IDLE:
			break
	Input.action_release("p2_skill")
	_check(boss.charges_blocked == 1 and _guardian.health.value == guardian_full, "the Shield blocks the lunge")
	_give(_guardian, "", 0)
	boss.expose(5.0)
	boss.take_damage(1000, _guardian, 0.0, 0.0, true)
	_check(boss.phase == 2 and boss.mode == Boss.Mode.TRANSITION, "66 %: phase 2 with a transition")
	_protect_players()


func _test_hit_count() -> void:
	print("== Hits taken: real damage only, retries roll back ==")
	_stage.mode = SaveData.Mode.CALM
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	var start: int = _stage.hits_taken
	# Soft pushes are no hits.
	_teleport(_guardian, _entrance())
	_teleport(_echo, _boss.global_position)
	_echo.health._invulnerable_left = 0.0
	await _frames(60)
	_check(_stage.hits_taken == start, "a soft push is not counted")
	# A hit while invulnerable is not counted, a real one is (once).
	_echo.health._invulnerable_left = 5.0
	_echo.health.take_hit(_boss.global_position, _boss)
	_check(_stage.hits_taken == start, "a hit during invulnerability is not counted")
	_echo.health._invulnerable_left = 0.0
	_echo.health.take_hit(_boss.global_position, _boss)
	_echo.health.take_hit(_boss.global_position, _boss)
	_check(_stage.hits_taken == start + 1, "a real hit counts once (the next is inside its invulnerability)")
	# A blocked hit is not counted.
	_give(_guardian, "shield", 1)
	var shield := _guardian.skills.active as ShieldSkill
	_teleport(_guardian, _boss.global_position + Vector2(0.0, -200.0))
	Input.action_press("p2_skill")
	await _frames(3)
	shield.shield_direction = _guardian.global_position.direction_to(_boss.global_position)
	_guardian.health._invulnerable_left = 0.0
	_guardian.health.take_hit(_boss.global_position, _boss)
	Input.action_release("p2_skill")
	_check(_stage.hits_taken == start + 1 and shield.blocks >= 1, "a blocked hit is not counted")
	_give(_guardian, "", 0)
	# A Calm retry rolls the count back to the level start.
	_stage._retry()
	await _frames(5)
	_check(_stage.hits_taken == _stage._level_start_counts[1] and _stage.hits_taken <= start, "a Calm retry does not add up the failed attempt (%d)" % _stage.hits_taken)
	_stage.mode = SaveData.Mode.CHALLENGE
	_stage.hits_taken = 9
	_stage._retry()
	await _frames(5)
	_check(_stage.hits_taken == 0, "a Challenge retry (stage from level 1) starts the count again")
	_protect_players()


func _test_playtest_start() -> void:
	print("== F6 playtest start at the boss ==")
	_stage.mode = SaveData.Mode.CALM
	_stage.stage_index = 0
	_stage.test_level_index = 2
	_stage.test_start_at = StageManager.TestStart.ARENA_DOOR
	_stage._start_level(_stage._first_level_index())
	await _frames(10)
	var boss := _builder.get_boss() as Boss
	var door: ShardDoor = _builder.get_exit_door()
	var door_center: Vector2 = door.to_global(door._center)
	_check(_stage.level_index == 2 and boss != null, "test_level_index 2 starts the boss level")
	_check(door.is_open and _stage.shards_collected == _stage.shards_total, "ARENA_DOOR: every shard counted, the door open")
	var outside: bool = _echo.global_position.distance_to(boss.global_position) > door_center.distance_to(boss.global_position)
	_check(outside and _echo.global_position.distance_to(door_center) < 200.0, "ARENA_DOOR: the players stand just outside the door")
	_check(boss.mode == Boss.Mode.DORMANT, "ARENA_DOOR: the boss still sleeps")
	_stage.test_start_at = StageManager.TestStart.IN_ARENA
	_stage._start_level(_stage._first_level_index())
	await _frames(10)
	boss = _builder.get_boss() as Boss
	door = _builder.get_exit_door()
	door_center = door.to_global(door._center)
	var inside: bool = _echo.global_position.distance_to(boss.global_position) < door_center.distance_to(boss.global_position)
	_check(door.is_open and inside, "IN_ARENA: the players are inside the arena")
	_check(boss.mode == Boss.Mode.INTRO, "IN_ARENA: the boss wakes (intro)")
	var spot: Vector2 = _echo.global_position
	if boss.killed.is_connected(_stage._on_boss_killed):
		boss.killed.disconnect(_stage._on_boss_killed)
	_stage._retry()
	await _frames(10)
	_check(_stage.level_index == 2 and _echo.global_position.distance_to(spot) < 40.0 and _builder.get_exit_door().is_open, "a Calm retry starts at the same spot")
	_stage.test_level_index = 0
	_stage.test_start_at = StageManager.TestStart.LEVEL_START
	_stage.mode = SaveData.Mode.CHALLENGE
	_protect_players()


## Every attack frozen except these ids.
func _freeze_except(boss: Boss, ids: Array[StringName]) -> void:
	for attack: BossAttack in boss.attacks:
		boss._cooldowns[attack.id] = 0.0 if ids.has(attack.id) else 999.0


## Damages it into a phase (and waits out the transition).
func _to_phase(target_phase: int) -> void:
	while _boss.phase < target_phase:
		_boss.expose(5.0)
		await _frames(1)
		_boss.take_damage(1000, _guardian, 0.0, 0.0, true)
	await _frames(int((_boss.transition_time + 0.2) * PHYSICS_FPS))
	_freeze(_boss)


func _test_hitboxes() -> void:
	print("== Hurtbox and hitboxes follow the drawn shape ==")
	await _build_fighting()
	_freeze(_boss)
	_boss.move_speed = 0.0
	await _frames(5)
	var body: AnglerBody = _boss.visual.body
	var hurtbox: PackedVector2Array = _boss.get_hurtbox()
	var heading: Vector2 = body.heading
	var head_front: Vector2 = body.get_head_center() + heading * (body.head_front - 4.0)
	var tail_root: Vector2 = body.point_at(1.0, 0.0)
	_check(Geometry2D.is_point_in_polygon(head_front, hurtbox), "the front of the head is in the hurtbox")
	_check(Geometry2D.is_point_in_polygon(body.point_at(0.95, 0.0), hurtbox), "the tail root is in the hurtbox")
	_check(Geometry2D.is_point_in_polygon(body.point_at(0.3, 0.0) + Vector2(0.0, body.flank_depth * 0.5), hurtbox), "so is the 3/4 flank below the back")
	_check(not Geometry2D.is_point_in_polygon(_boss.global_position + Vector2(0.0, -body.head_half_width * 2.5), hurtbox), "open water above it is not")
	# The sword: a swing at the tail lands; the old circle (body_radius) missed it.
	var sword: SwordAbility = _guardian.find_children("*", "SwordAbility", true, false)[0] as SwordAbility
	var reach: float = sword.quick_range
	var half_arc: float = sword.get_arc_radians(false) * 0.5
	var behind_tail: Vector2 = tail_root - heading * (reach - 10.0)
	_check(_boss.is_in_swing(behind_tail, heading, reach, half_arc), "a swing at the tail lands")
	_check(behind_tail.distance_to(_boss.global_position) > reach + _boss.body_radius, "(out of reach of the old circle: %.0f px)" % behind_tail.distance_to(_boss.global_position))
	var in_front: Vector2 = head_front + heading * (reach - 10.0)
	_check(_boss.is_in_swing(in_front, -heading, reach, half_arc), "a swing at the face lands")
	_check(not _boss.is_in_swing(in_front, heading, reach, half_arc), "a swing away from it does not")
	_check(not _boss.is_in_swing(in_front + heading * reach, -heading, reach, half_arc), "nor one from too far away")
	# Contact (push, charge hits, returning orbs) is measured to the drawn shape.
	_check(_boss._contact_distance(head_front) < 0.0 and _boss._contact_distance(in_front) > 0.0, "contact distance: inside < 0 < outside")
	# The bite reaches the drawn mouth with the jaw fully open, the sweep the arc's circle.
	var mouth: PackedVector2Array = body.get_mouth_polygon(1.0)
	_check(_boss.get_bite_zone() == mouth, "the bite zone is the drawn mouth, jaw fully open")
	var jaw_tip: Vector2 = mouth[mouth.size() / 2]
	for point: Vector2 in mouth:
		if (point - body.get_head_center()).dot(heading) > (jaw_tip - body.get_head_center()).dot(heading):
			jaw_tip = point
	var sweep: PackedVector2Array = _boss.get_sweep_zone()
	var sweep_center: Vector2 = _boss.visual.glow.get_sweep_center()
	_check(absf(sweep[0].distance_to(sweep_center) - _boss.visual.sweep_arc_radius) < 0.5, "the sweep zone is the drawn arc's circle (%.0f px)" % _boss.visual.sweep_arc_radius)
	# A bite: just in front of the open jaw's tip (it follows the head) is safe.
	var safe_reach: float = (jaw_tip - body.get_head_center()).dot(heading) + _boss.player_hit_radius + 18.0
	_teleport(_guardian, _entrance())
	_teleport(_echo, body.get_head_center() + heading * safe_reach)
	_echo.health._invulnerable_left = 0.0
	var full: float = _echo.health.value
	_boss.target_player = _echo
	_boss.start_attack(_boss.get_attack(&"bite"))
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		_teleport(_echo, body.get_head_center() + heading * safe_reach)
		if _boss.mode == Boss.Mode.IDLE or _boss.mode == Boss.Mode.RECOVERY:
			break
	_check(_echo.health.value == full, "a player just past the open jaw is not bitten")
	_protect_players()
	_freeze(_boss)


func _test_sweep() -> void:
	print("== Tail sweep (players stay close) ==")
	await _build_fighting()
	_freeze_except(_boss, [&"sweep"])
	_boss.move_speed = 0.0
	_teleport(_guardian, _entrance())
	_teleport(_echo, _boss.global_position + Vector2(0.0, -95.0))
	_echo.health._invulnerable_left = 0.0
	var full: float = _echo.health.value
	var wound: bool = false
	var hit_speed: float = 0.0
	var waited: float = 0.0
	for i: int in int((_boss.get_sweep_trigger_time() + 3.5) * PHYSICS_FPS):
		await _frames(1)
		waited += 1.0 / PHYSICS_FPS
		if _boss.visual._sweep_wind > 0.3:
			wound = true
		if hit_speed == 0.0 and _echo.health.value < full:
			hit_speed = _echo.velocity.length()
		if _boss.sweeps_done > 0 and _boss.mode == Boss.Mode.RECOVERY:
			break
		# She stays close (the player keeps hugging it) until it sweeps.
		if _boss.mode == Boss.Mode.IDLE:
			_teleport(_echo, _boss.global_position + Vector2(0.0, -95.0))
	var sweep: BossAttack = _boss.get_attack(&"sweep")
	print("  swept after %.1f s, knockback %.0f px/s" % [waited, hit_speed])
	_check(_boss.sweeps_done == 1, "staying close makes it sweep (after ~%.1f s)" % _boss.get_sweep_trigger_time())
	_check(wound, "the telegraph: it coils with flared fins")
	_check(is_equal_approx(full - _echo.health.value, sweep.get_damage(true)) and _boss.strikes_landed == 1, "one hit")
	_check(hit_speed > 300.0, "it knocks her away")


func _test_orbs() -> void:
	print("== Homing orbs (phase 2) ==")
	await _build_fighting()
	await _to_phase(2)
	_boss.move_speed = 0.0
	_teleport(_echo, _boss.global_position + Vector2(380.0, -380.0))
	_teleport(_guardian, _boss.global_position + Vector2(430.0, -340.0))
	_boss.start_attack(_boss.get_attack(&"orbs"))
	var volley: float = _boss.get_attack(&"orbs").get_telegraph(true) + _boss.orb_interval * float(_boss.challenge_orb_count) + 0.1
	await _frames(int(volley * PHYSICS_FPS))
	var orbs: Array[AnglerOrb] = _orbs()
	_check(orbs.size() == _boss.challenge_orb_count and _boss.orbs_fired == _boss.challenge_orb_count, "it fires %d orbs (Challenge)" % orbs.size())
	_check(_boss.get_attack(&"orbs").min_phase == 2, "orbs start in phase 2")
	var armored_count: int = 0
	for fired: AnglerOrb in orbs:
		armored_count += 1 if fired.armored else 0
	_check(armored_count >= 1 and armored_count < orbs.size(), "a volley mixes cyan and armored orbs (%d armored of %d)" % [armored_count, orbs.size()])
	# Phase 3: one orb more per volley and more of them armored.
	_boss.phase = 3
	var phase3_count: int = _boss.get_orb_count()
	_boss._plan_volley(phase3_count)
	var phase3_armored: int = _boss._volley_armored.count(true)
	_boss.phase = 2
	_boss._plan_volley(_boss.get_orb_count())
	var phase2_armored: int = _boss._volley_armored.count(true)
	_boss._volley_armored.clear()
	_check(phase3_count == _boss.challenge_orb_count + _boss.orb_phase3_extra and phase3_armored > phase2_armored
		and phase3_armored < phase3_count, "phase 3: %d orbs, %d armored (phase 2: %d armored)" % [phase3_count, phase3_armored, phase2_armored])
	# Orbs go for the Echo first.
	var preference: float = _boss.orb_echo_preference
	_boss.orb_echo_preference = 1.0
	var echo_first: bool = _boss._pick_orb_prey() == _echo
	_boss.orb_echo_preference = 0.0
	var guardian_otherwise: bool = _boss._pick_orb_prey() == _guardian
	_boss.orb_echo_preference = preference
	_check(echo_first and guardian_otherwise and preference > 0.5, "orbs prefer the Echo (%.0f %%)" % (preference * 100.0))
	# The pulse pops cyan orbs close to the Echo only; armored ones never.
	for fired: AnglerOrb in orbs:
		fired.set_physics_process(false)
	var near_cyan: AnglerOrb = orbs[0]
	var far_cyan: AnglerOrb = orbs[1]
	var near_armored: AnglerOrb = orbs[2]
	near_cyan.armored = false
	far_cyan.armored = false
	near_armored.armored = true
	near_cyan.global_position = _echo.global_position + Vector2(near_cyan.pulse_pop_radius * 0.6, 0.0)
	far_cyan.global_position = _echo.global_position + Vector2(-near_cyan.pulse_pop_radius * 1.8, 0.0)
	near_armored.global_position = _echo.global_position + Vector2(0.0, near_cyan.pulse_pop_radius * 0.6)
	var pulse: PulseAbility = _echo.find_children("*", "PulseAbility", true, false)[0] as PulseAbility
	_check(far_cyan.global_position.distance_to(_echo.global_position) < pulse.get_radius(), "the far orb is inside the pulse's reach")
	pulse.cooldown_left = 0.0
	pulse.emit_pulse()
	await _frames(int(1.6 * PHYSICS_FPS))
	_check(not near_cyan.is_homing(), "the pulse pops a cyan orb close to the Echo")
	_check(far_cyan.is_homing(), "but not one farther than %.0f px" % near_cyan.pulse_pop_radius)
	_check(near_armored.is_homing(), "an armored orb ignores the pulse")
	for fired: AnglerOrb in orbs:
		if is_instance_valid(fired):
			fired.pop()
	# The Guardian's sword sends one back: it stuns the Angler.
	_freeze(_boss)
	await _frames(int(2.0 * PHYSICS_FPS))
	_freeze(_boss)
	_boss.start_attack(_boss.get_attack(&"orbs"))
	await _frames(int(1.5 * PHYSICS_FPS))
	# The Echo stays behind him (the shared camera keeps them together).
	_teleport(_echo, _guardian.global_position + _boss.global_position.direction_to(_guardian.global_position) * 120.0)
	var orb: AnglerOrb = _orbs()[0] if not _orbs().is_empty() else null
	_check(orb != null, "a new volley")
	if orb == null:
		return
	for other: AnglerOrb in _orbs():
		if other != orb:
			other.pop()
	# Armored: only the Guardian can stop it, and his blade sends it back.
	orb.armored = true
	orb.target = _guardian
	var swung: bool = false
	for i: int in int(6.0 * PHYSICS_FPS):
		await _frames(1)
		if not is_instance_valid(orb):
			break
		_guardian.facing = _guardian.global_position.direction_to(orb.global_position)
		if orb.is_homing() and orb.global_position.distance_to(_guardian.global_position) < 70.0 and not swung:
			swung = true
			Input.action_press("p2_action")
		elif swung:
			Input.action_release("p2_action")
		if _boss.orb_stuns > 0:
			break
	Input.action_release("p2_action")
	_check(_boss.orb_stuns == 1, "a sword hit sends an armored orb back: it stuns the Angler")
	_check(_boss.mode == Boss.Mode.STUNNED and _boss.is_exposed(), "stunned counts as Exposed")
	# The Shield sends one back too.
	await _frames(int((_boss.orb_stun_time + 0.3) * PHYSICS_FPS))
	_freeze(_boss)
	_give(_guardian, "shield", 1)
	var shield := _guardian.skills.active as ShieldSkill
	Input.action_press("p2_skill")
	await _frames(3)
	_boss.start_attack(_boss.get_attack(&"orbs"))
	await _frames(int(1.5 * PHYSICS_FPS))
	orb = _orbs()[0] if not _orbs().is_empty() else null
	for other: AnglerOrb in _orbs():
		if other != orb:
			other.pop()
	_guardian.health._invulnerable_left = 0.0
	var guardian_full: float = _guardian.health.value
	var deflected: bool = false
	if orb:
		orb.target = _guardian
		for i: int in int(6.0 * PHYSICS_FPS):
			await _frames(1)
			if not is_instance_valid(orb):
				break
			shield.shield_direction = _guardian.global_position.direction_to(orb.global_position)
			if orb.is_deflected():
				deflected = true
				break
	Input.action_release("p2_skill")
	_check(deflected and _guardian.health.value == guardian_full, "the Shield sends it back (no damage)")
	_give(_guardian, "", 0)
	_protect_players()


func _test_mines() -> void:
	print("== Lure mines (phase 3) ==")
	await _build_fighting()
	await _to_phase(3)
	for creature: Creature in _boss.summoned:
		if is_instance_valid(creature):
			creature.queue_free()
	_boss.move_speed = 0.0
	_teleport(_echo, _entrance())
	_teleport(_guardian, _entrance() + Vector2(40.0, 0.0))
	_boss.start_attack(_boss.get_attack(&"mines"))
	await _frames(int(3.2 * PHYSICS_FPS))
	var mines: Array[AnglerMine] = _mines()
	_check(mines.size() == _boss.challenge_mine_count, "it lobs %d mines (Challenge)" % mines.size())
	var dim: bool = true
	for mine: AnglerMine in mines:
		dim = dim and not mine.is_revealed()
	_check(dim, "they lie dim in the dark")
	var pulse: PulseAbility = _echo.find_children("*", "PulseAbility", true, false)[0] as PulseAbility
	_teleport(_echo, _boss.global_position + Vector2(0.0, -300.0))
	pulse.cooldown_left = 0.0
	pulse.emit_pulse()
	await _frames(int(1.6 * PHYSICS_FPS))
	var revealed: int = 0
	for mine: AnglerMine in mines:
		if is_instance_valid(mine) and mine.is_revealed():
			revealed += 1
	# Every mine the pulse front can see (no rock in between) is revealed.
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	var visible_mines: int = 0
	for mine: AnglerMine in mines:
		if not is_instance_valid(mine) or mine.global_position.distance_to(_echo.global_position) > pulse.get_radius():
			continue
		var query := PhysicsRayQueryParameters2D.create(_echo.global_position, mine.global_position, 1)
		if space.intersect_ray(query).is_empty():
			visible_mines += 1
	_check(revealed >= visible_mines and revealed > 0, "the pulse reveals every mine in its sight (%d revealed, %d in sight, %d total)" % [revealed, visible_mines, mines.size()])
	# Touching one blows it up; the blast hits once.
	var touched: AnglerMine = mines[0]
	_guardian.health._invulnerable_left = 0.0
	var guardian_full: float = _guardian.health.value
	_teleport(_guardian, touched.global_position)
	await _frames(2)
	_check(not is_instance_valid(touched) or not touched.is_armed(), "touching a mine blows it up")
	_check(is_equal_approx(guardian_full - _guardian.health.value, _boss.challenge_mine_damage), "one hit from the blast")
	_teleport(_guardian, _entrance())
	# The fuse: a player beside (not on) a mine is hit when it blows.
	# Deterministic: one mine only, on a fixed open spot, with a fixed fuse.
	var fused: AnglerMine = _mines()[0]
	for mine: AnglerMine in _mines():
		if mine != fused:
			mine.fizzle()
	var fuse_spot: Vector2 = _boss.global_position + Vector2(0.0, -300.0)
	fused.global_position = fuse_spot
	fused._fuse_left = MINE_TEST_FUSE
	_teleport(_guardian, _entrance())
	_protect_players()
	_teleport(_echo, fuse_spot + Vector2(60.0, 0.0))
	_echo.health._invulnerable_left = 0.0
	var echo_full: float = _echo.health.value
	var blast_frame: int = -1
	for i: int in int((MINE_TEST_FUSE + 0.5) * PHYSICS_FPS):
		await _frames(1)
		if _echo.health.value < echo_full:
			blast_frame = i
			break
		_teleport(_echo, fuse_spot + Vector2(60.0, 0.0))
	var blast_time: float = float(blast_frame + 1) / PHYSICS_FPS
	_check(blast_frame >= 0 and absf(blast_time - MINE_TEST_FUSE) < 0.1
		and is_equal_approx(echo_full - _echo.health.value, _boss.challenge_mine_damage),
		"its fuse runs out: the blast hits her once (after %.2f s, fuse %.1f s)" % [blast_time, MINE_TEST_FUSE])
	_teleport(_echo, _entrance())
	for mine: AnglerMine in _mines():
		mine.fizzle()
	# Charging over a mine blows it up on the Angler.
	await _frames(int(1.0 * PHYSICS_FPS))
	_freeze(_boss)
	await _frames(int(2.0 * PHYSICS_FPS))
	_freeze(_boss)
	var direction := Vector2(0.0, -1.0)
	var bait: Vector2 = _boss.global_position + Vector2(-260.0, -60.0)
	direction = _boss.global_position.direction_to(bait)
	var planted := (load("res://scenes/bosses/angler_mine.tscn") as PackedScene).instantiate() as AnglerMine
	var spot: Vector2 = _boss.global_position + direction * 170.0
	planted.setup(_boss, _builder._level.to_local(spot), _builder._level.to_local(spot), 30.0, _boss.mine_blast_radius, 1.0, 300.0)
	_builder._level.add_child(planted)
	await _frames(int(1.0 * PHYSICS_FPS))
	_teleport(_echo, bait)
	_boss.target_player = _echo
	var before: float = _boss.boss_health
	_boss.start_attack(_boss.get_attack(&"charge"))
	for i: int in int(3.0 * PHYSICS_FPS):
		await _frames(1)
		if _boss.mine_hits > 0:
			break
	_check(_boss.mine_hits == 1, "charging over a mine blows it up on the Angler")
	_check(_boss.mode == Boss.Mode.STUNNED and before - _boss.boss_health >= _boss.boss_max_health * _boss.mine_damage_ratio - 0.01, "damage + a short stun")
	_protect_players()


func _test_vents() -> void:
	print("== Bubble vents ==")
	await _build_fighting()
	var vents: Array[Node] = get_tree().get_nodes_in_group("bubble_vents")
	_check(vents.size() == 2, "the arena has 2 vents")
	if vents.is_empty():
		return
	var vent := vents[0] as BubbleVent
	_freeze(_boss)
	_boss.move_speed = 0.0
	# The Guardian stays close (the shared camera keeps the players together),
	# just outside the vent.
	_teleport(_guardian, vent.global_position + Vector2(0.0, -(vent.radius + 50.0)))
	_teleport(_echo, vent.global_position)
	_echo.pressure.value = _echo.pressure.max_value * 0.2
	await _frames(int(2.0 * PHYSICS_FPS))
	_check(_echo.pressure.get_ratio() > 0.55, "standing at a vent refills oxygen (20 %% -> %.0f %% in 2 s)" % (_echo.pressure.get_ratio() * 100.0))
	# A player lingering there may become its prey (chance forced to 1 here).
	_boss.challenge_vent_punish_chance = 1.0
	_teleport(_echo, vent.global_position + Vector2(0.0, -(vent.radius + 30.0)))
	await _frames(2)
	_teleport(_echo, vent.global_position)
	_freeze_except(_boss, [&"charge"])
	_boss._gap_left = 999.0
	await _frames(int((_boss.vent_notice_time + 0.3) * PHYSICS_FPS))
	_boss._gap_left = 0.0
	var charged: bool = false
	for i: int in int(1.0 * PHYSICS_FPS):
		await _frames(1)
		if _boss.current_attack and _boss.current_attack.id == &"charge":
			charged = true
			break
	_check(charged and _boss.target_player == _echo and _boss.vent_charges == 1, "it charges the player at the vent")
	_protect_players()


func _orbs() -> Array[AnglerOrb]:
	var result: Array[AnglerOrb] = []
	for node: Node in get_tree().get_nodes_in_group("angler_projectiles"):
		if node is AnglerOrb and (node as AnglerOrb).is_homing():
			result.append(node as AnglerOrb)
	return result


func _mines() -> Array[AnglerMine]:
	var result: Array[AnglerMine] = []
	for node: Node in get_tree().get_nodes_in_group("angler_mines"):
		result.append(node as AnglerMine)
	return result


# --- Helpers -----------------------------------------------------------------------

## Builds stage 1 level 3 (the Angler; stage_index 1 / 2 = a placeholder
## boss) with the players at the start.
func _build(stage_index: int = 0) -> void:
	_stage.stage_index = stage_index
	_stage._start_level(2)
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature and creature != _builder.get_boss():
			creature.remove_from_group("creatures")
			creature.queue_free()
	_boss = _builder.get_boss() as AnglerBoss
	var boss: Boss = _builder.get_boss() as Boss
	# The tests check the boss alone (no stage summary when it dies).
	if boss and boss.killed.is_connected(_stage._on_boss_killed):
		boss.killed.disconnect(_stage._on_boss_killed)
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
	return door_center + door_center.direction_to(_builder.get_boss().global_position) * 160.0


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
