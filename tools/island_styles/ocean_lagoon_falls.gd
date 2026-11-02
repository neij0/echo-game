extends JourneyIsland
## Ocean island, style C "Lagoon Falls" (a proposal: tools/island_style_preview):
## two rock shoulders, a tall leaning pinnacle and a rounded reef, hold a
## lagoon of glowing water; kelp rises out of it and the water pours over the
## front into a long waterfall that runs down past the rock and dissolves into
## mist. No outlines. The water brightens step by step; stage 3 (the world's
## marker): a beam of light rises from the lagoon and the falls shine.

const KELP_SEGMENTS: int = 16
## Rows of the waterfall (its flowing bands need a fine split).
const FALLS_LEVELS: int = 44

@export_group("Shape")
## The lagoon's surface (y) and its shores (x shares of the half width).
@export var water_level: float = -22.0
@export var lagoon_from: float = -0.5
@export var lagoon_to: float = 0.48
@export var basin_depth: float = 44.0
## The left shoulder, a leaning pinnacle: control points (x share, y) from the
## island's left end up to the peak and down towards the lagoon.
@export var pinnacle: PackedVector2Array = PackedVector2Array([Vector2(-1.0, 4.0), Vector2(-1.0, -22.0), Vector2(-0.96, -58.0),
	Vector2(-0.9, -98.0), Vector2(-0.83, -134.0), Vector2(-0.76, -160.0), Vector2(-0.7, -172.0), Vector2(-0.65, -158.0),
	Vector2(-0.62, -128.0), Vector2(-0.59, -96.0), Vector2(-0.56, -66.0), Vector2(-0.53, -40.0)])
## The right shoulder, a reef: control points from the lagoon to the right end.
@export var reef: PackedVector2Array = PackedVector2Array([Vector2(0.54, -38.0), Vector2(0.6, -54.0), Vector2(0.68, -66.0),
	Vector2(0.77, -72.0), Vector2(0.85, -66.0), Vector2(0.91, -52.0), Vector2(0.96, -32.0), Vector2(0.995, -10.0), Vector2(1.0, 4.0)])
## Where the falls leave the lagoon (x share) and how they fall.
@export var falls_x: float = 0.3
@export var falls_length: float = 330.0
@export var falls_width: Vector2 = Vector2(13.0, 38.0)
@export var falls_speed: float = 1.5
@export var underside_depth: float = 230.0
@export var kelp_sway: float = 8.0
@export var kelp_sway_speed: float = 0.7

@export_group("Light")
@export var light_dir: Vector2 = Vector2(0.5, 1.0)
@export var rock_top_color: Color = Color(0.03, 0.07, 0.09)
@export var rock_base_color: Color = Color(0.008, 0.014, 0.024)
@export var mid_rock_color: Color = Color(0.016, 0.034, 0.048)
@export var far_rock_color: Color = Color(0.03, 0.068, 0.09)
@export var locked_color: Color = Color(0.006, 0.009, 0.015)
@export var rim_color: Color = Color(0.55, 0.95, 1.0)
@export var water_surface_color: Color = Color(0.16, 0.62, 0.72)
@export var water_deep_color: Color = Color(0.01, 0.06, 0.1)
@export var locked_water_color: Color = Color(0.008, 0.014, 0.024)
@export var falls_color: Color = Color(0.55, 0.95, 1.0)
@export var beam_color: Color = Color(0.85, 1.0, 1.0)
@export var polyp_color: Color = Color(0.35, 1.0, 0.85)
@export var polyp_alt_color: Color = Color(0.8, 0.55, 1.0)
@export var beam_height: float = 240.0
@export var mist_count: int = 9

var _pinnacle_edge := PackedVector2Array()
var _reef_edge := PackedVector2Array()
var _pinnacle_facing := PackedFloat32Array()
var _reef_facing := PackedFloat32Array()
var _floor := PackedVector2Array()
var _peak_y: float = 0.0
## The shoulders, the lagoon's floor and the rock under them (IslandArt.build_island_rock).
var _rock: Dictionary = {}
## {root, height, width, phase, step, order}
var _kelp: Array[Dictionary] = []
## {at, size, color, phase, step, order}
var _polyps: Array[Dictionary] = []
## {side, phase, speed}
var _mist: Array[Dictionary] = []
var _water_on: float = 0.0


