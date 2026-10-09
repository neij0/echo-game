class_name Player
extends CharacterBody2D
## Swimming movement (acceleration, drag, glide) and the sonar pulse input.

signal pulse_emitted(origin: Vector2)

@export_group("Swimming")
@export var acceleration: float = 900.0
@export var max_speed: float = 260.0
## Drag while the player is pressing a direction.
@export var drag: float = 2.5
## Lower drag when input stops, so the player glides a little.
@export var glide_drag: float = 1.2

@export_group("Pulse")
@export var pulse_ring_scene: PackedScene
@export var pulse_cooldown: float = 2.0

@export_group("Visual")
@export var body_radius: float = 14.0
@export var body_color: Color = Color(0.85, 0.9, 1.0)

var pulse_cooldown_left: float = 0.0


func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity += input_dir * acceleration * delta

	# Frame-rate independent drag: weaker drag when gliding.
	var current_drag: float = drag if input_dir != Vector2.ZERO else glide_drag
	velocity *= exp(-current_drag * delta)
	velocity = velocity.limit_length(max_speed)

	move_and_slide()


func _process(delta: float) -> void:
	pulse_cooldown_left = maxf(pulse_cooldown_left - delta, 0.0)
	if Input.is_action_just_pressed("pulse") and is_pulse_ready():
		_emit_pulse()


func is_pulse_ready() -> bool:
	return pulse_cooldown_left <= 0.0


func _emit_pulse() -> void:
	pulse_cooldown_left = pulse_cooldown
	if pulse_ring_scene:
		var ring: Node2D = pulse_ring_scene.instantiate()
		ring.position = position
		get_parent().add_child(ring)
	pulse_emitted.emit(global_position)


func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius, body_color)
