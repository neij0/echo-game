extends JourneyIsland
## Ocean island, style B "Sea Globe" (a proposal: tools/island_style_preview):
## a sphere of sea water held in a rock cradle and lit from within. A reef
## mound, kelp and a small school of fish inside are dark silhouettes against
## the glowing water; no outlines (the globe's edge is a soft fresnel glow).
## The water brightens step by step; stage 3 (the world's marker): the ancient
## light wakes at its heart with slow rays, and bubbles leave the globe. Under
## it the layered jagged rock fades into the dark, water dripping from it.

const KELP_SEGMENTS: int = 14
## Points along the cradle's lip every LIP_STEP px.
const LIP_STEP: float = 3.0

@export_group("Shape")
@export var globe_radius: float = 110.0
## Height of the globe's centre above the top surface.
@export var globe_lift: float = 86.0
## The cradle's horns: how far out (half width) and how high they hold the globe.
@export var lip_half_width: float = 112.0
@export var lip_height: float = 32.0
@export var underside_depth: float = 230.0
@export var fish_count: int = 5
@export var kelp_sway: float = 7.0
@export var kelp_sway_speed: float = 0.8

@export_group("Light")
@export var light_dir: Vector2 = Vector2(0.5, 1.0)
@export var water_top_color: Color = Color(0.05, 0.3, 0.4)
@export var water_deep_color: Color = Color(0.008, 0.05, 0.1)
@export var water_edge_color: Color = Color(0.35, 0.9, 1.0)
@export var locked_water_color: Color = Color(0.007, 0.012, 0.02)
@export var inner_color: Color = Color(0.004, 0.014, 0.026)
@export var rock_top_color: Color = Color(0.028, 0.06, 0.078)
@export var rock_base_color: Color = Color(0.008, 0.014, 0.024)
@export var mid_rock_color: Color = Color(0.016, 0.034, 0.048)
@export var far_rock_color: Color = Color(0.03, 0.068, 0.09)
@export var locked_color: Color = Color(0.006, 0.009, 0.015)
@export var rim_color: Color = Color(0.55, 0.95, 1.0)
@export var heart_color: Color = Color(0.85, 1.0, 1.0)
@export var glass_color: Color = Color(0.7, 0.96, 1.0)
@export var polyp_color: Color = Color(0.35, 1.0, 0.85)
@export var polyp_alt_color: Color = Color(0.8, 0.55, 1.0)
@export var bubble_count: int = 16
@export var drip_count: int = 5

var _center: Vector2 = Vector2.ZERO
var _lip := PackedVector2Array()
var _lip_facing := PackedFloat32Array()
## The cup's dark inside, seen between the globe and the horns.
var _hollow := PackedVector2Array()
var _mound := PackedVector2Array()
var _mound_top: float = 0.0
## The cradle and the rock under it (IslandArt.build_island_rock).
var _rock: Dictionary = {}
## {root, height, width, phase, step, order}
var _kelp: Array[Dictionary] = []
## {at, size, color, phase, step, order}
var _polyps: Array[Dictionary] = []
## {offset (along the loop), lane (px up / down), size}
var _fish: Array[Dictionary] = []
## {x, phase, speed, size, escape}
var _bubbles: Array[Dictionary] = []
## {x, phase, speed}
var _drips: Array[Dictionary] = []
## How lit the water is now (set before drawing, read by _water_shade).
var _water_on: float = 0.0


func _build_shape(rng: RandomNumberGenerator) -> void:
	_center = Vector2(0.0, -globe_lift)
	var count: int = int(half_width * 2.0 / LIP_STEP)
	for i: int in count + 1:
		var x: float = lerpf(-half_width, half_width, float(i) / float(count))
		_lip.append(Vector2(x, _lip_y(x)))
	_lip_facing = IslandArt.facing(_lip, light_dir, 0.0)
	for i: int in _lip_facing.size():
		_lip_facing[i] = pow(_lip_facing[i], 2.0)
	# Its top corners above the horns (clear of the lip's bumps), then the lip
	# back from right to left.
	var hollow_top: float = -lip_height - 12.0
	_hollow = PackedVector2Array([Vector2(-lip_half_width, hollow_top), Vector2(lip_half_width, hollow_top)])
	for i: int in range(_lip.size() - 1, -1, -1):
		if absf(_lip[i].x) < lip_half_width:
			_hollow.append(_lip[i])
	# The cradle's lip closed by the jagged rock under it: one silhouette that
	# hides the globe's lower part.
	_rock = IslandArt.build_island_rock(rng, _lip, half_width, 6.0, -lip_height, underside_depth, 0.05)
	# The reef mound inside the globe: a lumpy top, its bottom on the globe's edge.
	var half: float = globe_radius * 0.9
	var top_edge := PackedVector2Array()
	var bottom_edge := PackedVector2Array()
	for i: int in 31:
		var x: float = lerpf(-half, half, float(i) / 30.0)
		var floor_y: float = _center.y + sqrt(maxf(globe_radius * globe_radius - x * x, 0.0))
		var rise: float = globe_radius * 0.78 * pow(maxf(1.0 - pow(x / half, 2.0), 0.0), 0.6)
		rise += (6.0 * sin(x * 0.09 + 0.7) + 3.0 * sin(x * 0.23)) * minf(rise / 20.0, 1.0)
		top_edge.append(Vector2(x, floor_y - rise))
		bottom_edge.append(Vector2(x, floor_y))
		_mound_top = minf(_mound_top, floor_y - rise)
	bottom_edge.reverse()
	_mound = top_edge
	_mound.append_array(bottom_edge)


