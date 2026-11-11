class_name CreatureEyes
extends Node3D
## Two faint glowing eyes that fade in when the hidden creature is very close to
## the nearest player (no pulse needed), or faintly when it is a silhouette in
## the Echo's light (Creature.silhouette_ratio), and clearly when the Guardian's
## close sense feels it (Creature.sense_ratio), looking where it is moving.
## They flare up (brighter, bigger, fully visible) during the creature's lunge
## wind-up: the warning that a lunge is coming.
## Whether they show is decided on the floor (distance, rock between the
## creature and the player); once they show, they are drawn over rock too, so
## the camera never hides a warning the players should see (plan section 5.3).

@export var creature: Creature

@export_group("Range")
## Eyes start to fade in at this distance from the player...
@export var show_distance: float = 3.6
## ...and are fully visible at this distance.
@export var full_distance: float = 2.2
## Hide the eyes when a rock is between the creature and the player.
@export var require_line_of_sight: bool = true
## Height of the line-of-sight ray (rock lower than this does not hide them).
@export var sight_height: float = 0.4
@export_flags_3d_physics var wall_mask: int = 1

@export_group("Look")
@export var color: Color = Color(1.0, 0.75, 0.3)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 2.5
## Maximum opacity, kept low so they stay "faint".
@export_range(0.0, 1.0) var max_alpha: float = 0.6
@export var eye_radius: float = 0.05
## Distance between the two eyes.
@export var eye_spacing: float = 0.18
## How far forward from the body's centre the eyes sit (share of its radius),
## and how high (share of its height).
@export var eye_forward: float = 0.9
@export var eye_height: float = 0.62
## How fast the eyes fade in/out (alpha per second).
@export var fade_speed: float = 4.0
## Eyes of a creature seen as a silhouette in the Echo's light: this share of
## max_alpha at full silhouette, so they stay faint.
@export_range(0.0, 1.0) var silhouette_eye_share: float = 0.45
## Eyes of a creature felt by the Guardian's close sense: this share of
## max_alpha (high, so he always sees what is about to hit him).
@export_range(0.0, 1.0) var sensed_eye_share: float = 1.0
## Lunge flare (Creature.get_lunge_flare): brightness and size multipliers at
## its peak, and its colour.
@export var flare_energy: float = 3.0
@export var flare_size: float = 1.6
@export var flare_color: Color = Color(1.0, 0.45, 0.25)

var _alpha: float = 0.0
var _visible_target: float = 0.0
var _flare: float = 0.0
var _eyes: Array[MeshInstance3D] = []
var _material: StandardMaterial3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.no_depth_test = true
	_material.disable_fog = true
	_material.render_priority = 11
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	for i: int in 2:
		var eye := MeshInstance3D.new()
		eye.mesh = sphere
		eye.material_override = _material
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(eye)
		_eyes.append(eye)


## How visible the eyes are right now (0-1; tests).
func get_alpha() -> float:
	return _alpha


func _physics_process(_delta: float) -> void:
	if creature == null:
		return
	var player: Player = creature.get_nearest_player()
	if player == null:
		_visible_target = 0.0
		return
	var offset := Vector2(player.global_position.x - creature.global_position.x, player.global_position.z - creature.global_position.z)
	var distance: float = offset.length()
	_visible_target = clampf((show_distance - distance) / (show_distance - full_distance), 0.0, 1.0)
	if _visible_target > 0.0 and require_line_of_sight:
		var lift := Vector3(0.0, sight_height, 0.0)
		var query := PhysicsRayQueryParameters3D.create(creature.global_position + lift, player.global_position + lift, wall_mask)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_visible_target = 0.0
	_visible_target = maxf(_visible_target, creature.silhouette_ratio * silhouette_eye_share)
	_visible_target = maxf(_visible_target, creature.sense_ratio * sensed_eye_share)


func _process(delta: float) -> void:
	if creature == null:
		return
	_alpha = move_toward(_alpha, _visible_target, fade_speed * delta)
	# The flare shows at once (no fade-in): it is a warning.
	_flare = creature.get_lunge_flare()
	_alpha = maxf(_alpha, _flare)
	var shown: bool = _alpha > 0.0
	for eye: MeshInstance3D in _eyes:
		eye.visible = shown
	if not shown:
		return
	var tint: Color = color.lerp(flare_color, _flare)
	var boost: float = energy * lerpf(1.0, flare_energy, _flare)
	_material.albedo_color = Color(tint.r * boost, tint.g * boost, tint.b * boost, minf(_alpha * lerpf(max_alpha, 1.0, _flare), 1.0))
	var radius: float = eye_radius * lerpf(1.0, flare_size, _flare)
	var forward: Vector3 = creature.facing
	var side: Vector3 = forward.cross(Vector3.UP) * eye_spacing * 0.5
	var center: Vector3 = creature.get_global_transform_interpolated().origin \
		+ forward * creature.body_radius * eye_forward + Vector3(0.0, creature.body_height * eye_height, 0.0)
	_eyes[0].global_position = center + side
	_eyes[1].global_position = center - side
	for eye: MeshInstance3D in _eyes:
		eye.scale = Vector3.ONE * radius
