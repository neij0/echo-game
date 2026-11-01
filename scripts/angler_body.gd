class_name AnglerBody
extends Node2D
## The Angler's body (boss), drawn in the world so only real lights show it
## (the Echo's light and its own lure): a dark silhouette with detail that the
## light picks out. Seen in the game's 3/4 view: the back from above, and a
## darker flank below it (the body drawn again lower, like a rock's face).
## A spine of points follows the head (follow-the-leader), so turning swings
## the tail out; a travelling wave adds the swimming undulation.
## Parts: wide head with a deep underbite (lower jaw wider, reaching past the
## upper lip), long uneven needle teeth, armour plates down the back, ragged
## pectoral / pelvic / tail fins with rippling rays, a ragged dorsal ridge,
## scars and barnacle clusters, gill slits that pulse, small eye sockets.
## Driven by AnglerVisual (update_pose); points are worked out in world space.

@export_group("Size")
@export var spine_count: int = 12
## Head centre (first spine point) to the tail root (last spine point).
@export var body_length: float = 175.0
@export var head_half_width: float = 52.0
## How far the head reaches in front of the first spine point.
@export var head_front: float = 30.0
## Half width along the spine (head -> tail root), as a share of head_half_width.
@export var width_profile: PackedFloat32Array = PackedFloat32Array([1.0, 1.02, 0.98, 0.9, 0.79, 0.67, 0.55, 0.44, 0.34, 0.25, 0.18, 0.13])
## 3/4 view: how far the flank shows below the back.
@export var flank_depth: float = 16.0
## Side profile: no part of the spine tilts more than this from horizontal.
@export var max_segment_tilt_degrees: float = 38.0

@export_group("Swimming")
## Sideways wave along the body: amplitude at the tail (pixels), less at the head.
@export var wave_amplitude: float = 14.0
## Waves along the body at once.
@export var wave_count: float = 0.85
## Share of the wave amplitude kept at the head.
@export_range(0.0, 1.0) var wave_head_share: float = 0.08
## Telegraph: how much the body coils (spine shorter, curled to one side).
@export_range(0.0, 1.0) var coil_compress: float = 0.18
@export var coil_curl: float = 26.0

@export_group("Jaw")
## Underbite: the lower jaw reaches this far past the upper lip when closed...
@export var underbite: float = 12.0
## ...and this much further when fully open.
@export var jaw_open_reach: float = 26.0
## The lower jaw is this much wider than the head.
@export var jaw_width_scale: float = 1.08
@export var lower_teeth: int = 11
@export var upper_teeth: int = 8
@export var tooth_length_min: float = 7.0
@export var tooth_length_max: float = 24.0
@export var tooth_width: float = 3.2

@export_group("Fins")
@export var pectoral_at: float = 0.3
@export var pectoral_length: float = 50.0
@export var pectoral_rays: int = 7
@export var pectoral_spread_degrees: float = 75.0
@export var pelvic_at: float = 0.58
@export var pelvic_length: float = 24.0
@export var tail_fin_length: float = 58.0
@export var tail_fin_spread_degrees: float = 46.0
@export var tail_fin_rays: int = 9
## Ray ripple: degrees and cycles per second.
@export var fin_ripple_degrees: float = 9.0
@export var fin_ripple_speed: float = 1.3

@export_group("Back")
@export var plate_count: int = 4
@export var plate_from: float = 0.12
@export var plate_to: float = 0.66
@export var dorsal_from: float = 0.4
@export var dorsal_to: float = 0.86
@export var dorsal_spikes: int = 9
@export var scar_count: int = 5
@export var barnacle_clusters: int = 4
@export var gill_at: float = 0.2
@export var gill_slits: int = 3
## Gill pulse: cycles per second.
@export var gill_speed: float = 0.55
## Seed of the scars, barnacles, ragged edges and teeth (the same every time).
@export var detail_seed: int = 7

