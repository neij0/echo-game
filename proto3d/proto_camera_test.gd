class_name ProtoCameraTest
extends ProtoRoom
## Phase A, day 1: choose the camera by playing. Three real Ocean rooms (their
## 2D floor plans pulled up into 3D rock, at the 2D heights) joined in a row,
## and keys to switch the camera while playing:
##   1 = yaw 45 (isometric)      2 = yaw 0 (north is up, like the 2D game)
##   3 = pitch 45 / 55           4 = speed compensation 100 / 50 / 0 %
##   5 = keys follow the walls / keys give the exact screen direction
##   gamepad: Y = yaw, LB = pitch, RB = compensation
## Run with F6. "-- shots <folder>" saves pictures of both views and prints
## the speeds per direction (ProtoCameraShots).

## Room scene, grid cell, clockwise quarter turns.
const PLACEMENTS: Array[Array] = [
	["res://scenes/chunks/ocean/room_tunnel_bend.tscn", Vector2i(0, 0), 0],
	["res://scenes/chunks/ocean/room_kelp_maze.tscn", Vector2i(1, 0), 0],
	["res://scenes/chunks/ocean/room_tunnel_straight.tscn", Vector2i(2, 0), 1],
]
## Opening bits as in RoomGrid.Side: north, east, south, west.
const SIDES: Array[int] = [1, 2, 4, 8]
const SIDE_STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const OPPOSITE: Array[int] = [4, 8, 1, 2]

@export_group("Floor Plans")
## World units per pixel of the 2D rooms (50 px = 1 unit).
@export var units_per_pixel: float = 0.02
## The Ocean WorldConfig's room values, in pixels.
@export var room_size_px: float = 1600.0
@export var room_wall_band_px: float = 100.0
@export var room_door_width_px: float = 360.0
## How much wider than the doorway a seal is on each side, in pixels.
@export var seal_overlap_px: float = 30.0
## Corners sharper than this get a hard edge (and a sonar line).
@export var rock_smooth_degrees: float = 40.0

@export_group("Views")
@export var isometric_yaw: float = 45.0
@export var flat_yaw: float = 0.0
@export var pitches: PackedFloat32Array = PackedFloat32Array([45.0, 55.0])
@export var compensations: PackedFloat32Array = PackedFloat32Array([1.0, 0.5, 0.0])
## The marine snow drifts in a box of this size round the camera's focus.
@export var snow_box_size: float = 44.0
@export var snow_count: int = 2200

## Spawn markers of each room in world units, by marker name ("Player1"...),
## one dictionary per placement.
var room_markers: Array[Dictionary] = []
var _pitch_index: int = 0
var _compensation_index: int = 0


func _ready() -> void:
	# ProtoRoom builds everything (its _build_room is replaced below).
	super()
	var maze_center: Vector3 = _cell_center(PLACEMENTS[1][1] as Vector2i)
	creature.roam_center = maze_center
	creature.roam_extent = room_size_px * units_per_pixel * 0.5 - 4.0
	camera.yaw_degrees = isometric_yaw
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "shots":
		var shots := ProtoCameraShots.new()
		shots.test = self
		shots.folder = arguments[1]
		add_child(shots)


func _process(delta: float) -> void:
	super(delta)
	var focus: Vector3 = camera.get_focus()
	_snow.global_position = Vector3(focus.x, snow_height * 0.5, focus.z)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1:
				camera.yaw_degrees = isometric_yaw
			KEY_2:
				camera.yaw_degrees = flat_yaw
			KEY_3:
				_next_pitch()
			KEY_4:
				_next_compensation()
			KEY_5:
				camera.keys_follow_walls = not camera.keys_follow_walls
	var button := event as InputEventJoypadButton
	if button and button.pressed:
		match button.button_index:
			JOY_BUTTON_Y:
				camera.yaw_degrees = flat_yaw if is_equal_approx(camera.yaw_degrees, isometric_yaw) else isometric_yaw
			JOY_BUTTON_LEFT_SHOULDER:
				_next_pitch()
			JOY_BUTTON_RIGHT_SHOULDER:
				_next_compensation()


func _next_pitch() -> void:
	_pitch_index = (_pitch_index + 1) % pitches.size()
	camera.pitch_degrees = pitches[_pitch_index]


func _next_compensation() -> void:
	_compensation_index = (_compensation_index + 1) % compensations.size()
	camera.speed_compensation = compensations[_compensation_index]


