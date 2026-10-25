class_name PressureStation
extends Node2D
## A refill station for the world's pressure meter (an old oxygen tank in the
## Ocean). A player touching it gets a full meter, then it is used up. A slow
## blinking beacon makes it findable in the dark.

signal used(player: Player)

@export var touch_radius: float = 34.0
@export_flags_2d_physics var player_mask: int = 2
@export var refill_stream: AudioStream
@export var refill_volume_db: float = -4.0

@export_group("Beacon")
@export var beacon_color: Color = Color(1.0, 0.85, 0.35)
@export var beacon_energy: float = 0.9
@export var beacon_radius: float = 110.0
## Blinks per second.
@export var beacon_speed: float = 0.6
## 0-1: brightness at the dark point of the blink.
@export_range(0.0, 1.0) var beacon_min: float = 0.25

@export_group("Look")
@export var tank_size: Vector2 = Vector2(26.0, 40.0)
@export var full_color: Color = Color(0.85, 0.75, 0.35)
@export var empty_color: Color = Color(0.3, 0.3, 0.3)
## HDR multiplier of the small indicator lamp on top (above 1.0 = blooms).
@export var lamp_energy: float = 2.0
@export var lamp_radius: float = 4.0

var is_used: bool = false
var _time: float = 0.0
var _beacon: PointLight2D
var _audio: AudioStreamPlayer2D


func _ready() -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = player_mask
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = touch_radius
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)

	_beacon = PointLight2D.new()
	_beacon.texture = LightTextures.radial(128, 0.0)
	_beacon.texture_scale = LightTextures.scale_for_radius(_beacon.texture, beacon_radius)
	_beacon.color = beacon_color
	_beacon.energy = beacon_energy
	add_child(_beacon)

	_audio = AudioStreamPlayer2D.new()
	_audio.stream = refill_stream
	_audio.bus = &"SFX"
	_audio.volume_db = refill_volume_db
	add_child(_audio)


func _process(delta: float) -> void:
	if is_used:
		return
	_time += delta
	var blink: float = 0.5 + 0.5 * sin(_time * TAU * beacon_speed)
	_beacon.energy = beacon_energy * lerpf(beacon_min, 1.0, blink)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if is_used or player == null or player.health.is_downed:
		return
	is_used = true
	player.pressure.refill()
	_beacon.enabled = false
	if refill_stream:
		_audio.play()
	queue_redraw()
	used.emit(player)


func _draw() -> void:
	var rect := Rect2(-tank_size * 0.5, tank_size)
	draw_rect(rect, empty_color if is_used else full_color)
	if not is_used:
		var lamp := Color(beacon_color.r * lamp_energy, beacon_color.g * lamp_energy, beacon_color.b * lamp_energy)
		draw_circle(Vector2(0.0, -tank_size.y * 0.5 - lamp_radius), lamp_radius, lamp)