@export_group("Colors")
## All dark: they only show where a light reaches them.
@export var back_color: Color = Color(0.05, 0.055, 0.065)
@export var flank_color: Color = Color(0.022, 0.024, 0.03)
@export var plate_color: Color = Color(0.085, 0.09, 0.095)
@export var plate_edge_color: Color = Color(0.03, 0.032, 0.036)
@export var fin_color: Color = Color(0.06, 0.07, 0.08, 0.92)
@export var fin_ray_color: Color = Color(0.11, 0.12, 0.13, 0.9)
@export var rim_color: Color = Color(0.14, 0.16, 0.18)
@export var scar_color: Color = Color(0.17, 0.16, 0.15)
@export var barnacle_color: Color = Color(0.24, 0.25, 0.21)
@export var tooth_color: Color = Color(0.7, 0.67, 0.58)
@export var mouth_color: Color = Color(0.02, 0.004, 0.008)
@export var gum_color: Color = Color(0.12, 0.03, 0.035)
@export var gill_color: Color = Color(0.13, 0.03, 0.03)
@export var socket_color: Color = Color(0.01, 0.01, 0.012)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.4)
## The pale belly shown when it rolls onto its side (stunned, dying).
@export var belly_color: Color = Color(0.3, 0.28, 0.24)
@export var belly_ridge_color: Color = Color(0.4, 0.37, 0.31)

## World points: the spine (head first), its shape this frame (with the
## undulation), the forward direction at each point and the half widths.
var spine: PackedVector2Array = PackedVector2Array()
var shape: PackedVector2Array = PackedVector2Array()
var forwards: PackedVector2Array = PackedVector2Array()
var widths: PackedFloat32Array = PackedFloat32Array()
## Set by AnglerVisual each frame.
var heading: Vector2 = Vector2.RIGHT
var jaw_open: float = 0.0
var coil: float = 0.0
var lunge: float = 0.0
## 0 = upright, 1 = rolled on its side (stunned: the pale belly shows on top).
var roll: float = 0.0
var gill_open: float = 0.0
var fin_tuck: float = 0.0
## 0-1: fins spread wide and long (the tail sweep's warning).
var fin_flare: float = 0.0
## Sideways bend at the tail (pixels, signed): the tail sweep.
var sweep_curl: float = 0.0
## The pectoral fin rays drawn last frame (world segments: root, tip), for
## AnglerGlow's fin flare.
var fin_rays: Array[PackedVector2Array] = []
## Extra sideways kink at the middle (hit flinch), pixels.
var kink: float = 0.0
var _time: float = 0.0
var _wave_phase: float = 0.0
var _rng := RandomNumberGenerator.new()
var _scars: Array[Vector4] = []
var _barnacles: Array[Vector3] = []
var _lower_teeth: Array[Vector3] = []
var _upper_teeth: Array[Vector3] = []
var _ragged: PackedFloat32Array = PackedFloat32Array()
## The outline of the back this frame (a union of the body pieces, so a
## coiled or bent body never makes a broken polygon).
var _outline: PackedVector2Array = PackedVector2Array()
var _batch := ShapeBatch.new()


func _ready() -> void:
	_build_details()


## Mirrors the body round the vertical line x = center_x (a turn: the fish
## faces the other way at once).
func mirror_x(center_x: float) -> void:
	heading.x = -heading.x
	for i: int in spine.size():
		spine[i].x = 2.0 * center_x - spine[i].x
	_update_shape()
	_build_outline()


## Lays the spine out straight behind head_position.
func reset(head_position: Vector2, direction: Vector2) -> void:
	heading = direction.normalized()
	spine.resize(spine_count)
	for i: int in spine_count:
		spine[i] = head_position - heading * _segment() * i
	_update_shape()
	_build_outline()