func _build_kind(rng: RandomNumberGenerator) -> void:
	# x share of the radius, height, width, step, order
	for spec: Array in [[-0.5, 84.0, 11.0, 1, 0.3], [0.3, 116.0, 12.0, 2, 0.2], [0.68, 78.0, 10.0, 3, 0.5]]:
		var x: float = float(spec[0]) * globe_radius
		_kelp.append({"root": Vector2(x, _mound_y(x) + 8.0), "height": float(spec[1]), "width": float(spec[2]),
			"phase": rng.randf() * TAU, "step": spec[3], "order": spec[4]})
	for spec: Array in [[-0.3, 1, 0.0], [0.5, 1, 0.6], [-0.7, 2, 0.2], [0.05, 2, 0.5], [0.8, 3, 0.3], [-0.05, 3, 0.8]]:
		var color: Color = polyp_alt_color if rng.randf() < 0.35 else polyp_color
		for k: int in rng.randi_range(3, 5):
			var x: float = float(spec[0]) * globe_radius * 0.85 + rng.randf_range(-9.0, 9.0)
			_polyps.append({"at": Vector2(x, _mound_y(x) + rng.randf_range(5.0, 16.0)), "size": rng.randf_range(0.7, 1.2),
				"color": color, "phase": rng.randf() * TAU, "step": spec[1], "order": float(spec[2]) + rng.randf() * 0.2})
	for i: int in fish_count:
		_fish.append({"offset": float(i) * 0.42 + rng.randf_range(-0.08, 0.08), "lane": rng.randf_range(-7.0, 7.0),
			"size": rng.randf_range(0.85, 1.15)})
	for i: int in bubble_count:
		_bubbles.append({"x": rng.randf_range(-0.6, 0.6) * globe_radius, "phase": rng.randf(), "speed": rng.randf_range(0.1, 0.18),
			"size": rng.randf_range(1.1, 2.2), "escape": i % 3 == 0})
	for i: int in drip_count:
		_drips.append({"x": rng.randf_range(-0.55, 0.55) * half_width, "phase": rng.randf(), "speed": rng.randf_range(0.35, 0.6)})


## The cradle's top edge at x: shoulders rising to a horn each side of the
## globe and a lip dipping low in front of it, with rocky bumps.
func _lip_y(x: float) -> float:
	var reach: float = absf(x)
	var y: float
	if reach <= lip_half_width:
		var share: float = reach / lip_half_width
		y = -lip_height + (lip_height - 2.0) * pow(1.0 - share * share, 1.4)
	else:
		y = lerpf(-lip_height, 6.0, pow((reach - lip_half_width) / (half_width - lip_half_width), 1.3))
	return y + sin(x * 0.09 + 1.0) * 1.6 + sin(x * 0.23) * 0.7


## The mound's top inside the globe at x.
func _mound_y(x: float) -> float:
	for i: int in range(1, _mound.size()):
		if _mound[i].x >= x:
			return lerpf(_mound[i - 1].y, _mound[i].y, inverse_lerp(_mound[i - 1].x, _mound[i].x, x))
	return _mound_top


func get_visual_rect() -> Rect2:
	var top: float = _center.y - globe_radius - frame_margin * 3.0
	return Rect2(-half_width - frame_margin * 2.0, top, (half_width + frame_margin * 2.0) * 2.0, underside_depth * 0.8 - top)


