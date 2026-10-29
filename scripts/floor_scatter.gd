class_name FloorScatter
extends Node2D
## Small things lying on a room's floor: pebbles, little stone clusters,
## shell fragments and bits of dead coral, so the same room type looks
## different in every level (the LevelBuilder places one per room, its spots
## and kinds picked by the level and the cell, on open floor). Drawn once,
## low contrast, over the floor and under the shadows, lit like the floor.

## Spots (this node's space) and the colour of the floor they lie on (set by
## the LevelBuilder before _ready).
var spots := PackedVector2Array()
var floor_color: Color = Color(0.2, 0.3, 0.36)
var scatter_seed: int = 0

## Shares of the kinds (the rest are dead coral bits).
@export_range(0.0, 1.0) var pebble_share: float = 0.45
@export_range(0.0, 1.0) var cluster_share: float = 0.25
@export_range(0.0, 1.0) var shell_share: float = 0.18
@export var pebble_size: Vector2 = Vector2(2.5, 6.0)
## How much darker / lighter than the floor (low contrast).
@export_range(0.0, 1.0) var stone_darken: float = 0.3
@export_range(0.0, 1.0) var shell_lift: float = 0.22
@export var shell_tint: Color = Color(0.55, 0.5, 0.45)
@export var coral_tint: Color = Color(0.45, 0.35, 0.4)
## Over the floor (-4) and the accents (-3, drawn before), under the shadows (-2).
@export var scatter_z_index: int = -3


func _ready() -> void:
	z_as_relative = false
	z_index = scatter_z_index


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	var stone: Color = floor_color.darkened(stone_darken)
	for spot: Vector2 in spots:
		var kind: float = rng.randf()
		if kind < pebble_share:
			_pebble(spot, rng.randf_range(pebble_size.x, pebble_size.y), stone, rng)
		elif kind < pebble_share + cluster_share:
			for _k: int in rng.randi_range(3, 5):
				_pebble(spot + Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-6.0, 6.0)), rng.randf_range(pebble_size.x, pebble_size.y * 0.8), stone, rng)
		elif kind < pebble_share + cluster_share + shell_share:
			_shell(spot, rng.randf_range(3.5, 6.0), rng.randf() * TAU, floor_color.lerp(shell_tint, 0.35).lightened(shell_lift))
		else:
			_coral_bit(spot, rng.randf_range(6.0, 12.0), rng.randf() * TAU, floor_color.lerp(coral_tint, 0.35).lightened(shell_lift * 0.5))


func _pebble(at: Vector2, size: float, stone: Color, rng: RandomNumberGenerator) -> void:
	var shade: Color = stone.lightened(rng.randf_range(0.0, 0.15))
	draw_colored_polygon(Landmark.ellipse(at, Vector2(size, size * 0.65), 7, 0.15, rng.randf() * 10.0), shade)
	draw_line(at + Vector2(-size * 0.5, -size * 0.35), at + Vector2(size * 0.4, -size * 0.4), shade.lightened(0.18), 1.0)


## A fan-shaped shell fragment with ribs.
func _shell(at: Vector2, size: float, angle: float, shell: Color) -> void:
	var fan := PackedVector2Array([at])
	for k: int in 6:
		fan.append(at + Vector2.from_angle(angle - 0.8 + 1.6 * k / 5.0) * size * Vector2(1.0, 0.7))
	draw_colored_polygon(fan, shell)
	for k: int in 3:
		draw_line(at, at + Vector2.from_angle(angle - 0.5 + 0.5 * k) * size * Vector2(0.9, 0.63), shell.darkened(0.3), 1.0)


## A small broken coral twig lying flat.
func _coral_bit(at: Vector2, size: float, angle: float, coral: Color) -> void:
	var direction: Vector2 = Vector2.from_angle(angle) * Vector2(1.0, 0.6)
	var tip: Vector2 = at + direction * size
	draw_line(at, tip, coral, 2.0)
	draw_line(at.lerp(tip, 0.5), at.lerp(tip, 0.5) + direction.rotated(0.7) * size * 0.5, coral, 1.5)
	draw_line(at.lerp(tip, 0.7), at.lerp(tip, 0.7) + direction.rotated(-0.8) * size * 0.35, coral, 1.2)
