class_name JourneyIslandOcean
extends JourneyIsland
## The Ocean on the Journey screen. Its vessel of the Ancient Light: a sphere
## of sea water gripped by stone fingers rising out of an irregular rocky
## cradle. Inside, a reef mound, kelp and a small school of fish are dark
## silhouettes against the water (no outlines; the globe's edge is a soft
## fresnel glow).
##   stage 1: dark water, a few polyps glowing on the reef;
##   stage 2: the water glows softly, bubbles rise, water drips from the rock;
##   stage 3: the Ancient Light core awakens at its heart with slow rays, and
##            bubbles leave the globe.

const KELP_SEGMENTS: int = 14

@export_group("Globe")
@export var globe_radius: float = 108.0
## Height of the globe's centre above the cradle's corners.
@export var globe_lift: float = 94.0
## The stone fingers: (start angle, end angle) in degrees round the globe's
## centre (0 = right, 90 = down), their thickness at the root.
@export var fingers: PackedVector3Array = PackedVector3Array([Vector3(146.0, 202.0, 17.0), Vector3(122.0, 166.0, 13.0),
	Vector3(36.0, -18.0, 16.0), Vector3(60.0, 18.0, 12.0)])
@export var fish_count: int = 5
@export var kelp_sway: float = 7.0
@export var kelp_sway_speed: float = 0.8
@export var water_top_color: Color = Color(0.05, 0.3, 0.4)
@export var water_deep_color: Color = Color(0.008, 0.05, 0.1)
@export var water_edge_color: Color = Color(0.35, 0.9, 1.0)
## Stage 1: the water is there but dark.
@export var dark_water_color: Color = Color(0.012, 0.03, 0.052)
@export var locked_water_color: Color = Color(0.007, 0.012, 0.02)
@export var inner_color: Color = Color(0.004, 0.014, 0.026)
@export var glass_color: Color = Color(0.7, 0.96, 1.0)
@export var heart_color: Color = Color(0.85, 1.0, 1.0)
@export var polyp_color: Color = Color(0.35, 1.0, 0.85)
@export var polyp_alt_color: Color = Color(0.8, 0.55, 1.0)
@export var bubble_count: int = 16
@export var drip_count: int = 5

var _center: Vector2 = Vector2.ZERO
## The cup's dark inside, seen between the globe and the cradle's crags.
var _hollow := PackedVector2Array()
var _mound := PackedVector2Array()
var _mound_top: float = 0.0
## {outer (edge walked with the finger on its right), shape}
var _fingers: Array[Dictionary] = []
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
var _water_dark: Color = Color.BLACK


func _init() -> void:
	crown_height = globe_lift + globe_radius + 40.0


## The cradle: irregular rock rising to a crag each side of the globe, low
## and chipped in front of it.
func _build_top(rng: RandomNumberGenerator) -> PackedVector2Array:
	var controls := PackedVector2Array()
	for spec: Vector2 in [Vector2(-1.0, 0.0), Vector2(-0.94, -14.0), Vector2(-0.86, -20.0), Vector2(-0.8, -34.0),
			Vector2(-0.72, -30.0), Vector2(-0.66, -22.0), Vector2(-0.5, -16.0), Vector2(-0.3, -8.0), Vector2(-0.12, -12.0),
			Vector2(0.04, -5.0), Vector2(0.2, -10.0), Vector2(0.38, -14.0), Vector2(0.56, -20.0), Vector2(0.68, -30.0),
			Vector2(0.76, -38.0), Vector2(0.84, -24.0), Vector2(0.93, -16.0), Vector2(1.0, 0.0)]:
		var jitter: float = 0.0 if absf(spec.x) > 0.99 else rng.randf_range(-3.0, 3.0)
		controls.append(Vector2(spec.x * half_width, spec.y + jitter))
	var edge: PackedVector2Array = IslandArt.smooth_path(controls, 3)
	_center = Vector2(0.0, -globe_lift)
	# The hollow: from above the crags down to the cradle's edge between them.
	var reach: float = globe_radius + 18.0
	_hollow = PackedVector2Array([Vector2(-reach, -globe_lift * 0.55), Vector2(reach, -globe_lift * 0.55)])
	for i: int in range(edge.size() - 1, -1, -1):
		if absf(edge[i].x) < reach:
			_hollow.append(edge[i])
	return edge


