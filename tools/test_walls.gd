extends Node
## Headless: nobody can climb onto rock or leave the walkable area. On every
## Ocean level, bodies are pushed into every wall (chunk rock, seals, landmark
## footprints), sliding along it, from a spot every sample_spacing pixels:
## - probes with the real collision shapes of the Echo, the Guardian and a
##   creature (from their scenes), moved by FloorMotion like the real ones, at
##   a swimming speed and a lunge / knockback speed;
## - the real Echo and Guardian (their own movement code) along every wall
##   near a doorway (where the rock is lowest) and a sparser walk everywhere.
## Fails when a body ends above the floor (on rock), with its centre inside a
## rock outline, or outside every room.
## godot --headless --path . --fixed-fps 60 res://tools/test_walls.tscn [-- N]
## (N = only that world level, 1-9).
## Exits with 1 when a check fails.

const LEVEL_TEST_SCENE: PackedScene = preload("res://tools/level_test.tscn")
const BODY_SCENES: Dictionary = {
	"Echo": preload("res://scenes/echo.tscn"),
	"Guardian": preload("res://scenes/guardian.tscn"),
	"Creature": preload("res://scenes/creature.tscn"),
}

## Pixels between two starting spots along a wall.
@export var sample_spacing: float = 40.0
## Probe speeds (units/s): swimming, and a lunge / knockback.
@export var probe_speeds: PackedFloat32Array = PackedFloat32Array([7.5, 16.0])
## Physics frames each push lasts (it slides along the wall meanwhile).
@export var push_frames: int = 18
@export var batch_size: int = 900
## Gap between the body and the wall at the start (pixels).
@export var start_gap: float = 3.0
## Above this height (units) a body is on rock.
@export var height_tolerance: float = 0.02
## Real players: spacing near a doorway / elsewhere (pixels), frames per push.
@export var real_doorway_spacing: float = 60.0
@export var real_other_spacing: float = 600.0
@export var real_push_frames: int = 20
## Failures printed per level and kind.
@export var examples_shown: int = 4

var _failures: int = 0
var _checks: int = 0
var test: LevelTest
var _shapes: Dictionary = {}
var _probes: Array[Probe] = []
var _driven: Array[Probe] = []
var _rocks: Array[PackedVector2Array] = []
var _rock_bounds: Array[Rect2] = []
var _rooms: Array[Rect2] = []
## What each rock is (room wall, seal, landmark), for the failure lines.
var _rock_kinds: PackedStringArray = PackedStringArray()


## One pushed body: where it started, which way it is driven.
class Probe:
	var body: CharacterBody3D
	var kind: String
	var start: Vector2
	var direction: Vector3
	var speed: float


func _ready() -> void:
	# Runs before the players, so the real players' velocity is set first.
	process_physics_priority = -100
	_run.call_deferred()


func _run() -> void:
	print("")
	print("TEST WALLS (3D): nobody climbs onto rock or leaves the walkable area")
	for kind: String in BODY_SCENES:
		var instance: Node = (BODY_SCENES[kind] as PackedScene).instantiate()
		var collider := instance.get_node("CollisionShape3D") as CollisionShape3D
		_shapes[kind] = {"shape": collider.shape, "transform": collider.transform, "radius": _radius_of(collider.shape)}
		instance.free()
	test = LEVEL_TEST_SCENE.instantiate() as LevelTest
	add_child(test)
	await _frames(3)
	test.oxygen_drain = false
	var started: int = Time.get_ticks_msec()
	var only: int = -1
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			only = arg.to_int()
	var number: int = 0
	for stage: int in test.world.get_stage_count():
		for level: int in test.world.get_level_count(stage):
			number += 1
			if only > 0 and number != only:
				continue
			await _test_level(stage, level, "level %d (%d-%d)" % [number, stage + 1, level + 1])
	print("")
	print("%d checks, %d failed (%.0f s)" % [_checks, _failures, (Time.get_ticks_msec() - started) / 1000.0])
	print("RESULT: ", "WALLS OK" if _failures == 0 else "WALLS FAIL")
	get_tree().quit(0 if _failures == 0 else 1)