func _info_text() -> String:
	return "CAMERA TEST   %d FPS\n" % int(Engine.get_frames_per_second()) \
		+ "[1] yaw 45 (isometric)   [2] yaw 0 (north up, like 2D)        now: yaw %d\n" % int(camera.yaw_degrees) \
		+ "[3] pitch: %d      [4] speed compensation: %d %%      [5] keys: %s\n" % [
			int(camera.pitch_degrees), int(camera.speed_compensation * 100.0),
			"follow the walls" if camera.keys_follow_walls else "exact screen direction"] \
		+ "Gamepad: Y = yaw, LB = pitch, RB = compensation\n" \
		+ "Echo: WASD + Space (pulse)   Guardian: arrows + Enter (sword)   or two gamepads"


## Builds the rooms of PLACEMENTS from their 2D scenes instead of the
## prototype's box room.
func _build_room() -> void:
	# The snow box follows the camera here, so it only has to cover the view.
	room_size = snow_box_size
	snow_amount = snow_count
	var floor_material: ShaderMaterial = _surface_material(floor_color, floor_fill_energy)
	var rock_material: ShaderMaterial = _surface_material(rock_color, rock_fill_energy)
	var room_units: float = room_size_px * units_per_pixel
	var openings: Dictionary[Vector2i, int] = {}

	for placement: Array in PLACEMENTS:
		var cell: Vector2i = placement[1]
		var chunk := (load(placement[0] as String) as PackedScene).instantiate() as LevelChunk
		chunk.rotate_quarters(placement[2] as int, room_size_px)
		chunk.position = Vector2(cell) * room_size_px
		openings[cell] = chunk.openings

		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(room_units, room_units)
		var floor_instance := MeshInstance3D.new()
		floor_instance.name = "Floor"
		floor_instance.mesh = floor_mesh
		floor_instance.material_override = floor_material
		floor_instance.position = _cell_center(cell)
		add_child(floor_instance, true)

		for polygon: PackedVector2Array in chunk.get_wall_polygons():
			var height: float = lerpf(chunk.rock_height_min, chunk.rock_height_max, _rng.randf())
			_add_rock(polygon, height, rock_material)

		var markers: Dictionary = {}
		for marker: Marker2D in chunk.get_spawn_markers(""):
			markers[String(marker.name)] = _to_world(chunk.transform * marker.position)
		room_markers.append(markers)
		chunk.free()

	# A doorway with no matching doorway next to it is closed with rock.
	for cell: Vector2i in openings:
		for i: int in SIDES.size():
			if openings[cell] & SIDES[i] == 0:
				continue
			var next: Vector2i = cell + SIDE_STEPS[i]
			if openings.has(next) and openings[next] & OPPOSITE[i] != 0:
				continue
			_add_rock(_seal_outline(cell, i), room_wall_band_px * 0.5, rock_material)

	echo_start = room_markers[0]["Player1"]
	guardian_start = room_markers[0]["Player2"]
	creature_start = room_markers[1]["Creature1"]


func _add_rock(outline_px: PackedVector2Array, height_px: float, material: Material) -> void:
	var outline := PackedVector2Array()
	for point: Vector2 in outline_px:
		outline.append(point * units_per_pixel)
	var body: StaticBody3D = ProtoPlanMesher.rock_body(outline, height_px * units_per_pixel, rock_smooth_degrees, material)
	body.name = "Rock"
	add_child(body, true)


## The rock that fills the doorway on side index i of a cell, in pixels.
func _seal_outline(cell: Vector2i, side_index: int) -> PackedVector2Array:
	var half_door: float = room_door_width_px * 0.5 + seal_overlap_px
	var middle: float = room_size_px * 0.5
	var band: float = room_wall_band_px
	var rect: Rect2
	match side_index:
		0:
			rect = Rect2(middle - half_door, 0.0, half_door * 2.0, band)
		1:
			rect = Rect2(room_size_px - band, middle - half_door, band, half_door * 2.0)
		2:
			rect = Rect2(middle - half_door, room_size_px - band, half_door * 2.0, band)
		_:
			rect = Rect2(0.0, middle - half_door, band, half_door * 2.0)
	rect.position += Vector2(cell) * room_size_px
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


## 2D pixels (x right, y down) to the 3D floor (x right, z towards the camera
## at yaw 0), so north stays "up".
func _to_world(point_px: Vector2) -> Vector3:
	return Vector3(point_px.x, 0.0, point_px.y) * units_per_pixel


func _cell_center(cell: Vector2i) -> Vector3:
	return _to_world((Vector2(cell) + Vector2(0.5, 0.5)) * room_size_px)
