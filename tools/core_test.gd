class_name CoreTest
extends Node3D
## Phase A play-test stage for the 3D core (run with F6): three real Ocean
## rooms (their 2D floor plans pulled up into rock at the 2D heights) with the
## real Player (Echo + Guardian scenes: sword, close sense, distress pulse,
## goal arrow, rings), real creatures on a navigation mesh baked from the
## floor plans, SharedCamera, Sonar, Darkness, MarineSnow, ViewCutaway,
## partner mending, Depth Awareness and the audio. Two test shards and a test
## exit give the goal arrow something to point at (walk onto a shard to take it).
## Keys: C = rock cut-away on / off, T = rock height normal / tall, M = Calm /
## Challenge, I = physics interpolation on / off, F = freeze and hide every
## creature (to try mending and the other partner features calmly), R = back
## to the start (revived, shards back). Killed creatures come back after respawn_time, on
## the Creature marker furthest from the players. Oxygen does not drain here.
## "-- shots <folder>" saves pictures, prints checks and the FPS benchmark
## (CoreTestShots).

const ECHO_SCENE: PackedScene = preload("res://scenes/echo.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://scenes/guardian.tscn")
const CREATURE_SCENE: PackedScene = preload("res://scenes/creature.tscn")
const UNKILLABLE_SCENE: PackedScene = preload("res://scenes/creature_unkillable.tscn")
const SURFACE_SHADER: Shader = preload("res://shaders/rock_surface.gdshader")
const PING_STREAM: AudioStream = preload("res://assets/audio/sfx/pulse_ping.wav")
const TICK_STREAM: AudioStream = preload("res://assets/audio/sonar_tick.wav")

## Room scene, grid cell, clockwise quarter turns.
const PLACEMENTS: Array[Array] = [
	["res://scenes/chunks/ocean/room_tunnel_bend.tscn", Vector2i(0, 0), 0],
	["res://scenes/chunks/ocean/room_kelp_maze.tscn", Vector2i(1, 0), 0],
	["res://scenes/chunks/ocean/room_tunnel_straight.tscn", Vector2i(2, 0), 1],
]
## Creatures: room index, marker name, unkillable.
const CREATURES: Array[Array] = [
	[1, "Creature1", false],
	[1, "Creature3", false],
	[1, "Creature4", true],
	[2, "Creature1", false],
]
## Test shards (room index, marker) and the test exit (room index, marker).
const SHARDS: Array[Array] = [[1, "Shard1"], [2, "Shard1"]]
const EXIT: Array = [2, "Goal"]
## The groups a frozen creature leaves (key F).
const FROZEN_GROUPS: Array[String] = ["creatures", "sonar_targets", "cutaway_targets"]
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

@export_group("Navigation")
## The 2D game baked for 26 px (0.52 units) round every rock. The radius must
## be a whole number of cells (the bake rounds it up): 0.5 = 4 x 0.125.
@export var agent_radius: float = 0.5
@export var cell_size: float = 0.125
@export var cell_height: float = 0.125

@export_group("Creatures")
@export var respawn_time: float = 4.0

@export_group("Test Shards")
## A player this close takes a shard.
@export var pickup_distance: float = 0.8
@export var shard_color: Color = Color(0.55, 0.95, 1.0)
@export var exit_color: Color = Color(1.0, 0.82, 0.35)

@export_group("Look")
@export var floor_color: Color = Color(0.15, 0.19, 0.25)
@export var rock_color: Color = Color(0.24, 0.29, 0.36)

