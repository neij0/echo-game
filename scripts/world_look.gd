class_name WorldLook
extends Resource
## The natural look of a world's levels (WorldConfig.look): the floor and rock
## materials (shaders with real textures; every look value is a parameter of
## these two materials, edited in the inspector), the rock kit the walls are
## dressed with (RockDresser) and how the pieces are placed. The LevelBuilder
## uses it while its natural_look is on; the classic look (plain shaders,
## extruded rock only) stays as it was.

@export_group("Materials")
## The sea floor (shaders/ocean_floor.gdshader).
@export var floor_material: ShaderMaterial
## Room rock and kit pieces (shaders/ocean_rock.gdshader).
@export var rock_material: ShaderMaterial
## How much darker the outer rock round the level is.
@export_range(0.0, 1.0) var outer_rock_darken: float = 0.25

@export_group("Rock Kit")
## A scene of rock meshes named rock_<kind>_<letter> (kinds: boulder, slab,
## column, spire, overhang, chunk, rubble, pebbles), each standing on the
## floor at its origin (tools/blender/make_rock_kit.py).
@export var rock_kit: PackedScene
## Chance weight of each kind along a wall of normal height.
@export var kind_weights: Dictionary = {"boulder": 4.0, "chunk": 2.5, "slab": 1.5, "overhang": 1.2, "column": 1.0, "spire": 0.5}
## Kinds that only stand where the rock is at least tall_height high.
@export var tall_kinds: PackedStringArray = PackedStringArray(["column", "spire", "overhang"])
@export var tall_height: float = 0.9
## Kinds used where the rock is lower than low_height (near doorways).
@export var low_kinds: PackedStringArray = PackedStringArray(["rubble", "slab"])
@export var low_height: float = 0.5

@export_group("Wall Pieces")
## Distance between two pieces along a rock's outline (world units).
@export var piece_spacing: float = 0.85
## Width scale of a piece (random in this range).
@export var piece_scale_min: float = 0.9
@export var piece_scale_max: float = 1.4
## A piece's top, as a share of the rock's height at that spot.
@export var piece_height_min: float = 0.85
@export var piece_height_max: float = 1.45
## Limits of a piece's height scale (so no piece is squashed flat or drawn
## out into a needle).
@export var height_scale_min: float = 0.3
@export var height_scale_max: float = 1.5
## How far inside the outline a piece's middle sits, as a share of its reach.
@export_range(0.0, 1.0) var piece_inset: float = 0.8
## The farthest a piece may stick out past the outline (the collision stays
## on the outline, so this is rock a body can swim through).
@export var piece_overhang: float = 0.22
## Largest lean of a piece (degrees).
@export var piece_tilt: float = 9.0

@export_group("Top Pieces")
## Pieces lying on top of wide rock: distance between two (0 = none), how
## much of one is sunk into the rock, and the clear rock it needs round it.
@export var top_spacing: float = 1.1
@export_range(0.0, 1.0) var top_sunk: float = 0.5
@export var top_clearance: float = 0.4
@export var top_kinds: PackedStringArray = PackedStringArray(["slab", "boulder", "chunk"])

@export_group("Pebbles")
## Small stones on the sand along the walls (never solid): one cluster about
## every pebble_spacing units, up to pebble_reach from the rock.
@export var pebble_spacing: float = 3.0
@export var pebble_reach: float = 0.8
@export var pebble_scale_min: float = 0.6
@export var pebble_scale_max: float = 1.3

@export_group("Silt Haze")
## A thin, drifting haze over the floor that the lights shine into (a
## FogVolume): density (0 = none), how high it reaches, the size of its
## clouds and how fast they drift.
@export var haze_density: float = 0.06
@export var haze_height: float = 1.6
@export var haze_cloud_size: float = 7.0
@export var haze_drift: Vector2 = Vector2(0.12, 0.05)
@export var haze_color: Color = Color(0.5, 0.68, 0.85)

var _pieces: Array[Dictionary] = []
var _kit_read: bool = false


## The kit's pieces: name, kind, mesh, height and reach (the farthest it
## extends sideways from its origin), read once from rock_kit.
func get_pieces() -> Array[Dictionary]:
	if _kit_read:
		return _pieces
	_kit_read = true
	if rock_kit == null:
		return _pieces
	var root: Node = rock_kit.instantiate()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var parts: PackedStringArray = String(instance.name).split("_")
		if instance.mesh == null or parts.size() < 2:
			continue
		var bounds: AABB = instance.mesh.get_aabb()
		_pieces.append({
			"name": String(instance.name),
			"kind": parts[1],
			"mesh": instance.mesh,
			"height": bounds.end.y,
			"reach": maxf(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))),
		})
	root.free()
	return _pieces


## The pieces of the given kinds.
func pieces_of(kinds: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for piece: Dictionary in get_pieces():
		if String(piece["kind"]) in kinds:
			result.append(piece)
	return result
