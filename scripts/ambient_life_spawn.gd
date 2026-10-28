class_name AmbientLifeSpawn
extends Resource
## One kind of harmless life a world scatters over its levels
## (WorldConfig.ambient_life): fish schools, jellyfish, crabs, sea plants.
## The LevelBuilder places them on open floor with the attempt's seed.

## An AmbientLife scene.
@export var scene: PackedScene
## How many per room (random in this range).
@export var per_room_min: int = 0
@export var per_room_max: int = 1
## True: only on open floor right next to rock (crabs, plants at a rock's foot).
@export var near_rock: bool = false
## Open floor needed around the spot (pixels, beyond the player clearance).
@export var free_radius: float = 40.0
