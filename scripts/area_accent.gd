class_name AreaAccent
extends Node2D
## A soft, muted colour accent on the floor (teal, violet, warm amber near a
## vent): a large disc fading out to its edge, drawn over the floor and under
## the rocks and shadows. Lit like the floor, so it only shows near a light
## and the far rooms stay dark. Placed by the LevelBuilder (one per room,
## and one around each landmark with an accent).

## Colour of the accent; its alpha is the strength in the middle.
@export var accent: Color = Color(0.1, 0.32, 0.32, 0.3)
@export var radius: float = 700.0
## Rings from the middle out (more = a smoother fade).
@export var rings: int = 6
@export var segments: int = 40
## Over the floor (-4), under the ground shadows (-2).
@export var accent_z_index: int = -3


func _ready() -> void:
	z_as_relative = false
	z_index = accent_z_index


func _draw() -> void:
	if accent.a <= 0.0:
		return
	for ring: int in rings:
		var r0: float = radius * ring / rings
		var r1: float = radius * (ring + 1) / rings
		# Smooth fall-off (smoothstep) from the middle to the edge.
		var inner := Color(accent, accent.a * _falloff(float(ring) / rings))
		var outer := Color(accent, accent.a * _falloff(float(ring + 1) / rings))
		for k: int in segments:
			var d0: Vector2 = Vector2.from_angle(TAU * k / segments)
			var d1: Vector2 = Vector2.from_angle(TAU * (k + 1) / segments)
			if ring == 0:
				draw_polygon(PackedVector2Array([Vector2.ZERO, d0 * r1, d1 * r1]), PackedColorArray([inner, outer, outer]))
			else:
				draw_polygon(PackedVector2Array([d0 * r0, d0 * r1, d1 * r1, d1 * r0]), PackedColorArray([inner, outer, outer, inner]))


func _falloff(t: float) -> float:
	var s: float = 1.0 - t
	return s * s * (3.0 - 2.0 * s)