## One frame: the head moves to head_position facing heading; wave_speed in
## cycles per second, wave_scale scales the amplitude.
func update_pose(head_position: Vector2, delta: float, wave_speed: float, wave_scale: float) -> void:
	_time += delta
	_wave_phase += TAU * wave_speed * delta
	if spine.size() != spine_count:
		reset(head_position, heading)
	var segment: float = _segment() * (1.0 - coil_compress * coil)
	# Side profile: every segment stays within max_segment_tilt_degrees of
	# straight back, so swimming up / down never stands the body up.
	var back := Vector2(-signf(heading.x) if heading.x != 0.0 else -1.0, 0.0)
	var limit: float = deg_to_rad(max_segment_tilt_degrees)
	spine[0] = head_position
	for i: int in range(1, spine_count):
		var offset: Vector2 = spine[i] - spine[i - 1]
		if offset.length() < 0.001:
			offset = -heading
		var direction: Vector2 = back.rotated(clampf(back.angle_to(offset), -limit, limit))
		spine[i] = spine[i - 1] + direction * segment
	_update_shape(wave_scale)
	_build_outline()
	queue_redraw()


func _segment() -> float:
	return body_length / float(maxi(spine_count - 1, 1))


func _update_shape(wave_scale: float = 1.0) -> void:
	var count: int = spine.size()
	shape.resize(count)
	forwards.resize(count)
	widths.resize(count)
	for i: int in count:
		var forward: Vector2 = heading if i == 0 else (spine[i - 1] - spine[i]).normalized()
		forwards[i] = forward
		var s: float = float(i) / float(maxi(count - 1, 1))
		var side: Vector2 = forward.orthogonal()
		var amplitude: float = wave_amplitude * wave_scale * lerpf(wave_head_share, 1.0, s * s)
		var lateral: float = sin(_wave_phase - s * TAU * wave_count) * amplitude
		lateral += coil * coil_curl * s * s + kink * sin(s * PI) + sweep_curl * s * s
		shape[i] = spine[i] + side * lateral
		widths[i] = head_half_width * _profile(s)
	# Forward directions from the waved shape (the outline follows the wave).
	for i: int in range(1, count):
		forwards[i] = (shape[i - 1] - shape[i]).normalized()


func _profile(s: float) -> float:
	if width_profile.is_empty():
		return 1.0
	var x: float = clampf(s, 0.0, 1.0) * float(width_profile.size() - 1)
	var k: int = mini(floori(x), width_profile.size() - 2)
	if width_profile.size() == 1:
		return width_profile[0]
	return lerpf(width_profile[k], width_profile[k + 1], x - float(k))


# --- Sampling the body (also used by AnglerGlow / AnglerLure) -----------------

## A point on the back: s = 0 head centre .. 1 tail root, v = -1 .. 1 across
## (left .. right of the heading), in world space.
func point_at(s: float, v: float) -> Vector2:
	var frame: Array = _frame(s)
	return (frame[0] as Vector2) + (frame[1] as Vector2).orthogonal() * v * float(frame[2])


func forward_at(s: float) -> Vector2:
	return _frame(s)[1] as Vector2


func half_width_at(s: float) -> float:
	return float(_frame(s)[2])


## [point, forward, half width] at s, from the waved shape.
func _frame(s: float) -> Array:
	var count: int = shape.size()
	if count < 2:
		return [global_position, heading, head_half_width]
	var x: float = clampf(s, 0.0, 1.0) * float(count - 1)
	var k: int = mini(floori(x), count - 2)
	var t: float = x - float(k)
	return [shape[k].lerp(shape[k + 1], t), forwards[k].lerp(forwards[k + 1], t).normalized(), lerpf(widths[k], widths[k + 1], t)]


## Where the head's front edge is (the upper lip), world space.
func get_head_center() -> Vector2:
	return (shape[0] if not shape.is_empty() else global_position) + heading * lunge


## The outline of the back (head cap + both sides + tail root), world space.
func get_outline() -> PackedVector2Array:
	return _outline


