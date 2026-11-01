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
## - Phase 2: faster charges; now and then the lure goes dark and glows at a
##   fake spot (its light moves there too).
## - Phase 3: calls small creatures (summon_scene, per mode) and the arena
##   gets darker (Darkness.set_extra_darkness).
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

@export_group("Body")
## Half thickness of its body (contact push, charge hits).
@export var body_half_width: float = 46.0

var visual: AnglerVisual
## Debug / tests.
var charges_blocked: int = 0
var pillar_stuns: int = 0
var wall_bumps: int = 0
var summoned: Array[Creature] = []
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
	_update_fake_lure(delta)


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


## A decoy beats the usual choice: the next attack is a charge at it.
func _pick_attack() -> BossAttack:
	var charge: BossAttack = get_attack(&"charge")
	if _bait_left > 0.0 and charge and charge.min_phase <= phase:
		return charge
	return super()


func _on_fight_start() -> void:
	visual.reveal()


func _on_idle_start() -> void:
	visual.set_state(AnglerVisual.State.SWIM)
	visual.face(Vector2.ZERO)


func _on_telegraph_start(attack: BossAttack) -> void:
	_aim = _aim_direction()
	visual.set_state(AnglerVisual.State.TELEGRAPH)
	visual.face(_aim)
	if attack.id == &"bite":
		_snaps_done = 0
		_snap_left = 0.0
		_snap_check_left = -1.0


func _on_telegraph(attack: BossAttack, delta: float) -> void:
	var desired: Vector2 = Vector2.ZERO
	if attack.id == &"charge":
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
	if attack.id == &"charge":
		_bait_left = 0.0
		visual.face(Vector2.ZERO)
		visual.set_state(AnglerVisual.State.CHARGE)
		velocity = _aim * get_charge_speed()
	else:
		visual.set_state(AnglerVisual.State.SWIM)
		visual.face(_aim)


func _on_attack_active(attack: BossAttack, delta: float) -> void:
	if attack.id == &"charge":
		_update_charge(delta)
	else:
		_update_bite(delta)


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
