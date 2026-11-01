class_name Boss
extends Creature
## The base of every boss: a fight made of readable attack patterns instead of
## a creature that hurts by touch. Reusable: a boss script extends this, lists
## its attacks (BossAttack resources) and fills in the hooks below.
## - DORMANT until a standing player is within wake_radius in line of sight
##   (the arena door is rock, so it wakes once they come in), then INTRO
##   (intro_time, cannot be hurt), then the fight: the name + health bar at the
##   top of the screen (BossHealthBar, AR / EN).
## - Every attack: TELEGRAPH (BossAttack timing per mode) -> ACTIVE -> RECOVERY
##   (it stands open: recovery_damage_scale), then a cooldown per attack.
## - NO contact damage: touching it only pushes the player softly aside
##   (soft_push_*). Damage comes from attacks only (strike), at most once per
##   attack and player, with a short knockback and the player's invulnerability,
##   so hits never chain.
## - Phases: at each phase_thresholds share of its health (66 %, 33 %) it
##   enters a TRANSITION (transition_time, cannot be hurt; one hit never skips a
##   phase), then fights in the next phase (_on_phase_start).
## - STUNNED (stun(seconds)): helpless; counts as Exposed when stun_exposed.
## - Calm vs Challenge: per-attack timing / damage, challenge_health_scale,
##   challenge_speed_scale.
## A pulse makes it Exposed (with the Echo's "exposed_time_add" bonus), but a
## finisher on an Exposed boss never kills it outright: _scale_damage decides.
## The boss stays in the "creatures" group (the sword, the sonar, the music:
## Creature.state is CHASE while it fights) but ignores pulses, noise, alerts
## and frenzy. Downed players are never targeted.

signal fight_started
signal phase_changed(new_phase: int)
signal attack_started(attack: BossAttack)
signal stunned
## Emitted on every change of its health (the health bar).
signal health_changed(ratio: float)

enum Mode { DORMANT, INTRO, IDLE, TELEGRAPH, ACTIVE, RECOVERY, TRANSITION, STUNNED, DEAD }

@export_group("Boss")
## UiText keys of its name and the line under it (title card, health bar).
@export var name_key: String = ""
@export var subtitle_key: String = ""
@export var attacks: Array[BossAttack] = []
## Health shares where a new phase starts (phase 2 at the first, 3 at the next).
@export var phase_thresholds: PackedFloat32Array = PackedFloat32Array([0.66, 0.33])
## Seconds of a phase change (it roars; cannot be hurt).
@export var transition_time: float = 1.6
## Challenge: more health and a little faster.
@export var challenge_health_scale: float = 1.25
@export var challenge_speed_scale: float = 1.1
## Damage share taken during an attack's recovery (the vulnerable window).
@export var recovery_damage_scale: float = 1.0
## A stun counts as Exposed (finisher damage, the Exposed look).
@export var stun_exposed: bool = true
## Draws the plain creature body (Creature.draw_shape) for a boss without
## a visual of its own (the placeholder bosses).
@export var draws_creature_body: bool = false

@export_group("Waking")
## Wakes when a standing player is this close and in line of sight.
@export var wake_radius: float = 700.0
## Seconds of the intro (it shows itself; no attacks, cannot be hurt).
@export var intro_time: float = 2.6
## Speed while it comes closer during the intro.
@export var intro_speed: float = 70.0

@export_group("Moving")
## Speed between attacks (Calm; Challenge x challenge_speed_scale).
@export var move_speed: float = 110.0
## It closes in until the target is this far, then circles slowly.
@export var keep_distance: float = 260.0
## Circling speed as a share of move_speed.
@export_range(0.0, 1.0) var circle_speed_ratio: float = 0.4
## Seconds between two attacks at least (after a recovery).
@export var attack_gap: float = 0.7

@export_group("Contact")
## A player this close to the body (Boss._contact_distance) is pushed aside
## at soft_push_speed. Never damage.
@export var soft_push_margin: float = 14.0
@export var soft_push_speed: float = 180.0

@export_group("Partner Mending")
## Mending is allowed while it is stunned or recovering, or while it is this
## far from both players; never during a telegraph or an attack.
@export var mend_safe_distance: float = 400.0

