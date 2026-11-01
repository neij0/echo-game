class_name AnglerBoss
extends Boss
## "The Angler" (أبو صنارة العملاق), the Ocean's first boss. Its look is an
## AnglerVisual (+ AnglerVoice) made here; the fight:
## - Armoured: the sword barely hurts it (armored_damage_scale) unless it is
##   Exposed (an Echo pulse, Longer Exposure applies; a stun). Exposed hits
##   deal exposed_damage_scale, the finisher exposed_finisher_scale, and a
##   stun against a pillar adds stunned_damage_scale (the big opening); never
##   an instant kill. A new phase clears Exposed (Boss).
## - Charge ("charge" attack): it lines up on its target (the lure flares, the
##   body coils), the aim locks charge_aim_lock seconds before the end of the
##   telegraph, then a straight dash. Running into an ArenaPillar stuns it
##   (pillar_stun_time, counts as Exposed) and the pillar takes a blow; a wall
##   ends the dash. The Guardian's raised Shield blocks it (recoil, a longer
##   recovery). A Lure Pulse decoy in its hearing baits the next charge at the
##   decoy ("decoy_listeners" group: hear_decoy).
## - Bite ("bite" attack, a player close to its head): the jaw opens wide
##   (telegraph), then bite_snaps snaps, each one lunging a little.
## - Tail sweep ("sweep", every phase, weight 0: only as a punish): a player
##   close to its body for sweep_trigger_time (per mode) makes it coil with
##   flared fins (telegraph), then it spins and sweeps its tail round: every
##   player within sweep_reach of its body is hit once and knocked away.
## - Bubble vents (BubbleVent) refill oxygen; a player standing at one for
##   vent_notice_time may become its "vent prey" (vent_punish_chance per stay,
##   per mode): its next charge goes at them.
## - Phase 2: faster charges; now and then the lure goes dark and glows at a
##   fake spot (its light moves there too). Homing orbs ("orbs"): the lure
##   flares, then fires orb_count (per mode) slow electric AnglerOrbs at the
##   players; the Echo's pulse pops them, the Guardian's sword or Shield sends
##   them back: an orb that comes home stuns it (orb_stun_time, Exposed).
## - Phase 3: calls small creatures (summon_scene, per mode), the arena gets
##   darker (Darkness.set_extra_darkness), orbs come less often
##   (orb_phase3_cooldown_scale), and lure mines ("mines"): mine_count (per
##   mode) AnglerMines lobbed round the arena, dim until a pulse shows them,
##   each blowing up after its fuse or when touched; charging over one blows it
##   up on the Angler (mine_damage_ratio of its health + mine_stun_time).
## Touching it never hurts (Boss: soft push only).

@export_group("Armor")
## Stunned against a pillar (the real opening): on top of Exposed (the armour
## and Exposed values are the Boss's).
@export var stunned_damage_scale: float = 1.5

@export_group("Charge")
@export var calm_charge_speed: float = 520.0
@export var challenge_charge_speed: float = 600.0
## Phase 2 and later: charges this much faster.
@export var fast_charge_scale: float = 1.3
## The aim locks this many seconds before the telegraph ends (time to dodge).
@export var charge_aim_lock: float = 0.3
## It backs off this fast while it coils (telegraph).
@export var coil_speed: float = 35.0
## Its head reaches this far ahead of its middle (pillar / wall checks).
@export var head_reach: float = 110.0
@export var pillar_stun_time: float = 3.0
@export var pillar_shake_strength: float = 10.0
@export var pillar_shake_time: float = 0.45
@export var wall_shake_strength: float = 5.0
@export var wall_shake_time: float = 0.3
## Blocked by the Shield: it recoils this fast and its recovery lasts this
## much longer (a bigger opening).
@export var block_recoil_speed: float = 220.0
@export var block_recovery_scale: float = 1.4

@export_group("Bite")
@export var bite_snaps: int = 2
@export var bite_snap_interval: float = 0.45
@export var bite_lunge_speed: float = 240.0
## The jaws reach a circle of bite_radius, bite_forward in front of the head.
@export var bite_radius: float = 64.0
@export var bite_forward: float = 40.0
## It edges closer while the jaw opens.
@export var bite_approach_speed: float = 40.0

