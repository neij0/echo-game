class_name CapsuleBody
extends MeshInstance3D
## PLACEHOLDER body of a player until the characters get their 3D models
## (Phase C): a dark capsule of the player's size with a glowing rim in the
## character's colour, and the same outline drawn through rock when rock
## covers it. Downed: it sinks and the rim dims. Follows the sword's small body
## lunge per hit (SwordAbility.get_lunge_offset), if the player has a sword.

const BODY_SHADER: Shader = preload("res://shaders/character.gdshader")
const SEE_THROUGH_SHADER: Shader = preload("res://shaders/see_through.gdshader")

@export var player: Player
@export var color: Color = Color(0.3, 0.9, 1.0)
@export var rim_energy: float = 2.2
## Downed: share of the rim's glow that is left, and of the body's height.
@export_range(0.0, 1.0) var downed_rim_share: float = 0.25
@export_range(0.1, 1.0) var downed_height_share: float = 0.55
## How fast it sinks and comes back up.
@export var change_speed: float = 6.0

var _material: ShaderMaterial
var _downed: float = 0.0


func _ready() -> void:
	var see_through := ShaderMaterial.new()
	see_through.shader = SEE_THROUGH_SHADER
	see_through.set_shader_parameter("outline_color", color)
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("body_color", color.darkened(0.9))
	_material.set_shader_parameter("rim_color", color)
	_material.set_shader_parameter("rim_energy", rim_energy)
	_material.next_pass = see_through
	var capsule := CapsuleMesh.new()
	capsule.radius = player.body_radius if player else 0.3
	capsule.height = player.body_height if player else 1.0
	mesh = capsule
	material_override = _material
	position.y = capsule.height * 0.5


func _process(delta: float) -> void:
	if player == null or player.health == null:
		return
	var target: float = 1.0 if player.health.is_downed else 0.0
	_downed = move_toward(_downed, target, change_speed * delta)
	var height_share: float = lerpf(1.0, downed_height_share, _downed)
	scale = Vector3(1.0, height_share, 1.0)
	var sword := player.get_node_or_null("Sword") as SwordAbility
	var lunge: Vector3 = sword.get_lunge_offset() if sword else Vector3.ZERO
	position = lunge + Vector3(0.0, player.body_height * 0.5 * height_share, 0.0)
	_material.set_shader_parameter("rim_energy", rim_energy * lerpf(1.0, downed_rim_share, _downed))