## Joins the head cap and one quad per spine segment into one polygon.
func _build_outline() -> void:
	var count: int = shape.size()
	_outline = PackedVector2Array()
	if count < 2:
		return
	var center: Vector2 = get_head_center()
	var side: Vector2 = heading.orthogonal()
	var cap := PackedVector2Array()
	var steps: int = 14
	for k: int in steps + 1:
		var angle: float = PI * 0.5 - PI * float(k) / float(steps)
		cap.append(center + heading * cos(angle) * head_front + side * sin(angle) * widths[0])
	cap.append(shape[1] - forwards[1].orthogonal() * widths[1])
	cap.append(shape[1] + forwards[1].orthogonal() * widths[1])
	var merged: PackedVector2Array = cap
	for i: int in count - 1:
		var quad := PackedVector2Array([
			shape[i] + forwards[i].orthogonal() * widths[i], shape[i + 1] + forwards[i + 1].orthogonal() * widths[i + 1],
			shape[i + 1] - forwards[i + 1].orthogonal() * widths[i + 1], shape[i] - forwards[i].orthogonal() * widths[i],
		])
		merged = _union(merged, quad)
	_outline = merged


## The outer polygon of a union (holes and slivers dropped).
static func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var pieces: Array[PackedVector2Array] = Geometry2D.merge_polygons(a, b)
	var best: PackedVector2Array = a
	var best_area: float = -1.0
	for piece: PackedVector2Array in pieces:
		if Geometry2D.is_polygon_clockwise(piece) != Geometry2D.is_polygon_clockwise(a) and pieces.size() > 1:
			continue
		var area: float = absf(_area(piece))
		if area > best_area:
			best_area = area
			best = piece
	return best


static func _area(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in points.size():
		var j: int = (i + 1) % points.size()
		total += points[i].x * points[j].y - points[j].x * points[i].y
	return total * 0.5


## The whole silhouette from above: the back and the lower jaw (rim flash,
## charge afterimages).
func get_silhouette() -> PackedVector2Array:
	if _outline.size() < 3:
		return _outline
	return _union(_outline, _jaw_polygon(0.0))


## The hurtbox (world): the silhouette (back + lower jaw) and its 3/4 flank
## below it, as drawn this frame (tilt, flip, undulation, open jaw).
func get_hurt_polygon() -> PackedVector2Array:
	var silhouette: PackedVector2Array = get_silhouette()
	if silhouette.size() < 3:
		return silhouette
	var flank := PackedVector2Array()
	for point: Vector2 in silhouette:
		flank.append(point + Vector2(0.0, flank_depth))
	return _union(silhouette, flank)


## The mouth with the jaw open by open_share (world), at the current lunge:
## the bite's reach.
func get_mouth_polygon(open_share: float) -> PackedVector2Array:
	var saved: float = jaw_open
	jaw_open = open_share
	var polygon: PackedVector2Array = _jaw_polygon(0.0)
	jaw_open = saved
	return polygon


## The armour plates (world polygons), for the Exposed outline.
func get_plates() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for p: int in plate_count:
		var s0: float = lerpf(plate_from, plate_to, float(p) / float(plate_count))
		var s1: float = s0 + (plate_to - plate_from) / float(plate_count) * 1.25
		var polygon := PackedVector2Array()
		for k: int in 7:
			var v: float = lerpf(-0.78, 0.78, float(k) / 6.0)
			# The front edge bulges forward in the middle (overlapping scales).
			polygon.append(point_at(s0 - 0.03 * (1.0 - v * v), v))
		for k: int in 7:
			var v: float = lerpf(0.7, -0.7, float(k) / 6.0)
			polygon.append(point_at(s1, v))
		result.append(polygon)
	return result


## Weak spots shown while Exposed: the gills and the soft gap behind the head.
func get_weak_spots() -> PackedVector2Array:
	return PackedVector2Array([point_at(gill_at, 0.82), point_at(gill_at, -0.82), point_at(plate_from - 0.04, 0.0)])


## Teeth tips in world space (the bite flash).
func get_teeth() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for tooth: Vector3 in _lower_teeth:
		result.append(_lower_tooth(tooth))
	for tooth: Vector3 in _upper_teeth:
		result.append(_upper_tooth(tooth))
	return result


# --- Details (fixed per seed) -------------------------------------------------

func _build_details() -> void:
	_rng.seed = detail_seed
	_scars.clear()
	for i: int in scar_count:
		# s, v, angle (radians), length (pixels)
		_scars.append(Vector4(_rng.randf_range(0.15, 0.7), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.7, 0.7), _rng.randf_range(14.0, 30.0)))
	_barnacles.clear()
	for i: int in barnacle_clusters:
		var s: float = _rng.randf_range(0.25, 0.65)
		var v: float = _rng.randf_range(-0.55, 0.55)
		for b: int in _rng.randi_range(4, 7):
			_barnacles.append(Vector3(s + _rng.randf_range(-0.03, 0.03), v + _rng.randf_range(-0.12, 0.12), _rng.randf_range(1.8, 4.2)))
	_lower_teeth.clear()
	for i: int in lower_teeth:
		# angle across the jaw (-1..1), length, sideways hook
		_lower_teeth.append(Vector3(lerpf(-0.86, 0.86, float(i) / float(maxi(lower_teeth - 1, 1))) + _rng.randf_range(-0.04, 0.04),
			_rng.randf_range(tooth_length_min, tooth_length_max) * (1.0 if i % 3 != 1 else 0.6), _rng.randf_range(-0.25, 0.25)))
	_upper_teeth.clear()
	for i: int in upper_teeth:
		_upper_teeth.append(Vector3(lerpf(-0.75, 0.75, float(i) / float(maxi(upper_teeth - 1, 1))) + _rng.randf_range(-0.05, 0.05),
			_rng.randf_range(tooth_length_min * 0.8, tooth_length_max * 0.6), _rng.randf_range(-0.2, 0.2)))
	_ragged.resize(64)
	for i: int in _ragged.size():
		_ragged[i] = _rng.randf_range(0.72, 1.12)