@export_group("Death")
## Seconds after death before it is removed (its death animation).
@export var remove_delay: float = 5.0

var mode: Mode = Mode.DORMANT
var phase: int = 1
var boss_health: float = 0.0
var boss_max_health: float = 0.0
var current_attack: BossAttack
## Seconds left in the current mode (telegraph, attack, recovery, stun...).
var mode_left: float = 0.0
var target_player: Player
## Debug / tests: hits it landed, soft pushes.
var strikes_landed: int = 0
var _cooldowns: Dictionary = {}
var _struck: Array[Player] = []
var _gap_left: float = 0.0
var _circle_side: float = 1.0
var _health_bar: BossHealthBar
var _title: BossTitle


func _ready() -> void:
	super()
	# Bosses run their own movement (no stuck safety net nudging them mid-attack).
	for child: Node in get_children():
		if child is CreatureStuckWatch:
			child.queue_free()
	_reset_health()
	_health_bar = BossHealthBar.new()
	add_child(_health_bar)
	_title = BossTitle.new()
	add_child(_title)


func _exit_tree() -> void:
	get_tree().call_group("darkness", "set_extra_darkness", 0.0)


# --- Creature overrides ---------------------------------------------------------

func set_challenge_mode(enabled: bool) -> void:
	super(enabled)
	if mode == Mode.DORMANT:
		_reset_health()


## Bosses wake by sight only.
func hear_pulse(_origin: Vector2, _player: Player) -> void:
	pass


func hear_noise(_origin: Vector2, _radius: float) -> void:
	pass


func hear_alert(_source: Creature) -> void:
	pass


func hunt(_player: Player) -> void:
	pass


func set_frenzy(_enabled: bool) -> void:
	pass


## No contact damage: touches only push (see _soft_push).
func _on_hitbox_body_entered(_body: Node2D) -> void:
	pass


## A pulse front: revealed, and Exposed with the Echo's skill bonus.
func on_sonar_hit(_origin: Vector2) -> void:
	_revealed_left = pulse_reveal_time
	if mode != Mode.DORMANT and mode != Mode.DEAD:
		expose(exposed_time + PlayerSkills.team_bonus(get_tree(), "exposed_time_add"))
	var mark_time: float = PlayerSkills.team_bonus(get_tree(), "mark_time_add")
	if mark_time > 0.0:
		_marked_total = mark_time
		_marked_left = mark_time
	_echo.flash(self, body_radius)


## A blocked attack (the Guardian's Shield): the boss script reacts.
func repel(direction: Vector2, _speed: float, _stagger_time: float) -> void:
	if _dying:
		return
	_on_blocked(direction)


## A sword hit. Returns true for a big hit (a finisher while Exposed: the
## sword plays its heavy effect), never an instant kill.
func take_damage(amount: int, attacker: Player, _stagger_time: float, _knockback: float, is_finisher: bool = false) -> bool:
	if not can_be_hurt():
		return false
	var was_exposed: bool = is_exposed()
	var dealt: float = _scale_damage(float(amount), is_finisher)
	if mode == Mode.RECOVERY:
		dealt *= recovery_damage_scale
	_flash_left = hit_flash_time
	_echo.flash(self, body_radius)
	_apply_damage(dealt)
	_on_hit(attacker, dealt, is_finisher)
	return is_finisher and was_exposed


## Not while asleep, showing itself, changing phase or dying.
func can_be_hurt() -> bool:
	return not _dying and mode != Mode.DORMANT and mode != Mode.INTRO and mode != Mode.TRANSITION and mode != Mode.DEAD


func _die() -> void:
	if _dying:
		return
	_dying = true
	mode = Mode.DEAD
	current_attack = null
	velocity = Vector2.ZERO
	killed.emit()
	_hitbox.set_deferred("monitoring", false)
	remove_from_group("creatures")
	remove_from_group("sonar_targets")
	for child: Node in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", true)
	_health_bar.hide_bar()
	get_tree().call_group("darkness", "set_extra_darkness", 0.0)
	_on_death()
	await get_tree().create_timer(remove_delay, false).timeout
	if is_instance_valid(self):
		queue_free()


