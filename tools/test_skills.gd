extends Node
## Headless test of the skills and the pause menu, run as a scene so the Game
## autoload exists (it loads the real game.tscn):
##   godot --headless --path . --fixed-fps 60 res://tools/test_skills.tscn
## Checks:
## - offers: cards / picks per stage and after a boss, none after the world's
##   final boss, own + shared pool only, no repeats, higher ranks, max rank,
##   the active slot (never two new actives, none once one is owned),
##   available_from_world, the fallback when nothing is left;
## - a skill made in code from an existing stat works without code changes;
## - every Ocean skill's effect value in the game systems;
## - the choice flow (screen -> loadout -> players), retries keep the skills of
##   the level start (Calm) / stage start (Challenge), the saved loadout;
## - the pause menu freezes creatures, oxygen and the escape timer, and its
##   Restart level restores the level start;
## - aiming: per-player device binding, Lure / Shield / sword with the right
##   stick (independent of moving) and with the keyboard (hold + move keys);
## - cooldown readability: icon states, the ready flash and the ReadyCue on
##   the character (active skills and the Echo's pulse).

const GAME_SCENE: String = "res://scenes/game.tscn"
const CREATURE_SCENE: String = "res://scenes/creature.tscn"
## Random offers built per rule check.
const OFFER_RUNS: int = 300

