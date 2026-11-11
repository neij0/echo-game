class_name ArenaPillar
extends RockWall
## A rock pillar in a boss arena: rock like any wall (collision, shadow, sonar
## edge, 3/4 faces), but a charging boss that runs into it is stunned
## (AnglerBoss) and the pillar takes the blow: after crack_at blows it shows
## cracks, after break_at it breaks apart (rubble on the floor, dust, the
## rock fades away: no collision, no shadow, no sonar edge). The LevelBuilder
## rebakes the navigation when it breaks (broken signal).

signal cracked
signal broken

@export_group("Blows")
@export var crack_at: int = 2
@export var break_at: int = 3

@export_group("Cracks")
@export var crack_color: Color = Color(0.02, 0.02, 0.025)
@export var crack_edge_color: Color = Color(0.32, 0.31, 0.28)
@export var crack_width: float = 2.2
@export var crack_count: int = 5

@export_group("Breaking")
@export var break_fade_time: float = 0.5
@export var rubble_count: int = 9
@export var rubble_color: Color = Color(0.1, 0.11, 0.12)
@export var dust_color: Color = Color(0.55, 0.52, 0.45, 0.6)
@export var shake_strength: float = 9.0
@export var shake_time: float = 0.5
@export var crack_sound: String = "world_rock_fall"
@export var break_sound: String = "world_barrier_close"

var blows: int = 0
var is_cracked: bool = false
var is_broken: bool = false
var _fade_left: float = 0.0
var _cracks: Node2D
var _crack_lines: Array[PackedVector2Array] = []


func _ready() -> void:
	super()
	add_to_group("arena_pillars")


## A charging boss hit it. Returns true if this blow broke it.
func take_blow() -> bool:
	if is_broken:
		return false
	blows += 1
	if blows >= break_at:
		break_apart()
		return true
	if blows >= crack_at and not is_cracked:
		_crack()
	_play(crack_sound)
	return false


func break_apart() -> void:
	if is_broken:
		return
	is_broken = true
	remove_from_group("rock_walls")
	for child: Node in get_children():
		if child is CollisionPolygon2D:
			(child as CollisionPolygon2D).set_deferred("disabled", true)
		elif child is LightOccluder2D:
			child.queue_free()
	_fade_left = break_fade_time
	_add_rubble()
	_add_dust()
	_play(break_sound)
	get_tree().call_group("shared_camera", "shake_with", shake_strength, shake_time)
	get_tree().call_group("sonar_overlay", "rebuild_samples")
	broken.emit()


## The base polygon in the space of an ancestor (the LevelBuilder's).
func get_polygon_in(ancestor: Node2D) -> PackedVector2Array:
	return ancestor.global_transform.affine_inverse() * (global_transform * polygon)


func _process(delta: float) -> void:
	if _fade_left <= 0.0:
		return
	_fade_left = maxf(_fade_left - delta, 0.0)
	var alpha: float = _fade_left / maxf(break_fade_time, 0.01)
	for child: Node in get_children():
		if child is RockFace or child is Polygon2D or child == _cracks:
			(child as CanvasItem).modulate.a = alpha
	if _fade_left <= 0.0:
		# Gone: the faces leave the cover lookup (RockFace._exit_tree).
		for child: Node in get_children():
			if child is RockFace or child == _cracks:
				child.queue_free()