## Lower jaw: centre and half sizes (forward, across).
func _jaw_frame() -> Array:
	var center: Vector2 = get_head_center()
	var reach: float = underbite + jaw_open_reach * jaw_open
	var jaw_center: Vector2 = center + heading * (reach * 0.5)
	return [jaw_center, head_front + reach * 0.5, widths[0] * jaw_width_scale if not widths.is_empty() else head_half_width]


func _jaw_rim(angle_share: float, inset: float) -> Vector2:
	var frame: Array = _jaw_frame()
	var angle: float = angle_share * PI * 0.5
	var side: Vector2 = heading.orthogonal()
	return (frame[0] as Vector2) + heading * cos(angle) * (float(frame[1]) - inset) + side * sin(angle) * (float(frame[2]) - inset)


func _lower_tooth(tooth: Vector3) -> PackedVector2Array:
	var base: Vector2 = _jaw_rim(tooth.x, 4.0)
	var inward: Vector2 = (get_head_center() - base).normalized()
	# They point back over the upper lip and outward a little (an open trap).
	var direction: Vector2 = inward.rotated(tooth.z + tooth.x * 0.5).lerp(heading, 0.25 - 0.2 * jaw_open).normalized()
	var length: float = tooth.y * (0.8 + 0.4 * jaw_open)
	var side: Vector2 = direction.orthogonal() * tooth_width * 0.5
	var tip: Vector2 = base + direction * length + direction.orthogonal() * tooth.z * length * 0.3
	return PackedVector2Array([base + side, tip, base - side])