## A boss with no look of its own (draws_creature_body) uses the creature's
## round body; others draw nothing here.
func _draw() -> void:
	if draws_creature_body:
		super()


# --- Public API (boss scripts, tests) ---------------------------------------------

func get_health_ratio() -> float:
	return boss_health / boss_max_health if boss_max_health > 0.0 else 0.0


func is_fighting() -> bool:
	return mode != Mode.DORMANT and mode != Mode.INTRO and mode != Mode.DEAD


## Wakes it now (tests, scripted events): the intro starts.
func wake() -> void:
	if mode != Mode.DORMANT:
		return
	mode = Mode.INTRO
	mode_left = intro_time
	target_player = _nearest_standing_player()
	state = State.CHASE
	_chased = target_player
	_on_intro_start()


## Skips the intro (tests).
func start_fight() -> void:
	if mode == Mode.DORMANT:
		wake()
	if mode != Mode.INTRO:
		return
	mode = Mode.IDLE
	_gap_left = attack_gap
	_health_bar.show_bar(name_key, get_health_ratio(), phase_thresholds)
	if name_key != "":
		_title.show_title(name_key, subtitle_key)
	_on_fight_start()
	fight_started.emit()


## Starts this attack now (the boss script's choice, a bait, tests).
func start_attack(attack: BossAttack) -> void:
	if attack == null or not is_fighting() or mode == Mode.TRANSITION or mode == Mode.STUNNED:
		return
	current_attack = attack
	mode = Mode.TELEGRAPH
	mode_left = attack.get_telegraph(challenge_mode)
	_struck.clear()
	_on_telegraph_start(attack)
	attack_started.emit(attack)


## Ends the current attack early (it hit a wall...) and starts its recovery.
func end_active(recovery_scale: float = 1.0) -> void:
	if mode != Mode.ACTIVE and mode != Mode.TELEGRAPH:
		return
	mode = Mode.RECOVERY
	mode_left = current_attack.get_recovery(challenge_mode) * recovery_scale if current_attack else 0.5
	_on_recovery_start(current_attack)


## Helpless for this many seconds (Exposed too when stun_exposed).
func stun(seconds: float) -> void:
	if not is_fighting() or mode == Mode.TRANSITION:
		return
	if current_attack:
		_cooldowns[current_attack.id] = current_attack.cooldown
	current_attack = null
	mode = Mode.STUNNED
	mode_left = seconds
	if stun_exposed:
		expose(seconds)
	_on_stunned()
	stunned.emit()


## Exposed for at least this many seconds.
func expose(seconds: float) -> void:
	if seconds > _exposed_left:
		_exposed_total = seconds
		_exposed_left = seconds
	_revealed_left = maxf(_revealed_left, seconds)


## The attack lands on this player (once per attack and player). Returns true
## if it hit (not blocked, not invulnerable, not downed already).
func strike(player: Player) -> bool:
	if player == null or current_attack == null or _struck.has(player) or player.health.is_downed:
		return false
	_struck.append(player)
	var before: float = player.health.value
	player.health.take_hit(global_position, self, current_attack.get_damage(challenge_mode), current_attack.knockback_speed)
	if player.health.value < before:
		strikes_landed += 1
		return true
	return false


## Can these two players mend each other right now (PartnerMending)?
func allows_mending(a: Player, b: Player) -> bool:
	match mode:
		Mode.TELEGRAPH, Mode.ACTIVE:
			return false
		Mode.STUNNED, Mode.RECOVERY, Mode.DORMANT, Mode.DEAD:
			return true
	for player: Player in [a, b]:
		if player and global_position.distance_to(player.global_position) <= mend_safe_distance:
			return false
	return true


func get_attack(id: StringName) -> BossAttack:
	for attack: BossAttack in attacks:
		if attack.id == id:
			return attack
	return null


func get_cooldown(id: StringName) -> float:
	return float(_cooldowns.get(id, 0.0))


func get_mode_name() -> String:
	return String(Mode.keys()[mode])


func get_state_name() -> String:
	var text: String = get_mode_name()
	if current_attack:
		text += " " + String(current_attack.id)
	return text