@export_group("Lure Bait")
## Seconds a decoy keeps its attention (its next charge goes at the decoy).
@export var bait_memory: float = 2.5

@export_group("Phase 2: Fake Lure")
@export var fake_lure_interval: float = 4.5
@export var fake_lure_time: float = 1.4
@export var fake_lure_distance: float = 240.0
## Seconds the fake fades in / out.
@export var fake_lure_fade: float = 0.25

@export_group("Phase 3: Summons")
@export var summon_scene: PackedScene
## "0-1 in Calm": set calm_summon_count to 0 for none.
@export var calm_summon_count: int = 1
@export var challenge_summon_count: int = 2
@export var summon_distance: float = 360.0
@export_range(0.0, 1.0) var phase3_darkness: float = 0.35

@export_group("Tail Sweep")
## A player this close to its body (contact distance) for sweep_trigger_time
## (Calm / Challenge) seconds makes it sweep.
@export var sweep_trigger_distance: float = 110.0
@export var calm_sweep_trigger_time: float = 3.5
@export var challenge_sweep_trigger_time: float = 3.0
## The tail reaches this far from its body.
@export var sweep_reach: float = 130.0
@export var sweep_shake_strength: float = 6.0
@export var sweep_shake_time: float = 0.3

@export_group("Vents")
## Standing at a vent this long makes a player noticed...
@export var vent_notice_time: float = 1.2
## ...and with this chance (once per stay) its next charge goes at them.
@export_range(0.0, 1.0) var calm_vent_punish_chance: float = 0.4
@export_range(0.0, 1.0) var challenge_vent_punish_chance: float = 0.6

@export_group("Orbs")
@export var orb_scene: PackedScene
@export var calm_orb_count: int = 2
@export var challenge_orb_count: int = 3
## Seconds between two orbs of one volley.
@export var orb_interval: float = 0.18
@export var calm_orb_speed: float = 100.0
@export var challenge_orb_speed: float = 125.0
## Degrees per second an orb turns towards its player (slow: they can be outrun).
@export var calm_orb_turn_rate: float = 55.0
@export var challenge_orb_turn_rate: float = 75.0
@export var orb_lifetime: float = 8.0
@export var calm_orb_damage: float = 1.0
@export var challenge_orb_damage: float = 1.5
@export var orb_knockback: float = 280.0
## A deflected orb that reaches it stuns it this long (counts as Exposed).
@export var orb_stun_time: float = 1.8
## Phase 3 fires orbs less often (cooldown x this).
@export var orb_phase3_cooldown_scale: float = 1.7

@export_group("Mines")
@export var mine_scene: PackedScene
@export var calm_mine_count: int = 4
@export var challenge_mine_count: int = 5
## Seconds between two mines of one volley.
@export var mine_interval: float = 0.12
## Fuse (seconds) picked in this range per mine.
@export var calm_mine_fuse: Vector2 = Vector2(7.0, 8.5)
@export var challenge_mine_fuse: Vector2 = Vector2(6.0, 7.0)
@export var mine_blast_radius: float = 110.0
@export var calm_mine_damage: float = 1.0
@export var challenge_mine_damage: float = 1.5
@export var mine_knockback: float = 420.0
## Mines land this far from it, at least mine_spacing apart.
@export var mine_distance: Vector2 = Vector2(180.0, 620.0)
@export var mine_spacing: float = 150.0
## A mine blowing up on it: this share of its health and a short stun.
@export var mine_damage_ratio: float = 0.05
@export var mine_stun_time: float = 1.5

@export_group("Body")
## Half thickness of its body (contact push, charge hits).
@export var body_half_width: float = 46.0