func _upper_tooth(tooth: Vector3) -> PackedVector2Array:
	var center: Vector2 = get_head_center()
	var angle: float = tooth.x * PI * 0.5
	var side: Vector2 = heading.orthogonal()
	var w0: float = widths[0] if not widths.is_empty() else head_half_width
	var base: Vector2 = center + heading * cos(angle) * (head_front - 3.0) + side * sin(angle) * (w0 - 3.0)
	var direction: Vector2 = (base - center).normalized().rotated(tooth.z).lerp(heading, 0.5).normalized()
	var half: Vector2 = direction.orthogonal() * tooth_width * 0.45
	return PackedVector2Array([base + half, base + direction * tooth.y * (0.6 + 0.6 * jaw_open), base - half])


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	if shape.size() < 2:
		return
	var outline: PackedVector2Array = get_outline()
	var flank: float = flank_depth
	var down := Vector2(0.0, flank)
	var local_outline: PackedVector2Array = _local(outline)
	# Soft ground shadow, then everything under the back.
	draw_colored_polygon(_offset(local_outline, Vector2(0.0, flank + 10.0)), shadow_color)
	_draw_tail_fin()
	_draw_fin(pelvic_at, pelvic_length, 4, 50.0, 1.0)
	_draw_fin(pelvic_at, pelvic_length, 4, 50.0, -1.0)
	fin_rays.clear()
	var pectoral: float = pectoral_length * (1.0 - 0.45 * fin_tuck) * (1.0 + 0.7 * fin_flare)
	var spread: float = pectoral_spread_degrees + 35.0 * fin_flare
	_draw_fin(pectoral_at, pectoral, pectoral_rays, spread, 1.0, true)
	_draw_fin(pectoral_at, pectoral, pectoral_rays, spread, -1.0, true)
	# The flank (3/4 view) and the lower jaw's flank.
	draw_colored_polygon(_offset(local_outline, down), flank_color)
	var jaw: PackedVector2Array = _jaw_polygon(0.0)
	draw_colored_polygon(_offset(_local(jaw), down), flank_color)
	_draw_mouth(jaw)
	# The back.
	draw_colored_polygon(local_outline, back_color)
	_draw_plates()
	_draw_dorsal()
	_draw_scars()
	_draw_barnacles()
	_draw_belly()
	_draw_gills()
	_draw_eye_sockets()
	for tooth: Vector3 in _upper_teeth:
		_batch.add_convex(_local(_upper_tooth(tooth)), tooth_color)
	_batch.draw(self)
	# A faint rim along the edges that face up (they catch light first).
	_draw_rim(outline)


func _draw_mouth(jaw: PackedVector2Array) -> void:
	draw_colored_polygon(_local(jaw), back_color.lerp(flank_color, 0.4))
	if jaw_open > 0.02:
		# The open mouth: the dark cavity between the lips, with gums at its rim.
		var cavity: PackedVector2Array = _jaw_polygon(5.0 + 4.0 * (1.0 - jaw_open))
		draw_colored_polygon(_local(cavity), gum_color.lerp(mouth_color, 0.5))
		draw_colored_polygon(_local(_jaw_polygon(9.0)), mouth_color)
	for tooth: Vector3 in _lower_teeth:
		_batch.add_convex(_local(_lower_tooth(tooth)), tooth_color)
	_batch.draw(self)


## The lower jaw's outline (inset = pixels inside its rim), the front half only.
func _jaw_polygon(inset: float) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var steps: int = 16
	for k: int in steps + 1:
		polygon.append(_jaw_rim(lerpf(1.0, -1.0, float(k) / float(steps)), inset))
	# Close it behind the upper lip (hidden under the head).
	var center: Vector2 = get_head_center()
	polygon.append(center - heading * 8.0)
	return polygon


func _draw_fin(at: float, length: float, rays: int, spread_degrees: float, side: float, record: bool = false) -> void:
	var root: Vector2 = point_at(at, side * 0.92)
	var forward: Vector2 = forward_at(at)
	var outward: Vector2 = forward.orthogonal() * side
	var base_angle: float = (outward.rotated(-side * deg_to_rad(28.0))).angle()
	# The edge: ray tips with notches between them (ragged).
	var edge := PackedVector2Array([root + forward * length * 0.2])
	var ray_tips := PackedVector2Array()
	for r: int in rays:
		var t: float = float(r) / float(maxi(rays - 1, 1))
		var ripple: float = sin(_time * TAU * fin_ripple_speed - t * 2.5 + side) * deg_to_rad(fin_ripple_degrees)
		var angle: float = base_angle + side * deg_to_rad(spread_degrees) * (t - 0.2) + ripple
		var ragged: float = _ragged[(r * 7 + (3 if side > 0.0 else 11)) % _ragged.size()]
		var tip: Vector2 = root + Vector2.from_angle(angle) * length * ragged * (1.0 - 0.25 * t)
		ray_tips.append(tip)
		edge.append(tip)
		if r < rays - 1:
			var next_angle: float = angle + side * deg_to_rad(spread_degrees) / float(rays - 1) * 0.5
			edge.append(root + Vector2.from_angle(next_angle) * length * 0.7 * ragged)
	edge.append(root - forward * length * 0.22)
	var local_root: Vector2 = to_local(root)
	for k: int in edge.size() - 1:
		_batch.add_convex(PackedVector2Array([local_root, to_local(edge[k]), to_local(edge[k + 1])]), fin_color)
	for tip: Vector2 in ray_tips:
		_batch.add_segment(local_root, to_local(tip), 1.6, 0.6, fin_ray_color)
		if record:
			fin_rays.append(PackedVector2Array([root, tip]))
	_batch.draw(self)