# --- Per frame ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_reveal(delta)
	if state != _last_state:
		var old_state: State = _last_state
		_last_state = state
		state_changes += 1
		state_changed.emit(old_state, state)
	for id: StringName in _cooldowns.keys():
		_cooldowns[id] = maxf(float(_cooldowns[id]) - delta, 0.0)
	_gap_left = maxf(_gap_left - delta, 0.0)
	mode_left -= delta
	match mode:
		Mode.DORMANT:
			velocity = Vector2.ZERO
			if _sees_a_player():
				wake()
		Mode.INTRO:
			_move_towards_target(intro_speed, delta)
			if mode_left <= 0.0:
				start_fight()
		Mode.IDLE:
			_update_idle(delta)
		Mode.TELEGRAPH:
			_on_telegraph(current_attack, delta)
			if mode == Mode.TELEGRAPH and mode_left <= 0.0:
				mode = Mode.ACTIVE
				mode_left = current_attack.active_time
				_on_attack_start(current_attack)
		Mode.ACTIVE:
			_on_attack_active(current_attack, delta)
			if mode == Mode.ACTIVE and mode_left <= 0.0:
				end_active()
		Mode.RECOVERY:
			_on_recovery(current_attack, delta)
			if mode_left <= 0.0:
				_finish_attack()
		Mode.TRANSITION:
			velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))
			if mode_left <= 0.0:
				_back_to_idle()
		Mode.STUNNED:
			velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * 2.0 * delta))
			if mode_left <= 0.0:
				_on_stun_end()
				_back_to_idle()
		Mode.DEAD:
			velocity = Vector2.ZERO
	_soft_push(delta)
	move_and_slide()
	_after_move(delta)


func _update_idle(delta: float) -> void:
	var nearest: Player = _nearest_standing_player()
	if nearest:
		target_player = nearest
		_chased = nearest
	if target_player == null or target_player.health.is_downed:
		velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))
		return
	if _gap_left <= 0.0:
		var attack: BossAttack = _pick_attack()
		if attack:
			start_attack(attack)
			return
	var distance: float = global_position.distance_to(target_player.global_position)
	if distance > keep_distance:
		_move_towards_target(get_move_speed(), delta)
	else:
		# Close enough: circle round the target slowly (it stays readable).
		var around: Vector2 = global_position.direction_to(target_player.global_position).orthogonal() * _circle_side
		velocity = velocity.lerp(around * get_move_speed() * circle_speed_ratio, 1.0 - exp(-steering * delta))
		if get_slide_collision_count() > 0:
			_circle_side = -_circle_side


func get_move_speed() -> float:
	return move_speed * (challenge_speed_scale if challenge_mode else 1.0)


func _move_towards_target(speed: float, delta: float) -> void:
	if target_player == null:
		return
	target = target_player.global_position
	var direction: Vector2 = global_position.direction_to(_next_path_point(delta))
	velocity = velocity.lerp(direction * speed, 1.0 - exp(-steering * delta))


func _finish_attack() -> void:
	if current_attack:
		_cooldowns[current_attack.id] = current_attack.cooldown
	_back_to_idle()


func _back_to_idle() -> void:
	current_attack = null
	mode = Mode.IDLE
	_gap_left = attack_gap
	_on_idle_start()


## A random attack (by weight) that fits: this phase, off cooldown, in range.
func _pick_attack() -> BossAttack:
	var fitting: Array[BossAttack] = []
	var total: float = 0.0
	for attack: BossAttack in attacks:
		if attack.min_phase > phase or get_cooldown(attack.id) > 0.0:
			continue
		var distance: float = _attack_distance(attack, target_player)
		if distance < attack.min_range or distance > attack.max_range:
			continue
		fitting.append(attack)
		total += attack.weight
	if fitting.is_empty():
		return null
	var roll: float = randf() * total
	for attack: BossAttack in fitting:
		roll -= attack.weight
		if roll <= 0.0:
			return attack
	return fitting[fitting.size() - 1]