var visual: AnglerVisual
## Debug / tests.
var charges_blocked: int = 0
var pillar_stuns: int = 0
var wall_bumps: int = 0
var summoned: Array[Creature] = []
var sweeps_done: int = 0
var orbs_fired: int = 0
var orb_stuns: int = 0
var mines_launched: int = 0
var mine_hits: int = 0
var vent_charges: int = 0
## Seconds a player has been close to its body (the sweep trigger).
var close_time: float = 0.0
var _vent_time: Dictionary = {}
var _vent_rolled: Dictionary = {}
var _vent_prey: Player
var _shots_left: int = 0
var _shot_left: float = 0.0
var _volley_target: int = 0
var _mine_spots: Array[Vector2] = []
var bait_point: Vector2 = Vector2.ZERO
var _bait_left: float = 0.0
## The charge / bite direction.
var _aim: Vector2 = Vector2.LEFT
var _snaps_done: int = 0
var _snap_left: float = 0.0
var _snap_check_left: float = -1.0
var _fake_timer: float = 0.0
var _fake_age: float = -1.0
var _fake_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	super()
	add_to_group("decoy_listeners")
	visual = AnglerVisual.new()
	add_child(visual)
	visual.snap_heading(_aim)
	visual.hide_for_intro()
	var voice := AnglerVoice.new()
	voice.visual = visual
	add_child(voice)


func _physics_process(delta: float) -> void:
	super(delta)
	if visual == null:
		return
	_bait_left = maxf(_bait_left - delta, 0.0)
	visual.set_exposed(1.0 if is_exposed() and mode != Mode.DEAD else 0.0)
	visual.set_sweep_wind(clampf(1.0 - mode_left / maxf(current_attack.get_telegraph(challenge_mode), 0.01), 0.0, 1.0)
		if mode == Mode.TELEGRAPH and current_attack and current_attack.id == &"sweep" else 0.0)
	_update_fake_lure(delta)
	_update_close_time(delta)
	_update_vents(delta)


## A Lure Pulse ping (LurePulseSkill): within its hearing the decoy draws the
## next charge, at once if it is free.
func hear_decoy(origin: Vector2, radius: float) -> void:
	if not is_fighting() or mode == Mode.TRANSITION or mode == Mode.STUNNED:
		return
	if global_position.distance_to(origin) > radius:
		return
	bait_point = origin
	_bait_left = bait_memory
	var charge: BossAttack = get_attack(&"charge")
	if mode == Mode.IDLE and charge and charge.min_phase <= phase:
		start_attack(charge)


func is_baited() -> bool:
	return _bait_left > 0.0


func get_aim() -> Vector2:
	return _aim


func get_charge_speed() -> float:
	var speed: float = challenge_charge_speed if challenge_mode else calm_charge_speed
	return speed * (fast_charge_scale if phase >= 2 else 1.0)


## The jaws' centre (world).
func get_bite_point() -> Vector2:
	if visual == null or visual.body == null or visual.body.shape.is_empty():
		return global_position + _aim * head_reach
	return visual.body.get_head_center() + visual.heading * bite_forward


# --- Boss hooks ------------------------------------------------------------------

func _damage_multipliers(is_finisher: bool) -> Dictionary:
	var multipliers: Dictionary = super(is_finisher)
	if is_exposed() and mode == Mode.STUNNED:
		multipliers["stunned"] = stunned_damage_scale
	return multipliers


func _contact_distance(point: Vector2) -> float:
	return point.distance_to(_closest_on_body(point)) - body_half_width


func _push_direction(point: Vector2) -> Vector2:
	var away: Vector2 = point - _closest_on_body(point)
	return away.normalized() if away.length() > 0.01 else Vector2.DOWN


func _attack_distance(attack: BossAttack, player: Player) -> float:
	if player == null:
		return INF
	if attack.id == &"bite":
		return get_bite_point().distance_to(player.global_position)
	return global_position.distance_to(player.global_position)


## A player too close for too long -> the tail sweep; a decoy -> a charge at
## it; a noticed player at a vent -> a charge at them; else the usual choice.
func _pick_attack() -> BossAttack:
	var sweep: BossAttack = get_attack(&"sweep")
	if sweep and close_time >= get_sweep_trigger_time() and get_cooldown(&"sweep") <= 0.0:
		close_time = 0.0
		return sweep
	var charge: BossAttack = get_attack(&"charge")
	if _bait_left > 0.0 and charge and charge.min_phase <= phase:
		return charge
	if is_instance_valid(_vent_prey) and charge and get_cooldown(&"charge") <= 0.0 and _at_vent(_vent_prey):
		target_player = _vent_prey
		_vent_prey = null
		vent_charges += 1
		return charge
	return super()


func _attack_cooldown(attack: BossAttack) -> float:
	if attack.id == &"orbs" and phase >= 3:
		return attack.cooldown * orb_phase3_cooldown_scale
	return attack.cooldown