func _draw_tail_fin() -> void:
	var count: int = shape.size()
	var root: Vector2 = shape[count - 1]
	var back: Vector2 = -forwards[count - 1]
	var swing: float = sin(_wave_phase - TAU * wave_count) * 0.35
	var points := PackedVector2Array([to_local(root + back.orthogonal() * widths[count - 1])])
	var tips := PackedVector2Array()
	for r: int in tail_fin_rays:
		var t: float = float(r) / float(maxi(tail_fin_rays - 1, 1))
		var angle: float = back.angle() + swing + deg_to_rad(tail_fin_spread_degrees) * (t * 2.0 - 1.0)
		angle += sin(_time * TAU * fin_ripple_speed * 0.8 - t * 3.0) * deg_to_rad(fin_ripple_degrees * 0.6)
		# Longer at the two lobes, shorter in the middle (forked), ragged.
		var lobe: float = 0.7 + 0.3 * absf(t * 2.0 - 1.0)
		var tip: Vector2 = root + Vector2.from_angle(angle) * tail_fin_length * lobe * _ragged[(r * 5 + 21) % _ragged.size()]
		tips.append(tip)
		points.append(to_local(tip))
	points.append(to_local(root - back.orthogonal() * widths[count - 1]))
	var local_root: Vector2 = to_local(root)
	for k: int in points.size() - 1:
		_batch.add_convex(PackedVector2Array([local_root, points[k], points[k + 1]]), fin_color)
	for tip: Vector2 in tips:
		_batch.add_segment(local_root, to_local(tip), 2.0, 0.6, fin_ray_color)
	_batch.draw(self)


func _draw_plates() -> void:
	for polygon: PackedVector2Array in get_plates():
		var local_polygon: PackedVector2Array = _local(polygon)
		# A strip of quads (front edge point k with the rear edge point facing
		# it), so a bent body never makes a broken polygon.
		var half: int = local_polygon.size() / 2
		for k: int in half - 1:
			_batch.add_convex(PackedVector2Array([local_polygon[k], local_polygon[k + 1],
				local_polygon[local_polygon.size() - 2 - k], local_polygon[local_polygon.size() - 1 - k]]), plate_color)
		# The rear edge is darker (the next plate overlaps it).
		_batch.add_polyline(local_polygon.slice(half), plate_edge_color, 2.0)
	_batch.draw(self)


func _draw_dorsal() -> void:
	for i: int in dorsal_spikes:
		var s: float = lerpf(dorsal_from, dorsal_to, float(i) / float(maxi(dorsal_spikes - 1, 1)))
		var base: Vector2 = point_at(s, 0.0)
		var forward: Vector2 = forward_at(s)
		var length: float = lerpf(16.0, 7.0, float(i) / float(dorsal_spikes)) * _ragged[(i * 3 + 40) % _ragged.size()]
		var tip: Vector2 = base - forward * length + forward.orthogonal() * sin(_time * 1.3 + s * 6.0) * 2.0
		var side: Vector2 = forward.orthogonal() * 2.6
		_batch.add_convex(_local(PackedVector2Array([base + side + forward * 3.0, tip, base - side + forward * 3.0])), plate_color.lightened(0.1))
	_batch.draw(self)