func _test_level(stage: int, level: int, label: String) -> void:
	test.start_level(stage, level)
	test.set_creatures_frozen(true)
	await _frames(3)
	var layout: LevelBuilder.Layout = test.builder.get_layout()
	_collect_rock(layout)
	var samples: Array[Array] = _wall_samples(sample_spacing)
	_check_colliders(label)

	# Probes: every shape, every speed, every sample.
	var results: Dictionary = {}
	var queue: Array[Probe] = []
	for kind: String in _shapes:
		var radius: float = _shapes[kind]["radius"] / _units()
		for sample: Array in samples:
			var start: Vector2 = _start_spot(sample, radius)
			if start == Vector2.INF:
				continue
			for speed: float in probe_speeds:
				var probe := Probe.new()
				probe.kind = kind
				probe.start = start
				probe.direction = _push_direction(sample, queue.size())
				probe.speed = speed
				queue.append(probe)
	var probe_started: int = Time.get_ticks_msec()
	var index: int = 0
	while index < queue.size():
		var batch: Array[Probe] = queue.slice(index, index + batch_size)
		index += batch.size()
		for probe: Probe in batch:
			probe.body = _make_probe(probe.kind)
			add_child(probe.body)
			_place(probe.body, test.builder.to_world(probe.start))
		_probes = batch
		await _frames(push_frames)
		_probes = []
		for probe: Probe in batch:
			_judge(probe, results)
			probe.body.queue_free()
	for kind: String in _shapes:
		_report(label, "%s probes" % kind, results.get(kind, []), queue.filter(func(p: Probe) -> bool: return p.kind == kind).size())

	var probe_seconds: float = (Time.get_ticks_msec() - probe_started) / 1000.0
	# The real players.
	var real_started: int = Time.get_ticks_msec()
	var real_samples: Array[Array] = _real_samples(layout)
	var real_results: Dictionary = {}
	var pushes: int = 0
	for i: int in real_samples.size():
		var sample: Array = real_samples[i]
		var pair: Array[Probe] = []
		for player: Player in [test.echo, test.guardian]:
			var radius: float = _radius_of((player.get_node("CollisionShape3D") as CollisionShape3D).shape) / _units()
			var start: Vector2 = _start_spot(sample, radius)
			if start == Vector2.INF:
				continue
			var probe := Probe.new()
			probe.body = player
			probe.kind = "Echo" if player == test.echo else "Guardian"
			probe.start = start
			# The two slide opposite ways along the wall.
			probe.direction = _push_direction(sample, i * 2 + pair.size())
			probe.speed = player.max_speed * 2.0
			pair.append(probe)
			_place(player, test.builder.to_world(start))
		if pair.is_empty():
			continue
		_driven = pair
		await _frames(real_push_frames)
		_driven = []
		for probe: Probe in pair:
			pushes += 1
			_judge(probe, real_results)
			probe.body.velocity = Vector3.ZERO
	var real: Array = []
	for kind: String in real_results:
		real.append_array(real_results[kind])
	_report(label, "real players", real, pushes)
	print("    (%d wall spots; probes %.1f s, real players %.1f s)" % [samples.size(), probe_seconds, (Time.get_ticks_msec() - real_started) / 1000.0])


func _physics_process(_delta: float) -> void:
	for probe: Probe in _probes:
		probe.body.velocity = probe.direction * probe.speed
		FloorMotion.move(probe.body)
	for probe: Probe in _driven:
		probe.body.velocity = probe.direction * probe.speed


# --- Walls and samples ----------------------------------------------------------

## Every rock outline of the level has its colliders (one wall skin each).
func _check_colliders(label: String) -> void:
	var shapes: int = 0
	for room: Node in test.builder.find_children("Room_*", "", true, false):
		var rock := room.get_node_or_null("Rock") as StaticBody3D
		if rock:
			shapes += rock.find_children("*", "CollisionShape3D", false, false).size()
	_check(shapes == _rocks.size(), "%s: every rock has its walls (%d rocks, %d colliders)" % [label, _rocks.size(), shapes])


func _collect_rock(layout: LevelBuilder.Layout) -> void:
	_rocks.clear()
	_rock_bounds.clear()
	_rock_kinds.clear()
	for chunk: LevelChunk in layout.chunks:
		for polygon: PackedVector2Array in chunk.get_wall_polygons():
			_rocks.append(polygon)
			_rock_kinds.append("wall of %s" % chunk.scene_file_path.get_file())
	for polygon: PackedVector2Array in layout.seals:
		_rocks.append(polygon)
		_rock_kinds.append("seal")
	for polygon: PackedVector2Array in layout.landmark_polygons:
		_rocks.append(polygon)
		_rock_kinds.append("landmark")
	for polygon: PackedVector2Array in _rocks:
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon:
			bounds = bounds.expand(point)
		_rock_bounds.append(bounds)
	_rooms.clear()
	var size: float = test.world.room_size
	for cell: Vector2i in layout.rooms:
		_rooms.append(Rect2(Vector2(cell) * size, Vector2.ONE * size))


## Every wall edge cut into spots: [point on the edge, outward normal, tangent].
func _wall_samples(spacing: float) -> Array[Array]:
	var result: Array[Array] = []
	for polygon: PackedVector2Array in _rocks:
		var count: int = polygon.size()
		for e: int in count:
			var a: Vector2 = polygon[e]
			var b: Vector2 = polygon[(e + 1) % count]
			var length: float = a.distance_to(b)
			if length < 0.5:
				continue
			var tangent: Vector2 = (b - a) / length
			var normal: Vector2 = tangent.orthogonal()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + normal * 0.5, polygon):
				normal = -normal
			var steps: int = maxi(1, floori(length / spacing))
			for s: int in steps:
				result.append([a + tangent * length * (s + 0.5) / steps, normal, tangent])
	return result


