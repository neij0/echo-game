class_name JourneyTower
extends Node2D
## The five worlds as floating islands stacked up (Ocean at the bottom, then
## Caves, Forest, Desert, Snow), joined by a path of soft light motes that
## climbs from one island's shoulder to the next (drawn behind the islands, so
## it passes behind their rock; never across their tops).
## set_progress(world, stage) lights them for the save: finished worlds full
## (3), the current one by its stage (1-3), the ones above dark (0); the path is
## lit up to the current world. play_step_from(world, stage) animates the last
## step (the island lighting up one step, or the path climbing to the next
## world and that one's first lights); skip() jumps to the end. Used big on
## the Journey screen and small and dim behind the main menu.

signal step_finished

const ISLAND_SCRIPTS: Array[Script] = [
	preload("res://scripts/journey_island_ocean.gd"), preload("res://scripts/journey_island_caves.gd"),
	preload("res://scripts/journey_island_forest.gd"), preload("res://scripts/journey_island_desert.gd"),
	preload("res://scripts/journey_island_snow.gd"),
]

@export var island_spacing: float = 440.0
## Sideways offset of each island (bottom to top), so the tower is not straight.
@export var island_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 46.0, -38.0, 30.0, -12.0])
@export var island_accents: Array[Color] = [
	Color(0.45, 0.95, 1.0), Color(1.0, 0.62, 0.3), Color(0.65, 1.0, 0.45), Color(1.0, 0.75, 0.42), Color(0.8, 0.9, 1.0),
]
@export var path_color: Color = Color(1.0, 0.86, 0.55)
@export var path_energy: float = 1.5
## Px between two motes of the path, and their size.
@export var mote_spacing: float = 14.0
@export var mote_size: float = 1.6
## Seconds the island takes to light one step / the path to climb to the next.
@export var step_time: float = 1.8
@export var path_time: float = 1.4
## Seconds a spark takes to run along a lit path segment.
@export var spark_time: float = 2.2

var islands: Array[JourneyIsland] = []
## Lit path segments (segment i joins island i and i + 1); fractions while one lights.
var path_lit: float = 0.0
var _segments: Array[PackedVector2Array] = []
var _tween: Tween
var _time: float = 0.0


func _ready() -> void:
	for i: int in ISLAND_SCRIPTS.size():
		var island := ISLAND_SCRIPTS[i].new() as JourneyIsland
		island.seed_value = 11 + i * 7
		island.accent = island_accents[i % island_accents.size()]
		island.position = Vector2(island_offsets[i % island_offsets.size()], -island_spacing * float(i))
		add_child(island)
		islands.append(island)
	_build_path()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## How many steps a world is lit for a save at (world, stage).
static func light_for(island_index: int, world_index: int, stage_index: int) -> float:
	if island_index < world_index:
		return 3.0
	if island_index == world_index:
		return clampf(float(stage_index + 1), 1.0, 3.0)
	return 0.0


func set_progress(world_index: int, stage_index: int) -> void:
	if _tween:
		_tween.kill()
	for i: int in islands.size():
		islands[i].light = light_for(i, world_index, stage_index)
	path_lit = float(mini(world_index, _segments.size()))


## Shows the save before the last step (from_world, from_stage), then lights
## up to the progress now (to_world, to_stage).
func play_step(from_world: int, from_stage: int, to_world: int, to_stage: int) -> void:
	set_progress(from_world, from_stage)
	_tween = create_tween()
	if to_world == from_world:
		_tween.tween_property(islands[to_world], "light", light_for(to_world, to_world, to_stage), step_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif to_world < islands.size():
		_tween.tween_property(self, "path_lit", float(to_world), path_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(islands[to_world], "light", light_for(to_world, to_world, to_stage), step_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(step_finished.emit)


func is_animating() -> bool:
	return _tween != null and _tween.is_running()


## Ends a step animation at once.
func skip() -> void:
	if is_animating():
		_tween.custom_step(1000.0)


## Where the camera looks at an island (local).
func get_focus_point(index: int) -> Vector2:
	return islands[clampi(index, 0, islands.size() - 1)].get_focus_point()


## Each segment climbs from one island's shoulder (alternating sides) out
## and round to the next one's other shoulder, as motes mote_spacing apart.
func _build_path() -> void:
	_segments.clear()
	for i: int in islands.size() - 1:
		var low: JourneyIsland = islands[i]
		var high: JourneyIsland = islands[i + 1]
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var a: Vector2 = low.get_path_anchor(side)
		var d: Vector2 = high.get_path_anchor(-side)
		var b: Vector2 = a + Vector2(side * 150.0, -island_spacing * 0.2)
		var c: Vector2 = d + Vector2(-side * 160.0, island_spacing * 0.45)
		var curve := PackedVector2Array()
		for k: int in 241:
			curve.append(a.bezier_interpolate(b, c, d, float(k) / 240.0))
		var motes := PackedVector2Array([curve[0]])
		var walked: float = 0.0
		for k: int in range(1, curve.size()):
			walked += curve[k].distance_to(curve[k - 1])
			if walked >= mote_spacing:
				motes.append(curve[k])
				walked = 0.0
		_segments.append(motes)


func _draw() -> void:
	for i: int in _segments.size():
		var motes: PackedVector2Array = _segments[i]
		var lit_share: float = clampf(path_lit - float(i), 0.0, 1.0)
		var lit_count: int = int(round(lit_share * float(motes.size())))
		for k: int in motes.size():
			if k < lit_count:
				# A soft wave of light climbing the lit motes.
				var wave: float = 0.6 + 0.4 * sin(float(k) * 0.5 - _time * TAU / spark_time)
				IslandArt.soft_glow(self, motes[k], Vector2.ONE * mote_size * 6.0, Color(path_color, 0.28 * wave))
				draw_circle(motes[k], mote_size * 0.6, IslandArt.hdr(path_color, path_energy, 0.85 * wave))
			else:
				draw_circle(motes[k], mote_size * 0.5, Color(path_color, 0.1))