func get_sweep_trigger_time() -> float:
	return challenge_sweep_trigger_time if challenge_mode else calm_sweep_trigger_time


func _on_fight_start() -> void:
	visual.reveal()


func _on_idle_start() -> void:
	visual.set_state(AnglerVisual.State.SWIM)
	visual.face(Vector2.ZERO)


func _on_telegraph_start(attack: BossAttack) -> void:
	_aim = _aim_direction()
	if attack.id == &"sweep":
		# Coils with flared fins (AnglerVisual.set_sweep_wind), no lure flare.
		visual.set_state(AnglerVisual.State.SWIM)
		visual.face(Vector2.ZERO)
		_play("boss_angler_sweep_wind")
		return
	visual.set_state(AnglerVisual.State.TELEGRAPH)
	visual.face(_aim)
	if attack.id == &"orbs":
		_play("boss_angler_orb_charge")
	if attack.id == &"bite":
		_snaps_done = 0
		_snap_left = 0.0
		_snap_check_left = -1.0


func _on_telegraph(attack: BossAttack, delta: float) -> void:
	var desired: Vector2 = Vector2.ZERO
	if attack.id == &"sweep" or attack.id == &"orbs" or attack.id == &"mines":
		# It holds still (it gathers itself / its lure flares) and faces its prey.
		if attack.id != &"sweep":
			_aim = _aim_direction()
			visual.face(_aim)
	elif attack.id == &"charge":
		# It keeps turning on its target until the aim locks.
		if mode_left > charge_aim_lock:
			_aim = _aim_direction()
			visual.face(_aim)
		desired = -_aim * coil_speed
	else:
		_aim = _aim_direction()
		visual.face(_aim)
		desired = _aim * bite_approach_speed
	velocity = velocity.lerp(desired, 1.0 - exp(-steering * delta))


func _on_attack_start(attack: BossAttack) -> void:
	if attack.id == &"sweep":
		sweeps_done += 1
		visual.sweep(attack.active_time)
		_play("boss_angler_sweep")
		get_tree().call_group("shared_camera", "shake_with", sweep_shake_strength, sweep_shake_time)
		velocity = Vector2.ZERO
		return
	if attack.id == &"orbs" or attack.id == &"mines":
		visual.set_state(AnglerVisual.State.SWIM)
		_shots_left = (challenge_orb_count if challenge_mode else calm_orb_count) if attack.id == &"orbs" \
			else (challenge_mine_count if challenge_mode else calm_mine_count)
		_shot_left = 0.0
		_mine_spots.clear()
		velocity = Vector2.ZERO
		return
	if attack.id == &"charge":
		_bait_left = 0.0
		visual.face(Vector2.ZERO)
		visual.set_state(AnglerVisual.State.CHARGE)
		velocity = _aim * get_charge_speed()
	else:
		visual.set_state(AnglerVisual.State.SWIM)
		visual.face(_aim)


func _on_attack_active(attack: BossAttack, delta: float) -> void:
	match attack.id:
		&"charge":
			_update_charge(delta)
		&"bite":
			_update_bite(delta)
		&"sweep":
			_update_sweep(delta)
		&"orbs", &"mines":
			_update_volley(attack, delta)


func _on_recovery_start(_attack: BossAttack) -> void:
	visual.set_state(AnglerVisual.State.SWIM)
	visual.face(Vector2.ZERO)


func _on_attack_interrupted(_attack: BossAttack) -> void:
	visual.set_state(AnglerVisual.State.SWIM)


## The Shield stopped it: recoil and a longer opening.
func _on_blocked(direction: Vector2) -> void:
	if current_attack == null or (mode != Mode.ACTIVE and mode != Mode.TELEGRAPH):
		return
	if current_attack.id == &"charge" and mode == Mode.ACTIVE:
		charges_blocked += 1
	velocity = direction.normalized() * block_recoil_speed
	visual.hit(global_position - direction.normalized() * 60.0)
	end_active(block_recovery_scale)


func _on_stunned() -> void:
	visual.set_state(AnglerVisual.State.STUNNED)
	visual.face(Vector2.ZERO)


func _on_stun_end() -> void:
	visual.set_state(AnglerVisual.State.SWIM)


