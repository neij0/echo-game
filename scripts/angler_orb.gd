class_name AnglerOrb
extends Node2D
## An electric orb fired from the Angler's lure (phase 2+): slow, it turns
## towards its target player at turn_rate and fades after lifetime. Glowing,
## crackling and lighting the floor under it, it reads in the dark.
## - Touching a standing player: one hit (PlayerHealth.take_hit: damage,
##   knockback, the normal invulnerability), then it bursts.
## - The Echo's pulse front pops it ("sonar_targets": on_sonar_hit).
## - The Guardian's sword ("deflectables": deflect) or his raised Shield (a
##   blocked hit) knocks it back: it flies home to the Angler fast and stuns it
##   when it arrives (AnglerBoss.on_orb_return). A deflected orb hurts nobody.
## - Rock pops it. Set up by the AnglerBoss (setup) before entering the tree.

enum Phase { HOMING, DEFLECTED, GONE }

@export var hit_radius: float = 20.0
@export var deflected_speed: float = 420.0
@export var deflected_turn_rate: float = 540.0
@export var fade_time: float = 0.35
@export_flags_2d_physics var wall_mask: int = 1

@export_group("Look")
@export var color: Color = Color(0.55, 0.95, 1.0)
@export var deflected_color: Color = Color(1.0, 0.85, 0.4)
@export var core_energy: float = 4.0
@export var core_radius: float = 6.0
@export var halo_radius: float = 22.0
@export var light_radius: float = 110.0
@export var light_energy: float = 0.9
@export var arc_count: int = 4
## Seconds between new crackle shapes.
@export var arc_interval: float = 0.06
@export var trail_points: int = 10

@export_group("Sound")
@export var crackle_sound: String = "boss_angler_orb_crackle"
@export var crackle_interval: float = 0.7
@export var pop_sound: String = "boss_angler_orb_pop"
@export var deflect_sound: String = "boss_angler_orb_deflect"

var phase: Phase = Phase.HOMING
var boss: AnglerBoss
var target: Player
var speed: float = 110.0
var turn_rate: float = 70.0
var lifetime: float = 8.0
var damage: float = 1.0
var knockback: float = 280.0
var velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _gone_age: float = 0.0
var _arc_left: float = 0.0
var _crackle_left: float = 0.0
var _arcs: Array[PackedVector2Array] = []
var _trail: PackedVector2Array = PackedVector2Array()
var _glow: Node2D
var _light: PointLight2D


func setup(from_boss: AnglerBoss, prey: Player, start_direction: Vector2, orb_speed: float, orb_turn_rate: float,
		orb_lifetime: float, orb_damage: float, orb_knockback: float) -> void:
	boss = from_boss
	target = prey
	speed = orb_speed
	turn_rate = orb_turn_rate
	lifetime = orb_lifetime
	damage = orb_damage
	knockback = orb_knockback
	velocity = start_direction.normalized() * speed


func _ready() -> void:
	add_to_group("sonar_targets")
	add_to_group("deflectables")
	add_to_group("angler_projectiles")
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(128, 0.2)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, light_radius)
	_light.color = color
	_light.energy = light_energy
	add_child(_light)
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_glow = Node2D.new()
	_glow.draw.connect(_draw_glow)
	layer.add_child(_glow)
	_crackle_left = randf() * crackle_interval


func _physics_process(delta: float) -> void:
	_age += delta
	match phase:
		Phase.HOMING:
			_home(target.global_position if is_instance_valid(target) and not target.health.is_downed else global_position + velocity, turn_rate, delta)
			global_position += velocity * delta
			_touch_players()
			if phase == Phase.HOMING and (_age >= lifetime or _in_rock()):
				pop()
		Phase.DEFLECTED:
			if not is_instance_valid(boss) or boss.is_dying():
				pop()
			else:
				_home(boss.global_position, deflected_turn_rate, delta)
				velocity = velocity.normalized() * deflected_speed
				global_position += velocity * delta
				if boss._contact_distance(global_position) <= hit_radius:
					boss.on_orb_return(self)
					_vanish()
		Phase.GONE:
			_gone_age += delta
			if _gone_age >= fade_time:
				queue_free()
	_update_look(delta)


