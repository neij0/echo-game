class_name JourneyTower
extends Node2D
## The five worlds as floating islands stacked up (Ocean at the bottom, then
## Caves, Forest, Desert, Snow), joined by a thin glowing path that climbs from
## one to the next (drawn behind the islands, so it passes behind their rock).
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

@export var island_spacing: float = 330.0
## Sideways offset of each island (bottom to top), so the tower is not straight.
@export var island_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 46.0, -38.0, 30.0, -12.0])
@export var island_accents: Array[Color] = [
	Color(0.45, 0.95, 1.0), Color(1.0, 0.62, 0.3), Color(0.65, 1.0, 0.45), Color(1.0, 0.75, 0.42), Color(0.8, 0.9, 1.0),
]
@export var island_top_colors: Array[Color] = [
	Color(0.02, 0.06, 0.09), Color(0.05, 0.045, 0.045), Color(0.03, 0.05, 0.035), Color(0.08, 0.06, 0.04), Color(0.1, 0.12, 0.15),
]
@export var path_color: Color = Color(1.0, 0.86, 0.55)
@export var path_energy: float = 1.5
@export var path_width: float = 1.4
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
		island.top_color = island_top_colors[i % island_top_colors.size()]
		island.path_color = path_color
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


func _build_path() -> void:
	_segments.clear()
	for i: int in islands.size() - 1:
		var low: JourneyIsland = islands[i]
		var high: JourneyIsland = islands[i + 1]
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var start: Vector2 = Vector2(side * low.half_width * 0.55, low.top_depth * 0.15)
		var finish: Vector2 = Vector2(-side * high.half_width * 0.45, high.top_depth * 0.35)
		low.path_out = start
		low.has_path_out = true
		high.path_in = finish
		high.has_path_in = true
		var a: Vector2 = low.position + start
		var d: Vector2 = high.position + finish
		var b: Vector2 = a + Vector2(side * 140.0, -island_spacing * 0.15)
		var c: Vector2 = d + Vector2(-side * 150.0, island_spacing * 0.45)
		var points := PackedVector2Array()
		for k: int in 49:
			var t: float = float(k) / 48.0
			points.append(a.bezier_interpolate(b, c, d, t))
		_segments.append(points)


func _draw() -> void:
	var hdr := Color(path_color.r * path_energy, path_color.g * path_energy, path_color.b * path_energy)
	for i: int in _segments.size():
		var points: PackedVector2Array = _segments[i]
		var lit_share: float = clampf(path_lit - float(i), 0.0, 1.0)
		var lit_count: int = int(round(lit_share * float(points.size() - 1)))
		if lit_count >= 1:
			GlowFx.glow_line(self, points.slice(0, lit_count + 1), Color(hdr, 0.7), path_width)
			# A spark running up the lit part.
			var t: float = fposmod(_time / spark_time + float(i) * 0.37, 1.0) * float(lit_count)
			var spark: Vector2 = points[int(t)].lerp(points[mini(int(t) + 1, lit_count)], fmod(t, 1.0))
			GlowFx.dot(self, spark, 2.0, Color(hdr * 1.4, 0.9))
		for k: int in range(lit_count, points.size() - 1, 2):
			draw_line(points[k], points[k + 1], Color(path_color, 0.12), 1.0, true)