func _apply_damage(dealt: float) -> void:
	var before: float = boss_health
	boss_health = maxf(boss_health - dealt, 0.0)
	# One hit never skips a phase: it stops at the next threshold.
	if phase - 1 < phase_thresholds.size():
		var floor_value: float = phase_thresholds[phase - 1] * boss_max_health
		if before > floor_value and boss_health <= floor_value:
			boss_health = floor_value
			_sync_health()
			_start_transition()
			return
	_sync_health()
	if boss_health <= 0.0:
		_die()


func _sync_health() -> void:
	health = ceili(boss_health)
	_health_bar.set_ratio(get_health_ratio())
	health_changed.emit(get_health_ratio())


func _start_transition() -> void:
	if current_attack and mode != Mode.RECOVERY:
		_on_attack_interrupted(current_attack)
	current_attack = null
	phase += 1
	mode = Mode.TRANSITION
	mode_left = transition_time
	_on_phase_start(phase)
	phase_changed.emit(phase)


func _reset_health() -> void:
	boss_max_health = float(max_health) * (challenge_health_scale if challenge_mode else 1.0)
	boss_health = boss_max_health
	health = ceili(boss_health)


## Pushes touching players softly aside (never damage).
func _soft_push(delta: float) -> void:
	if mode == Mode.DEAD or mode == Mode.DORMANT:
		return
	for player: Player in Players.all(get_tree()):
		if player.health.is_downed:
			continue
		var gap: float = _contact_distance(player.global_position)
		if gap >= soft_push_margin:
			continue
		var away: Vector2 = _push_direction(player.global_position)
		var depth: float = clampf((soft_push_margin - gap) / maxf(soft_push_margin, 1.0), 0.0, 2.0)
		player.move_and_collide(away * soft_push_speed * depth * delta)


func _nearest_standing_player() -> Player:
	var best: Player = null
	var best_distance: float = INF
	for player: Player in Players.all(get_tree()):
		if player.health.is_downed:
			continue
		var distance: float = global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## A standing player within wake_radius in line of sight. The arena's own
## pillars do not hide anyone (the closed door does).
func _sees_a_player() -> bool:
	var pillars: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		pillars.append((node as CollisionObject2D).get_rid())
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for player: Player in Players.all(get_tree()):
		if player.health.is_downed or global_position.distance_to(player.global_position) > wake_radius:
			continue
		var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position, wall_mask)
		query.exclude = pillars
		if space.intersect_ray(query).is_empty():
			return true
	return false


# --- Hooks for the boss script ------------------------------------------------

## Damage after armour / Exposed (amount = the sword's damage).
func _scale_damage(amount: float, _is_finisher: bool) -> float:
	return amount


## How far a player is from the body's edge (negative = inside it).
func _contact_distance(point: Vector2) -> float:
	return point.distance_to(global_position) - body_radius


## Which way a touching player is pushed.
func _push_direction(point: Vector2) -> Vector2:
	var away: Vector2 = point - global_position
	return away.normalized() if away.length() > 0.01 else Vector2.DOWN


## Distance used for an attack's range check.
func _attack_distance(_attack: BossAttack, player: Player) -> float:
	return global_position.distance_to(player.global_position) if player else INF


func _on_intro_start() -> void:
	pass


func _on_fight_start() -> void:
	pass


func _on_idle_start() -> void:
	pass


func _on_telegraph_start(_attack: BossAttack) -> void:
	pass


func _on_telegraph(_attack: BossAttack, delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))


func _on_attack_start(_attack: BossAttack) -> void:
	pass


func _on_attack_active(_attack: BossAttack, _delta: float) -> void:
	pass


func _on_recovery_start(_attack: BossAttack) -> void:
	pass


func _on_recovery(_attack: BossAttack, delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))


func _on_attack_interrupted(_attack: BossAttack) -> void:
	pass


func _on_blocked(_direction: Vector2) -> void:
	pass


func _on_stunned() -> void:
	pass


func _on_stun_end() -> void:
	pass


func _on_hit(_attacker: Player, _dealt: float, _is_finisher: bool) -> void:
	pass


func _on_phase_start(_new_phase: int) -> void:
	pass


func _on_death() -> void:
	pass


## After moving each frame (collisions of the move are readable here).
func _after_move(_delta: float) -> void:
	pass