func _build_kind(rng: RandomNumberGenerator) -> void:
	_build_mound()
	for spec: Vector3 in fingers:
		_fingers.append(_build_finger(spec, rng))
	# x share of the radius, height, width, step, order
	for spec: Array in [[-0.5, 84.0, 11.0, 2, 0.3], [0.3, 116.0, 12.0, 2, 0.6], [0.68, 78.0, 10.0, 3, 0.5]]:
		var x: float = float(spec[0]) * globe_radius
		_kelp.append({"root": Vector2(x, _mound_y(x) + 8.0), "height": float(spec[1]), "width": float(spec[2]),
			"phase": rng.randf() * TAU, "step": spec[3], "order": spec[4]})
	for spec: Array in [[-0.3, 1, 0.0], [0.5, 1, 0.6], [-0.7, 2, 0.2], [0.05, 2, 0.5], [0.8, 3, 0.3], [-0.05, 3, 0.8]]:
		var color: Color = polyp_alt_color if rng.randf() < 0.35 else polyp_color
		for k: int in rng.randi_range(3, 5):
			var x: float = float(spec[0]) * globe_radius * 0.85 + rng.randf_range(-9.0, 9.0)
			_polyps.append({"at": Vector2(x, _mound_y(x) + rng.randf_range(5.0, 16.0)), "size": rng.randf_range(0.6, 0.9),
				"color": color, "phase": rng.randf() * TAU, "step": spec[1], "order": float(spec[2]) + rng.randf() * 0.2})
	for i: int in fish_count:
		_fish.append({"offset": float(i) * 0.42 + rng.randf_range(-0.08, 0.08), "lane": rng.randf_range(-7.0, 7.0),
			"size": rng.randf_range(0.85, 1.15)})
	for i: int in bubble_count:
		_bubbles.append({"x": rng.randf_range(-0.6, 0.6) * globe_radius, "phase": rng.randf(), "speed": rng.randf_range(0.1, 0.18),
			"size": rng.randf_range(1.1, 2.2), "escape": i % 3 == 0})
	for i: int in drip_count:
		_drips.append({"x": rng.randf_range(-0.5, 0.5) * half_width, "phase": rng.randf(), "speed": rng.randf_range(0.35, 0.6)})


## The reef mound inside the globe: a lumpy top, its bottom on the globe's edge.
func _build_mound() -> void:
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


## A stone finger curling round the globe from spec.x to spec.y (degrees),
## thick at its root (spec.z) and thin at the tip, with a knuckle; it lies
## just over the glass, so it grips the globe.
func _build_finger(spec: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var count: int = 14
	var knuckle: float = rng.randf_range(0.45, 0.6)
	for k: int in count + 1:
		var t: float = float(k) / float(count)
		var angle: float = deg_to_rad(lerpf(spec.x, spec.y, t))
		var thickness: float = spec.z * lerpf(1.0, 0.18, pow(t, 0.8)) * (1.0 + 0.25 * exp(-pow((t - knuckle) * 7.0, 2.0)))
		var direction: Vector2 = Vector2.from_angle(angle)
		outer.append(_center + direction * (globe_radius - 2.0 + maxf(thickness, 3.0)))
		inner.append(_center + direction * (globe_radius - 8.0))
	var shape: PackedVector2Array = outer.duplicate()
	# The tip, a little beyond the last step.
	var beyond: float = spec.y + signf(spec.y - spec.x) * 5.0
	shape.append(_center + Vector2.from_angle(deg_to_rad(beyond)) * (globe_radius - 4.0))
	inner.reverse()
	shape.append_array(inner)
	# The rim follows the outer edge with the finger on its right.
	if spec.y < spec.x:
		outer.reverse()
	return {"outer": outer, "shape": shape}


## The mound's top inside the globe at x.
func _mound_y(x: float) -> float:
	for i: int in range(1, _mound.size()):
		if _mound[i].x >= x:
			return lerpf(_mound[i - 1].y, _mound[i].y, inverse_lerp(_mound[i - 1].x, _mound[i].x, x))
	return _mound_top


func _draw_back() -> void:
	_water_on = soft_level() * 0.62 + core_level() * 0.38
	_water_dark = locked_water_color.lerp(dark_water_color, unlocked())
	IslandArt.mass(self, _hollow, -globe_lift, 0.0, dark(), dark())
	IslandArt.shaded_disc(self, _center, Vector2(globe_radius, globe_radius), _water_shade, 64)
	var core: float = core_level()
	var heart: Vector2 = _center + Vector2(0.0, -6.0)
	if core > 0.0:
		rays(heart, 7, globe_radius * 0.92, 0.06, heart_color, core)
		IslandArt.soft_glow(self, heart, Vector2(globe_radius, globe_radius) * 0.75, Color(heart_color, 0.3 * core))
	var silhouette: Color = locked_water_color.lerp(inner_color, unlocked())
	_draw_fish(silhouette)
	for kelp: Dictionary in _kelp:
		_draw_kelp(kelp, silhouette)
	IslandArt.mass(self, _mound, _mound_top, _center.y + globe_radius, silhouette.lerp(water_deep_color, 0.35 * _water_on), silhouette)
	for polyp: Dictionary in _polyps:
		spark(polyp.at, 1.6 * float(polyp.size), polyp.color,
			lit(polyp.step, polyp.order) * (0.75 + 0.25 * sin(_time * 1.6 + float(polyp.phase))))
	_draw_inner_bubbles()
	if core > 0.0:
		draw_circle(heart, 5.0, IslandArt.hdr(heart_color, 3.2, core))
		IslandArt.soft_glow(self, heart, Vector2(30.0, 30.0), IslandArt.hdr(heart_color, 1.6, 0.85 * core))
	# The glass: a soft highlight high on the left, near its edge; no edge line.
	IslandArt.soft_glow(self, _center + Vector2(-0.3, -0.68) * globe_radius, Vector2(0.28, 0.13) * globe_radius,
		IslandArt.hdr(glass_color, 1.1, 0.16 * _water_on + 0.05 * unlocked()))


func _draw_front() -> void:
	for finger: Dictionary in _fingers:
		var shape: PackedVector2Array = finger.shape
		IslandArt.mass(self, shape, _center.y - globe_radius, _top_y, lifted(rock_top_color), dark())
		rim_edge(finger.outer, 6.0)
	# The globe's light on the cradle and the fingers.
	IslandArt.soft_glow(self, Vector2(0.0, -8.0), Vector2(globe_radius * 1.05, 20.0), Color(water_edge_color, 0.2 * _water_on))
	_draw_escaping_bubbles()
	_draw_drips()


## The water's colour at a point of the globe (share: 0 middle, 1 edge):
## lighter up high, deep below, a brighter edge (fresnel).
func _water_shade(point: Vector2, share: float) -> Color:
	var down: float = clampf((point.y - (_center.y - globe_radius)) / (globe_radius * 2.0), 0.0, 1.0)
	var fresnel: float = pow(share, 3.5)
	var lit_water: Color = water_top_color.lerp(water_deep_color, down).lerp(water_edge_color, fresnel * 0.45)
	var dark_water: Color = _water_dark.lerp(rim_color() * 0.25, fresnel * lerpf(locked_rim, 0.6, unlocked()) * 0.6)
	return dark_water.lerp(lit_water, _water_on)


func _draw_kelp(kelp: Dictionary, color: Color) -> void:
	var line: PackedVector2Array = IslandArt.sway_line(kelp.root, kelp.height, KELP_SEGMENTS, kelp_sway, _time * kelp_sway_speed,
		kelp.phase, 1.0, 4.0)
	var outline: PackedVector2Array = IslandArt.shaped_ribbon(line, IslandArt.kelp_widths(line.size(), kelp.width, kelp.phase))
	IslandArt.mass(self, outline, line[line.size() - 1].y, line[0].y, color.lerp(water_deep_color, 0.25 * _water_on), color)
	var tip: Vector2 = line[line.size() - 2]
	var float_on: float = lit(kelp.step, kelp.order) * (0.8 + 0.2 * sin(_time * 2.0 + float(kelp.phase)))
	draw_circle(tip, 3.0, color)
	spark(tip, 2.4, polyp_color, float_on)


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
	var strength: float = unlocked() * (0.25 + 0.75 * _water_on)
	if strength <= 0.0:
		return
	for bubble: Dictionary in _bubbles:
		if bubble.escape:
			continue
		var x: float = bubble.x
		var t: float = fposmod(_time * float(bubble.speed) + float(bubble.phase), 1.0)
		var from_y: float = _mound_y(x) - 2.0
		var to_y: float = _center.y - sqrt(maxf(globe_radius * globe_radius - x * x, 0.0)) + 6.0
		var at := Vector2(x + sin(t * TAU * 1.2 + float(bubble.phase) * 6.0) * 3.0, lerpf(from_y, to_y, t))
		var alpha: float = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.75, 1.0, t)) * strength
		IslandArt.soft_glow(self, at, Vector2.ONE * float(bubble.size) * 3.2, IslandArt.hdr(water_edge_color, 1.3, 0.45 * alpha))
		draw_circle(at, float(bubble.size) * 0.5, IslandArt.hdr(water_edge_color, 1.8, 0.7 * alpha))


