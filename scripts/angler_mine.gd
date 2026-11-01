class_name AnglerMine
extends Node2D
## A lure mine (the Angler, phase 3): lobbed from its lure to a spot in the
## arena (flight_time), then it lies there, dim in the dark, and counts down
## its fuse with a slow blink that speeds up. The Echo's pulse front reveals it
## clearly for reveal_time ("sonar_targets": on_sonar_hit). warning_time before
## it blows, the ring of its blast_radius shows. It explodes:
## - when its fuse runs out, or a standing player touches it: every player
##   inside blast_radius takes one hit (damage, knockback, invulnerability);
## - when the charging Angler runs over it (AnglerBoss checks
##   try_trigger_by_boss): on the Angler (AnglerBoss.on_mine_hit: damage +
##   a short stun), players near it are hit too.
## Set up by the AnglerBoss (setup) before entering the tree.

enum Phase { FLYING, ARMED, GONE }

@export var touch_radius: float = 26.0
@export var flight_time: float = 0.7
@export var flight_height: float = 90.0
@export var reveal_time: float = 3.0
@export var warning_time: float = 1.2

@export_group("Look")
@export var color: Color = Color(0.45, 1.0, 0.85)
@export var warning_color: Color = Color(1.0, 0.45, 0.3)
@export var dim_energy: float = 0.7
@export_range(0.0, 1.0) var dim_alpha: float = 0.3
@export var revealed_energy: float = 2.6
@export var core_radius: float = 6.0
@export var spike_count: int = 7
@export var light_radius: float = 70.0
@export var light_energy: float = 0.35
## Blinks per second at the start and at the end of the fuse.
@export var blink_start: float = 0.8
@export var blink_end: float = 5.0
@export var blast_time: float = 0.45
@export var shake_strength: float = 5.0
@export var shake_time: float = 0.25

@export_group("Sound")
@export var tick_sound: String = "boss_angler_mine_tick"
## Ticks only play this many seconds before the blast.
@export var tick_window: float = 2.5
@export var blast_sound: String = "boss_angler_mine_blast"

var phase: Phase = Phase.FLYING
var boss: AnglerBoss
var fuse: float = 7.0
var blast_radius: float = 110.0
var damage: float = 1.0
var knockback: float = 420.0
var exploded_on_boss: bool = false
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _fuse_left: float = 0.0
var _revealed_left: float = 0.0
var _blink_phase: float = 0.0
var _last_blink: int = 0
var _gone_age: float = 0.0
var _glow: Node2D
var _light: PointLight2D


func setup(from_boss: AnglerBoss, from: Vector2, to: Vector2, mine_fuse: float, mine_radius: float, mine_damage: float, mine_knockback: float) -> void:
	boss = from_boss
	_from = from
	_to = to
	fuse = mine_fuse
	blast_radius = mine_radius
	damage = mine_damage
	knockback = mine_knockback
	position = from


func _ready() -> void:
	add_to_group("angler_projectiles")
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(128, 0.25)
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


func _physics_process(delta: float) -> void:
	_age += delta
	match phase:
		Phase.FLYING:
			var t: float = clampf(_age / flight_time, 0.0, 1.0)
			global_position = _from.lerp(_to, t)
			if t >= 1.0:
				phase = Phase.ARMED
				_fuse_left = fuse
				add_to_group("sonar_targets")
				add_to_group("angler_mines")
		Phase.ARMED:
			_fuse_left -= delta
			_revealed_left = maxf(_revealed_left - delta, 0.0)
			var ratio: float = 1.0 - _fuse_left / maxf(fuse, 0.01)
			_blink_phase += lerpf(blink_start, blink_end, ratio * ratio) * delta
			if int(_blink_phase) != _last_blink:
				_last_blink = int(_blink_phase)
				if _fuse_left <= tick_window:
					_play(tick_sound)
			if _fuse_left <= 0.0:
				explode()
			else:
				for player: Player in Players.all(get_tree()):
					if not player.health.is_downed and player.global_position.distance_to(global_position) <= touch_radius:
						explode()
						break
		Phase.GONE:
			_gone_age += delta
			if _gone_age >= blast_time:
				queue_free()
	_update_look()


## The charging Angler: explodes on it if its body is over the mine.
func try_trigger_by_boss(contact_distance: float) -> bool:
	if phase != Phase.ARMED or contact_distance > touch_radius:
		return false
	exploded_on_boss = true
	explode()
	return true


