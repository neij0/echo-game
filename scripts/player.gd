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
## Input actions are "<prefix>move_left", ..., "<prefix>action", "<prefix>skill",
## "<prefix>aim_left" ... (the right stick of this player's own gamepad).
@export var input_prefix: String = "p1_"
## Which skills this character can own (SkillDefinition.owner): Echo or Guardian.
@export var skill_owner: SkillDefinition.Owner = SkillDefinition.Owner.ECHO
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

@export_group("Aim")
## Right stick push (0-1) needed to count as aiming.
@export_range(0.0, 1.0) var aim_deadzone: float = 0.35
## Stick push (0-1) on this player's gamepad that switches them to gamepad
## controls (keys of their own actions switch back).
@export_range(0.0, 1.0) var gamepad_switch_threshold: float = 0.5

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
## Share of max_speed / acceleration allowed right now (a raised Shield: < 1).
var speed_scale: float = 1.0
## True while an active skill uses the move keys to aim (keyboard Lure Pulse):
## the player stands still.
var move_locked: bool = false
## True when this player last used their own gamepad, false after their own
## keys. Decides how skills aim (right stick vs. hold + move keys).
var uses_gamepad: bool = false
## The gamepad bound to this player's actions (-1 = none / any).
var joypad_device: int = -1
var _knockback_left: float = 0.0

@onready var health: PlayerHealth = $Health
@onready var pressure: PlayerPressure = $Pressure
@onready var light: PlayerLight = $PlayerLight
@onready var skills: PlayerSkills = $Skills


func _ready() -> void:
	add_to_group("players")
	joypad_device = _find_joypad_device()


## Switches between keyboard and gamepad aiming on this player's own input only
## (the other player's keys or gamepad never change it).
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if joypad_device >= 0 and event.device != joypad_device:
			return
		if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < gamepad_switch_threshold:
			return
		if event is InputEventJoypadButton and not (event as InputEventJoypadButton).pressed:
			return
		uses_gamepad = true
	elif event is InputEventKey and (event as InputEventKey).pressed and _is_own_key(event):
		uses_gamepad = false

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	if not health.is_downed and not move_locked:
		input_dir = Input.get_vector(_action("move_left"), _action("move_right"), _action("move_up"), _action("move_down"))
	if input_dir != Vector2.ZERO:
		facing = input_dir.normalized()
	velocity += input_dir * acceleration * speed_scale * delta

	# Frame-rate independent drag: weaker drag when gliding.
	var current_drag: float = drag if input_dir != Vector2.ZERO else glide_drag
	velocity *= exp(-current_drag * delta)
	if _knockback_left > 0.0:
		_knockback_left -= delta
	else:
		velocity = velocity.limit_length(max_speed * speed_scale)
	_apply_leash()

	move_and_slide()


## The other living player (null when playing alone).
func get_partner() -> Player:
	for player: Player in Players.all(get_tree()):
		if player != self:
			return player
	return null


## How far this player's own light reaches (0 if it has none).
func get_light_radius() -> float:
	return light.radius if light else 0.0


## "echo" or "guardian": this player's entry in the SkillLoadout.
func get_character_key() -> String:
	return SkillDefinition.owner_key(skill_owner)


## True when this player's action button was just pressed and may be used by an
## ability (not downed, not busy reviving the partner, no active skill such as
## a raised shield holding it).
func try_action_pressed() -> bool:
	if health.is_downed or is_reviving():
		return false
	if skills and skills.active and skills.active.blocks_actions():
		return false
	return Input.is_action_just_pressed(_action("action"))


## The skill button (active skills), same rules as the action button.
func try_skill_pressed() -> bool:
	if health.is_downed or is_reviving():
		return false
	return Input.is_action_just_pressed(_action("skill"))


func is_skill_held() -> bool:
	return not health.is_downed and Input.is_action_pressed(_action("skill"))


## The current move input (zero while downed), also while move_locked (then
## it aims instead of moving).
func get_move_input() -> Vector2:
	if health.is_downed:
		return Vector2.ZERO
	return Input.get_vector(_action("move_left"), _action("move_right"), _action("move_up"), _action("move_down"))


## The right stick of this player's gamepad (normalized), zero inside aim_deadzone.
func get_stick_aim() -> Vector2:
	if health.is_downed:
		return Vector2.ZERO
	var aim: Vector2 = Input.get_vector(_action("aim_left"), _action("aim_right"), _action("aim_up"), _action("aim_down"))
	return aim.normalized() if aim.length() >= aim_deadzone else Vector2.ZERO


## Where skills aim: the right stick, else the move direction, else the facing.
func get_aim_direction() -> Vector2:
	var stick: Vector2 = get_stick_aim()
	if stick != Vector2.ZERO:
		return stick
	var move: Vector2 = get_move_input()
	return move.normalized() if move.length() > 0.1 else facing


## Where sword hits go: the right stick, else the facing (keyboard: always the facing).
func get_attack_direction() -> Vector2:
	var stick: Vector2 = get_stick_aim()
	return stick if stick != Vector2.ZERO else facing


func is_action_held() -> bool:
	return not health.is_downed and Input.is_action_pressed(_action("action"))


## True while a downed partner is close enough to revive: the action button
## is then used for reviving instead of the ability.
func is_reviving() -> bool:
	var helper := get_node_or_null("Revive") as ReviveHelper
	return helper != null and helper.has_target()


func knock_back(impulse: Vector2) -> void:
	burst(impulse, knockback_time)


## Sets the velocity and lets it go above max_speed for `duration` seconds
## (knockback, Dash). Drag still slows it down.
func burst(new_velocity: Vector2, duration: float) -> void:
	velocity = new_velocity
	_knockback_left = duration


func _action(action_name: String) -> String:
	return input_prefix + action_name


func _is_own_key(event: InputEvent) -> bool:
	for action_name: String in ["move_left", "move_right", "move_up", "move_down", "action", "skill"]:
		if InputMap.has_action(_action(action_name)) and event.is_action(_action(action_name)):
			return true
	return false


## The device of the first gamepad event bound to this player's move actions.
func _find_joypad_device() -> int:
	var move_action: String = _action("move_left")
	if not InputMap.has_action(move_action):
		return -1
	for event: InputEvent in InputMap.action_get_events(move_action):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			return event.device
	return -1


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
