class_name PlaceholderBoss
extends Boss
## The stand-in boss of stages 2-3 until they get their own: the plain round
## creature body (draws_creature_body) on the boss framework, so it plays fair
## (no contact damage, telegraphs, recovery windows, one hit per attack,
## name + health bar). Attacks (BossAttack ids):
## - "lunge": its eyes flare and hiss and a faint line shows the path
##   (telegraph; the aim locks dash_aim_lock before the end), then a straight
##   dash; rock ends it, the Shield stops it (a longer recovery).
## - "slam": a ring shows its reach (telegraph), then every player inside
##   slam_radius is hit once.
## Every phase makes it a little faster (phase_speed_bonus).

@export_group("Lunge")
@export var dash_speed: float = 540.0
## The aim locks this many seconds before the telegraph ends (time to dodge).
@export var dash_aim_lock: float = 0.25
## Blocked by the Shield: recoil speed and how much longer it recovers.
@export var block_recoil_speed: float = 200.0
@export var block_recovery_scale: float = 1.3

@export_group("Slam")
@export var slam_radius: float = 150.0

@export_group("Warning")
## The telegraph marks (unlit, so they read in the dark).
@export var warning_color: Color = Color(1.0, 0.55, 0.3)
@export var warning_energy: float = 1.8
@export_range(0.0, 1.0) var warning_alpha: float = 0.55
@export var warning_width: float = 2.0
@export var warning_dash: float = 12.0
@export var strike_flash_time: float = 0.3

@export_group("Phases")
## Speed added per phase after the first (share of its speed).
@export var phase_speed_bonus: float = 0.15

## Debug / tests.
var charges_blocked: int = 0
var _aim: Vector2 = Vector2.RIGHT
var _warning: Node2D
var _flash_age: float = -1.0


func _ready() -> void:
	super()
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_warning = Node2D.new()
	_warning.draw.connect(_draw_warning)
	layer.add_child(_warning)


func _physics_process(delta: float) -> void:
	super(delta)
	if _flash_age >= 0.0:
		_flash_age += delta
		if _flash_age >= strike_flash_time:
			_flash_age = -1.0
	_warning.queue_redraw()


func get_aim() -> Vector2:
	return _aim


func get_move_speed() -> float:
	return super() * _phase_scale()


func get_dash_speed() -> float:
	return dash_speed * (challenge_speed_scale if challenge_mode else 1.0) * _phase_scale()


## The eyes (CreatureEyes) flare through the telegraph and the attack.
func get_lunge_flare() -> float:
	match mode:
		Mode.TELEGRAPH:
			var total: float = current_attack.get_telegraph(challenge_mode) if current_attack else 1.0
			return clampf(1.0 - mode_left / maxf(total, 0.01), 0.25, 1.0)
		Mode.ACTIVE:
			return 1.0
		Mode.RECOVERY:
			var total: float = current_attack.get_recovery(challenge_mode) if current_attack else 1.0
			return clampf(mode_left / maxf(total, 0.01), 0.0, 1.0) * 0.6
	return 0.0


# --- Boss hooks ------------------------------------------------------------------

func _on_telegraph_start(_attack: BossAttack) -> void:
	_aim = _aim_at_target()
	_facing = _aim
	# CreatureVoice hisses on it.
	lunge_started.emit()


func _on_telegraph(attack: BossAttack, delta: float) -> void:
	if attack.id == &"lunge" and mode_left > dash_aim_lock:
		_aim = _aim_at_target()
		_facing = _aim
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-steering * delta))


func _on_attack_start(attack: BossAttack) -> void:
	if attack.id == &"lunge":
		velocity = _aim * get_dash_speed()
		return
	# Slam: everyone inside the ring, once.
	_flash_age = 0.0
	for player: Player in Players.all(get_tree()):
		if player.global_position.distance_to(global_position) <= slam_radius:
			strike(player)


func _on_attack_active(attack: BossAttack, _delta: float) -> void:
	if attack.id != &"lunge":
		return
	velocity = _aim * get_dash_speed()
	for player: Player in Players.all(get_tree()):
		if mode != Mode.ACTIVE:
			return
		if _contact_distance(player.global_position) < soft_push_margin:
			strike(player)


func _after_move(_delta: float) -> void:
	if mode == Mode.ACTIVE and current_attack and current_attack.id == &"lunge" and get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		end_active()


func _on_blocked(direction: Vector2) -> void:
	if current_attack == null or mode != Mode.ACTIVE:
		return
	if current_attack.id == &"lunge":
		charges_blocked += 1
	velocity = direction.normalized() * block_recoil_speed
	end_active(block_recovery_scale)


func _aim_at_target() -> Vector2:
	if target_player == null:
		return _aim
	var direction: Vector2 = target_player.global_position - global_position
	return direction.normalized() if direction.length() > 1.0 else _aim


func _phase_scale() -> float:
	return 1.0 + phase_speed_bonus * float(phase - 1)


# --- Telegraph marks -----------------------------------------------------------------

func _draw_warning() -> void:
	var color: Color = Color(warning_color.r * warning_energy, warning_color.g * warning_energy, warning_color.b * warning_energy, 1.0)
	if mode == Mode.TELEGRAPH and current_attack:
		var t: float = clampf(1.0 - mode_left / maxf(current_attack.get_telegraph(challenge_mode), 0.01), 0.0, 1.0)
		if current_attack.id == &"lunge":
			var reach: float = get_dash_speed() * current_attack.active_time
			_warning.draw_dashed_line(global_position + _aim * body_radius, global_position + _aim * (body_radius + reach),
				Color(color, warning_alpha * t), warning_width, warning_dash)
		else:
			_warning.draw_arc(global_position, slam_radius, 0.0, TAU, 64, Color(color, warning_alpha * t), warning_width)
			_warning.draw_arc(global_position, slam_radius * t, 0.0, TAU, 48, Color(color, warning_alpha * 0.5), warning_width * 0.7)
	if _flash_age >= 0.0:
		var fade: float = 1.0 - _flash_age / strike_flash_time
		_warning.draw_arc(global_position, slam_radius, 0.0, TAU, 64, Color(color, fade), warning_width * 2.5)
