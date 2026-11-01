class_name BubbleVent
extends Node2D
## A crack in the arena floor that breathes out a column of bubbles: a player
## standing within radius gets oxygen back (refill_per_second of a full meter),
## so a boss fight is never lost to the meter. A soft glow and the rising
## bubbles make it findable in the dark; the bubbles swell while someone
## breathes there. Bosses may punish standing here (AnglerBoss: vent prey).
## Placed by the LevelBuilder on the boss arena's "Vent*" markers.

@export var radius: float = 70.0
## Share of a full meter per second while a player stands in it.
@export var refill_per_second: float = 0.22

@export_group("Look")
@export var crack_color: Color = Color(0.03, 0.05, 0.06)
@export var rim_color: Color = Color(0.18, 0.3, 0.32)
@export var glow_color: Color = Color(0.45, 0.95, 1.0)
@export var glow_energy: float = 1.3
@export var ring_alpha: float = 0.16
@export var light_radius: float = 120.0
@export var light_energy: float = 0.6
@export var bubble_color: Color = Color(0.7, 0.95, 1.0, 0.75)

@export_group("Sound")
@export var breathe_sound: String = "world_vent_breathe"
## Seconds between breathe sounds while someone refills.
@export var breathe_interval: float = 1.4

var _time: float = 0.0
var _busy: bool = false
var _breathe_left: float = 0.0
var _bubbles: CPUParticles2D
var _glow: Node2D
var _light: PointLight2D


func _ready() -> void:
	add_to_group("bubble_vents")
	z_index = -3
	_bubbles = CPUParticles2D.new()
	_bubbles.amount = 26
	_bubbles.lifetime = 2.2
	_bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = 14.0
	_bubbles.direction = Vector2.UP
	_bubbles.spread = 14.0
	_bubbles.gravity = Vector2(0.0, -30.0)
	_bubbles.initial_velocity_min = 20.0
	_bubbles.initial_velocity_max = 55.0
	_bubbles.scale_amount_min = 1.5
	_bubbles.scale_amount_max = 4.0
	_bubbles.color = bubble_color
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_bubbles.color_ramp = fade
	_bubbles.z_as_relative = false
	_bubbles.z_index = 1
	add_child(_bubbles)
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(128, 0.2)
	_light.texture_scale = LightTextures.scale_for_radius(_light.texture, light_radius)
	_light.color = glow_color
	_light.energy = light_energy
	add_child(_light)
	_light.add_to_group("falloff_lights")
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_glow = Node2D.new()
	_glow.draw.connect(_draw_glow)
	layer.add_child(_glow)


func _physics_process(delta: float) -> void:
	_time += delta
	_busy = false
	for player: Player in Players.all(get_tree()):
		if is_player_at(player):
			player.pressure.add_ratio(refill_per_second * delta)
			_busy = true
	_bubbles.speed_scale = 1.8 if _busy else 1.0
	_light.energy = light_energy * (1.6 if _busy else 1.0) * (0.85 + 0.15 * sin(_time * 2.1))
	_breathe_left -= delta
	if _busy and _breathe_left <= 0.0:
		_breathe_left = breathe_interval
		var audio: AudioDirector = AudioDirector.find(get_tree())
		if audio:
			audio.play(breathe_sound, global_position)
	_glow.global_position = global_position
	_glow.queue_redraw()


func is_player_at(player: Player) -> bool:
	return not player.health.is_downed and player.global_position.distance_to(global_position) <= radius


func _draw() -> void:
	# The crack in the floor (lit like the floor).
	var crack := PackedVector2Array()
	for i: int in 9:
		var angle: float = TAU * float(i) / 9.0
		crack.append(Vector2.from_angle(angle) * (16.0 + 6.0 * sin(float(i) * 2.7)) * Vector2(1.0, 0.6))
	draw_colored_polygon(crack, crack_color)
	crack.append(crack[0])
	draw_polyline(crack, rim_color, 2.0)


func _draw_glow() -> void:
	var pulse: float = 0.75 + 0.25 * sin(_time * 2.1)
	var color := Color(glow_color.r * glow_energy, glow_color.g * glow_energy, glow_color.b * glow_energy, 1.0)
	_glow.draw_circle(Vector2.ZERO, 7.0, Color(color, 0.5 * pulse))
	_glow.draw_circle(Vector2.ZERO, 3.0, Color(color, 0.9))
	# Where it reaches (brighter while someone breathes there).
	_glow.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, ring_alpha * (2.0 if _busy else 1.0) * pulse), 1.5)