func _on_hit(attacker: Player, _dealt: float, _is_finisher: bool) -> void:
	visual.hit(attacker.global_position if attacker else global_position + Vector2.LEFT)


func _on_phase_start(new_phase: int) -> void:
	visual.set_state(AnglerVisual.State.SWIM)
	visual.roar()
	_fake_age = -1.0
	_fake_timer = 0.0
	visual.set_fake_lure(Vector2.ZERO, 0.0)
	if new_phase >= 3:
		_summon()
		get_tree().call_group("darkness", "set_extra_darkness", phase3_darkness)


func _on_death() -> void:
	visual.set_fake_lure(Vector2.ZERO, 0.0)
	visual.die()
	# Its orbs and mines go out with it.
	for node: Node in get_tree().get_nodes_in_group("angler_projectiles"):
		if node.has_method("fizzle"):
			node.call("fizzle")
		elif node.has_method("pop"):
			node.call("pop")


## A deflected orb came home: stunned (Exposed).
func on_orb_return(_orb: Node2D) -> void:
	if not is_fighting() or mode == Mode.TRANSITION:
		return
	orb_stuns += 1
	visual.hit(global_position + Vector2.UP * 40.0)
	stun(orb_stun_time)


## A mine blew up on it (it charged over it): damage and a short stun.
func on_mine_hit(_mine: Node2D) -> void:
	if not is_fighting():
		return
	mine_hits += 1
	apply_external_damage(boss_max_health * mine_damage_ratio, "mine")
	if is_fighting() and mode != Mode.TRANSITION:
		visual.hit(_mine.global_position if is_instance_valid(_mine) else global_position)
		stun(mine_stun_time)


func _after_move(_delta: float) -> void:
	# The body itself bumped into rock during a dash (the ray ahead missed it).
	if mode != Mode.ACTIVE or current_attack == null or current_attack.id != &"charge":
		return
	for i: int in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider is RockWall:
			_charge_hit_rock(collider as RockWall)
			return


## The CreatureEcho (sonar echo) draws its silhouette.
func draw_shape(canvas: CanvasItem, fill: Color, outline: Color, _with_eye: bool) -> void:
	if visual == null or visual.body == null:
		return
	var silhouette: PackedVector2Array = visual.body.get_silhouette()
	if silhouette.size() < 3:
		return
	var local := PackedVector2Array()
	for point: Vector2 in silhouette:
		local.append(point - global_position)
	if fill.a > 0.0:
		canvas.draw_colored_polygon(local, fill)
	if outline.a > 0.0:
		local.append(local[0])
		canvas.draw_polyline(local, outline, outline_width, true)


# --- Attacks ---------------------------------------------------------------------

func _update_charge(delta: float) -> void:
	var speed: float = get_charge_speed()
	velocity = _aim * speed
	# Rock ahead of the head: a pillar stuns it, a wall ends the dash.
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + _aim * (head_reach + speed * delta), wall_mask)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is RockWall:
		_charge_hit_rock(hit["collider"] as RockWall)
		return
	# Over a mine: it blows up on the Angler (AnglerMine -> on_mine_hit).
	for node: Node in get_tree().get_nodes_in_group("angler_mines"):
		var mine := node as AnglerMine
		if mine and mine.try_trigger_by_boss(_contact_distance(mine.global_position)):
			return
	for player: Player in Players.all(get_tree()):
		if mode != Mode.ACTIVE:
			return
		if _contact_distance(player.global_position) < soft_push_margin:
			strike(player)


func _charge_hit_rock(rock: RockWall) -> void:
	var pillar := rock as ArenaPillar
	velocity = -_aim * 60.0
	if pillar and not pillar.is_broken:
		pillar_stuns += 1
		pillar.take_blow()
		get_tree().call_group("shared_camera", "shake_with", pillar_shake_strength, pillar_shake_time)
		stun(pillar_stun_time)
	else:
		wall_bumps += 1
		get_tree().call_group("shared_camera", "shake_with", wall_shake_strength, wall_shake_time)
		end_active()


