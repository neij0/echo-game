class_name ProtoCreature
extends CharacterBody3D
## STAND-IN until the real Creature is ported to 3D (Phase A): works with the
## real Player (health, downed) and SharedCamera.
## The prototype's one creature: a dark shape with glowing eyes that wanders,
## investigates pulses, chases a player it can see and lunges (telegraphed).
## Like in the 2D game the sword only hurts it while it is revealed (a pulse,
## the Echo's light, the Guardian's close sense) and a pulse makes it Exposed
## (the finisher kills). It comes back after respawn_time so testing goes on.

signal died

enum State { WANDER, INVESTIGATE, CHASE, WINDUP, LUNGE, RECOVER, STAGGER, DEAD }

const BODY_SHADER: Shader = preload("res://shaders/character.gdshader")
const SEE_THROUGH_SHADER: Shader = preload("res://shaders/see_through.gdshader")

@export var body_radius: float = 0.45
@export var body_height: float = 0.8
@export var max_health: int = 3
## Half the side of the square it may wander in (the room, inside the walls).
@export var roam_extent: float = 10.0
@export var roam_center: Vector3 = Vector3.ZERO
@export var respawn_time: float = 2.5
## False = it stands still (screenshots); it still shows reveals.
@export var ai_enabled: bool = true

@export_group("Movement")
@export var wander_speed: float = 1.4
@export var investigate_speed: float = 2.4
## Chase speed as a share of the chased player's max_speed (2D: Calm 0.82-0.88).
@export var chase_ratio: float = 0.85
@export var turn_acceleration: float = 14.0
## How far ahead it checks for rock, and the side angles it tries (degrees).
@export var steer_look_ahead: float = 1.3
@export var steer_angles: PackedFloat32Array = PackedFloat32Array([0.0, 30.0, 60.0, 90.0, 130.0])

@export_group("Senses")
@export var sight_radius: float = 6.0
## Seconds without seeing the chased player before it gives up.
@export var lose_time: float = 3.0
@export_flags_3d_physics var wall_mask: int = 1

@export_group("Lunge")
@export var lunge_range: float = 2.4
@export var lunge_windup: float = 0.3
@export var lunge_speed: float = 9.0
@export var lunge_time: float = 0.25
@export var lunge_recovery: float = 0.6

@export_group("Reveal")
## Seconds it stays Exposed after a pulse reached it in sight.
@export var expose_time: float = 4.0
## Within this distance of the Echo it counts as lit (2D: 115 px).
@export var light_reveal_radius: float = 2.3
## Within this distance of the Guardian he senses it (2D: 90 px).
@export var close_sense_radius: float = 1.8

@export_group("Look")
@export var body_color: Color = Color(0.015, 0.012, 0.02)
@export var glow_color: Color = Color(1.0, 0.32, 0.22)
@export var eye_color: Color = Color(1.0, 0.45, 0.3)
@export var exposed_rim_energy: float = 3.0
@export var lit_rim_energy: float = 0.9
@export var eye_idle_energy: float = 2.0
@export var eye_chase_energy: float = 4.0
@export var eye_flare_energy: float = 9.0
@export var hit_flash_time: float = 0.15
@export var bob_height: float = 0.06
@export var bob_speed: float = 2.2

## Optional: makes its speed look the same on screen in every direction, like
## the players' (SharedCamera.speed_scale).
var camera: SharedCamera
var state: State = State.WANDER
var facing: Vector3 = Vector3.BACK
var _health: int = 0
var _state_time: float = 0.0
var _goal: Vector3 = Vector3.ZERO
var _wander_time: float = 0.0
var _target: Player
var _last_seen: Vector3 = Vector3.ZERO
var _lost_time: float = 0.0
var _lunge_direction: Vector3 = Vector3.ZERO
var _lunge_hit: bool = false
var _stagger_time: float = 0.0
var _reveal_left: float = 0.0
var _flash_left: float = 0.0
var _side: float = 1.0
var _time: float = 0.0
var _visual: Node3D
var _body_material: ShaderMaterial
var _see_material: ShaderMaterial
var _eye_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("proto_creatures")
	add_to_group("sonar_targets")
	add_to_group("cutaway_targets")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = wall_mask
	_health = max_health
	_build_visual()
	_pick_wander_goal()


## ViewCutaway: rock never hides it while it lunges or is Exposed.
func wants_cutaway() -> bool:
	return state == State.WINDUP or state == State.LUNGE or is_exposed()


func is_exposed() -> bool:
	return _reveal_left > 0.0


