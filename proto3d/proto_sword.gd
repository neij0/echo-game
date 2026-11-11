class_name ProtoSword
extends Node3D
## The Guardian's 3-hit combo (two quick slashes, then a finisher with a
## wind-up), with the 2D SwordAbility's timings at 50 px = 1 unit. Draws a
## simple blade and a glowing slash arc. Hits everything in the
## "proto_creatures" group inside the arc; a creature that is not revealed
## cannot be hurt.

signal hit_landed(finisher: bool, killed: bool)

enum Phase { IDLE, WINDUP, SWING, RECOVERY }

@export var player: ProtoPlayer

@export_group("Quick Slash (hits 1 and 2)")
@export var quick_damage: int = 1
@export var quick_range: float = 1.25
@export var quick_arc_degrees: float = 100.0
@export var quick_duration: float = 0.2
@export var quick_stagger: float = 0.3
@export var quick_knockback: float = 2.8

@export_group("Finisher (hit 3)")
@export var finisher_damage: int = 2
@export var finisher_range: float = 1.65
@export var finisher_arc_degrees: float = 170.0
@export var finisher_windup: float = 0.14
@export var finisher_duration: float = 0.3
@export var finisher_stagger: float = 0.7
@export var finisher_knockback: float = 6.4
@export var finisher_recovery: float = 0.35

@export_group("Combo")
## Seconds after a hit in which the next press continues the combo.
@export var combo_window: float = 0.45
## A press this long before the swing ends is remembered.
@export var buffer_time: float = 0.2
## Forward push of the Guardian on each hit.
@export var step_speed: float = 0.6

@export_group("Impact")
@export var hit_stop_duration: float = 0.08
@export_range(0.0, 1.0) var hit_stop_time_scale: float = 0.02
@export var hit_shake: float = 0.07
@export var kill_shake: float = 0.18

@export_group("Look")
@export var blade_length: float = 0.75
@export var blade_offset: float = 0.3
@export var blade_height: float = 0.75
@export var blade_color: Color = Color(0.05, 0.05, 0.07)
@export var edge_color: Color = Color(1.0, 0.78, 0.25)
@export var edge_energy: float = 1.2
@export var arc_energy: float = 3.0
@export var arc_inner: float = 0.45
@export var arc_fade_time: float = 0.15
@export var arc_segments: int = 20
## Where the blade hangs at rest, degrees from the facing.
@export var rest_angle_degrees: float = 115.0

var _phase: Phase = Phase.IDLE
var _time: float = 0.0
var _step: int = 0
var _combo_left: float = 0.0
var _buffer_left: float = 0.0
var _direction: Vector3 = Vector3.BACK
var _swing_sign: float = 1.0
var _arc_fade: float = 0.0
var _arc_reach: float = 0.0
var _arc_from: float = 0.0
var _arc_to: float = 0.0
var _pivot: Node3D
var _arc_mesh: ImmediateMesh
var _arc_material: StandardMaterial3D


func _ready() -> void:
	_build_look()


func is_swinging() -> bool:
	return _phase != Phase.IDLE


func _physics_process(delta: float) -> void:
	_buffer_left = maxf(_buffer_left - delta, 0.0)
	if Input.is_action_just_pressed(player.input_prefix + "action"):
		_buffer_left = buffer_time
	_time += delta
	match _phase:
		Phase.IDLE:
			_combo_left -= delta
			if _combo_left <= 0.0:
				_step = 0
			if _buffer_left > 0.0:
				_start_hit()
		Phase.WINDUP:
			if _time >= finisher_windup:
				_begin_swing()
		Phase.SWING:
			if _time >= _duration():
				_end_swing()
		Phase.RECOVERY:
			if _time >= finisher_recovery:
				_phase = Phase.IDLE


func _is_finisher() -> bool:
	return _step == 2


func _duration() -> float:
	return finisher_duration if _is_finisher() else quick_duration


func _arc() -> float:
	return deg_to_rad(finisher_arc_degrees if _is_finisher() else quick_arc_degrees)


func _range() -> float:
	return finisher_range if _is_finisher() else quick_range


func _start_hit() -> void:
	_buffer_left = 0.0
	_direction = player.facing
	_swing_sign = -_swing_sign
	_time = 0.0
	if _is_finisher():
		_phase = Phase.WINDUP
	else:
		_begin_swing()