func _update_bite(delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))
	_snap_left -= delta
	if _snap_left <= 0.0 and _snaps_done < bite_snaps:
		# Each snap turns a little towards the target, then lunges.
		if target_player:
			_aim = _aim.slerp(global_position.direction_to(target_player.global_position), 0.5).normalized()
			visual.face(_aim)
		visual.bite()
		velocity = _aim * bite_lunge_speed
		_snaps_done += 1
		_snap_left = bite_snap_interval
		_snap_check_left = visual.bite_snap_at
	if _snap_check_left >= 0.0:
		_snap_check_left -= delta
		if _snap_check_left < 0.0:
			# The jaw shuts: whoever is inside it is bitten (once per attack).
			var jaws: Vector2 = get_bite_point()
			for player: Player in Players.all(get_tree()):
				if mode != Mode.ACTIVE:
					return
				if player.global_position.distance_to(jaws) <= bite_radius:
					strike(player)
	if _snaps_done >= bite_snaps and _snap_left <= 0.0 and _snap_check_left < 0.0:
		end_active()


## The tail sweep: whoever is within sweep_reach of its body while it spins is
## hit once (Boss.strike: one per attack and player, knockback, invulnerability).
func _update_sweep(delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))
	for player: Player in Players.all(get_tree()):
		if mode != Mode.ACTIVE:
			return
		if _contact_distance(player.global_position) <= sweep_reach:
			strike(player)


## Orbs / mines: one launch every orb_interval / mine_interval from the lure.
func _update_volley(attack: BossAttack, delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))
	_shot_left -= delta
	if _shots_left > 0 and _shot_left <= 0.0:
		_shots_left -= 1
		if attack.id == &"orbs":
			_shot_left = orb_interval
			_fire_orb()
		else:
			_shot_left = mine_interval
			_launch_mine()
	if _shots_left <= 0 and _shot_left <= 0.0:
		end_active()


func _fire_orb() -> void:
	if orb_scene == null:
		return
	var prey: Array[Player] = _standing_players()
	if prey.is_empty():
		return
	var chosen: Player = prey[_volley_target % prey.size()]
	_volley_target += 1
	var orb := orb_scene.instantiate() as AnglerOrb
	var from: Vector2 = visual.get_orb_position()
	var spread: float = randf_range(-0.6, 0.6)
	orb.setup(self, chosen, from.direction_to(chosen.global_position).rotated(spread),
		challenge_orb_speed if challenge_mode else calm_orb_speed,
		challenge_orb_turn_rate if challenge_mode else calm_orb_turn_rate, orb_lifetime,
		challenge_orb_damage if challenge_mode else calm_orb_damage, orb_knockback)
	orb.position = get_parent().to_local(from)
	get_parent().add_child(orb)
	orbs_fired += 1
	_play("boss_angler_orb_fire")


func _launch_mine() -> void:
	if mine_scene == null:
		return
	var spot: Vector2 = _pick_mine_spot()
	_mine_spots.append(spot)
	var fuse_range: Vector2 = challenge_mine_fuse if challenge_mode else calm_mine_fuse
	var mine := mine_scene.instantiate() as AnglerMine
	var from: Vector2 = visual.get_orb_position()
	mine.setup(self, get_parent().to_local(from), get_parent().to_local(spot), randf_range(fuse_range.x, fuse_range.y),
		mine_blast_radius, challenge_mine_damage if challenge_mode else calm_mine_damage, mine_knockback)
	get_parent().add_child(mine)
	mines_launched += 1
	_play("boss_angler_mine_launch")


## Open floor round it, away from the other mines of this volley and rock.
func _pick_mine_spot() -> Vector2:
	var map: RID = get_world_2d().navigation_map
	var best: Vector2 = global_position
	var best_gap: float = -INF
	for attempt: int in 12:
		var wanted: Vector2 = global_position + Vector2.from_angle(randf() * TAU) * randf_range(mine_distance.x, mine_distance.y)
		var spot: Vector2 = NavigationServer2D.map_get_closest_point(map, wanted)
		var gap: float = INF
		for other: Vector2 in _mine_spots:
			gap = minf(gap, other.distance_to(spot))
		for node: Node in get_tree().get_nodes_in_group("angler_mines"):
			gap = minf(gap, (node as Node2D).global_position.distance_to(spot))
		if gap >= mine_spacing:
			return spot
		if gap > best_gap:
			best_gap = gap
			best = spot
	return best