## Turns the velocity towards point, at most rate degrees per second.
func _home(point: Vector2, rate: float, delta: float) -> void:
	var wanted: Vector2 = point - global_position
	if wanted.length() < 1.0:
		return
	var turn: float = clampf(velocity.angle_to(wanted), -deg_to_rad(rate) * delta, deg_to_rad(rate) * delta)
	velocity = velocity.rotated(turn)


func _touch_players() -> void:
	for player: Player in Players.all(get_tree()):
		if player.health.is_downed or player.global_position.distance_to(global_position) > hit_radius + 12.0:
			continue
		var before: float = player.health.value
		player.health.take_hit(global_position, self, damage, knockback)
		if player.health.last_hit_blocked:
			deflect(player)
			return
		if player.health.value < before or player.health.is_invulnerable():
			pop()
			return


## The Guardian's blade or Shield: back to the Angler. Returns true if it was
## deflected (only a homing orb can be).
func deflect(_attacker: Player = null) -> bool:
	if phase != Phase.HOMING:
		return false
	phase = Phase.DEFLECTED
	remove_from_group("deflectables")
	remove_from_group("sonar_targets")
	if is_instance_valid(boss):
		velocity = global_position.direction_to(boss.global_position) * deflected_speed
	_play(deflect_sound)
	return true


## The Echo's pulse front pops it.
func on_sonar_hit(_origin: Vector2) -> void:
	if phase == Phase.HOMING:
		pop()


## Bursts (fades out quickly).
func pop() -> void:
	if phase == Phase.GONE:
		return
	_play(pop_sound)
	_vanish()


func _vanish() -> void:
	phase = Phase.GONE
	_gone_age = 0.0
	remove_from_group("deflectables")
	remove_from_group("sonar_targets")
	remove_from_group("angler_projectiles")


func is_homing() -> bool:
	return phase == Phase.HOMING


func is_deflected() -> bool:
	return phase == Phase.DEFLECTED


func _in_rock() -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = wall_mask
	return not get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


func _update_look(delta: float) -> void:
	_trail.append(global_position)
	while _trail.size() > trail_points:
		_trail.remove_at(0)
	_arc_left -= delta
	if _arc_left <= 0.0:
		_arc_left = arc_interval
		_arcs.clear()
		for i: int in arc_count:
			var arc := PackedVector2Array([Vector2.ZERO])
			var direction: Vector2 = Vector2.from_angle(randf() * TAU)
			for k: int in range(1, 4):
				arc.append(direction * halo_radius * 0.45 * float(k) + direction.orthogonal() * randf_range(-5.0, 5.0))
			_arcs.append(arc)
	if phase == Phase.HOMING:
		_crackle_left -= delta
		if _crackle_left <= 0.0:
			_crackle_left = crackle_interval
			_play(crackle_sound)
	var fade: float = 1.0 - clampf(_gone_age / fade_time, 0.0, 1.0) if phase == Phase.GONE else 1.0
	_light.color = deflected_color if phase == Phase.DEFLECTED else color
	_light.energy = light_energy * fade * (0.8 + 0.2 * sin(_age * 31.0))
	_glow.global_position = global_position
	_glow.queue_redraw()


func _draw_glow() -> void:
	var base: Color = deflected_color if phase == Phase.DEFLECTED else color
	var fade: float = 1.0 - clampf(_gone_age / fade_time, 0.0, 1.0) if phase == Phase.GONE else 1.0
	var burst: float = 1.0 + 1.5 * (1.0 - fade) if phase == Phase.GONE else 1.0
	var hdr := Color(base.r * core_energy, base.g * core_energy, base.b * core_energy, fade)
	# The trail (fading behind it), the halo, the crackles, the core.
	for i: int in range(1, _trail.size()):
		var t: float = float(i) / float(_trail.size())
		_glow.draw_line(_trail[i - 1] - global_position, _trail[i] - global_position, Color(hdr, 0.35 * t * fade), core_radius * t)
	for k: int in 6:
		_glow.draw_circle(Vector2.ZERO, halo_radius * burst * (1.0 - float(k) / 6.0), Color(base, 0.05 * fade))
	for arc: PackedVector2Array in _arcs:
		_glow.draw_polyline(arc, Color(hdr, 0.8 * fade), 1.4)
	_glow.draw_circle(Vector2.ZERO, core_radius * burst, Color(hdr, fade))
	_glow.draw_circle(Vector2.ZERO, core_radius * 0.5, Color(3.0, 3.0, 3.0, fade))


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and sound_name != "":
		audio.play(sound_name, global_position)