func _build_shape(rng: RandomNumberGenerator) -> void:
	var controls := PackedVector2Array()
	for point: Vector2 in pinnacle:
		controls.append(Vector2(point.x * half_width, point.y))
	controls.append(Vector2(lagoon_from * half_width, water_level - 2.0))
	_pinnacle_edge = IslandArt.smooth_path(controls, 4)
	controls = PackedVector2Array([Vector2(lagoon_to * half_width, water_level - 1.0)])
	for point: Vector2 in reef:
		controls.append(Vector2(point.x * half_width, point.y))
	_reef_edge = IslandArt.smooth_path(controls, 4)
	# Coral heads: small rounded bumps along the reef.
	for i: int in _reef_edge.size():
		var x: float = _reef_edge[i].x
		var lift: float = 5.0 * absf(sin(x * 0.11 + 0.6)) * smoothstep(lagoon_to * half_width, lagoon_to * half_width + 20.0, x)
		_reef_edge[i] = _reef_edge[i] - Vector2(0.0, lift * smoothstep(half_width, half_width - 20.0, x))
	_pinnacle_facing = _squared(IslandArt.facing(_pinnacle_edge, light_dir, 0.0))
	_reef_facing = _squared(IslandArt.facing(_reef_edge, light_dir, 0.0))
	for i: int in 25:
		var share: float = float(i) / 24.0
		var x: float = lerpf(lagoon_from, lagoon_to, share) * half_width
		_floor.append(Vector2(x, water_level + basin_depth * pow(sin(PI * share), 0.7) + 3.0 * sin(x * 0.17)))
	var top_edge: PackedVector2Array = _pinnacle_edge.duplicate()
	top_edge.append_array(_floor.slice(1, _floor.size() - 1))
	top_edge.append_array(_reef_edge)
	for point: Vector2 in _pinnacle_edge:
		_peak_y = minf(_peak_y, point.y)
	_rock = IslandArt.build_island_rock(rng, top_edge, half_width, 4.0, _peak_y, underside_depth, 0.0, 0.7)


func _build_kind(rng: RandomNumberGenerator) -> void:
	# x share, height, width, step, order
	for spec: Array in [[-0.3, 98.0, 12.0, 1, 0.3], [-0.06, 138.0, 14.0, 2, 0.2], [0.18, 86.0, 11.0, 3, 0.4]]:
		var x: float = float(spec[0]) * half_width
		_kelp.append({"root": Vector2(x, _floor_y(x) - 2.0), "height": float(spec[1]), "width": float(spec[2]),
			"phase": rng.randf() * TAU, "step": spec[3], "order": spec[4]})
	# Polyps: x share, px under the edge, step, order (on the reef and the pinnacle's foot)
	for spec: Array in [[0.7, 12.0, 1, 0.1], [0.86, 16.0, 2, 0.5], [0.6, 26.0, 2, 0.2], [-0.6, 70.0, 1, 0.6], [-0.86, 50.0, 3, 0.3],
			[0.95, 30.0, 3, 0.7]]:
		var color: Color = polyp_alt_color if rng.randf() < 0.35 else polyp_color
		for k: int in rng.randi_range(3, 5):
			var x: float = float(spec[0]) * half_width + rng.randf_range(-9.0, 9.0)
			_polyps.append({"at": Vector2(x, _edge_y(x) + float(spec[1]) + rng.randf_range(-5.0, 5.0)), "size": rng.randf_range(0.7, 1.2),
				"color": color, "phase": rng.randf() * TAU, "step": spec[2], "order": float(spec[3]) + rng.randf() * 0.2})
	for i: int in mist_count:
		_mist.append({"side": rng.randf_range(-1.0, 1.0), "phase": rng.randf(), "speed": rng.randf_range(0.08, 0.14)})


func _squared(values: PackedFloat32Array) -> PackedFloat32Array:
	for i: int in values.size():
		values[i] = values[i] * values[i]
	return values


func _floor_y(x: float) -> float:
	return _line_y(_floor, x)


## The top of the rock at x (the pinnacle or the reef).
func _edge_y(x: float) -> float:
	return _line_y(_pinnacle_edge if x < 0.0 else _reef_edge, x)