func _standing_players() -> Array[Player]:
	var result: Array[Player] = []
	for player: Player in Players.all(get_tree()):
		if not player.health.is_downed:
			result.append(player)
	return result


## How long a standing player has stayed close (the sweep trigger).
func _update_close_time(delta: float) -> void:
	if mode != Mode.IDLE and mode != Mode.RECOVERY:
		return
	var close: bool = false
	for player: Player in _standing_players():
		if _contact_distance(player.global_position) <= sweep_trigger_distance:
			close = true
	close_time = close_time + delta if close else maxf(close_time - delta * 2.0, 0.0)


## Players lingering at a vent may become its prey.
func _update_vents(delta: float) -> void:
	if not is_fighting():
		return
	var chance: float = challenge_vent_punish_chance if challenge_mode else calm_vent_punish_chance
	for player: Player in Players.all(get_tree()):
		if not _at_vent(player):
			_vent_time.erase(player)
			_vent_rolled.erase(player)
			continue
		_vent_time[player] = float(_vent_time.get(player, 0.0)) + delta
		if float(_vent_time[player]) >= vent_notice_time and not _vent_rolled.has(player):
			_vent_rolled[player] = true
			if randf() < chance:
				_vent_prey = player


func _at_vent(player: Player) -> bool:
	for node: Node in get_tree().get_nodes_in_group("bubble_vents"):
		var vent := node as BubbleVent
		if vent and vent.is_player_at(player):
			return true
	return false


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio:
		audio.play(sound_name, global_position)


func _aim_direction() -> Vector2:
	var point: Vector2 = bait_point if _bait_left > 0.0 else (target_player.global_position if target_player else global_position + _aim)
	var direction: Vector2 = point - global_position
	return direction.normalized() if direction.length() > 1.0 else _aim


## The nearest point on the line through its body (tail root -> head).
func _closest_on_body(point: Vector2) -> Vector2:
	if visual == null or visual.body == null or visual.body.shape.size() < 2:
		return global_position
	var head: Vector2 = visual.body.get_head_center()
	var tail: Vector2 = visual.body.point_at(0.8, 0.0)
	return Geometry2D.get_closest_point_to_segment(point, tail, head)


# --- Phases ----------------------------------------------------------------------

func _update_fake_lure(delta: float) -> void:
	if phase < 2 or mode == Mode.DEAD or mode == Mode.STUNNED or mode == Mode.TRANSITION:
		if _fake_age >= 0.0:
			_fake_age = -1.0
			visual.set_fake_lure(Vector2.ZERO, 0.0)
		return
	if _fake_age < 0.0:
		_fake_timer += delta
		if _fake_timer >= fake_lure_interval:
			_fake_timer = 0.0
			_fake_age = 0.0
			# Sideways or up from where it really is (never inside it).
			var angle: float = randf_range(-PI * 0.85, -PI * 0.15)
			_fake_offset = Vector2.from_angle(angle) * fake_lure_distance
		return
	_fake_age += delta
	var strength: float = clampf(minf(_fake_age, fake_lure_time - _fake_age) / maxf(fake_lure_fade, 0.01), 0.0, 1.0)
	visual.set_fake_lure(_fake_offset, strength)
	if _fake_age >= fake_lure_time:
		_fake_age = -1.0
		visual.set_fake_lure(Vector2.ZERO, 0.0)


func is_faking_lure() -> bool:
	return _fake_age >= 0.0


func _summon() -> void:
	var count: int = challenge_summon_count if challenge_mode else calm_summon_count
	if summon_scene == null or count <= 0:
		return
	var map: RID = get_world_2d().navigation_map
	var start_angle: float = randf() * TAU
	for i: int in count:
		var wanted: Vector2 = global_position + Vector2.from_angle(start_angle + TAU * float(i) / float(count)) * summon_distance
		var spot: Vector2 = NavigationServer2D.map_get_closest_point(map, wanted)
		var creature := summon_scene.instantiate() as Creature
		if creature == null:
			continue
		creature.position = get_parent().to_local(spot)
		get_parent().add_child(creature)
		creature.set_challenge_mode(challenge_mode)
		var prey: Player = _nearest_standing_player()
		if prey:
			creature.hunt(prey)
		summoned.append(creature)