## True when the Guardian's sword can hurt it right now.
func is_hittable() -> bool:
	if state == State.DEAD:
		return false
	if is_exposed():
		return true
	for player: Player in _players():
		var reach: float = light_reveal_radius if player.light_reveal_radius > 0.0 else close_sense_radius
		if _flat_distance(player.global_position) <= reach:
			return true
	return false


## Called by the Sonar when a wave reaches it in line of sight.
func on_sonar_hit(origin: Vector3) -> void:
	if state == State.DEAD:
		return
	_reveal_left = expose_time
	if state == State.WANDER or state == State.INVESTIGATE:
		_goal = origin
		_set_state(State.INVESTIGATE)


## Returns false when the hit did nothing (not revealed).
func take_sword_hit(damage: int, push: Vector3, stagger: float, finisher: bool) -> bool:
	if not is_hittable():
		return false
	var dealt: int = damage
	if finisher and is_exposed():
		dealt = _health
	_health -= dealt
	velocity = push
	_flash_left = hit_flash_time
	if _health <= 0:
		_die()
	else:
		_stagger_time = stagger
		_set_state(State.STAGGER)
	return true


func _physics_process(delta: float) -> void:
	_time += delta
	_state_time += delta
	_reveal_left = maxf(_reveal_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if not ai_enabled:
		_update_look()
		return
	match state:
		State.WANDER:
			if _try_spot():
				_set_state(State.CHASE)
			else:
				if _state_time > _wander_time or _flat_distance(_goal) < 0.6:
					_pick_wander_goal()
				_move_towards(_goal, wander_speed, delta)
		State.INVESTIGATE:
			if _try_spot():
				_set_state(State.CHASE)
			elif _flat_distance(_goal) < 0.8 or _state_time > lose_time * 2.0:
				_pick_wander_goal()
				_set_state(State.WANDER)
			else:
				_move_towards(_goal, investigate_speed, delta)
		State.CHASE:
			_update_chase(delta)
		State.WINDUP:
			velocity *= exp(-8.0 * delta)
			if _target:
				_face(_target.global_position - global_position)
			if _state_time >= lunge_windup:
				_lunge_direction = facing
				_lunge_hit = false
				_set_state(State.LUNGE)
		State.LUNGE:
			velocity = _lunge_direction * lunge_speed
			_check_lunge_hit()
			if _state_time >= lunge_time:
				_set_state(State.RECOVER)
		State.RECOVER:
			velocity *= exp(-6.0 * delta)
			if _state_time >= lunge_recovery:
				_set_state(State.CHASE)
		State.STAGGER:
			velocity *= exp(-5.0 * delta)
			if _state_time >= _stagger_time:
				_lost_time = 0.0
				_set_state(State.CHASE if _target else State.WANDER)
		State.DEAD:
			velocity = Vector3.ZERO
			if _state_time >= respawn_time:
				_respawn()
	velocity.y = 0.0
	move_and_slide()
	position.y = 0.0
	_update_look()


func _update_chase(delta: float) -> void:
	if _target == null or _target.health.is_downed:
		_target = null
		_set_state(State.WANDER)
		return
	if _can_see(_target):
		_last_seen = _target.global_position
		_lost_time = 0.0
		if _flat_distance(_last_seen) <= lunge_range:
			_set_state(State.WINDUP)
			return
	else:
		_lost_time += delta
		if _lost_time > lose_time:
			_goal = _last_seen
			_target = null
			_set_state(State.INVESTIGATE)
			return
	_move_towards(_last_seen, _target.max_speed * chase_ratio, delta)


func _try_spot() -> bool:
	var best: Player = null
	var best_distance: float = INF
	for player: Player in _players():
		var distance: float = _flat_distance(player.global_position)
		if distance < best_distance and _can_see(player):
			best = player
			best_distance = distance
	if best == null:
		return false
	_target = best
	_last_seen = best.global_position
	_lost_time = 0.0
	return true


func _can_see(player: Player) -> bool:
	if _flat_distance(player.global_position) > sight_radius:
		return false
	return not _blocked(global_position, player.global_position)


func _check_lunge_hit() -> void:
	if _lunge_hit:
		return
	for player: Player in _players():
		if _flat_distance(player.global_position) <= body_radius + player.body_radius:
			_lunge_hit = true
			player.health.take_hit(global_position, self)
			get_tree().call_group("shared_camera", "shake_with", 0.12, 0.2)


func _move_towards(goal: Vector3, speed: float, delta: float) -> void:
	var wanted: Vector3 = goal - global_position
	wanted.y = 0.0
	if wanted.length() < 0.05:
		velocity = velocity.move_toward(Vector3.ZERO, turn_acceleration * delta)
		return
	var direction: Vector3 = _steer(wanted.normalized())
	var view_scale: float = camera.speed_scale(direction) if camera else 1.0
	velocity = velocity.move_toward(direction * speed * view_scale, turn_acceleration * delta)
	_face(direction)


## The first direction near the wanted one with no rock just ahead. It keeps
## trying the side it last went round first, so it does not flip-flop.
func _steer(wanted: Vector3) -> Vector3:
	for angle: float in steer_angles:
		for sign_value: float in [_side, -_side]:
			var direction: Vector3 = wanted.rotated(Vector3.UP, deg_to_rad(angle) * sign_value)
			if not _blocked(global_position, global_position + direction * steer_look_ahead):
				if angle > 0.0:
					_side = sign_value
				return direction
			if angle == 0.0:
				break
	return wanted


func _blocked(from: Vector3, to: Vector3) -> bool:
	var lift := Vector3(0.0, body_radius, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from + lift, to + lift, wall_mask)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length() > 0.01:
		facing = direction.normalized()


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _players() -> Array[Player]:
	var result: Array[Player] = []
	for player: Player in Players.all(get_tree()):
		# Downed players are ignored, as in the 2D game.
		if not player.health.is_downed:
			result.append(player)
	return result


func _pick_wander_goal() -> void:
	_goal = roam_center + Vector3(randf_range(-roam_extent, roam_extent), 0.0, randf_range(-roam_extent, roam_extent))
	_wander_time = randf_range(2.0, 4.5)
	_state_time = 0.0


func _set_state(next: State) -> void:
	state = next
	_state_time = 0.0


func _die() -> void:
	_set_state(State.DEAD)
	_reveal_left = 0.0
	_target = null
	_visual.visible = false
	died.emit()


## Comes back in the corner furthest from the players.
func _respawn() -> void:
	var best := Vector3.ZERO
	var best_distance: float = -1.0
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			var corner: Vector3 = roam_center + Vector3(x, 0.0, z) * roam_extent * 0.85
			var nearest: float = INF
			for player: Player in _players():
				nearest = minf(nearest, corner.distance_to(player.global_position))
			if nearest > best_distance:
				best_distance = nearest
				best = corner
	global_position = best
	velocity = Vector3.ZERO
	_health = max_health
	_visual.visible = true
	_pick_wander_goal()
	_set_state(State.WANDER)


func _build_visual() -> void:
	var shape := SphereShape3D.new()
	shape.radius = body_radius
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = body_radius
	add_child(collider)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_see_material = ShaderMaterial.new()
	_see_material.shader = SEE_THROUGH_SHADER
	_see_material.set_shader_parameter("outline_color", glow_color)
	_see_material.set_shader_parameter("visibility", 0.0)
	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	_body_material.set_shader_parameter("body_color", body_color)
	_body_material.set_shader_parameter("rim_color", glow_color)
	_body_material.set_shader_parameter("rim_energy", 0.0)
	_body_material.next_pass = _see_material

	var body_mesh := SphereMesh.new()
	body_mesh.radius = body_radius
	body_mesh.height = body_radius * 2.0
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _body_material
	body.scale = Vector3(1.0, 0.8, 1.25)
	body.position.y = body_radius
	_visual.add_child(body)

	_eye_material = StandardMaterial3D.new()
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = body_radius * 0.18
	eye_mesh.height = body_radius * 0.36
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = _eye_material
		eye.position = Vector3(side * body_radius * 0.38, body_radius * 1.15, body_radius * 1.02)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(eye)


func _update_look() -> void:
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(facing.x, facing.z), 0.25)
	_visual.position.y = sin(_time * bob_speed) * bob_height + bob_height

	var exposed: float = clampf(_reveal_left / 0.6, 0.0, 1.0)
	var near: float = 1.0 if is_hittable() else 0.0
	var rim: float = maxf(exposed * exposed_rim_energy, near * lit_rim_energy)
	var color: Color = glow_color
	if _flash_left > 0.0:
		rim = exposed_rim_energy * 3.0
		color = Color.WHITE
	_body_material.set_shader_parameter("rim_energy", rim)
	_body_material.set_shader_parameter("rim_color", color)
	_see_material.set_shader_parameter("visibility", maxf(exposed, near * 0.6))

	var eye_energy: float = eye_idle_energy
	if state == State.WINDUP:
		eye_energy = eye_flare_energy
	elif state == State.CHASE or state == State.LUNGE or state == State.RECOVER:
		eye_energy = eye_chase_energy
	_eye_material.albedo_color = Color(eye_color.r * eye_energy, eye_color.g * eye_energy, eye_color.b * eye_energy)