var _game: Node2D
var _stage: StageManager
var _builder: LevelBuilder
var _echo: Player
var _guardian: Player
var _screen: SkillChoiceScreen
var _pause: PauseMenu
var _catalog: SkillCatalog
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_catalog = Game.skill_catalog
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Node2D
	_stage = _game.get_node("StageManager") as StageManager
	_stage.test_mode = SaveData.Mode.CALM
	add_child(_game)
	_builder = _game.get_node("LevelBuilder") as LevelBuilder
	_echo = _game.get_node("Echo") as Player
	_guardian = _game.get_node("Guardian") as Player
	_screen = _game.get_node("SkillChoiceScreen") as SkillChoiceScreen
	_pause = _game.get_node("PauseMenu") as PauseMenu
	(_game.get_node("DepthAwareness") as DepthAwareness).decay_per_second = 0.0
	await _frames(10)

	_test_catalog()
	_test_offer_sizes()
	_test_offer_rules()
	_test_new_skill_without_code()
	await _test_passive_effects()
	await _test_creature_effects()
	await _test_lure_pulse()
	await _test_shield()
	await _test_dash()
	await _test_device_binding()
	await _test_aim_lure()
	await _test_aim_shield()
	await _test_aim_sword()
	await _test_cooldown_states()
	await _test_choice_flow()
	await _test_retry_keeps_level_start_skills()
	await _test_pause()

	print("RESULT: %s" % ("ALL SKILL CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures))
	_game.queue_free()
	for i: int in 10:
		await get_tree().process_frame
		OS.delay_msec(30)
	get_tree().quit(0 if _failures == 0 else 1)


# --- Catalog and offers ------------------------------------------------------

func _test_catalog() -> void:
	print("== Catalog ==")
	_check(_catalog != null and _catalog.skills.size() == 13, "the catalog has the 13 Ocean skills (%d)" % (_catalog.skills.size() if _catalog else 0))
	var ids: Dictionary = {}
	for definition: SkillDefinition in _catalog.skills + _catalog.fallbacks:
		_check(definition.id != "" and not ids.has(definition.id), "%s: a unique id" % definition.id)
		ids[definition.id] = true
		_check(definition.name_en != "" and definition.name_ar != "" and definition.description_en != "" and definition.description_ar != ""
			and definition.tip_en != "" and definition.tip_ar != "", "%s: name, description and tip in English and Arabic" % definition.id)
		_check(definition.max_rank >= 1 and definition.max_rank <= 2, "%s: 1 or 2 ranks" % definition.id)
		for key: String in definition.values:
			_check(definition.values[key].size() >= definition.max_rank, "%s: a value per rank for %s" % [definition.id, key])
		if definition.is_active():
			var node: Node = definition.active_scene.instantiate() if definition.active_scene else null
			_check(node is ActiveSkill, "%s: its active scene is an ActiveSkill" % definition.id)
			if node:
				node.free()
	_check(not _catalog.fallbacks.is_empty() and _catalog.fallbacks[0].is_fallback, "there is a fallback")


func _test_offer_sizes() -> void:
	print("== Offer sizes per stage ==")
	var world: WorldConfig = _stage.world
	var expected: Array[Vector2i] = [
		Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 1),
		Vector2i(3, 1), Vector2i(3, 1), Vector2i(3, 2),
		Vector2i(3, 1), Vector2i(3, 1), Vector2i(0, 0),
	]
	for stage: int in 3:
		for level: int in 3:
			var size: Vector2i = SkillOffer.get_offer_size(world, stage, level)
			var want: Vector2i = expected[stage * 3 + level]
			_check(size == want, "stage %d level %d: %d cards, %d picks (expected %d / %d)" % [stage + 1, level + 1, size.x, size.y, want.x, want.y])


func _test_offer_rules() -> void:
	print("== Offer rules ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var empty := SkillLoadout.new("ocean")
	var own_pool_only: bool = true
	var no_repeats: bool = true
	var never_two_actives: bool = true
	var right_size: bool = true
	for run: int in OFFER_RUNS:
		for character: String in SkillLoadout.CHARACTERS:
			var offer: Array[SkillDefinition] = SkillOffer.build(_catalog, empty, character, 0, 3, rng)
			right_size = right_size and offer.size() == 3
			var actives: int = 0
			var seen: Dictionary = {}
			for definition: SkillDefinition in offer:
				own_pool_only = own_pool_only and definition.is_for(character)
				no_repeats = no_repeats and not seen.has(definition.id)
				seen[definition.id] = true
				if definition.is_active():
					actives += 1
			never_two_actives = never_two_actives and actives <= 1
	_check(right_size, "every offer has the asked number of cards")
	_check(own_pool_only, "offers only hold the character's own and shared skills")
	_check(no_repeats, "no skill twice in one offer")
	_check(never_two_actives, "never two new active skills in one offer (%d runs)" % OFFER_RUNS)

	var echo_pool: Array[SkillDefinition] = SkillOffer.get_candidates(_catalog, empty, "echo", 0)
	_check(echo_pool.size() == 8, "Echo pool: 5 own + 3 shared skills (%d)" % echo_pool.size())
	var guardian_pool: Array[SkillDefinition] = SkillOffer.get_candidates(_catalog, empty, "guardian", 0)
	_check(guardian_pool.size() == 8, "Guardian pool: 5 own + 3 shared skills (%d)" % guardian_pool.size())

	# Ranks.
	var ranked := SkillLoadout.new("ocean")
	ranked.add_rank("echo", _catalog.find("far_echo"))
	_check(_ids(SkillOffer.get_candidates(_catalog, ranked, "echo", 0)).has("far_echo"), "rank 2 of an owned skill can be offered")
	ranked.add_rank("echo", _catalog.find("far_echo"))
	_check(ranked.get_rank("echo", "far_echo") == 2, "a second pick gives rank 2")
	_check(not _ids(SkillOffer.get_candidates(_catalog, ranked, "echo", 0)).has("far_echo"), "a skill at max rank is not offered")
	ranked.add_rank("echo", _catalog.find("far_echo"))
	_check(ranked.get_rank("echo", "far_echo") == 2, "the rank never goes above max_rank")
	ranked.add_rank("echo", _catalog.find("quick_revive"))
	_check(ranked.get_rank("echo", "quick_revive") == 1 and ranked.get_rank("guardian", "quick_revive") == 0, "a shared skill is owned by one character at a time")
	_check(_ids(SkillOffer.get_candidates(_catalog, ranked, "guardian", 0)).has("quick_revive"), "the partner can still get his own copy of a shared skill")

	# The active slot.
	var with_active := SkillLoadout.new("ocean")
	with_active.add_rank("guardian", _catalog.find("shield"))
	var after_active: PackedStringArray = _ids(SkillOffer.get_candidates(_catalog, with_active, "guardian", 0))
	_check(not after_active.has("dash") and not after_active.has("shield"), "once an active skill is owned, no active skill is offered")
	_check(with_active.has_active("guardian", _catalog) and not with_active.has_active("echo", _catalog), "the active slot is per character")

	# Worlds.
	var later := _catalog.find("far_echo").duplicate() as SkillDefinition
	later.id = "later_world_skill"
	later.available_from_world = 1
	var catalog := _catalog.duplicate() as SkillCatalog
	catalog.skills = _catalog.skills.duplicate()
	catalog.skills.append(later)
	_check(not _ids(SkillOffer.get_candidates(catalog, empty, "echo", 0)).has("later_world_skill"), "a skill of a later world is not offered in the Ocean")
	_check(_ids(SkillOffer.get_candidates(catalog, empty, "echo", 1)).has("later_world_skill"), "it is offered from its world on")

	# Nothing left: the fallback.
	var full := SkillLoadout.new("ocean")
	for definition: SkillDefinition in _catalog.skills:
		if definition.is_for("echo"):
			full.set_rank("echo", definition.id, definition.max_rank)
	var fallback_offer: Array[SkillDefinition] = SkillOffer.build(_catalog, full, "echo", 0, 3, rng)
	_check(fallback_offer.size() == 1 and fallback_offer[0].is_fallback, "nothing left: the fallback is offered")
	var almost := full.copy()
	almost.set_rank("echo", "far_echo", 1)
	var short_offer: Array[SkillDefinition] = SkillOffer.build(_catalog, almost, "echo", 0, 3, rng)
	_check(short_offer.size() == 2 and _ids(short_offer).has("far_echo") and short_offer[1].is_fallback, "one skill left: it and the fallback are offered")

	# The world change.
	_check(SaveData.from_dict({"world": "caves", "skills": full.to_dict()}).skills.is_empty(), "Ocean skills are dropped when the save is in the next world")


## A skill made only from data (no code) that reuses an existing stat.
func _test_new_skill_without_code() -> void:
	print("== A new data-only skill ==")
	var custom := SkillDefinition.new()
	custom.id = "test_wide_pulse"
	custom.owner = SkillDefinition.Owner.ECHO
	custom.values = {"pulse_radius_mult": PackedFloat32Array([2.0])}
	var catalog := SkillCatalog.new()
	catalog.skills = [custom]
	_echo.skills.set_skills({"test_wide_pulse": 1}, catalog)
	var pulse := _echo.get_node("Pulse") as PulseAbility
	_check(is_equal_approx(pulse.get_radius(), pulse.pulse_radius * 2.0), "a .tres-only skill doubles the pulse radius")
	_echo.skills.set_skills({}, _catalog)


# --- Effects -----------------------------------------------------------------

func _test_passive_effects() -> void:
	print("== Passive skill effects ==")
	await _build(0, 0)
	var pulse := _echo.get_node("Pulse") as PulseAbility
	var base_radius: float = pulse.pulse_radius
	_give(_echo, "far_echo", 1)
	_check(is_equal_approx(pulse.get_radius(), base_radius * 1.3), "Far Echo 1: pulse radius x1.3 (%.0f)" % pulse.get_radius())
	_give(_echo, "far_echo", 2)
	_check(is_equal_approx(pulse.get_radius(), base_radius * 1.5), "Far Echo 2: pulse radius x1.5 (%.0f)" % pulse.get_radius())

	var base_cost: float = _echo.pressure.pulse_cost_ratio
	_give(_echo, "calm_lungs", 1)
	_check(is_equal_approx(_echo.pressure.get_pulse_cost_ratio(), base_cost * 0.7), "Calm Lungs 1: pulse cost -30%")
	_give(_echo, "calm_lungs", 2)
	_check(is_equal_approx(_echo.pressure.get_pulse_cost_ratio(), base_cost * 0.5), "Calm Lungs 2: pulse cost -50%")
	_echo.pressure.refill()
	var before: float = _echo.pressure.value
	_echo.pulse_emitted.emit(_echo.global_position)
	_check(absf(before - _echo.pressure.value - _echo.pressure.max_value * base_cost * 0.5) < 0.01, "a pulse really costs half")

	var sword := _guardian.get_node("UnlitLayer/Sword") as SwordAbility
	_give(_guardian, "wide_swing", 1)
	_check(is_equal_approx(rad_to_deg(sword.get_arc_radians(false)), sword.quick_arc_degrees * 1.3), "Wide Swing 1: quick arc x1.3")
	_give(_guardian, "wide_swing", 2)
	_check(is_equal_approx(rad_to_deg(sword.get_arc_radians(true)), sword.finisher_arc_degrees * 1.6), "Wide Swing 2: finisher arc x1.6")

	var sense := _guardian.get_node("CloseSense") as CloseSense
	_give(_guardian, "keener_sense", 1)
	_check(is_equal_approx(sense.get_radius(), 130.0), "Keener Sense 1: close sense 130 px (%.0f)" % sense.get_radius())
	_give(_guardian, "keener_sense", 2)
	_check(is_equal_approx(sense.get_radius(), 160.0), "Keener Sense 2: close sense 160 px (%.0f)" % sense.get_radius())

	_give(_guardian, "", 0)
	var base_drain: float = _guardian.pressure.get_drain_per_second()
	_give(_guardian, "iron_lungs", 1)
	_check(is_equal_approx(_guardian.pressure.get_drain_per_second(), base_drain * 0.8), "Iron Lungs 1: drain -20%")
	_give(_guardian, "iron_lungs", 2)
	_check(is_equal_approx(_guardian.pressure.get_drain_per_second(), base_drain * 0.65), "Iron Lungs 2: drain -35%")

	var revive := _echo.get_node("Revive") as ReviveHelper
	_give(_echo, "quick_revive", 1)
	_check(is_equal_approx(revive.get_revive_time(), 1.4), "Quick Revive 1: 1.4 s (%.2f)" % revive.get_revive_time())
	_give(_echo, "quick_revive", 2)
	_check(is_equal_approx(revive.get_revive_time(), 1.0), "Quick Revive 2: 1.0 s")
	_check(is_equal_approx((_guardian.get_node("Revive") as ReviveHelper).get_revive_time(), 2.0), "the partner without it still needs 2.0 s")

	var mending := _game.get_node("MendLayer/PartnerMending") as PartnerMending
	_give(_echo, "", 0)
	_give(_guardian, "", 0)
	var base_distance: float = mending.get_mend_distance()
	_give(_echo, "stronger_bond", 1)
	_check(is_equal_approx(mending.get_mend_distance(), base_distance * 1.35), "Stronger Bond 1: mending range x1.35")
	_give(_guardian, "stronger_bond", 2)
	_check(is_equal_approx(mending.get_mend_distance(), base_distance * 1.7), "Stronger Bond 2 (either player): range x1.7")
	_check(is_equal_approx(_echo.skills.get_multiplier("mend_rate_mult"), 1.5)
		and is_equal_approx(_guardian.skills.get_multiplier("mend_rate_mult"), 2.0), "each player mends at their own rate")
	# Measured: both close, hurt, nobody chased.
	_clear_creatures()
	_guardian.global_position = _echo.global_position + Vector2(40.0, 0.0)
	_echo.health.set_segments(1.0)
	_guardian.health.set_segments(1.0)
	await _frames(60)
	var echo_gain: float = _echo.health.value - 1.0
	var guardian_gain: float = _guardian.health.value - 1.0
	_check(echo_gain > 0.0 and absf(guardian_gain / echo_gain - 2.0 / 1.5) < 0.1, "mending really heals the rank-2 player faster (%.3f vs %.3f)" % [guardian_gain, echo_gain])

	_give(_echo, "shard_resonance", 1)
	_give(_guardian, "", 0)
	_echo.health.set_segments(1.0)
	_guardian.health.set_segments(1.0)
	_stage._on_shard_collected(null)
	_check(is_equal_approx(_echo.health.value, 3.0), "Shard Resonance: a shard restores 2 segments (%.1f)" % _echo.health.value)
	_check(is_equal_approx(_guardian.health.value, 2.0), "without it: 1 segment (%.1f)" % _guardian.health.value)
	_give(_echo, "", 0)
	_protect_players()


func _test_creature_effects() -> void:
	print("== Longer Exposure, Echo Mark ==")
	await _build(0, 0)
	var spot: Vector2 = _far_spot(_echo.global_position, 700.0)
	var creature: Creature = _spawn_creature(spot)
	await _frames(2)
	creature.on_sonar_hit(spot)
	_check(is_equal_approx(creature._exposed_left, creature.exposed_time), "no skill: Exposed %.1f s" % creature.exposed_time)
	_check(creature.get_mark_ratio() == 0.0, "no skill: no Echo Mark")
	_give(_echo, "longer_exposure", 1)
	creature.on_sonar_hit(spot)
	_check(is_equal_approx(creature._exposed_left, 2.5), "Longer Exposure 1: Exposed 2.5 s (%.2f)" % creature._exposed_left)
	_give(_echo, "longer_exposure", 2)
	creature.on_sonar_hit(spot)
	_check(is_equal_approx(creature._exposed_left, 3.2), "Longer Exposure 2: Exposed 3.2 s (%.2f)" % creature._exposed_left)
	await _frames(roundi(60.0 * (creature.pulse_reveal_time + 0.3)))
	_check(creature.is_exposed() and creature.is_revealed(), "still Exposed and hittable after the normal reveal time")

	_give(_echo, "echo_mark", 1)
	creature.on_sonar_hit(spot)
	await _frames(roundi(60.0 * 3.2))
	_check(creature.get_mark_ratio() > 0.0, "Echo Mark: the outline stays after 3 s")
	_check(not creature.is_revealed(), "the mark alone does not make it hittable")
	await _frames(60)
	_check(creature.get_mark_ratio() == 0.0, "the mark ends after 4 s")
	creature.queue_free()
	_give(_echo, "", 0)


func _test_lure_pulse() -> void:
	print("== Lure Pulse ==")
	await _build(0, 0)
	_give(_echo, "lure_pulse", 1)
	var lure := _echo.skills.active as LurePulseSkill
	_check(lure != null, "the Echo gets the Lure Pulse node")
	if lure == null:
		return
	_guardian.global_position = _echo.global_position + Vector2(20.0, 0.0)
	_echo.facing = _open_direction(_echo.global_position, 350.0)
	var landing: Vector2 = lure.get_landing_point(_echo.facing)
	_check(landing.distance_to(_echo.global_position) <= 351.0, "the decoy lands at most 350 px away (%.0f)" % landing.distance_to(_echo.global_position))
	var near: Creature = _spawn_creature(_open_spot(landing, 300.0))
	var far: Creature = _spawn_creature(_far_spot(landing, 900.0))
	for creature: Creature in [near, far]:
		# Only the lure may move them in this check.
		creature.spot_distance = 0.0
		creature.pulse_spot_distance = 0.0
	await _frames(2)
	_echo.pressure.refill()
	lure.throw_decoy(_echo.facing)
	_check(is_equal_approx(_echo.pressure.get_ratio(), 0.98), "a throw costs 2%% oxygen (%.3f)" % _echo.pressure.get_ratio())
	_check(is_equal_approx(lure.cooldown_left, 10.0), "10 s cooldown")
	await _frames(30)
	_check(near.state == Creature.State.INVESTIGATE and near.target.distance_to(lure.decoy_position) < 1.0, "a creature within 500 px investigates the decoy")
	_check(far.state != Creature.State.INVESTIGATE, "a creature 900 px away does not")
	near.queue_free()
	far.queue_free()
	_give(_echo, "", 0)
	_check(_echo.skills.active == null, "losing the skill removes the node")


func _test_shield() -> void:
	print("== Shield ==")
	await _build(0, 0)
	_give(_guardian, "shield", 1)
	var shield := _guardian.skills.active as ShieldSkill
	_check(shield != null, "the Guardian gets the Shield node")
	if shield == null:
		return
	var center: Vector2 = _guardian.global_position
	_guardian.facing = Vector2.RIGHT
	Input.action_press("p2_skill")
	await _frames(3)
	_check(shield.is_raised and shield.blocks_actions(), "holding the skill button raises it (no sword swings)")
	_check(is_equal_approx(_guardian.speed_scale, 0.55), "moving at 55% while holding it")
	var creature: Creature = _spawn_creature(center + Vector2(200.0, 0.0))
	await _frames(1)
	_guardian.health._invulnerable_left = 0.0
	var before: float = _guardian.health.value
	_guardian.health.take_hit(center + Vector2(40.0, 0.0), creature)
	_check(_guardian.health.value == before and shield.blocks == 1, "a hit from the front is blocked")
	_guardian.health.take_hit(center + Vector2(28.0, 22.0), creature)
	_check(_guardian.health.value == before, "a hit 38° off the front is blocked (120° arc)")
	_guardian.health.take_hit(center + Vector2(-40.0, 0.0), creature)
	_check(_guardian.health.value < before, "a hit from behind is not blocked")
	_echo.global_position = center + Vector2(-60.0, 0.0)
	_echo.health._invulnerable_left = 0.0
	var echo_before: float = _echo.health.value
	_echo.health.take_hit(center + Vector2(40.0, 0.0), creature)
	_check(_echo.health.value == echo_before, "the Echo right behind him is protected")
	_echo.global_position = center + Vector2(90.0, 0.0)
	_echo.health.take_hit(center + Vector2(130.0, 0.0), creature)
	_check(_echo.health.value < echo_before, "the Echo in front of him is not")
	Input.action_release("p2_skill")
	await _frames(3)
	_check(not shield.is_raised and is_equal_approx(_guardian.speed_scale, 1.0), "letting go lowers it, normal speed")
	creature.queue_free()
	_give(_guardian, "", 0)
	_protect_players()


func _test_dash() -> void:
	print("== Dash ==")
	await _build(0, 0)
	_give(_guardian, "dash", 1)
	var dash := _guardian.skills.active as DashSkill
	_check(dash != null, "the Guardian gets the Dash node")
	if dash == null:
		return
	_guardian.global_position = _echo.global_position + Vector2(20.0, 0.0)
	_guardian.facing = _open_direction(_guardian.global_position, 200.0)
	var start: Vector2 = _guardian.global_position
	_guardian.health._invulnerable_left = 0.0
	dash.dash()
	_check(_guardian.velocity.length() > _guardian.max_speed * 3.0, "a dash is much faster than swimming (%.0f px/s)" % _guardian.velocity.length())
	_check(_guardian.health.is_invulnerable(), "invulnerable during the dash")
	_check(is_equal_approx(dash.cooldown_left, 4.0), "4 s cooldown")
	await _frames(12)
	_check(_guardian.global_position.distance_to(start) > 80.0, "the dash moves him (%.0f px)" % _guardian.global_position.distance_to(start))
	await _frames(12)
	_check(not _guardian.health.is_invulnerable(), "the invulnerability is short")
	_give(_guardian, "", 0)
	_protect_players()


# --- Aiming ----------------------------------------------------------------

func _test_device_binding() -> void:
	print("== Aim: per-player device binding ==")
	_check(_echo.joypad_device == 0 and _guardian.joypad_device == 1, "Echo = gamepad 1, Guardian = gamepad 2")
	for prefix: String in ["p1_", "p2_"]:
		for action_name: String in ["aim_left", "aim_right", "aim_up", "aim_down"]:
			var events: Array[InputEvent] = InputMap.action_get_events(prefix + action_name)
			var device: int = 0 if prefix == "p1_" else 1
			_check(events.size() == 1 and events[0] is InputEventJoypadMotion and events[0].device == device,
				"%s%s: the right stick of gamepad %d only" % [prefix, action_name, device + 1])
	var other_stick := InputEventJoypadMotion.new()
	other_stick.device = 1
	other_stick.axis = JOY_AXIS_RIGHT_X
	other_stick.axis_value = 1.0
	_check(not other_stick.is_action("p1_aim_right") and other_stick.is_action("p2_aim_right"), "gamepad 2's right stick never aims for the Echo")
	_echo.uses_gamepad = false
	_guardian.uses_gamepad = false
	var button := InputEventJoypadButton.new()
	button.device = 1
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	_echo._input(button)
	_guardian._input(button)
	_check(not _echo.uses_gamepad and _guardian.uses_gamepad, "a button on gamepad 2 switches only the Guardian to gamepad aiming")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	_guardian._input(key)
	_check(_guardian.uses_gamepad, "the Echo's keys do not switch the Guardian back")
	var arrow := InputEventKey.new()
	arrow.physical_keycode = KEY_UP
	arrow.pressed = true
	_guardian._input(arrow)
	_check(not _guardian.uses_gamepad, "his own keys switch him back to keyboard aiming")
	var small := InputEventJoypadMotion.new()
	small.device = 0
	small.axis = JOY_AXIS_LEFT_X
	small.axis_value = 0.1
	_echo._input(small)
	_check(not _echo.uses_gamepad, "stick drift below the threshold does not switch")


func _test_aim_lure() -> void:
	print("== Aim: Lure Pulse ==")
	await _build(0, 0)
	_give(_echo, "lure_pulse", 1)
	var lure := _echo.skills.active as LurePulseSkill
	_guardian.global_position = _echo.global_position + Vector2(0.0, 30.0)
	await _frames(2)
	# Gamepad: move left, aim right.
	_echo.uses_gamepad = true
	_echo.facing = Vector2.UP
	var right: Vector2 = _open_both_ways(_echo.global_position, 350.0, 150.0)
	_press_aim("p1_", right)
	_press_move("p1_", -right)
	await _frames(20)
	_check(lure.is_aiming(), "gamepad: the indicator shows while the right stick is pushed")
	_check(_echo.velocity.dot(-right) > 50.0, "gamepad: she keeps moving the other way while aiming (%.0f px/s)" % _echo.velocity.dot(-right))
	_check(_echo.get_aim_direction().dot(right) > 0.99, "gamepad: the aim is the right stick, not the move direction")
	lure.throw_decoy(_echo.get_aim_direction())
	_check(_echo.global_position.direction_to(lure.decoy_position).dot(right) > 0.95, "gamepad: the decoy flies along the right stick")
	_release_aim("p1_")
	_release_move("p1_")
	await _frames(2)
	_check(not lure.is_aiming(), "gamepad: no indicator on cooldown / with the stick neutral")
	# Stick neutral: the move direction, else the facing.
	_check(_echo.get_aim_direction() == _echo.facing, "stick neutral and standing: the facing")
	Input.action_press("p1_move_down")
	await _frames(1)
	_check(_echo.get_aim_direction().dot(Vector2.DOWN) > 0.99, "stick neutral and moving: the move direction")
	Input.action_release("p1_move_down")
	await _frames(20)

	# Keyboard: hold = stop + aim with the move keys, release = throw.
	lure.cooldown_left = 0.0
	_echo.uses_gamepad = false
	_echo.velocity = Vector2.ZERO
	_echo.facing = Vector2.RIGHT
	# The skill's own _process reads the press (just pressed = this frame).
	Input.action_press("p1_skill")
	await get_tree().process_frame
	await _frames(1)
	_check(lure.is_key_aiming and lure.is_aiming() and _echo.move_locked, "keyboard: holding the skill button starts aiming")
	var aim_dir: Vector2 = _open_direction(_echo.global_position, 350.0, 8)
	var start: Vector2 = _echo.global_position
	_press_move("p1_", aim_dir)
	await _frames(20)
	_check(_echo.global_position.distance_to(start) < 3.0, "keyboard: she stands still while aiming (%.1f px)" % _echo.global_position.distance_to(start))
	_check(lure.key_aim_direction.dot(aim_dir.normalized()) > 0.9, "keyboard: the move keys aim")
	_check(lure.cooldown_left == 0.0, "keyboard: nothing is thrown while held")
	Input.action_release("p1_skill")
	await _frames(2)
	_check(not lure.is_key_aiming and not _echo.move_locked and lure.cooldown_left > 0.0, "keyboard: releasing throws and frees the movement")
	_check(_echo.global_position.direction_to(lure.decoy_position).dot(aim_dir.normalized()) > 0.9, "keyboard: the decoy flies where the keys aimed")
	_release_move("p1_")
	_give(_echo, "", 0)
	_check(not _echo.move_locked, "losing the skill never leaves her locked")


func _test_aim_shield() -> void:
	print("== Aim: Shield ==")
	await _build(0, 0)
	_give(_guardian, "shield", 1)
	var shield := _guardian.skills.active as ShieldSkill
	_guardian.global_position = _echo.global_position + Vector2(0.0, 40.0)
	await _frames(2)
	# Gamepad: right stick aims left while the left stick strafes right.
	_guardian.uses_gamepad = true
	var move_dir: Vector2 = _open_direction(_guardian.global_position, 150.0, 8)
	var aim_dir: Vector2 = -move_dir
	_guardian.facing = move_dir
	_press_aim("p2_", aim_dir)
	Input.action_press("p2_skill")
	_press_move("p2_", move_dir)
	await _frames(20)
	_check(shield.is_raised and shield.shield_direction.dot(aim_dir) > 0.99, "gamepad: the right stick points the shield")
	_check(_guardian.velocity.dot(move_dir) > 20.0, "gamepad: he strafes the other way (%.0f px/s)" % _guardian.velocity.dot(move_dir))
	_check(_guardian.velocity.length() <= _guardian.max_speed * 0.55 + 1.0, "gamepad: strafing is slow")
	var center: Vector2 = _guardian.global_position
	_guardian.health._invulnerable_left = 0.0
	var before: float = _guardian.health.value
	_check(shield.blocks_hit(_guardian, center + aim_dir * 40.0, null), "a hit from the aimed side is blocked")
	_check(not shield.blocks_hit(_guardian, center + move_dir * 40.0, null), "a hit from the move side is not")
	_release_aim("p2_")
	await _frames(10)
	_check(shield.shield_direction.dot(aim_dir) > 0.99, "gamepad: stick neutral keeps the shield locked")
	_release_move("p2_")
	Input.action_release("p2_skill")
	await _frames(3)
	_check(_guardian.health.value == before, "no damage taken")

	# Keyboard: locked to the aim when raised, the keys turn it, slow strafing.
	_guardian.uses_gamepad = false
	var keys_dir: Vector2 = _open_direction(_guardian.global_position, 150.0, 8)
	_guardian.facing = keys_dir.orthogonal()
	_guardian.velocity = Vector2.ZERO
	Input.action_press("p2_skill")
	await _frames(2)
	_check(shield.shield_direction.dot(keys_dir.orthogonal()) > 0.99, "keyboard: raised towards the facing")
	_press_move("p2_", keys_dir)
	await _frames(6)
	var partial: float = rad_to_deg(shield.shield_direction.angle_to(keys_dir))
	_check(absf(partial) > 20.0, "keyboard: the keys turn it gradually (%.0f° left after 0.1 s)" % absf(partial))
	await _frames(40)
	_check(shield.shield_direction.dot(keys_dir) > 0.99, "keyboard: after a moment it faces the keys")
	_check(_guardian.velocity.dot(keys_dir) > 20.0 and _guardian.velocity.length() <= _guardian.max_speed * 0.55 + 1.0, "keyboard: he moves slowly meanwhile")
	_release_move("p2_")
	await _frames(10)
	_check(shield.shield_direction.dot(keys_dir) > 0.99, "keyboard: no keys = the shield stays where it was")
	Input.action_release("p2_skill")
	await _frames(3)
	_give(_guardian, "", 0)
	_protect_players()


func _test_aim_sword() -> void:
	print("== Aim: sword ==")
	await _build(0, 0)
	var sword := _guardian.get_node("UnlitLayer/Sword") as SwordAbility
	_guardian.uses_gamepad = true
	_guardian.facing = Vector2.RIGHT
	_press_aim("p2_", Vector2.DOWN)
	await _frames(2)
	_check(sword.is_showing_aim_tick(), "gamepad: the aim tick shows while the right stick is pushed")
	sword._start_hit(0)
	_check(sword._swing_dir.dot(Vector2.DOWN) > 0.99, "gamepad: the swing goes along the right stick, not the facing")
	_release_aim("p2_")
	await _frames(40)
	_check(not sword.is_showing_aim_tick(), "stick neutral: no tick")
	sword._start_hit(0)
	_check(sword._swing_dir.dot(Vector2.RIGHT) > 0.99, "stick neutral: the swing goes along the facing")
	await _frames(40)
	_guardian.uses_gamepad = false
	_guardian.facing = Vector2.LEFT
	sword._start_hit(0)
	_check(sword._swing_dir.dot(Vector2.LEFT) > 0.99, "keyboard: the swing goes along the facing")
	await _frames(40)


# --- Cooldown readability --------------------------------------------------

func _test_cooldown_states() -> void:
	print("== Cooldown states ==")
	await _build(0, 0)
	var icon := SkillIcon.new()
	icon.setup(_catalog.find("dash"), 1, 34.0)
	add_child(icon)
	icon.set_state(0.6, false)
	var dim: Color = icon.get_shape_color()
	var full: Color = _catalog.find("dash").icon_color
	_check(icon.is_cooling() and dim.s < full.s * 0.5 and dim.v < full.v * 0.6, "recharging: the icon is dimmed and desaturated")
	icon.set_state(0.0, false)
	_check(not icon.is_cooling() and icon.get_shape_color() == full, "ready: full colour")
	_check(icon.is_flashing() and icon.flashes == 1, "becoming ready flashes once")
	icon.set_state(0.0, false)
	_check(icon.flashes == 1, "staying ready does not flash again")
	icon.queue_free()

	# Active skill: the HUD icon and the cue in the world.
	_give(_guardian, "dash", 1)
	var dash := _guardian.skills.active as DashSkill
	await _frames(2)
	var status: PlayerStatus = _status_of(_guardian)
	var heard: Array[String] = []
	var audio: AudioDirector = AudioDirector.find(get_tree())
	var listen: Callable = func(sound_name: String, _at: Vector2) -> void: heard.append(sound_name)
	audio.sound_played.connect(listen)
	var ready_signals: Array[int] = [0]
	dash.became_ready.connect(func() -> void: ready_signals[0] += 1)
	dash.dash()
	await _frames(30)
	_check(status.get_active_icon().is_cooling(), "Dash on cooldown: the HUD icon shows it")
	_check(dash.ready_cue.plays == 0 and not heard.has("skill_ready"), "no ready cue while recharging")
	await _frames(roundi(60.0 * 4.0))
	_check(ready_signals[0] == 1, "became_ready fires once when the cooldown ends")
	_check(dash.ready_cue.plays == 1, "the ready ring plays on the Guardian")
	_check(heard.has("skill_ready"), "the soft ready chime plays")
	_check(not status.get_active_icon().is_cooling() and status.get_active_icon().flashes == 1, "the HUD icon is ready and flashed")

	# The Echo's pulse: same treatment.
	var pulse := _echo.get_node("Pulse") as PulseAbility
	var echo_status: PlayerStatus = _status_of(_echo)
	_check(echo_status.get_pulse_icon() != null, "the Echo's HUD shows the pulse")
	_check(_status_of(_guardian).get_pulse_icon() == null, "the Guardian's HUD has no pulse icon")
	var plays: int = pulse.ready_cue.plays
	heard.clear()
	pulse.emit_pulse()
	await _frames(20)
	_check(echo_status.get_pulse_icon().is_cooling(), "after a pulse the pulse icon recharges")
	await _frames(roundi(60.0 * pulse.pulse_cooldown))
	_check(pulse.ready_cue.plays == plays + 1 and heard.has("skill_ready"), "pulse ready again: ring + chime")
	_check(not echo_status.get_pulse_icon().is_cooling(), "and the pulse icon is ready")
	audio.sound_played.disconnect(listen)
	_give(_guardian, "", 0)


func _status_of(player: Player) -> PlayerStatus:
	for node: Node in _game.get_node("Hud/PlayerStatuses").get_children():
		var status := node as PlayerStatus
		if status and status.player == player:
			return status
	return null


## A direction (of `steps` around) with no rock for `forward` px ahead and
## `back` px behind.
func _open_both_ways(from: Vector2, forward: float, back: float) -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	for i: int in 16:
		var direction: Vector2 = Vector2.from_angle(TAU * i / 16.0)
		var ahead := PhysicsRayQueryParameters2D.create(from, from + direction * forward, 1)
		var behind := PhysicsRayQueryParameters2D.create(from, from - direction * back, 1)
		if space.intersect_ray(ahead).is_empty() and space.intersect_ray(behind).is_empty():
			return direction
	return Vector2.RIGHT


## Simulates this player's right stick.
func _press_aim(prefix: String, direction: Vector2) -> void:
	_release_aim(prefix)
	if direction.x < -0.01:
		Input.action_press(prefix + "aim_left", -direction.x)
	elif direction.x > 0.01:
		Input.action_press(prefix + "aim_right", direction.x)
	if direction.y < -0.01:
		Input.action_press(prefix + "aim_up", -direction.y)
	elif direction.y > 0.01:
		Input.action_press(prefix + "aim_down", direction.y)


func _release_aim(prefix: String) -> void:
	for action_name: String in ["aim_left", "aim_right", "aim_up", "aim_down"]:
		Input.action_release(prefix + action_name)


func _press_move(prefix: String, direction: Vector2) -> void:
	_release_move(prefix)
	if direction.x < -0.3:
		Input.action_press(prefix + "move_left")
	elif direction.x > 0.3:
		Input.action_press(prefix + "move_right")
	if direction.y < -0.3:
		Input.action_press(prefix + "move_up")
	elif direction.y > 0.3:
		Input.action_press(prefix + "move_down")


func _release_move(prefix: String) -> void:
	for action_name: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(prefix + action_name)


# --- Flow -----------------------------------------------------------------

func _test_choice_flow() -> void:
	print("== Choice flow ==")
	await _build(1, 2)
	_stage.loadout = SkillLoadout.new("ocean")
	_stage._apply_loadout()
	get_tree().paused = true
	_stage._offer_skills()
	await _frames(2)
	_check(_screen.is_open, "the choice screen opens (stage 2 boss: 3 cards, 2 picks)")
	_pause.open()
	_check(not _pause.is_open, "the pause menu cannot open over the choice")
	var picks: Dictionary = _screen.get_picks()
	_check(picks.size() == 2, "one side per player")
	for player: Player in [_echo, _guardian]:
		_screen.press_pick(player)
		_screen.move_cursor(player, 1)
		_screen.press_pick(player)
	var result: Dictionary = await _stage.skills_chosen
	_check(not _screen.is_open, "the screen closes after the summary")
	for player: Player in [_echo, _guardian]:
		var got: Array = result.get(player, [])
		_check(got.size() == 2, "%s picked 2 skills" % player.display_name)
		for definition: SkillDefinition in got:
			_check(_stage.loadout.get_rank(player.get_character_key(), definition.id) == 1 and player.skills.get_rank(definition.id) == 1,
				"%s owns %s (loadout + player)" % [player.display_name, definition.id])
	var hud_icons: int = 0
	for node: Node in _game.get_node("Hud/PlayerStatuses").find_children("*", "", true, false):
		if node is SkillIcon and not node.is_queued_for_deletion():
			hud_icons += 1
	_check(hud_icons == 5, "the HUD shows the pulse + the 4 owned skills (%d)" % hud_icons)
	get_tree().paused = false
	# The world's final boss: no choice.
	_stage.stage_index = 2
	_stage.level_index = 2
	_stage._offer_skills()
	await _frames(2)
	_check(not _screen.is_open, "no choice after the world's final boss")


func _test_retry_keeps_level_start_skills() -> void:
	print("== Retries keep the level start skills ==")
	_stage.stage_index = 0
	_stage.loadout = SkillLoadout.new("ocean")
	_stage._stage_start_loadout = _stage.loadout.copy()
	_stage._apply_loadout()
	_stage._start_level(0)
	await _frames(2)
	# Picked between level 1 and 2 (owned at the start of level 2).
	_stage.apply_picks({_echo: [_catalog.find("far_echo")]})
	_stage._start_level(1)
	await _frames(2)
	# Not possible in play (picks only come between levels): checks the snapshot.
	_stage.apply_picks({_echo: [_catalog.find("calm_lungs")]})
	_stage.mode = SaveData.Mode.CALM
	_stage._retry()
	await _frames(5)
	_check(_stage.level_index == 1 and _echo.skills.get_rank("far_echo") == 1, "Calm retry: the level again with the skills from its start")
	_check(_echo.skills.get_rank("calm_lungs") == 0, "a skill gained after the level start is not kept")
	_stage.mode = SaveData.Mode.CHALLENGE
	_stage._retry()
	await _frames(5)
	_check(_stage.level_index == 0 and _echo.skills.get_rank("far_echo") == 0, "Challenge retry: level 1 with the skills of the stage start")
	_stage.mode = SaveData.Mode.CALM
	_protect_players()


func _test_pause() -> void:
	print("== Pause menu ==")
	await _build(0, 0)
	_stage.loadout = SkillLoadout.new("ocean")
	_stage.loadout.set_rank("echo", "far_echo", 2)
	_stage._apply_loadout()
	await _frames(2)
	_stage._start_level(0)
	await _frames(12)
	var creature: Creature = _spawn_creature(_far_spot(_echo.global_position, 700.0))
	creature.min_speed = 60.0
	creature._investigate(creature.global_position + Vector2(300.0, 0.0))
	var escape: EscapeEvent = _game.get_node("EnvironmentLayer/EscapeEvent") as EscapeEvent
	escape.start(30.0)
	_echo.health._invulnerable_left = 0.0
	await _frames(20)
	_pause.open()
	_check(_pause.is_open and get_tree().paused, "the pause menu opens and pauses the game")
	var oxygen: float = _echo.pressure.value
	var timer: float = escape.time_left
	var position: Vector2 = creature.global_position
	var stage_time: float = _stage.stage_time
	await _frames(60)
	_check(_echo.pressure.value == oxygen, "oxygen is frozen")
	_check(escape.time_left == timer, "the escape timer is frozen")
	_check(creature.global_position == position, "creatures are frozen")
	_check(_stage.stage_time == stage_time, "the stage time is frozen")
	var info_text: String = ""
	for node: Node in _pause._info.find_children("*", "", true, false):
		if node is Label:
			info_text += (node as Label).text + " "
	_check(info_text.contains(Game.mode_name(_stage.mode)) and info_text.contains(_catalog.find("far_echo").display_name(Game.language)),
		"it shows the mode and the skills")
	_pause.close()
	await _frames(30)
	_check(_echo.pressure.value < oxygen and escape.time_left < timer, "after Resume oxygen and the timer run again")
	_check(creature.global_position != position, "creatures move again")

	# Restart level: back to the level start.
	_echo.pressure.value = _echo.pressure.max_value * 0.3
	_stage.apply_picks({_echo: [_catalog.find("calm_lungs")]})
	_pause.open()
	_pause._ask(PauseMenu.Confirm.RESTART)
	_pause._on_confirmed()
	await _frames(5)
	_check(not get_tree().paused and not _pause.is_open, "Restart level resumes the game")
	_check(_echo.pressure.get_ratio() > 0.9, "Restart level restores the oxygen of the level start")
	_check(_echo.skills.get_rank("far_echo") == 2 and _echo.skills.get_rank("calm_lungs") == 0, "and the skills of the level start")
	_check(not escape.is_active, "and stops the escape")

	# Challenge: Restart level = the whole stage from level 1 (like both downed).
	print("== Pause menu: Restart in Challenge ==")
	_stage.mode = SaveData.Mode.CHALLENGE
	_stage.loadout = SkillLoadout.new("ocean")
	_stage._stage_start_loadout = _stage.loadout.copy()
	_stage._apply_loadout()
	_stage._start_level(0)
	await _frames(2)
	_stage.apply_picks({_echo: [_catalog.find("far_echo")]})
	_stage._start_level(1)
	await _frames(12)
	_echo.pressure.value = _echo.pressure.max_value * 0.3
	_guardian.health.set_segments(1.0)
	_pause.open()
	_check(_pause._restart_button.text == Game.text("pause_restart_stage"), "the button says Restart stage")
	_pause._ask(PauseMenu.Confirm.RESTART)
	_check(_pause._confirm_label.text == Game.text("pause_confirm_restart_stage")
		and _pause._confirm_warning.text == Game.text("pause_restart_stage_warning"), "the confirmation says the whole stage restarts")
	_pause._on_confirmed()
	await _frames(5)
	_check(not get_tree().paused and not _pause.is_open, "it resumes the game")
	_check(_stage.level_index == 0, "back to level 1 of the stage (level %d)" % (_stage.level_index + 1))
	# A few frames of drain since the restart.
	_check(_echo.pressure.get_ratio() > 0.99 and _guardian.health.is_full(), "full oxygen and health, like both downed (%.3f)" % _echo.pressure.get_ratio())
	_check(_echo.skills.get_rank("far_echo") == 0, "only the skills of the stage start")
	_stage.mode = SaveData.Mode.CALM
	_pause.open()
	_check(_pause._restart_button.text == Game.text("pause_restart"), "Calm: the button says Restart level")
	_pause.close()
	_protect_players()


# --- Helpers ---------------------------------------------------------------

## Gives the player exactly this one skill (empty id = none).
func _give(player: Player, skill_id: String, rank: int) -> void:
	var entries: Dictionary = {}
	if skill_id != "":
		entries[skill_id] = rank
	player.skills.set_skills(entries, _catalog)


func _ids(list: Array[SkillDefinition]) -> PackedStringArray:
	var result := PackedStringArray()
	for definition: SkillDefinition in list:
		result.append(definition.id)
	return result


func _build(stage_index: int, level_index: int) -> void:
	get_tree().paused = false
	_stage.stage_index = stage_index
	_stage._start_level(level_index)
	_clear_creatures()
	if _builder.get_boss():
		_builder.get_boss().set_physics_process(false)
	if _builder.get_lockdown():
		_builder.get_lockdown().enabled = false
	await _frames(12)
	await _wait_for_navigation()
	_protect_players()


func _wait_for_navigation() -> void:
	var map: RID = get_viewport().world_2d.navigation_map
	for i: int in 300:
		var path: PackedVector2Array = NavigationServer2D.map_get_path(map, _echo.global_position, _echo.global_position + Vector2(5.0, 0.0), true)
		if not path.is_empty():
			return
		await get_tree().physics_frame


func _clear_creatures() -> void:
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		if node != _builder.get_boss():
			node.queue_free()


func _spawn_creature(at: Vector2) -> Creature:
	var creature := (load(CREATURE_SCENE) as PackedScene).instantiate() as Creature
	creature.position = _builder.to_local(at)
	_builder._level.add_child(creature)
	(creature.get_node("Hitbox") as Area2D).set_deferred("monitoring", false)
	return creature


func _protect_players() -> void:
	for player: Player in [_echo, _guardian]:
		if player.health.is_downed:
			player.health.revive()
		player.health._invulnerable_left = 999.0
		player.health.refill()
		player.pressure.refill()


## A direction (of `steps` around; 8 = the key directions) with no rock for `distance` px.
func _open_direction(from: Vector2, distance: float, steps: int = 16) -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	for i: int in steps:
		var direction: Vector2 = Vector2.from_angle(TAU * i / float(steps))
		var query := PhysicsRayQueryParameters2D.create(from, from + direction * distance, 1)
		if space.intersect_ray(query).is_empty():
			return direction
	return Vector2.RIGHT


func _open_spot(center: Vector2, distance: float) -> Vector2:
	var map: RID = get_viewport().world_2d.navigation_map
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	for i: int in 16:
		var candidate: Vector2 = NavigationServer2D.map_get_closest_point(map, center + Vector2.from_angle(TAU * i / 16.0) * distance)
		var query := PhysicsRayQueryParameters2D.create(center, candidate, 1)
		if space.intersect_ray(query).is_empty() and candidate.distance_to(center) > distance * 0.7:
			return candidate
	return NavigationServer2D.map_get_closest_point(map, center + Vector2(distance, 0.0))


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


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("    [%s] %s" % ["ok" if ok else "FAIL", label])
