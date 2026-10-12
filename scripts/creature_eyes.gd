class_name CreatureEyes
extends Node2D
## Two faint glowing eyes that fade in when the hidden creature is very close to
## the nearest player (no pulse needed), or faintly when it is a silhouette in
## the Echo's light (Creature.silhouette_ratio), looking where it is moving.
## Must live on a CanvasLayer with follow_viewport_enabled, so the world's
## CanvasModulate darkness does not dim it.

@export var creature: Creature

@export_group("Range")
## Eyes start to fade in at this distance from the player...
@export var show_distance: float = 180.0
## ...and are fully visible at this distance.
@export var full_distance: float = 110.0
## Hide the eyes when a rock is between the creature and the player.
@export var require_line_of_sight: bool = true
@export_flags_2d_physics var wall_mask: int = 1

@export_group("Look")
@export var color: Color = Color(1.0, 0.75, 0.3)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 2.5
## Maximum opacity, kept low so they stay "faint".
@export_range(0.0, 1.0) var max_alpha: float = 0.6
@export var eye_radius: float = 2.5
## Distance between the two eyes.
@export var eye_spacing: float = 9.0
## How far forward from the creature's centre the eyes sit.
@export var eye_forward: float = 9.0
## How fast the eyes fade in/out (alpha per second).
@export var fade_speed: float = 4.0
## Eyes of a creature seen as a silhouette in the Echo's light (between her
## full reveal and the edge of her light): this share of max_alpha at full
## silhouette, so they stay faint.
@export_range(0.0, 1.0) var silhouette_eye_share: float = 0.45

var _alpha: float = 0.0
var _visible_target: float = 0.0
var _facing: Vector2 = Vector2.RIGHT


func _physics_process(_delta: float) -> void:
	if creature == null:
		return
	var player: Player = creature.get_nearest_player()
	if player == null:
		_visible_target = 0.0
		return
	var player_position: Vector2 = player.global_position
	var distance: float = creature.global_position.distance_to(player_position)
	_visible_target = clampf((show_distance - distance) / (show_distance - full_distance), 0.0, 1.0)
	if _visible_target > 0.0 and require_line_of_sight:
		var query := PhysicsRayQueryParameters2D.create(creature.global_position, player_position, wall_mask)
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			_visible_target = 0.0
	_visible_target = maxf(_visible_target, creature.silhouette_ratio * silhouette_eye_share)


func _process(delta: float) -> void:
	if creature == null:
		return
	global_position = creature.global_position
	if creature.velocity.length() > 1.0:
		_facing = creature.velocity.normalized()
	_alpha = move_toward(_alpha, _visible_target, fade_speed * delta)
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var glow := Color(color.r * energy, color.g * energy, color.b * energy, _alpha * max_alpha)
	var side: Vector2 = _facing.orthogonal() * eye_spacing * 0.5
	var forward: Vector2 = _facing * eye_forward
	draw_circle(forward + side, eye_radius, glow)
	draw_circle(forward - side, eye_radius, glow)