func _crack() -> void:
	is_cracked = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position.round())
	var outline: PackedVector2Array = get_global_outline()
	var center := Vector2.ZERO
	var bottom: float = -INF
	for point: Vector2 in outline:
		center += point / outline.size()
		bottom = maxf(bottom, point.y)
	var radius: float = 0.0
	for point: Vector2 in outline:
		radius = maxf(radius, point.distance_to(center))
	var top_center: Vector2 = center - Vector2(0.0, height_at(center))
	_crack_lines.clear()
	for i: int in crack_count:
		# Jagged lines out from the middle of the top...
		var direction: Vector2 = Vector2.from_angle(TAU * float(i) / float(crack_count) + rng.randf_range(-0.4, 0.4))
		var line := PackedVector2Array([top_center + direction * rng.randf_range(2.0, 8.0)])
		var steps: int = 4
		for k: int in range(1, steps + 1):
			var along: float = radius * 0.8 * float(k) / float(steps)
			line.append(top_center + direction * along + direction.orthogonal() * rng.randf_range(-5.0, 5.0))
		_crack_lines.append(line)
	for i: int in 2:
		# ...and two running down the front face.
		var x: float = center.x + rng.randf_range(-0.5, 0.5) * radius
		var face_top := Vector2(x, center.y + radius * 0.6 - height_at(center))
		var line := PackedVector2Array([face_top])
		for k: int in range(1, 4):
			line.append(Vector2(x + rng.randf_range(-6.0, 6.0), lerpf(face_top.y, bottom, float(k) / 3.0)))
		_crack_lines.append(line)
	# Sorted with the rock's front pieces (in front of what stands behind it).
	_cracks = Node2D.new()
	_cracks.z_as_relative = false
	_cracks.z_index = face_z_index
	_cracks.transform = global_transform.affine_inverse() * Transform2D(0.0, Vector2(0.0, bottom + 1.0))
	_cracks.draw.connect(_draw_cracks)
	add_child(_cracks)
	_add_dust()
	cracked.emit()


func _draw_cracks() -> void:
	var to_local_space: Transform2D = _cracks.global_transform.affine_inverse()
	for line: PackedVector2Array in _crack_lines:
		var local: PackedVector2Array = to_local_space * line
		_cracks.draw_polyline(local, crack_edge_color, crack_width + 1.6, false)
		_cracks.draw_polyline(local, crack_color, crack_width, false)


func _add_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position.round()) + 1
	var outline: PackedVector2Array = get_global_outline()
	var center := Vector2.ZERO
	for point: Vector2 in outline:
		center += point / outline.size()
	var rubble := Node2D.new()
	rubble.z_as_relative = false
	rubble.z_index = flat_z_index
	var pieces: Array[PackedVector2Array] = []
	for i: int in rubble_count:
		var at: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 60.0)
		var size: float = rng.randf_range(5.0, 14.0)
		var piece := PackedVector2Array()
		for k: int in 5:
			piece.append(at + Vector2.from_angle(TAU * float(k) / 5.0 + rng.randf_range(-0.3, 0.3)) * size * rng.randf_range(0.6, 1.0))
		pieces.append(piece)
	rubble.draw.connect(func() -> void:
		var inverse: Transform2D = rubble.global_transform.affine_inverse()
		for piece: PackedVector2Array in pieces:
			rubble.draw_colored_polygon(inverse * piece, rubble_color))
	# A sibling, so it stays when the pillar's own parts fade out.
	get_parent().add_child(rubble)


func _add_dust() -> void:
	var outline: PackedVector2Array = get_global_outline()
	var center := Vector2.ZERO
	for point: Vector2 in outline:
		center += point / outline.size()
	var dust := CPUParticles2D.new()
	dust.one_shot = true
	dust.amount = 40
	dust.lifetime = 1.2
	dust.explosiveness = 0.9
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 40.0
	dust.spread = 180.0
	dust.initial_velocity_min = 20.0
	dust.initial_velocity_max = 90.0
	dust.damping_min = 40.0
	dust.damping_max = 80.0
	dust.gravity = Vector2(0.0, 15.0)
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 4.5
	dust.color = dust_color
	dust.z_as_relative = false
	dust.z_index = face_z_index + 1
	dust.finished.connect(dust.queue_free)
	get_parent().add_child(dust)
	dust.global_position = center
	dust.emitting = true


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and sound_name != "":
		audio.play(sound_name, global_position)