func _draw() -> void:
	var unlock: float = clampf(light, 0.0, 1.0)
	var on: float = overall()
	var rim_k: float = lerpf(locked_rim, 1.0, unlock * 0.45 + on * 0.55)
	_water_on = 0.45 * unlock if light <= 1.0 else lerpf(0.45, 1.0, clampf((light - 1.0) / 2.0, 0.0, 1.0))
	var dark: Color = locked_color.lerp(rock_base_color, unlock)
	IslandArt.soft_glow(self, _center, Vector2(globe_radius, globe_radius) * 2.3, Color(accent, 0.16 * on))
	IslandArt.soft_glow(self, Vector2(0.0, 80.0), Vector2(half_width * 1.5, half_width * 1.1), Color(accent, 0.07 * on))
	var layer_on: float = unlock * (0.6 + 0.4 * on)
	IslandArt.draw_rock_layers(self, _rock, locked_color.lerp(far_rock_color, layer_on), locked_color.lerp(mid_rock_color, layer_on))
	IslandArt.mass(self, _hollow, -lip_height, 0.0, dark, dark)
	_draw_globe(dark, unlock)
	var top: Color = locked_color.lerp(rock_top_color, unlock * (0.6 + 0.4 * on))
	IslandArt.draw_rock_body(self, _rock, top, dark)
	IslandArt.rim(self, _lip, 12.0, Color(rim_color, 0.17 * rim_k), _lip_facing)
	IslandArt.haze(self, _lip, 14.0, Color(rim_color, 0.04 * rim_k), _lip_facing)
	# The globe's light on the lip in front of it.
	IslandArt.soft_glow(self, Vector2(0.0, -6.0), Vector2(lip_half_width * 0.9, 18.0), Color(water_edge_color, 0.22 * _water_on))
	_draw_escaping_bubbles()
	_draw_drips()


func _draw_globe(dark: Color, unlock: float) -> void:
	var radii := Vector2(globe_radius, globe_radius)
	IslandArt.shaded_disc(self, _center, radii, _water_shade, 64)
	var open: float = lit(3, 0.3)
	var heart: Vector2 = _center + Vector2(0.0, -6.0)
	if open > 0.0:
		# The ancient light: slow rays through the water behind the silhouettes.
		for k: int in 7:
			var angle: float = TAU * float(k) / 7.0 + _time * 0.06
			var end: float = globe_radius * 0.92
			draw_polygon(PackedVector2Array([heart, heart + Vector2.from_angle(angle - 0.06) * end, heart + Vector2.from_angle(angle + 0.06) * end]),
				PackedColorArray([IslandArt.hdr(heart_color, 1.4, 0.16 * open), Color(heart_color, 0.0), Color(heart_color, 0.0)]))
		IslandArt.soft_glow(self, heart, Vector2(globe_radius, globe_radius) * 0.75, Color(heart_color, 0.3 * open))
	var silhouette: Color = locked_water_color.lerp(inner_color, unlock)
	_draw_fish(silhouette)
	for kelp: Dictionary in _kelp:
		_draw_kelp(kelp, silhouette)
	IslandArt.mass(self, _mound, _mound_top, _center.y + globe_radius, silhouette.lerp(water_deep_color, 0.35 * _water_on), silhouette)
	for polyp: Dictionary in _polyps:
		var polyp_on: float = lit(polyp.step, polyp.order) * (0.75 + 0.25 * sin(_time * 1.6 + float(polyp.phase)))
		if polyp_on > 0.0:
			IslandArt.soft_glow(self, polyp.at, Vector2(9.0, 9.0) * float(polyp.size), Color(polyp.color, 0.45 * polyp_on))
			draw_circle(polyp.at, 1.5 * float(polyp.size), IslandArt.hdr(polyp.color, 2.4, polyp_on))
	_draw_inner_bubbles()
	if open > 0.0:
		draw_circle(heart, 5.0, IslandArt.hdr(heart_color, 3.2, open))
		IslandArt.soft_glow(self, heart, Vector2(30.0, 30.0), IslandArt.hdr(heart_color, 1.6, 0.85 * open))
	# The glass: a soft highlight high on the left, near its edge; no edge line.
	IslandArt.soft_glow(self, _center + Vector2(-0.3, -0.68) * globe_radius, Vector2(0.28, 0.13) * globe_radius,
		IslandArt.hdr(glass_color, 1.1, 0.16 * _water_on + 0.04 * unlock))


## The water's colour at a point of the globe (share: 0 middle, 1 edge):
## lighter up high, deep below, a brighter edge (fresnel).
func _water_shade(point: Vector2, share: float) -> Color:
	var down: float = clampf((point.y - (_center.y - globe_radius)) / (globe_radius * 2.0), 0.0, 1.0)
	var fresnel: float = pow(share, 3.5)
	var lit_water: Color = water_top_color.lerp(water_deep_color, down).lerp(water_edge_color, fresnel * 0.45)
	var dark: Color = locked_water_color.lerp(rim_color * 0.25, fresnel * locked_rim * 0.6)
	return dark.lerp(lit_water, _water_on)