func _begin_swing() -> void:
	_phase = Phase.SWING
	_time = 0.0
	_arc_fade = 1.0
	_arc_reach = _range()
	_arc_from = -_arc() * 0.5 * _swing_sign
	_arc_to = _arc_from
	player.velocity += _direction * step_speed
	_apply_hits()


func _end_swing() -> void:
	_time = 0.0
	if _is_finisher():
		_step = 0
		_phase = Phase.RECOVERY
	else:
		_step += 1
		_combo_left = combo_window
		_phase = Phase.IDLE


func _apply_hits() -> void:
	var finisher: bool = _is_finisher()
	var half_arc: float = _arc() * 0.5
	for node: Node in get_tree().get_nodes_in_group("proto_creatures"):
		var creature := node as ProtoCreature
		var offset: Vector3 = creature.global_position - player.global_position
		offset.y = 0.0
		if offset.length() > _range() + creature.body_radius:
			continue
		if offset.length() > creature.body_radius and _direction.angle_to(offset) > half_arc:
			continue
		var push: Vector3 = _direction * (finisher_knockback if finisher else quick_knockback)
		var damage: int = finisher_damage if finisher else quick_damage
		var stagger: float = finisher_stagger if finisher else quick_stagger
		if not creature.take_sword_hit(damage, push, stagger, finisher):
			continue
		var killed: bool = creature.state == ProtoCreature.State.DEAD
		get_tree().call_group("proto_camera", "shake_with", kill_shake if killed else hit_shake, 0.2)
		hit_landed.emit(finisher, killed)
		if killed:
			_hit_stop()


func _hit_stop() -> void:
	Engine.time_scale = hit_stop_time_scale
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	# Blade angle, measured from the facing (positive = towards the left hand).
	var angle: float = deg_to_rad(rest_angle_degrees) * _swing_sign
	var around: Vector3 = player.facing
	match _phase:
		Phase.WINDUP:
			around = _direction
			angle = -(_arc() * 0.5 + 0.5 * _time / finisher_windup) * _swing_sign
		Phase.SWING:
			around = _direction
			var t: float = clampf(_time / _duration(), 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - t, 3.0)
			angle = lerpf(-_arc() * 0.5, _arc() * 0.5, eased) * _swing_sign
			_arc_to = angle
		Phase.RECOVERY:
			around = _direction
			angle = _arc() * 0.5 * _swing_sign
	if _phase != Phase.SWING:
		_arc_fade = maxf(_arc_fade - delta / arc_fade_time, 0.0)
	var blade_direction: Vector3 = around.rotated(Vector3.UP, angle)
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, atan2(blade_direction.x, blade_direction.z), 0.6)
	_draw_arc()


func _draw_arc() -> void:
	_arc_mesh.clear_surfaces()
	if _arc_fade <= 0.0 or is_equal_approx(_arc_from, _arc_to):
		return
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _arc_material)
	for i: int in arc_segments + 1:
		var share: float = float(i) / float(arc_segments)
		var direction: Vector3 = _direction.rotated(Vector3.UP, lerpf(_arc_from, _arc_to, share))
		# The tail of the slash is faint, its leading edge bright.
		var alpha: float = share * share * _arc_fade
		_arc_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.0))
		_arc_mesh.surface_add_vertex(direction * arc_inner + Vector3(0.0, blade_height, 0.0))
		_arc_mesh.surface_set_color(Color(1.0, 1.0, 1.0, alpha))
		_arc_mesh.surface_add_vertex(direction * _arc_reach + Vector3(0.0, blade_height, 0.0))
	_arc_mesh.surface_end()


func _build_look() -> void:
	_pivot = Node3D.new()
	_pivot.name = "BladePivot"
	add_child(_pivot)
	var blade_material := StandardMaterial3D.new()
	blade_material.albedo_color = blade_color
	blade_material.emission_enabled = true
	blade_material.emission = edge_color
	blade_material.emission_energy_multiplier = edge_energy
	blade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.06, 0.04, blade_length)
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	blade.mesh = blade_mesh
	blade.material_override = blade_material
	blade.position = Vector3(0.0, blade_height, blade_offset + blade_length * 0.5)
	_pivot.add_child(blade)

	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.vertex_color_use_as_albedo = true
	_arc_material.albedo_color = Color(edge_color.r * arc_energy, edge_color.g * arc_energy, edge_color.b * arc_energy)
	_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mesh = ImmediateMesh.new()
	var arc := MeshInstance3D.new()
	arc.name = "SlashArc"
	arc.mesh = _arc_mesh
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arc)
