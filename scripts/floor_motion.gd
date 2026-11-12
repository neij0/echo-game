class_name FloorMotion
extends RefCounted
## Moves a body on the floor plane only (players, creatures, the wall test's
## probes): everything swims at y = 0 and the rock stops it like a wall. The
## rock's colliders are upright and taller than any body (RockMesher.
## add_colliders), so nothing should ever lift a body; if a contact still
## does, it is put back on the floor at once.


static func move(body: CharacterBody3D) -> void:
	body.velocity.y = 0.0
	body.move_and_slide()
	if body.global_position.y != 0.0:
		body.global_position.y = 0.0
