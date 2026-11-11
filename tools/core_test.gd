class_name CoreTest
extends Node3D
## Phase A play-test stage for the 3D core (run with F6): three real Ocean
## rooms (their 2D floor plans pulled up into rock at the 2D heights) with the
## real Player (Echo + Guardian scenes), SharedCamera, Sonar, Darkness,
## MarineSnow, ViewCutaway and the audio, plus two stand-ins from proto3d/
## until their real classes are ported: the creature and the sword.
## Keys: C = rock cut-away on / off, T = rock height normal (the 2D game's
## heights) / tall (to see the cut-away at its worst), R = both players back
## to the start (revived). Oxygen does not drain here (no stations yet).
## "-- shots <folder>" saves pictures of the cut-away (CoreTestShots).

const ECHO_SCENE: PackedScene = preload("res://scenes/echo.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://scenes/guardian.tscn")
const SURFACE_SHADER: Shader = preload("res://shaders/rock_surface.gdshader")
const PING_STREAM: AudioStream = preload("res://assets/audio/sfx/pulse_ping.wav")
const TICK_STREAM: AudioStream = preload("res://assets/audio/sonar_tick.wav")

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
## Rock heights are multiplied by this in "tall" mode (key T).
@export var tall_rock_scale: float = 2.6
@export var layout_seed: int = 7

@export_group("Look")
@export var floor_color: Color = Color(0.15, 0.19, 0.25)
@export var rock_color: Color = Color(0.24, 0.29, 0.36)
@export var sonar_color: Color = Color(0.25, 0.85, 1.0)
## How strongly the pulse lights flat ground compared with rock.
@export var floor_fill_energy: float = 0.07
@export var rock_fill_energy: float = 0.24

var sonar: Sonar
var camera: SharedCamera
var cutaway: ViewCutaway
var echo: Player
var guardian: Player
var creature: ProtoCreature
## Spawn markers of each room in world units, by marker name ("Player1"...),
## one dictionary per placement.
var room_markers: Array[Dictionary] = []
var _cut_radius: float = 0.0
var _tall: bool = false
var _rocks: Node3D
var _rock_material: ShaderMaterial
## Every rock as [outline in pixels, height in pixels], to build it again.
var _rock_plans: Array[Array] = []
var _info: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = layout_seed
	_add(Darkness.new(), "Darkness")
	_add(AudioDirector.new(), "AudioDirector")
	sonar = _add(Sonar.new(), "Sonar") as Sonar
	var sonar_audio := SonarAudio.new()
	sonar_audio.sonar = sonar
	sonar_audio.ping_stream = PING_STREAM
	sonar_audio.tick_stream = TICK_STREAM
	_add(sonar_audio, "SonarAudio")
	camera = _add(SharedCamera.new(), "SharedCamera") as SharedCamera
	cutaway = _add(ViewCutaway.new(), "ViewCutaway") as ViewCutaway
	_cut_radius = cutaway.radius
	_add(MarineSnow.new(), "MarineSnow")
	_build_rooms()
	_build_players()
	_build_creature()
	_build_info()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() >= 2 and arguments[0] == "shots":
		var shots := CoreTestShots.new()
		shots.test = self
		shots.folder = arguments[1]
		add_child(shots)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_C:
			set_cutaway(cutaway.radius <= 0.0)
		KEY_T:
			set_tall_rocks(not _tall)
		KEY_R:
			reset_players()


func set_cutaway(enabled: bool) -> void:
	cutaway.radius = _cut_radius if enabled else 0.0


## Builds every rock again, at the 2D game's heights or much taller.
func set_tall_rocks(enabled: bool) -> void:
	_tall = enabled
	if _rocks:
		_rocks.queue_free()
	_rocks = Node3D.new()
	_rocks.name = "Rocks"
	add_child(_rocks)
	var height_scale: float = tall_rock_scale if _tall else 1.0
	for plan: Array in _rock_plans:
		var outline := PackedVector2Array()
		for point: Vector2 in plan[0] as PackedVector2Array:
			outline.append(point * units_per_pixel)
		var height: float = (plan[1] as float) * units_per_pixel * height_scale
		var body: StaticBody3D = RockMesher.rock_body(outline, height, rock_smooth_degrees, _rock_material)
		body.name = "Rock"
		_rocks.add_child(body, true)