func explode() -> void:
	if phase == Phase.GONE:
		return
	phase = Phase.GONE
	_gone_age = 0.0
	remove_from_group("sonar_targets")
	remove_from_group("angler_mines")
	remove_from_group("angler_projectiles")
	for player: Player in Players.all(get_tree()):
		if not player.health.is_downed and player.global_position.distance_to(global_position) <= blast_radius:
			player.health.take_hit(global_position, self, damage, knockback)
	if exploded_on_boss and is_instance_valid(boss):
		boss.on_mine_hit(self)
	_play(blast_sound)
	get_tree().call_group("shared_camera", "shake_with", shake_strength, shake_time)


## Gone without a blast (the Angler died).
func fizzle() -> void:
	if phase == Phase.GONE:
		return
	phase = Phase.GONE
	_gone_age = blast_time * 0.5
	remove_from_group("sonar_targets")
	remove_from_group("angler_mines")
	remove_from_group("angler_projectiles")


func on_sonar_hit(_origin: Vector2) -> void:
	_revealed_left = reveal_time


func is_armed() -> bool:
	return phase == Phase.ARMED


func is_revealed() -> bool:
	return _revealed_left > 0.0


func get_fuse_left() -> float:
	return _fuse_left if phase == Phase.ARMED else (fuse if phase == Phase.FLYING else 0.0)


func _blink() -> float:
	return 0.5 + 0.5 * cos(_blink_phase * TAU)


func _update_look() -> void:
	var lit: float = 0.0
	match phase:
		Phase.FLYING:
			lit = 0.6
		Phase.ARMED:
			lit = lerpf(0.35, 1.0, _blink()) * (1.6 if is_revealed() else 1.0)
		Phase.GONE:
			lit = 4.0 * (1.0 - _gone_age / blast_time)
	_light.energy = light_energy * lit
	_light.color = warning_color if phase == Phase.ARMED and _fuse_left <= warning_time else color
	_glow.global_position = global_position
	_glow.queue_redraw()


func _draw_glow() -> void:
	var at := Vector2.ZERO
	if phase == Phase.FLYING:
		# Lobbed in an arc (drawn higher in the middle of the flight).
		at.y = -sin(clampf(_age / flight_time, 0.0, 1.0) * PI) * flight_height
	if phase == Phase.GONE:
		var t: float = _gone_age / blast_time
		var blast := Color(warning_color.r * 3.0, warning_color.g * 3.0, warning_color.b * 3.0, 1.0 - t)
		_glow.draw_circle(at, blast_radius * (0.4 + 0.6 * t), Color(blast, 0.18 * (1.0 - t)))
		_glow.draw_arc(at, blast_radius * (0.4 + 0.6 * t), 0.0, TAU, 48, Color(blast, 1.0 - t), 4.0 * (1.0 - t) + 1.0)
		return
	var revealed: bool = is_revealed()
	var warning: bool = phase == Phase.ARMED and _fuse_left <= warning_time
	var base: Color = warning_color if warning else color
	var energy: float = revealed_energy if revealed or warning else dim_energy
	var alpha: float = 1.0 if revealed or warning else dim_alpha
	var blink: float = _blink() if phase == Phase.ARMED else 0.6
	var hdr := Color(base.r * energy, base.g * energy, base.b * energy, alpha)
	# A spiky little lure-bulb.
	for i: int in spike_count:
		var direction: Vector2 = Vector2.from_angle(TAU * float(i) / float(spike_count) + _age * 0.6)
		_glow.draw_line(at + direction * core_radius, at + direction * core_radius * 2.0, Color(hdr, alpha * 0.7), 1.2)
	_glow.draw_circle(at, core_radius * (1.0 + 0.4 * blink), Color(hdr, alpha * lerpf(0.45, 1.0, blink)))
	if revealed:
		# The pulse shows its reach faintly...
		_glow.draw_arc(at, blast_radius, 0.0, TAU, 48, Color(hdr, 0.18), 1.2)
	if warning:
		# ...and just before the blast it shows clearly, closing in.
		var t: float = 1.0 - _fuse_left / maxf(warning_time, 0.01)
		_glow.draw_arc(at, blast_radius, 0.0, TAU, 48, Color(hdr, 0.35 + 0.5 * t), 2.0)
		_glow.draw_arc(at, blast_radius * (1.0 - t), 0.0, TAU, 32, Color(hdr, 0.4), 1.5)


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and sound_name != "":
		audio.play(sound_name, global_position)
