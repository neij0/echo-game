class_name ProtoPlayer
extends CharacterBody3D
## One of the two players of the 3D prototype. The movement is the 2D Player's
## (acceleration, drag, glide, soft leash to the partner), on the floor plane
## and relative to the camera. Values are the 2D ones at 50 px = 1 unit.
## The camera decides what a direction means: the stick maps to the exact
## screen direction, the keys to plain directions, and the speed limit grows
## in directions the camera squashes (ProtoCamera.speed_scale).

## Input actions are "<prefix>move_left" ... "<prefix>action" (the project's
## own InputMap: keyboard + this player's gamepad).
@export var input_prefix: String = "p1_"
@export var is_echo: bool = true
@export var body_radius: float = 0.3
## Left stick push (0-1) above which the stick, not the keys, steers.
@export_range(0.0, 1.0) var stick_deadzone: float = 0.2

@export_group("Movement")
@export var acceleration: float = 18.0
@export var max_speed: float = 5.2
## Drag while the player is pressing a direction.
@export var drag: float = 2.5
## Lower drag when input stops, so the player glides a little.
@export var glide_drag: float = 1.2

@export_group("Knockback")
## Seconds after a knockback during which max_speed is not applied.
@export var knockback_time: float = 0.25

@export_group("Leash")
@export var leash_distance: float = 16.0
## Over the last leash_soft_zone units, moving away gets harder and harder.
@export var leash_soft_zone: float = 3.2
## Pull back towards the partner per unit beyond leash_distance.
@export var leash_pull: float = 6.0

## Unit vector on the floor plane.
var facing: Vector3 = Vector3.BACK
## Maps input to the floor; without one, up = -z and no compensation.
var camera: ProtoCamera
## The gamepad bound to this player's move actions (-1 = none).
var joypad_device: int = -1
var _knockback_left: float = 0.0


func _ready() -> void:
	add_to_group("proto_players")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	joypad_device = _find_joypad_device()


func _physics_process(delta: float) -> void:
	var direction: Vector3 = _read_direction()
	if direction != Vector3.ZERO:
		facing = direction.normalized()
	velocity += direction * acceleration * _speed_scale(direction) * delta

	# Frame-rate independent drag: weaker drag when gliding.
	var current_drag: float = drag if direction != Vector3.ZERO else glide_drag
	velocity *= exp(-current_drag * delta)
	if _knockback_left > 0.0:
		_knockback_left -= delta
	else:
		velocity = velocity.limit_length(max_speed * _speed_scale(velocity))
	_apply_leash()

	velocity.y = 0.0
	move_and_slide()
	position.y = 0.0


## The wanted move on the floor (length 0-1): the stick if it is pushed, else
## the keys.
func _read_direction() -> Vector3:
	if joypad_device >= 0:
		var stick := Vector2(
				Input.get_joy_axis(joypad_device, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(joypad_device, JOY_AXIS_LEFT_Y))
		if stick.length() > stick_deadzone:
			stick = stick.limit_length(1.0)
			return camera.stick_to_world(stick) if camera else Vector3(stick.x, 0.0, stick.y)
	var keys: Vector2 = Input.get_vector(
			input_prefix + "move_left", input_prefix + "move_right",
			input_prefix + "move_up", input_prefix + "move_down")
	return camera.keys_to_world(keys) if camera else Vector3(keys.x, 0.0, keys.y)


func _speed_scale(direction: Vector3) -> float:
	return camera.speed_scale(direction) if camera else 1.0


func _find_joypad_device() -> int:
	var action: String = input_prefix + "move_left"
	if not InputMap.has_action(action):
		return -1
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion or event is InputEventJoypadButton:
			return event.device
	return -1


func apply_knockback(push: Vector3) -> void:
	velocity = push
	_knockback_left = knockback_time


func get_partner() -> ProtoPlayer:
	for node: Node in get_tree().get_nodes_in_group("proto_players"):
		if node != self:
			return node as ProtoPlayer
	return null


func _apply_leash() -> void:
	var partner: ProtoPlayer = get_partner()
	if partner == null:
		return
	var offset: Vector3 = global_position - partner.global_position
	var distance: float = offset.length()
	var soft_start: float = leash_distance - leash_soft_zone
	if distance <= soft_start or distance == 0.0:
		return
	var away: Vector3 = offset / distance
	var outward: float = velocity.dot(away)
	if outward > 0.0:
		# The closer to the limit, the more of the outward speed is removed.
		var t: float = clampf((distance - soft_start) / leash_soft_zone, 0.0, 1.0)
		velocity -= away * outward * t
	if distance > leash_distance:
		velocity -= away * (distance - leash_distance) * leash_pull
