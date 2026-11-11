class_name GlowLines
extends MeshInstance3D
## Glowing lines, arcs, rings and dots drawn flat on the floor (or at any
## height), unlit and additive, rebuilt every frame: the 3D replacement for the
## 2D draw_arc / draw_polyline / draw_circle markers (rings round a downed
## player, the revive progress, the goal arrow, the slash arc, the mending
## link...). Usage each frame: clear(), then add_arc / add_polyline /
## add_disc..., then commit(). Colours are tints (0-1) with alpha; the
## brightness comes from energy (above 1 blooms). With through_rock the marks
## are drawn over rock too, so a ring is never hidden.
## Widths and radii are world units. top_level: the points are world positions.

## Brightness multiplier of every mark.
@export var energy: float = 2.0
## Drawn over everything (rock, characters): markers that must always show.
@export var through_rock: bool = true
## Height above the floor of marks given as floor points.
@export var floor_height: float = 0.04
## Segments per full circle (arcs use their share).
@export var circle_segments: int = 48

var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _vertices: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = through_rock
	_material.render_priority = 10
	_material.disable_fog = true
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Big bounds: the marks can be anywhere in the level.
	custom_aabb = AABB(Vector3.ONE * -10000.0, Vector3.ONE * 20000.0)
	set_energy(energy)


func set_energy(value: float) -> void:
	energy = value
	if _material:
		_material.albedo_color = Color(energy, energy, energy, 1.0)


func clear() -> void:
	_vertices.clear()
	_colors.clear()


## An arc round center (a floor point; its y is replaced by floor_height + lift)
## from one angle to another (radians, measured on the floor from +x towards +z).
func add_arc(center: Vector3, radius: float, from_angle: float, to_angle: float, width: float, color: Color, lift: float = 0.0) -> void:
	var span: float = to_angle - from_angle
	var steps: int = maxi(2, ceili(absf(span) / TAU * circle_segments))
	var points := PackedVector3Array()
	for i: int in steps + 1:
		var angle: float = from_angle + span * float(i) / float(steps)
		points.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	add_polyline(points, width, color, lift)


func add_ring(center: Vector3, radius: float, width: float, color: Color, lift: float = 0.0) -> void:
	add_arc(center, radius, 0.0, TAU, width, color, lift)


## A flat band between two radii, filling the angles from one to the other.
## Each end has its own colour (a slash that fades behind the blade).
func add_band(center: Vector3, inner: float, outer: float, from_angle: float, to_angle: float, from_color: Color, to_color: Color, lift: float = 0.0) -> void:
	var span: float = to_angle - from_angle
	var steps: int = maxi(2, ceili(absf(span) / TAU * circle_segments))
	var y: float = floor_height + lift
	for i: int in steps:
		var a0: float = from_angle + span * float(i) / float(steps)
		var a1: float = from_angle + span * float(i + 1) / float(steps)
		var c0: Color = from_color.lerp(to_color, float(i) / float(steps))
		var c1: Color = from_color.lerp(to_color, float(i + 1) / float(steps))
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var base := Vector3(center.x, y, center.z)
		_quad(base + d0 * inner, base + d0 * outer, base + d1 * outer, base + d1 * inner, c0, c0, c1, c1)


## A line through floor points (their y is replaced by floor_height + lift).
func add_polyline(points: PackedVector3Array, width: float, color: Color, lift: float = 0.0) -> void:
	var raised := PackedVector3Array()
	for point: Vector3 in points:
		raised.append(Vector3(point.x, floor_height + lift, point.z))
	add_line_3d(raised, width, color)


## A line through points as they are (any height), as a flat ribbon that faces
## up (the camera looks down on it).
func add_line_3d(points: PackedVector3Array, width: float, color: Color) -> void:
	if points.size() < 2:
		return
	var half: float = width * 0.5
	for i: int in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if along.length_squared() < 0.0000001:
			continue
		var side: Vector3 = along.normalized().cross(Vector3.UP) * half
		_quad(a - side, a + side, b + side, b - side, color, color, color, color)


## A filled dot on the floor (soft: its edge fades out).
func add_disc(center: Vector3, radius: float, color: Color, lift: float = 0.0) -> void:
	var steps: int = maxi(8, circle_segments / 3)
	var middle := Vector3(center.x, floor_height + lift, center.z)
	var edge := Color(color, 0.0)
	for i: int in steps:
		var a0: float = TAU * float(i) / float(steps)
		var a1: float = TAU * float(i + 1) / float(steps)
		_triangle(middle, middle + Vector3(cos(a0), 0.0, sin(a0)) * radius,
			middle + Vector3(cos(a1), 0.0, sin(a1)) * radius, color, edge, edge)


## Sends everything added since clear() to the mesh.
func commit() -> void:
	_mesh.clear_surfaces()
	if _vertices.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in _vertices.size():
		_mesh.surface_set_color(_colors[i])
		_mesh.surface_add_vertex(_vertices[i])
	_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_triangle(a, b, c, ca, cb, cc)
	_triangle(a, c, d, ca, cc, cd)


func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_vertices.append(a)
	_vertices.append(b)
	_vertices.append(c)
	_colors.append(ca)
	_colors.append(cb)
	_colors.append(cc)