func _line_y(line: PackedVector2Array, x: float) -> float:
	for i: int in range(1, line.size()):
		if line[i].x >= x and line[i - 1].x <= x:
			return lerpf(line[i - 1].y, line[i].y, inverse_lerp(line[i - 1].x, line[i].x, x))
	return line[line.size() - 1].y


func get_visual_rect() -> Rect2:
	var top: float = _peak_y - frame_margin
	return Rect2(-half_width - frame_margin * 2.0, top, (half_width + frame_margin * 2.0) * 2.0, underside_depth * 0.85 - top)


func _draw() -> void:
	var unlock: float = clampf(light, 0.0, 1.0)
	var on: float = overall()
	var rim_k: float = lerpf(locked_rim, 1.0, unlock * 0.45 + on * 0.55)
	_water_on = 0.45 * unlock if light <= 1.0 else lerpf(0.45, 1.0, clampf((light - 1.0) / 2.0, 0.0, 1.0))
	var dark: Color = locked_color.lerp(rock_base_color, unlock)
	var middle: float = (lagoon_from + lagoon_to) * 0.5 * half_width
	IslandArt.soft_glow(self, Vector2(middle, -60.0), Vector2(half_width * 1.9, half_width * 1.7), Color(accent, 0.15 * on))
	IslandArt.soft_glow(self, Vector2(0.0, 80.0), Vector2(half_width * 1.5, half_width * 1.1), Color(accent, 0.07 * on))
	var layer_on: float = unlock * (0.6 + 0.4 * on)
	IslandArt.draw_rock_layers(self, _rock, locked_color.lerp(far_rock_color, layer_on), locked_color.lerp(mid_rock_color, layer_on))
	var open: float = lit(3, 0.3)
	if open > 0.0:
		IslandArt.beam(self, Vector2(middle, water_level), beam_height, 8.0, 52.0, IslandArt.hdr(beam_color, 1.5, 0.4 * open))
	var top: Color = locked_color.lerp(rock_top_color, unlock * (0.55 + 0.45 * on))
	IslandArt.draw_rock_body(self, _rock, top, dark)
	IslandArt.rim(self, _pinnacle_edge, 11.0, Color(rim_color, 0.24 * rim_k), _pinnacle_facing)
	IslandArt.haze(self, _pinnacle_edge, 16.0, Color(rim_color, 0.05 * rim_k), _pinnacle_facing)
	IslandArt.rim(self, _reef_edge, 10.0, Color(rim_color, 0.24 * rim_k), _reef_facing)
	_draw_lagoon(unlock)
	for kelp: Dictionary in _kelp:
		_draw_kelp(kelp, dark, unlock, rim_k)
	for polyp: Dictionary in _polyps:
		var polyp_on: float = lit(polyp.step, polyp.order) * (0.75 + 0.25 * sin(_time * 1.6 + float(polyp.phase)))
		if polyp_on > 0.0:
			IslandArt.soft_glow(self, polyp.at, Vector2(10.0, 10.0) * float(polyp.size), Color(polyp.color, 0.45 * polyp_on))
			draw_circle(polyp.at, 1.6 * float(polyp.size), IslandArt.hdr(polyp.color, 2.4, polyp_on))
	_draw_falls(open)


## The lagoon: glowing water from its surface down to the basin floor,
## brightest at the surface (a soft band of light, no line).
func _draw_lagoon(unlock: float) -> void:
	var water := PackedVector2Array()
	var from_x: float = lagoon_from * half_width
	var to_x: float = lagoon_to * half_width
	for i: int in 33:
		var x: float = lerpf(from_x, to_x, float(i) / 32.0)
		water.append(Vector2(x, water_level + sin(x * 0.08 + _time * 1.2) * 0.8))
	for i: int in range(_floor.size() - 1, -1, -1):
		water.append(Vector2(_floor[i].x, maxf(_floor[i].y, water_level + 1.0)))
	var surface: Color = locked_water_color.lerp(IslandArt.hdr(water_surface_color, 1.0), _water_on)
	var deep: Color = locked_water_color.lerp(water_deep_color, unlock)
	IslandArt.mass(self, water, water_level, water_level + basin_depth, surface, deep)
	var middle: float = (from_x + to_x) * 0.5
	IslandArt.soft_glow(self, Vector2(middle, water_level + 1.0), Vector2((to_x - from_x) * 0.55, 7.0),
		IslandArt.hdr(water_surface_color, 1.8, 0.55 * _water_on))
	IslandArt.soft_glow(self, Vector2(middle, water_level - 26.0), Vector2(half_width * 0.75, 60.0), Color(accent, 0.12 * _water_on))


