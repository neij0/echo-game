class_name CreatureBody
extends Node3D
## PLACEHOLDER look of a creature until the creature models (Phase C): a dark
## shape per type (Creature.look: a soft oval, a slowly turning spiky shell,
## or an arrowhead with flapping fins) that the real lights show, as in the 2D
## game's visibility zones: outside every light it is black on black; in the
## Echo's light it shows as a dark silhouette; inside her full reveal it gets a
## glowing outline (rim) in the type colour. A pulse front gives a bright echo
## in the type colour that fades (its sonar echo, even in the dark); a hit
## flashes it white. Where rock covers it, a revealed or Exposed creature
## shows its outline through the rock, a silhouette only faintly, a hidden one
## not at all (plan section 5.3).

const BODY_SHADER: Shader = preload("res://shaders/character.gdshader")
const SEE_THROUGH_SHADER: Shader = preload("res://shaders/see_through.gdshader")

@export var creature: Creature

@export_group("Outline")
## When fully revealed: the body colour darkened by this, with a rim in the
## type colour.
@export_range(0.0, 1.0) var fill_darken: float = 0.75
@export var outline_energy: float = 1.8
## Echo Mark skill outline (Creature.get_mark_ratio).
@export var mark_energy: float = 1.3

@export_group("Sonar Echo")
## The echo a pulse front leaves: bright, then fading to end_energy, then gone.
@export var echo_start_energy: float = 4.0
@export var echo_end_energy: float = 1.2
@export var echo_fade_time: float = 1.5

@export_group("Through Rock")
## Outline strength through rock: a silhouette shows only this share.
@export_range(0.0, 1.0) var silhouette_through_rock: float = 0.35

@export_group("Hit Flash")
@export var flash_color: Color = Color(1.0, 1.0, 1.0)
@export var flash_energy: float = 6.0

@export_group("Motion")
@export var bob_height: float = 0.05
@export var bob_speed: float = 2.2
## SPIKY shell: spikes and turn speed (radians per second).
@export var spike_count: int = 7
@export var spike_length: float = 0.55
@export var spike_spin_speed: float = 0.4
## ARROW fins: flaps per second.
@export var fin_flap_speed: float = 1.6
## A crest of spines standing up along the back (the Sentinel: "this one
## guards"); 0 = none. Length is a share of body_radius, spread in degrees.
@export var crest_spines: int = 0
@export var crest_length: float = 0.9
@export var crest_spread_degrees: float = 140.0
## How fast it turns to face where it moves.
@export var turn_speed: float = 10.0

var _material: ShaderMaterial
var _see_through: ShaderMaterial
var _shape: Node3D
var _spikes: Node3D
var _fins: Array[Node3D] = []
var _echo_left: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	if creature == null:
		return
	_see_through = ShaderMaterial.new()
	_see_through.shader = SEE_THROUGH_SHADER
	_see_through.set_shader_parameter("outline_color", creature.type_color)
	_see_through.set_shader_parameter("visibility", 0.0)
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("body_color", creature.body_color.darkened(fill_darken))
	_material.set_shader_parameter("rim_color", creature.type_color)
	_material.set_shader_parameter("rim_energy", 0.0)
	_material.next_pass = _see_through
	_shape = Node3D.new()
	_shape.name = "Shape"
	add_child(_shape)
	_build_shape()
	creature.pinged.connect(_on_pinged)


func _on_pinged() -> void:
	_echo_left = echo_fade_time


func _process(delta: float) -> void:
	if creature == null:
		return
	_time += delta
	_echo_left = maxf(_echo_left - delta, 0.0)
	var wanted_yaw: float = atan2(creature.facing.x, creature.facing.z)
	_shape.rotation.y = lerp_angle(_shape.rotation.y, wanted_yaw, 1.0 - exp(-turn_speed * delta))
	_shape.position.y = creature.body_height * 0.5 + sin(_time * TAU * bob_speed * 0.25) * bob_height
	if _spikes:
		_spikes.rotation.y = _time * spike_spin_speed
	for i: int in _fins.size():
		var flap: float = sin(_time * TAU * fin_flap_speed) * 0.5
		_fins[i].rotation.z = flap * (1.0 if i == 0 else -1.0)
	_update_glow()


