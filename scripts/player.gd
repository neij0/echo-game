class_name Player
extends CharacterBody2D
## One of the two playable creatures (Echo or Guardian): movement (acceleration,
## drag, glide), per-player input, the soft leash to the partner and the
## downed state. Abilities (pulse, sword) are child nodes that read input
## through try_action_pressed(). Joins the "players" group so creatures, the HUD
## and the stage logic never need a fixed player reference.

## Emitted by the PulseAbility (Echo only). Lives here so every system can
## listen to any player the same way.
signal pulse_emitted(origin: Vector2)

## 1 = Echo (P1), 2 = Guardian (P2). Used for spawn points and HUD order.
@export var player_number: int = 1
@export var display_name: String = "Echo"
## Input actions are "<prefix>move_left", ..., "<prefix>action".
@export var input_prefix: String = "p1_"
## Creatures within this distance of this player count as revealed (lit).
## 0 = this player's light does not reveal anything (Guardian).
@export var light_reveal_radius: float = 115.0

@export_group("Movement")
@export var acceleration: float = 900.0
@export var max_speed: float = 260.0
## Drag while the player is pressing a direction.
@export var drag: float = 2.5
## Lower drag when input stops, so the player glides a little.
@export var glide_drag: float = 1.2

@export_group("Knockback")
## Seconds after a knockback during which max_speed is not applied, so the
## push can be faster than normal movement. Drag still slows it down.
@export var knockback_time: float = 0.25

@export_group("Leash")
## The two players cannot get further apart than this (matches the camera's
## maximum zoom-out, so both always stay on screen).
@export var leash_distance: float = 800.0
## Over the last leash_soft_zone pixels, moving away gets harder and harder.
@export var leash_soft_zone: float = 160.0
## Pull back towards the partner per pixel beyond leash_distance.
@export var leash_pull: float = 6.0

var facing: Vector2 = Vector2.DOWN
var _knockback_left: float = 0.0

@onready var health: PlayerHealth = $Health
@onready var pressure: PlayerPressure = $Pressure
@onready var light: PlayerLight = $PlayerLight


func _ready() -> void:
	add_to_group("players")


func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	if not health.is_downed:
		input_dir = Input.get_vector(_action("move_left"), _action("move_right"), _action("move_up"), _action("move_down"))
	if input_dir != Vector2.ZERO:
		facing = input_dir.normalized()
	velocity += input_dir * acceleration * delta

	# Frame-rate independent drag: weaker drag when gliding.
	var current_drag: float = drag if input_dir != Vector2.ZERO else glide_drag
	velocity *= exp(-current_drag * delta)
	if _knockback_left > 0.0:
		_knockback_left -= delta
	else:
		velocity = velocity.limit_length(max_speed)
	_apply_leash()

	move_and_slide()


## The other living player (null when playing alone).
func get_partner() -> Player:
	for player: Player in Players.all(get_tree()):
		if player != self:
			return player
	return null


## True when this player's action button was just pressed and may be used by an
## ability (not downed, and not busy reviving the partner).
## How far this player's own light reaches (0 if it has none).
func get_light_radius() -> float:
	return light.radius if light else 0.0


func try_action_pressed() -> bool:
	if health.is_downed or is_reviving():
		return false
	return Input.is_action_just_pressed(_action("action"))


func is_action_held() -> bool:
	return not health.is_downed and Input.is_action_pressed(_action("action"))


## True while a downed partner is close enough to revive: the action button
## is then used for reviving instead of the ability.
func is_reviving() -> bool:
	var helper := get_node_or_null("Revive") as ReviveHelper
	return helper != null and helper.has_target()


func knock_back(impulse: Vector2) -> void:
	velocity = impulse
	_knockback_left = knockback_time


func _action(action_name: String) -> String:
	return input_prefix + action_name


func _apply_leash() -> void:
	var partner: Player = get_partner()
	if partner == null:
		return
	var offset: Vector2 = global_position - partner.global_position
	var distance: float = offset.length()
	var soft_start: float = leash_distance - leash_soft_zone
	if distance <= soft_start or distance == 0.0:
		return
	var away: Vector2 = offset / distance
	var outward: float = velocity.dot(away)
	if outward > 0.0:
		# The closer to the limit, the more of the outward speed is removed.
		var t: float = clampf((distance - soft_start) / leash_soft_zone, 0.0, 1.0)
		velocity -= away * outward * t
	if distance > leash_distance:
		velocity -= away * (distance - leash_distance) * leash_pull
