class_name ViewCutaway
extends Node
## Nobody is hidden behind rock: when rock stands between the camera and a
## character, the rock is removed inside a circle round that character on
## screen (cutaway.gdshaderinc, in the rock material). The hole only opens
## while a good part of the character is really covered (min_covered_share:
## feet behind a low rock are left to the see-through outline), and grows with
## how much of the body is covered. Characters are the nodes in the "cutaway_targets" group that
## answer wants_cutaway() with true (players always; a creature while it
## lunges or is Exposed); they may offer get_body_center() and body_height.
## Rock materials are registered once (register_material).

## Most holes at once (the shader's CUT_POINTS).
const MAX_POINTS: int = 6

## Radius of the hole on the screen plane (world units) when the whole body
## is covered, and the share of it used when just enough of it is.
@export var radius: float = 1.15
@export_range(0.0, 1.0) var partial_radius_share: float = 0.7
## Share of the body (of its sample heights) that must be covered before a
## hole opens at all.
@export_range(0.0, 1.0) var min_covered_share: float = 0.5
## Seconds the hole takes to open or close.
@export var open_time: float = 0.12
## Body height used for targets that do not say their own.
@export var default_height: float = 1.0
## How far towards the camera rock is looked for.
@export var check_distance: float = 14.0
## Shares of the body's height where it is tested for cover.
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.15, 0.5, 0.95])
@export_flags_3d_physics var wall_mask: int = 1
@export_group("Rim")
@export var rim_color: Color = Color(0.25, 0.6, 0.8)
@export var rim_energy: float = 0.35

var _materials: Array[ShaderMaterial] = []
## Target instance id -> how open its hole is (0-1) and how much is wanted.
var _open: Dictionary[int, float] = {}
var _wanted: Dictionary[int, float] = {}


static func find(tree: SceneTree) -> ViewCutaway:
	return tree.get_first_node_in_group("view_cutaway") as ViewCutaway if tree else null


func _ready() -> void:
	add_to_group("view_cutaway")


## Every rock material that should be cut (rock_surface.gdshader).
func register_material(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter("cut_enabled", true)
	material.set_shader_parameter("cut_rim_color", rim_color)
	material.set_shader_parameter("cut_rim_energy", rim_energy)


## How open the hole round target is right now (0-1), for tests and debug.
func get_openness(target: Node3D) -> float:
	return float(_open.get(target.get_instance_id(), 0.0))


## Which characters are covered: rays from the body towards the camera.
func _physics_process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var towards_camera: Vector3 = camera.global_basis.z
	_wanted.clear()
	for target: Node3D in _targets():
		var height: float = _height_of(target)
		var covered: int = 0
		for share: float in sample_heights:
			var from: Vector3 = target.global_position + Vector3(0.0, height * share, 0.0)
			var query := PhysicsRayQueryParameters3D.create(from, from + towards_camera * check_distance, wall_mask)
			if not space.intersect_ray(query).is_empty():
				covered += 1
		var share_covered: float = float(covered) / float(sample_heights.size())
		if covered > 0 and share_covered >= min_covered_share:
			var extra: float = inverse_lerp(min_covered_share, 1.0, share_covered) if min_covered_share < 1.0 else 1.0
			_wanted[target.get_instance_id()] = lerpf(partial_radius_share, 1.0, extra)


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var step: float = delta / maxf(open_time, 0.001)
	var alive: Dictionary[int, bool] = {}
	for target: Node3D in _targets():
		var id: int = target.get_instance_id()
		alive[id] = true
		var open: float = move_toward(float(_open.get(id, 0.0)), float(_wanted.get(id, 0.0)), step)
		_open[id] = open
		if open > 0.0 and points.size() < MAX_POINTS:
			points.append(_center_of(target))
			radii.append(radius * open)
	for id: int in _open.keys():
		if not alive.has(id):
			_open.erase(id)
	while points.size() < MAX_POINTS:
		points.append(Vector3.ZERO)
		radii.append(0.0)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("cut_point", points)
		material.set_shader_parameter("cut_radius", radii)
		material.set_shader_parameter("cut_view_right", camera.global_basis.x)
		material.set_shader_parameter("cut_view_up", camera.global_basis.y)
		material.set_shader_parameter("cut_view_back", camera.global_basis.z)


func _targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("cutaway_targets"):
		var target := node as Node3D
		if target and target.has_method("wants_cutaway") and target.call("wants_cutaway"):
			result.append(target)
	return result


func _height_of(target: Node3D) -> float:
	var height: Variant = target.get("body_height")
	return float(height) if height != null else default_height


func _center_of(target: Node3D) -> Vector3:
	if target.has_method("get_body_center"):
		return target.call("get_body_center")
	return target.global_position + Vector3(0.0, _height_of(target) * 0.5, 0.0)