func _update_glow() -> void:
	var lit: bool = creature.is_lit_by_echo()
	var echo: float = _echo_left / echo_fade_time if echo_fade_time > 0.0 else 0.0
	var rim: float = creature_outline() if lit else 0.0
	if echo > 0.0:
		rim = maxf(rim, lerpf(echo_end_energy, echo_start_energy, echo * echo))
	rim = maxf(rim, creature.get_mark_ratio() * mark_energy)
	var color: Color = creature.type_color
	var flash: float = creature.get_flash_ratio()
	if flash > 0.0:
		color = creature.type_color.lerp(flash_color, flash)
		rim = maxf(rim, flash_energy * flash)
	_material.set_shader_parameter("rim_energy", rim)
	_material.set_shader_parameter("rim_color", color)

	var through: float = 1.0 if lit else 0.0
	through = maxf(through, echo)
	through = maxf(through, creature.get_mark_ratio())
	through = maxf(through, 1.0 if creature.is_exposed() else 0.0)
	through = maxf(through, maxf(creature.silhouette_ratio, creature.sense_ratio) * silhouette_through_rock)
	_see_through.set_shader_parameter("visibility", through)
	_see_through.set_shader_parameter("outline_color", color)


## The rim of the full reveal.
func creature_outline() -> float:
	return outline_energy


## True while its sonar echo still glows (tests).
func is_echoing() -> bool:
	return _echo_left > 0.0


func _build_shape() -> void:
	var radius: float = creature.body_radius
	match creature.look:
		Creature.Look.SPIKY:
			_add_part(_sphere(radius * 0.85), Vector3.ZERO, Vector3.ONE)
			_spikes = Node3D.new()
			_shape.add_child(_spikes)
			for i: int in spike_count:
				var angle: float = TAU * float(i) / float(spike_count)
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = radius * 0.22
				cone.height = radius * spike_length * 1.6
				cone.radial_segments = 6
				var spike := MeshInstance3D.new()
				spike.mesh = cone
				spike.material_override = _material
				var outward := Vector3(cos(angle), 0.0, sin(angle))
				spike.position = outward * radius * (0.85 + spike_length * 0.5)
				# The cone's tip is its +y: point that outward (x = y cross z).
				spike.basis = Basis(outward.cross(Vector3.UP), outward, Vector3.UP)
				_spikes.add_child(spike)
		Creature.Look.ARROW:
			var head := CylinderMesh.new()
			head.top_radius = 0.0
			head.bottom_radius = radius * 0.8
			head.height = radius * 2.5
			head.radial_segments = 3
			var arrow := _add_part(head, Vector3.ZERO, Vector3(1.0, 1.0, 0.45))
			# Point the tip forward (+z).
			arrow.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			for side: float in [-1.0, 1.0]:
				var fin_mesh := BoxMesh.new()
				fin_mesh.size = Vector3(radius * 1.1, radius * 0.06, radius * 0.7)
				var pivot := Node3D.new()
				pivot.position = Vector3(side * radius * 0.3, 0.0, -radius * 0.2)
				_shape.add_child(pivot)
				var fin := MeshInstance3D.new()
				fin.mesh = fin_mesh
				fin.material_override = _material
				fin.position = Vector3(side * radius * 0.55, 0.0, 0.0)
				pivot.add_child(fin)
				_fins.append(pivot)
		_:
			# A soft oval, a little longer than wide, pointing where it moves.
			_add_part(_sphere(radius), Vector3.ZERO, Vector3(0.85, 0.8, 1.15))
	_add_crest(radius)


## Spines fanning up and back over the body (they turn with it).
func _add_crest(radius: float) -> void:
	for i: int in crest_spines:
		var t: float = float(i) / maxf(crest_spines - 1, 1) - 0.5
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = radius * 0.12
		cone.height = radius * crest_length * (1.0 - absf(t) * 0.5)
		cone.radial_segments = 5
		var spine := MeshInstance3D.new()
		spine.mesh = cone
		spine.material_override = _material
		# Up and towards the back (-z), fanned along the back.
		var tilt: float = deg_to_rad(crest_spread_degrees) * t
		var direction := Vector3(0.0, cos(tilt), -sin(tilt) - 0.35).normalized()
		spine.position = direction * radius * 0.7 + direction * cone.height * 0.5
		# The cone's tip is its +y: point that along direction (z = x cross y).
		spine.basis = Basis(Vector3.RIGHT, direction, Vector3.RIGHT.cross(direction))
		_shape.add_child(spine)


func _add_part(part_mesh: Mesh, at: Vector3, part_scale: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = part_mesh
	part.material_override = _material
	part.position = at
	part.scale = part_scale
	_shape.add_child(part)
	return part


static func _sphere(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	return sphere