## The real players: dense near doorways (the lowest rock), sparse elsewhere.
func _real_samples(layout: LevelBuilder.Layout) -> Array[Array]:
	var doorways: Array[Rect2] = []
	for corridor: Rect2 in test.builder._doorway_corridors(layout):
		doorways.append(corridor.grow(test.builder.doorway_clear_distance))
	var result: Array[Array] = []
	var since_other: float = INF
	for sample: Array in _wall_samples(real_doorway_spacing):
		var point: Vector2 = sample[0]
		var near_door: bool = doorways.any(func(zone: Rect2) -> bool: return zone.has_point(point))
		since_other += real_doorway_spacing
		if near_door or since_other >= real_other_spacing:
			result.append(sample)
			if not near_door:
				since_other = 0.0
	return result


## Where a body of this radius (pixels) starts in front of the wall spot, or
## Vector2.INF when it does not fit there (a narrow gap, another rock).
func _start_spot(sample: Array, radius: float) -> Vector2:
	var start: Vector2 = (sample[0] as Vector2) + (sample[1] as Vector2) * (radius + start_gap)
	if not _in_rooms(start, radius):
		return Vector2.INF
	if _clearance(start, radius + start_gap) < radius + 1.0:
		return Vector2.INF
	return start


## Into the wall, sliding along it (one way or the other by `turn`); every
## third push goes straight in.
func _push_direction(sample: Array, turn: int) -> Vector3:
	var normal: Vector2 = sample[1]
	var tangent: Vector2 = sample[2]
	var along: float = 0.0 if turn % 3 == 2 else (0.7 if turn % 2 == 0 else -0.7)
	var flat: Vector2 = (-normal + tangent * along).normalized()
	return Vector3(flat.x, 0.0, flat.y)


## Distance from p to the nearest rock (pixels; -1 inside rock), looked for
## within reach.
func _clearance(p: Vector2, reach: float) -> float:
	var best: float = INF
	for i: int in _rocks.size():
		if not _rock_bounds[i].grow(reach + 2.0).has_point(p):
			continue
		var polygon: PackedVector2Array = _rocks[i]
		if Geometry2D.is_point_in_polygon(p, polygon):
			return -1.0
		for e: int in polygon.size():
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, polygon[e], polygon[(e + 1) % polygon.size()])
			best = minf(best, closest.distance_to(p))
	return best


func _in_rooms(p: Vector2, margin: float) -> bool:
	for room: Rect2 in _rooms:
		if room.grow(-margin).has_point(p):
			return true
	return false


## The rock whose outline holds p, or -1.
func _rock_at(p: Vector2) -> int:
	for i: int in _rocks.size():
		if _rock_bounds[i].has_point(p) and Geometry2D.is_point_in_polygon(p, _rocks[i]):
			return i
	return -1


# --- Judging --------------------------------------------------------------------

func _judge(probe: Probe, results: Dictionary) -> void:
	var at: Vector3 = probe.body.global_position
	var plan: Vector2 = test.builder.to_plan(at)
	var problem: String = ""
	if absf(at.y) > height_tolerance:
		problem = "on top of rock (height %.2f)" % at.y
	elif _rock_at(plan) >= 0:
		problem = "inside rock (%s)" % _rock_kinds[_rock_at(plan)]
	elif not _in_rooms(plan, 0.0):
		problem = "outside every room"
	if problem.is_empty():
		return
	if not results.has(probe.kind):
		results[probe.kind] = []
	(results[probe.kind] as Array).append("%s %s: started (%.0f, %.0f), ended (%.0f, %.0f), speed %.1f, room %s" % [
		probe.kind, problem, probe.start.x, probe.start.y, plan.x, plan.y, probe.speed,
		Vector2i((plan / test.world.room_size).floor())])


func _report(label: String, what: String, problems: Array, total: int) -> void:
	_check(problems.is_empty(), "%s: %s stay on the floor and out of the rock (%d pushes, %d bad)" % [label, what, total, problems.size()])
	for i: int in mini(problems.size(), examples_shown):
		print("        ", problems[i])


# --- Helpers --------------------------------------------------------------------

func _make_probe(kind: String) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 0
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.shape = _shapes[kind]["shape"]
	collider.transform = _shapes[kind]["transform"]
	body.add_child(collider)
	return body


func _radius_of(shape: Shape3D) -> float:
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	return 0.5


func _units() -> float:
	return test.world.units_per_pixel


func _place(node: Node3D, at: Vector3) -> void:
	node.global_position = Vector3(at.x, 0.0, at.z)
	node.reset_physics_interpolation()
	if node is CharacterBody3D:
		(node as CharacterBody3D).velocity = Vector3.ZERO


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["ok  " if ok else "FAIL", label])


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