var sonar: Sonar
var camera: SharedCamera
var cutaway: ViewCutaway
var awareness: DepthAwareness
var mending: PartnerMending
var echo: Player
var guardian: Player
## Spawn markers of each room in world units, by marker name ("Player1"...),
## one dictionary per placement.
var room_markers: Array[Dictionary] = []
## Seconds the last navigation bake took.
var bake_seconds: float = 0.0
var challenge_mode: bool = false
## Key F: every creature frozen, hidden and out of every group (nothing sees it).
var creatures_frozen: bool = false
var _frozen: Array[Creature] = []
var _cut_radius: float = 0.0
var _tall: bool = false
var _rocks: Node3D
var _rock_material: ShaderMaterial
## Every rock as [outline in pixels, height in pixels], to build it again.
var _rock_plans: Array[Array] = []
var _shards: Array[Node3D] = []
var _respawns: Array[Dictionary] = []
var _info: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = layout_seed
	_add(Darkness.new(), "Darkness")
	_add(AudioDirector.new(), "AudioDirector")
	awareness = _add(DepthAwareness.new(), "DepthAwareness") as DepthAwareness
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
	mending = _add(PartnerMending.new(), "PartnerMending") as PartnerMending
	_build_rooms()
	_bake_navigation()
	_build_players()
	for entry: Array in CREATURES:
		spawn_creature(entry[0] as int, entry[1] as String, entry[2] as bool)
	_build_goals()
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
		KEY_M:
			set_challenge_mode(not challenge_mode)
		KEY_I:
			get_tree().physics_interpolation = not get_tree().physics_interpolation
		KEY_F:
			set_creatures_frozen(not creatures_frozen)
		KEY_R:
			reset_players()


func set_cutaway(enabled: bool) -> void:
	cutaway.radius = _cut_radius if enabled else 0.0


## Freezes and hides every creature (it forgets the players and leaves its
## groups, so mending, the music and the sonar ignore it), or brings them back.
func set_creatures_frozen(frozen: bool) -> void:
	creatures_frozen = frozen
	if frozen:
		for node: Node in get_tree().get_nodes_in_group("creatures"):
			_freeze(node as Creature)
		return
	for creature: Creature in _frozen:
		if not is_instance_valid(creature):
			continue
		for group: String in FROZEN_GROUPS:
			creature.add_to_group(group)
		creature.visible = true
		creature.process_mode = Node.PROCESS_MODE_INHERIT
		_set_sounds_paused(creature, false)
		creature.reset_physics_interpolation()
	_frozen.clear()


func _freeze(creature: Creature) -> void:
	creature.forget_players()
	creature.velocity = Vector3.ZERO
	for group: String in FROZEN_GROUPS:
		creature.remove_from_group(group)
	creature.visible = false
	# Disabled: no processing, and its bodies leave the physics world (no touch).
	creature.process_mode = Node.PROCESS_MODE_DISABLED
	_set_sounds_paused(creature, true)
	_frozen.append(creature)


func _set_sounds_paused(node: Node, paused: bool) -> void:
	for child: Node in node.find_children("*", "AudioStreamPlayer3D", true, false):
		(child as AudioStreamPlayer3D).stream_paused = paused


## Calm / Challenge for every node that has values per mode.
func set_challenge_mode(enabled: bool) -> void:
	challenge_mode = enabled
	get_tree().call_group("mode_listeners", "set_challenge_mode", enabled)
	get_tree().call_group("creatures", "set_challenge_mode", enabled)
	for player: Player in [echo, guardian]:
		player.health.set_challenge_mode(enabled)


## Builds every rock again, at the 2D game's heights or much taller (the
## navigation mesh stays: only the heights change).
func set_tall_rocks(enabled: bool) -> void:
	_tall = enabled
	if _rocks:
		_rocks.queue_free()
	_rocks = Node3D.new()
	_rocks.name = "Rocks"
	add_child(_rocks)
	var height_scale: float = tall_rock_scale if _tall else 1.0
	for plan: Array in _rock_plans:
		var body: StaticBody3D = RockMesher.rock_body(_to_units(plan[0] as PackedVector2Array),
			(plan[1] as float) * units_per_pixel * height_scale, rock_smooth_degrees, _rock_material)
		body.name = "Rock"
		_rocks.add_child(body, true)


