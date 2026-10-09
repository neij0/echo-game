class_name Creature
extends CharacterBody2D
## A deep-sea creature: wanders slowly, investigates the last pulse it heard.
## Its speed scales with Depth Awareness. Touching the player restarts the scene.

enum State { WANDER, INVESTIGATE }

@export var awareness: DepthAwareness
@export var player: Player

@export_group("Movement")
@export var min_speed: float = 45.0
@export var max_speed: float = 190.0
@export var steering: float = 4.0
@export var wander_radius: float = 300.0
@export var wander_pause: float = 1.5
@export var arrive_distance: float = 24.0

@export_group("Senses")
## Pulses further away than this are not heard.
@export var hearing_range: float = 1800.0
## How strongly lit coral zones push the creature away.
@export var safe_zone_push: float = 400.0

@export_group("Visual")
@export var body_radius: float = 20.0
@export var body_color: Color = Color(0.85, 0.25, 0.3)

var state: State = State.WANDER
var target: Vector2
var _home: Vector2
var _pause_left: float = 0.0

@onready var _hitbox: Area2D = $Hitbox


func _ready() -> void:
	_home = global_position
	target = global_position
	_hitbox.body_entered.connect(_on_hitbox_body_entered)


func hear_pulse(origin: Vector2) -> void:
	if global_position.distance_to(origin) > hearing_range:
		return
	state = State.INVESTIGATE
	target = origin
	_pause_left = 0.0


func get_state_name() -> String:
	return State.keys()[state]


func get_current_speed() -> float:
	var ratio: float = awareness.get_ratio() if awareness else 0.0
	return lerpf(min_speed, max_speed, ratio)


func _physics_process(delta: float) -> void:
	var desired: Vector2 = Vector2.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
	elif global_position.distance_to(target) <= arrive_distance:
		_on_target_reached()
	else:
		desired = global_position.direction_to(target) * get_current_speed()

	desired += _safe_zone_push()
	velocity = velocity.lerp(desired, 1.0 - exp(-steering * delta))
	move_and_slide()

	# If a wall blocks the way while wandering, pick another spot.
	if state == State.WANDER and get_slide_collision_count() > 0:
		_pick_wander_target()


func _on_target_reached() -> void:
	if state == State.INVESTIGATE:
		# Keep wandering around where the pulse was heard.
		_home = target
		state = State.WANDER
	_pause_left = wander_pause
	_pick_wander_target()


func _pick_wander_target() -> void:
	var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * wander_radius
	target = _home + offset


func _safe_zone_push() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral and coral.is_in_safe_zone(global_position):
			push += coral.global_position.direction_to(global_position) * safe_zone_push
	return push


func _is_player_safe() -> bool:
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral and coral.is_in_safe_zone(player.global_position):
			return true
	return false


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == player and not _is_player_safe():
		get_tree().reload_current_scene.call_deferred()


func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_circle(Vector2(body_radius * 0.45, 0.0), body_radius * 0.25, Color(1.0, 0.85, 0.3))