func reset_players() -> void:
	for player: Player in [echo, guardian]:
		player.health.revive()
		player.health.refill()
		player.velocity = Vector3.ZERO
	echo.global_position = room_markers[0]["Player1"]
	guardian.global_position = room_markers[0]["Player2"]
	camera.snap_to_players()


func _process(_delta: float) -> void:
	var pulse := echo.get_node("Pulse") as PulseAbility
	_info.text = "CORE TEST   %d FPS\n" % int(Engine.get_frames_per_second()) \
		+ "[C] rock cut-away: %s      [T] rock height: %s      [R] back to the start\n" % [
			"ON" if cutaway.radius > 0.0 else "off", "TALL (x%.1f)" % tall_rock_scale if _tall else "normal (2D heights)"] \
		+ "%s      %s      pulse %s\n" % [_status(echo), _status(guardian),
			"ready" if pulse.is_ready() else "%.1f s" % pulse.cooldown_left] \
		+ "Echo: WASD + Space (pulse)   Guardian: arrows + Enter (sword)   or two gamepads\n" \
		+ "Hold the action button next to a downed partner to revive"


func _status(player: Player) -> String:
	if player.health.is_downed:
		return "%s: DOWN" % player.display_name
	return "%s: %.1f / %d" % [player.display_name, player.health.value, player.health.segment_count]


func _add(node: Node, node_name: String) -> Node:
	node.name = node_name
	add_child(node)
	return node


func _surface_material(color: Color, fill_energy: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("sonar_color", sonar_color)
	material.set_shader_parameter("fill_energy", fill_energy)
	sonar.register_material(material)
	return material


## Builds the rooms of PLACEMENTS from their 2D scenes.
func _build_rooms() -> void:
	var floor_material: ShaderMaterial = _surface_material(floor_color, floor_fill_energy)
	_rock_material = _surface_material(rock_color, rock_fill_energy)
	# Only rock is cut away, never the floor.
	cutaway.register_material(_rock_material)
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
			_rock_plans.append([polygon, lerpf(chunk.rock_height_min, chunk.rock_height_max, _rng.randf())])

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
			_rock_plans.append([_seal_outline(cell, i), room_wall_band_px * 0.5])
	set_tall_rocks(false)


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


func _build_players() -> void:
	echo = ECHO_SCENE.instantiate() as Player
	echo.position = room_markers[0]["Player1"]
	add_child(echo)
	guardian = GUARDIAN_SCENE.instantiate() as Player
	guardian.position = room_markers[0]["Player2"]
	add_child(guardian)
	for player: Player in [echo, guardian]:
		# No stations in this test: the oxygen stays full.
		player.pressure.drain_scale = 0.0
	var sword := ProtoSword.new()
	sword.name = "Sword"
	sword.player = guardian
	guardian.add_child(sword)


func _build_creature() -> void:
	creature = ProtoCreature.new()
	creature.name = "Creature"
	creature.position = room_markers[1]["Creature1"]
	creature.roam_center = _cell_center(PLACEMENTS[1][1] as Vector2i)
	creature.roam_extent = room_size_px * units_per_pixel * 0.5 - 4.0
	creature.camera = camera
	add_child(creature)


func _build_info() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Info"
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(16.0, 12.0)
	_info.modulate = Color(0.6, 0.8, 0.9, 0.7)
	layer.add_child(_info)


## 2D pixels (x right, y down) to the 3D floor (x right, z towards the camera
## at yaw 0), so north stays "up".
func _to_world(point_px: Vector2) -> Vector3:
	return Vector3(point_px.x, 0.0, point_px.y) * units_per_pixel


func _cell_center(cell: Vector2i) -> Vector3:
	return _to_world((Vector2(cell) + Vector2(0.5, 0.5)) * room_size_px)