func _draw_escaping_bubbles() -> void:
	var core: float = core_level()
	if core <= 0.0:
		return
	for bubble: Dictionary in _bubbles:
		if not bubble.escape:
			continue
		var t: float = fposmod(_time * float(bubble.speed) * 0.8 + float(bubble.phase), 1.0)
		var start := Vector2(float(bubble.x) * 0.4, _center.y - globe_radius + 4.0)
		var at: Vector2 = start + Vector2(sin(t * TAU + float(bubble.phase) * 5.0) * 5.0, -t * 120.0)
		var alpha: float = (1.0 - t) * smoothstep(0.0, 0.1, t) * core
		IslandArt.soft_glow(self, at, Vector2.ONE * float(bubble.size) * 3.5, IslandArt.hdr(accent, 1.4, 0.5 * alpha))
		draw_circle(at, float(bubble.size) * 0.55, IslandArt.hdr(accent, 1.8, 0.7 * alpha))


## Water dripping from the rock under the cradle, falling and fading.
func _draw_drips() -> void:
	var soft: float = soft_level()
	if soft <= 0.0:
		return
	for drip: Dictionary in _drips:
		var t: float = fposmod(_time * float(drip.speed) + float(drip.phase), 1.0)
		var at := Vector2(float(drip.x), _top_y + underside_depth * 0.4 + t * t * 150.0)
		var alpha: float = smoothstep(0.0, 0.08, t) * (1.0 - t) * soft
		IslandArt.soft_glow(self, at, Vector2(3.0, 5.0), IslandArt.hdr(water_edge_color, 1.4, 0.55 * alpha))