## Both players back at the start, revived and healed; the shards come back.
func reset_players() -> void:
	for player: Player in [echo, guardian]:
		player.health.revive()
		player.health.refill()
		player.velocity = Vector3.ZERO
	echo.global_position = room_markers[0]["Player1"]
	guardian.global_position = room_markers[0]["Player2"]
	for player: Player in [echo, guardian]:
		player.reset_physics_interpolation()
	camera.snap_to_players()
	for shard: Node3D in _shards:
		shard.visible = true
		shard.add_to_group("echo_shards")


## A creature on a room's marker (the unkillable type if asked).
func spawn_creature(room: int, marker: String, unkillable: bool) -> Creature:
	var creature := (UNKILLABLE_SCENE if unkillable else CREATURE_SCENE).instantiate() as Creature
	creature.position = room_markers[room][marker]
	add_child(creature)
	creature.set_challenge_mode(challenge_mode)
	creature.killed.connect(_on_creature_killed.bind(room, unkillable))
	if creatures_frozen:
		_freeze.call_deferred(creature)
	return creature


func _on_creature_killed(room: int, unkillable: bool) -> void:
	_respawns.append({"room": room, "unkillable": unkillable, "left": respawn_time})


func _process(delta: float) -> void:
	_update_respawns(delta)
	_update_shards()
	var pulse := echo.get_node("Pulse") as PulseAbility
	_info.text = "CORE TEST   %d FPS\n" % int(Engine.get_frames_per_second()) \
		+ "[C] cut-away: %s   [T] rocks: %s   [M] mode: %s   [I] interpolation: %s   [F] creatures: %s   [R] restart\n" % [
			"ON" if cutaway.radius > 0.0 else "off", "TALL" if _tall else "normal",
			"Challenge" if challenge_mode else "Calm", "ON" if get_tree().physics_interpolation else "off",
			"FROZEN" if creatures_frozen else "on"] \
		+ "%s      %s      pulse %s      awareness %d%%%s\n" % [_status(echo), _status(guardian),
			"ready" if pulse.is_ready() else "%.1f s" % pulse.cooldown_left, roundi(awareness.get_ratio() * 100.0),
			"      MENDING" if mending.is_mending else ""] \
		+ "creatures: %s      shards left: %d\n" % ["frozen" if creatures_frozen else _creature_states(), get_tree().get_nodes_in_group("echo_shards").size()] \
		+ "Echo: WASD + Space (pulse)   Guardian: arrows + Enter (sword)   or two gamepads\n" \
		+ "Hold the action button next to a downed partner to revive; a downed Echo's button sends a distress pulse"


func _status(player: Player) -> String:
	if player.health.is_downed:
		return "%s: DOWN" % player.display_name
	return "%s: %.1f / %d" % [player.display_name, player.health.value, player.health.segment_count]


func _creature_states() -> String:
	var states := PackedStringArray()
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature:
			states.append(creature.get_state_name().to_lower())
	return ", ".join(states) if not states.is_empty() else "none"


func _update_respawns(delta: float) -> void:
	for i: int in range(_respawns.size() - 1, -1, -1):
		_respawns[i]["left"] = float(_respawns[i]["left"]) - delta
		if float(_respawns[i]["left"]) > 0.0:
			continue
		var room: int = _respawns[i]["room"]
		var unkillable: bool = _respawns[i]["unkillable"]
		_respawns.remove_at(i)
		spawn_creature(room, _farthest_creature_marker(room), unkillable)