## Rolled onto its side: the half of the back facing up the screen turns into
## the pale belly (one body; the plates and spikes on that side are covered).
func _draw_belly() -> void:
	if roll <= 0.01:
		return
	var up_side: float = 1.0 if heading.orthogonal().y < 0.0 else -1.0
	var steps: int = 12
	var color: Color = Color(belly_color, roll)
	for k: int in steps:
		var s0: float = lerpf(0.02, 0.9, float(k) / float(steps))
		var s1: float = lerpf(0.02, 0.9, float(k + 1) / float(steps))
		_batch.add_convex(_local(PackedVector2Array([point_at(s0, up_side), point_at(s1, up_side),
			point_at(s1, up_side * 0.15), point_at(s0, up_side * 0.15)])), color)
	# Faint ridges along the belly.
	for r: int in 3:
		var v: float = up_side * lerpf(0.35, 0.8, float(r) / 2.0)
		var ridge := PackedVector2Array()
		for k: int in steps + 1:
			ridge.append(point_at(lerpf(0.08, 0.8, float(k) / float(steps)), v))
		_batch.add_polyline(_local(ridge), Color(belly_ridge_color, roll * 0.8), 1.4)
	_batch.draw(self)


func _draw_scars() -> void:
	for scar: Vector4 in _scars:
		var center: Vector2 = point_at(scar.x, scar.y)
		var direction: Vector2 = forward_at(scar.x).orthogonal().rotated(scar.z)
		var a: Vector2 = center - direction * scar.w * 0.5
		var b: Vector2 = center + direction * scar.w * 0.5
		var bend: Vector2 = forward_at(scar.x) * 3.0
		draw_polyline(_local(PackedVector2Array([a, center + bend, b])), scar_color, 1.6, false)
		draw_polyline(_local(PackedVector2Array([a + Vector2(0.0, 1.5), center + bend + Vector2(0.0, 1.5), b + Vector2(0.0, 1.5)])), flank_color, 1.0, false)


func _draw_barnacles() -> void:
	for barnacle: Vector3 in _barnacles:
		var center: Vector2 = to_local(point_at(barnacle.x, barnacle.y))
		draw_circle(center, barnacle.z, barnacle_color, true, -1.0, false)
		draw_circle(center + Vector2(0.0, -barnacle.z * 0.2), barnacle.z * 0.38, socket_color, true, -1.0, false)


func _draw_gills() -> void:
	for side: float in [-1.0, 1.0]:
		for g: int in gill_slits:
			var s: float = gill_at + float(g) * 0.035
			var a: Vector2 = point_at(s, side * 0.62)
			var b: Vector2 = point_at(s + 0.012, side * 0.98)
			var open: float = 1.5 + 3.0 * gill_open
			draw_line(to_local(a), to_local(b), gill_color, open, false)
			draw_line(to_local(a - forward_at(s) * 1.5), to_local(b - forward_at(s) * 1.5), rim_color, 1.0, false)


func _draw_eye_sockets() -> void:
	for side: float in [-1.0, 1.0]:
		draw_circle(to_local(get_eye(side)), 5.5, socket_color, true, -1.0, false)


## An eye's world position (side = -1 / 1).
func get_eye(side: float) -> Vector2:
	return point_at(0.04, side * 0.6) + heading * (head_front * 0.35 + lunge)


func _draw_rim(outline: PackedVector2Array) -> void:
	var count: int = outline.size()
	for i: int in count - 1:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[i + 1]
		var normal: Vector2 = (b - a).orthogonal().normalized()
		# Edges facing up the screen (normal pointing up) catch the light.
		var facing: float = -normal.y
		if facing > 0.25:
			draw_line(to_local(a), to_local(b), Color(rim_color, clampf((facing - 0.25) * 1.6, 0.0, 1.0)), 1.6, false)


func _local(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	var inverse: Transform2D = global_transform.affine_inverse()
	for i: int in points.size():
		result[i] = inverse * points[i]
	return result


static func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i: int in points.size():
		result[i] = points[i] + by
	return result