func _draw_kelp(kelp: Dictionary, dark: Color, unlock: float, rim_k: float) -> void:
	var line: PackedVector2Array = IslandArt.sway_line(kelp.root, kelp.height, KELP_SEGMENTS, kelp_sway, _time * kelp_sway_speed,
		kelp.phase, 1.1, 5.0)
	var outline: PackedVector2Array = IslandArt.shaped_ribbon(line, IslandArt.kelp_widths(line.size(), kelp.width, kelp.phase))
	IslandArt.mass(self, outline, line[line.size() - 1].y, line[0].y, dark.lerp(rock_top_color, 0.3 * unlock), dark)
	var left: PackedVector2Array = outline.slice(0, line.size())
	IslandArt.rim(self, left, 4.0, Color(rim_color, 0.3 * rim_k), IslandArt.facing(left, light_dir, 0.1))
	var float_on: float = lit(kelp.step, kelp.order) * (0.8 + 0.2 * sin(_time * 2.0 + float(kelp.phase)))
	for share: float in [0.62, 0.95]:
		var at: Vector2 = line[int(round(share * float(KELP_SEGMENTS)))]
		if float_on > 0.0:
			IslandArt.soft_glow(self, at, Vector2(14.0, 14.0), Color(polyp_color, 0.5 * float_on))
		draw_circle(at, 3.2, dark.lerp(IslandArt.hdr(polyp_color, 2.2), float_on))


## The waterfall: a soft ribbon of light pouring from the lagoon, widening and
## fading as it falls, with bright bands running down it and mist at its end.
func _draw_falls(open: float) -> void:
	if _water_on <= 0.0:
		return
	var start := Vector2(falls_x * half_width, water_level + 1.0)
	var across: PackedFloat32Array = PackedFloat32Array([-1.0, -0.5, 0.0, 0.5, 1.0])
	var profile: PackedFloat32Array = PackedFloat32Array([0.0, 0.6, 1.0, 0.6, 0.0])
	var energy: float = lerpf(1.1, 1.8, open)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for k: int in FALLS_LEVELS + 1:
		var t: float = float(k) / float(FALLS_LEVELS)
		var center := Vector2(start.x + 8.0 * smoothstep(0.0, 0.1, t), start.y + falls_length * t)
		var half: float = lerpf(falls_width.x, falls_width.y, pow(t, 0.8)) * 0.5
		var flow: float = 0.7 + 0.3 * sin((t * 7.0 - _time * falls_speed) * TAU)
		var alpha: float = 0.85 * _water_on * pow(1.0 - t, 1.3) * flow
		for j: int in across.size():
			points.append(center + Vector2(across[j] * half, 0.0))
			colors.append(IslandArt.hdr(falls_color, energy, alpha * profile[j]))
	var indices := PackedInt32Array()
	var row: int = across.size()
	for k: int in FALLS_LEVELS:
		for j: int in row - 1:
			var a: int = k * row + j
			indices.append_array([a, a + 1, a + row + 1, a, a + row + 1, a + row])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
	IslandArt.soft_glow(self, start + Vector2(3.0, 4.0), Vector2(20.0, 12.0), IslandArt.hdr(falls_color, 1.6, 0.5 * _water_on))
	for mist: Dictionary in _mist:
		var t: float = fposmod(_time * float(mist.speed) + float(mist.phase), 1.0)
		var at := Vector2(start.x + 8.0 + float(mist.side) * (10.0 + t * 46.0), start.y + falls_length * 0.6 + t * 70.0)
		IslandArt.soft_glow(self, at, Vector2.ONE * (18.0 + 34.0 * t), Color(falls_color, 0.08 * sin(PI * t) * _water_on))