func _draw_kelp(kelp: Dictionary, color: Color) -> void:
	var line: PackedVector2Array = IslandArt.sway_line(kelp.root, kelp.height, KELP_SEGMENTS, kelp_sway, _time * kelp_sway_speed,
		kelp.phase, 1.0, 4.0)
	var outline: PackedVector2Array = IslandArt.shaped_ribbon(line, IslandArt.kelp_widths(line.size(), kelp.width, kelp.phase))
	IslandArt.mass(self, outline, line[line.size() - 1].y, line[0].y, color.lerp(water_deep_color, 0.25 * _water_on), color)
	var float_on: float = lit(kelp.step, kelp.order) * (0.8 + 0.2 * sin(_time * 2.0 + float(kelp.phase)))
	var tip: Vector2 = line[line.size() - 2]
	if float_on > 0.0:
		IslandArt.soft_glow(self, tip, Vector2(13.0, 13.0), Color(polyp_color, 0.5 * float_on))
	draw_circle(tip, 3.0, color.lerp(IslandArt.hdr(polyp_color, 2.2), float_on))


## A small school swimming round inside the globe: dark shapes, a little
## lighter and smaller on the far side of their loop.
func _draw_fish(color: Color) -> void:
	var loop_center: Vector2 = _center + Vector2(0.0, -globe_radius * 0.22)
	var loop := Vector2(globe_radius * 0.58, globe_radius * 0.13)
	for fish: Dictionary in _fish:
		var angle: float = _time * 0.45 + float(fish.offset)
		var far: float = clampf(-sin(angle), 0.0, 1.0)
		var at: Vector2 = loop_center + Vector2(cos(angle) * loop.x, sin(angle) * loop.y + float(fish.lane))
		var forward := Vector2(-sin(angle) * loop.x, cos(angle) * loop.y).normalized()
		var side: Vector2 = forward.orthogonal()
		var size: float = float(fish.size) * lerpf(1.0, 0.75, far)
		var body := PackedVector2Array()
		for k: int in 10:
			var a: float = TAU * float(k) / 10.0
			body.append(at + forward * cos(a) * 7.5 * size + side * sin(a) * 3.0 * size)
		var tail_root: Vector2 = at - forward * 6.0 * size
		var shade: Color = color.lerp(water_top_color, 0.45 * far * _water_on)
		draw_colored_polygon(body, shade)
		draw_colored_polygon(PackedVector2Array([tail_root, tail_root - forward * 6.0 * size + side * 4.0 * size,
			tail_root - forward * 6.0 * size - side * 4.0 * size]), shade)


func _draw_inner_bubbles() -> void:
	if _water_on <= 0.0:
		return
	for bubble: Dictionary in _bubbles:
		if bubble.escape:
			continue
		var x: float = bubble.x
		var t: float = fposmod(_time * float(bubble.speed) + float(bubble.phase), 1.0)
		var from_y: float = _mound_y(x) - 2.0
		var to_y: float = _center.y - sqrt(maxf(globe_radius * globe_radius - x * x, 0.0)) + 6.0
		var at := Vector2(x + sin(t * TAU * 1.2 + float(bubble.phase) * 6.0) * 3.0, lerpf(from_y, to_y, t))
		var alpha: float = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.75, 1.0, t)) * _water_on
		IslandArt.soft_glow(self, at, Vector2.ONE * float(bubble.size) * 3.2, IslandArt.hdr(water_edge_color, 1.3, 0.45 * alpha))
		draw_circle(at, float(bubble.size) * 0.5, IslandArt.hdr(water_edge_color, 1.8, 0.7 * alpha))


func _draw_escaping_bubbles() -> void:
	var open: float = lit(3, 0.5)
	if open <= 0.0:
		return
	for bubble: Dictionary in _bubbles:
		if not bubble.escape:
			continue
		var t: float = fposmod(_time * float(bubble.speed) * 0.8 + float(bubble.phase), 1.0)
		var start := Vector2(float(bubble.x) * 0.4, _center.y - globe_radius + 4.0)
		var at: Vector2 = start + Vector2(sin(t * TAU + float(bubble.phase) * 5.0) * 5.0, -t * 120.0)
		var alpha: float = (1.0 - t) * smoothstep(0.0, 0.1, t) * open
		IslandArt.soft_glow(self, at, Vector2.ONE * float(bubble.size) * 3.5, IslandArt.hdr(accent, 1.4, 0.5 * alpha))
		draw_circle(at, float(bubble.size) * 0.55, IslandArt.hdr(accent, 1.8, 0.7 * alpha))


## Water dripping from the rock under the cradle, falling and fading.
func _draw_drips() -> void:
	if _water_on <= 0.0:
		return
	for drip: Dictionary in _drips:
		var t: float = fposmod(_time * float(drip.speed) + float(drip.phase), 1.0)
		var at := Vector2(float(drip.x), 6.0 + underside_depth * 0.4 + t * t * 150.0)
		var alpha: float = smoothstep(0.0, 0.08, t) * (1.0 - t) * _water_on
		IslandArt.soft_glow(self, at, Vector2(3.0, 5.0), IslandArt.hdr(water_edge_color, 1.4, 0.55 * alpha))