## The room's Creature marker furthest from both players.
func _farthest_creature_marker(room: int) -> String:
	var best: String = "Creature1"
	var best_distance: float = -1.0
	for marker: String in room_markers[room]:
		if not marker.begins_with("Creature"):
			continue
		var spot: Vector3 = room_markers[room][marker]
		var nearest: float = minf(spot.distance_to(echo.global_position), spot.distance_to(guardian.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best = marker
	return best


func _update_shards() -> void:
	for shard: Node3D in _shards:
		if not shard.is_in_group("echo_shards"):
			continue
		for player: Player in [echo, guardian]:
			if not player.health.is_downed and player.global_position.distance_to(shard.global_position) <= pickup_distance:
				shard.remove_from_group("echo_shards")
				shard.visible = false


## Every Echo pulse: Depth Awareness and the creatures hear it (the
## StageManager does this in the real game).
func _on_pulse_emitted(origin: Vector3, player: Player) -> void:
	awareness.add_pulse()
	get_tree().call_group("creatures", "hear_pulse", origin, player)


func _add(node: Node, node_name: String) -> Node:
	node.name = node_name
	add_child(node)
	return node


func _surface_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("base_color", color)
	sonar.register_material(material)
	var darkness: Darkness = Darkness.find(get_tree())
	if darkness:
		darkness.register_material(material)
	return material


## Builds the rooms of PLACEMENTS from their 2D scenes.
func _build_rooms() -> void:
	var floor_material: ShaderMaterial = _surface_material(floor_color)
	_rock_material = _surface_material(rock_color)
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


## One navigation mesh for the three rooms, baked from the floor plans.
func _bake_navigation() -> void:
	var floors: Array[PackedVector2Array] = []
	for placement: Array in PLACEMENTS:
		var corner: Vector2 = Vector2(placement[1] as Vector2i) * room_size_px
		floors.append(_to_units(PackedVector2Array([corner, corner + Vector2(room_size_px, 0.0),
			corner + Vector2(room_size_px, room_size_px), corner + Vector2(0.0, room_size_px)])))
	var rocks: Array[Dictionary] = []
	for plan: Array in _rock_plans:
		rocks.append({"outline": _to_units(plan[0] as PackedVector2Array), "height": (plan[1] as float) * units_per_pixel})
	var started: int = Time.get_ticks_usec()
	var navigation_mesh: NavigationMesh = NavigationBaker.bake(floors, rocks, agent_radius, cell_size, cell_height)
	bake_seconds = float(Time.get_ticks_usec() - started) / 1000000.0
	NavigationBaker.apply_to_map(get_world_3d().navigation_map, cell_size, cell_height)
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = navigation_mesh
	add_child(region)
	print("CORE TEST navigation: %d polygons, baked in %.2f s" % [navigation_mesh.get_polygon_count(), bake_seconds])


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
		player.pulse_emitted.connect(_on_pulse_emitted.bind(player))


## Placeholder shards and exit for the goal arrow (the real ones come in Phase B).
func _build_goals() -> void:
	for entry: Array in SHARDS:
		var shard: Node3D = _goal_marker("TestShard", room_markers[entry[0] as int][entry[1] as String], shard_color, 0.5)
		shard.add_to_group("echo_shards")
		_shards.append(shard)
	var exit: Node3D = _goal_marker("TestExit", room_markers[EXIT[0] as int][EXIT[1] as String], exit_color, 0.8)
	exit.add_to_group("level_exit")


func _goal_marker(node_name: String, at: Vector3, color: Color, light_energy: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = at
	add_child(holder, true)
	var gem := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 4
	mesh.rings = 2
	gem.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0)
	gem.material_override = material
	gem.position.y = 0.6
	holder.add_child(gem)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = light_energy
	light.omni_range = 1.6
	light.position.y = 0.7
	holder.add_child(light)
	return holder


func _build_info() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Info"
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(16.0, 12.0)
	_info.modulate = Color(0.6, 0.8, 0.9, 0.7)
	layer.add_child(_info)


func _to_units(points_px: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points_px:
		result.append(point * units_per_pixel)
	return result


## 2D pixels (x right, y down) to the 3D floor (x right, z towards the camera
## at yaw 0), so north stays "up".
func _to_world(point_px: Vector2) -> Vector3:
	return Vector3(point_px.x, 0.0, point_px.y) * units_per_pixel


func _cell_center(cell: Vector2i) -> Vector3:
	return _to_world((Vector2(cell) + Vector2(0.5, 0.5)) * room_size_px)
