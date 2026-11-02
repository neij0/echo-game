class_name IslandArt
extends RefCounted
## Drawing helpers for the Journey islands' "silhouette + glow" look, with no
## outlines: solid masses with a vertical gradient, a soft rim light (a strip
## that fades away from the edge, never a drawn line), soft glows (one radial
## texture; over-bright colours bloom under a GlowEnvironment), soft beams of
## light, shaded discs (water, glass) and the layered jagged rock that hangs
## under an island and fades into the dark. Static: call them inside a _draw of
## the canvas item they draw on.

static var _glow: GradientTexture2D


## A soft round glow: a bright core fading out smoothly (HDR, so no rings).
static func glow_texture() -> GradientTexture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		for stop: Vector2 in [Vector2(0.1, 0.8), Vector2(0.25, 0.45), Vector2(0.42, 0.2), Vector2(0.6, 0.07), Vector2(0.8, 0.018)]:
			gradient.add_point(stop.x, Color(1.0, 1.0, 1.0, stop.y))
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
		_glow.use_hdr = true
	return _glow


## A soft glow round center (radii: an ellipse); color's alpha scales it.
static func soft_glow(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	if color.a <= 0.002 or radii.x <= 0.0 or radii.y <= 0.0:
		return
	canvas.draw_texture_rect(glow_texture(), Rect2(center - radii, radii * 2.0), false, color)


## An over-bright copy of color (energy > 1 blooms) with an alpha.
static func hdr(color: Color, energy: float, alpha: float = 1.0) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


## Colours of a vertical gradient: top_color at top_y to bottom_color at
## bottom_y (linear in y, so a polygon shows it exactly).
static func vertical_colors(points: PackedVector2Array, top_y: float, bottom_y: float, top_color: Color,
		bottom_color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(points.size())
	var span: float = bottom_y - top_y
	for i: int in points.size():
		var t: float = clampf((points[i].y - top_y) / span, 0.0, 1.0) if absf(span) > 0.001 else 0.0
		colors[i] = top_color.lerp(bottom_color, t)
	return colors


## A solid mass (a simple polygon, concave is fine) with a vertical gradient.
static func mass(canvas: CanvasItem, points: PackedVector2Array, top_y: float, bottom_y: float, top_color: Color,
		bottom_color: Color) -> void:
	if points.size() >= 3:
		canvas.draw_polygon(points, vertical_colors(points, top_y, bottom_y, top_color, bottom_color))


## Unit normals of a polyline, pointing to the right of the walking direction
## (for a top edge walked left to right: down, into the mass under it).
static func edge_normals(edge: PackedVector2Array) -> PackedVector2Array:
	var normals := PackedVector2Array()
	var count: int = edge.size()
	for i: int in count:
		var tangent: Vector2 = (edge[mini(i + 1, count - 1)] - edge[maxi(i - 1, 0)]).normalized()
		normals.append(Vector2(-tangent.y, tangent.x))
	return normals


## 0-1 per point of an edge (walked with the mass on its right): how much it
## faces a light shining along light_dir (e.g. (0.5, 1) = from the upper
## left); never below floor_value.
static func facing(edge: PackedVector2Array, light_dir: Vector2, floor_value: float = 0.0) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var toward_light: Vector2 = -light_dir.normalized()
	for normal: Vector2 in edge_normals(edge):
		result.append(lerpf(floor_value, 1.0, clampf(-normal.dot(toward_light), 0.0, 1.0)))
	return result


## A soft light along an edge (walked with the mass on its right): brightest
## on the edge, fading to nothing width px inside. strengths (0-1 per point,
## optional, see facing) dim it where the edge turns away from the light.
static func rim(canvas: CanvasItem, edge: PackedVector2Array, width: float, color: Color,
		strengths: PackedFloat32Array = PackedFloat32Array()) -> void:
	_edge_strip(canvas, edge, width, color, strengths)


## A faint haze just outside an edge (same rule), fading outwards over width px.
static func haze(canvas: CanvasItem, edge: PackedVector2Array, width: float, color: Color,
		strengths: PackedFloat32Array = PackedFloat32Array()) -> void:
	_edge_strip(canvas, edge, -width, color, strengths)


static func _edge_strip(canvas: CanvasItem, edge: PackedVector2Array, offset: float, color: Color,
		strengths: PackedFloat32Array) -> void:
	var count: int = edge.size()
	if count < 2 or color.a <= 0.002:
		return
	var normals: PackedVector2Array = edge_normals(edge)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i: int in count:
		var strength: float = strengths[i] if i < strengths.size() else 1.0
		points.append(edge[i])
		colors.append(Color(color, color.a * strength))
	for i: int in count:
		points.append(edge[i] + normals[i] * offset)
		colors.append(Color(color, 0.0))
	var indices := PackedInt32Array()
	for i: int in count - 1:
		indices.append_array([i, i + 1, count + i + 1, i, count + i + 1, count + i])
	_triangles(canvas, indices, points, colors)


## A soft column of light rising from base: height px, half widths at the base
## and the top; brightest along its middle and low down, fading upwards.
static func beam(canvas: CanvasItem, base: Vector2, height: float, base_half: float, top_half: float, color: Color,
		levels: int = 12) -> void:
	if color.a <= 0.002:
		return
	var across: PackedFloat32Array = PackedFloat32Array([-1.0, -0.45, 0.0, 0.45, 1.0])
	var profile: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0, 0.5, 0.0])
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for k: int in levels + 1:
		var t: float = float(k) / float(levels)
		var half: float = lerpf(base_half, top_half, t)
		var fade: float = pow(1.0 - t, 1.7) * smoothstep(0.0, 0.06, t)
		for j: int in across.size():
			points.append(base + Vector2(across[j] * half, -height * t))
			colors.append(Color(color, color.a * profile[j] * fade))
	var row: int = across.size()
	for k: int in levels:
		for j: int in row - 1:
			var a: int = k * row + j
			indices.append_array([a, a + 1, a + row + 1, a, a + row + 1, a + row])
	_triangles(canvas, indices, points, colors)


## A fan round center through ring (in order), the centre in center_color and
## each ring point in its own colour (a radial gradient). closed joins the last
## point to the first; feather (px) adds a soft outer edge fading to clear.
static func fan(canvas: CanvasItem, center: Vector2, center_color: Color, ring: PackedVector2Array, ring_colors: PackedColorArray,
		closed: bool, feather: float = 0.0) -> void:
	var count: int = ring.size()
	if count < 2:
		return
	var points := PackedVector2Array([center])
	var colors := PackedColorArray([center_color])
	points.append_array(ring)
	colors.append_array(ring_colors)
	var spans: int = count if closed else count - 1
	var indices := PackedInt32Array()
	for k: int in spans:
		indices.append_array([0, 1 + k, 1 + (k + 1) % count])
	if feather > 0.0:
		var first: int = points.size()
		for k: int in count:
			points.append(ring[k] + (ring[k] - center).normalized() * feather)
			colors.append(Color(ring_colors[k], 0.0))
		for k: int in spans:
			var a: int = 1 + k
			var b: int = 1 + (k + 1) % count
			indices.append_array([a, b, first + (k + 1) % count, a, first + (k + 1) % count, first + k])
	_triangles(canvas, indices, points, colors)


## A disc (an ellipse of radii) built of rings; shade.call(point, share)
## colours each vertex (share: 0 at the centre, 1 on the edge), and a last ring
## feather (share of the radius) outside fades it to clear: a soft edge.
static func shaded_disc(canvas: CanvasItem, center: Vector2, radii: Vector2, shade: Callable, segments: int = 48,
		ring_shares: PackedFloat32Array = PackedFloat32Array([0.35, 0.65, 0.85, 0.95, 1.0]), feather: float = 0.04) -> void:
	var shares: PackedFloat32Array = ring_shares.duplicate()
	if feather > 0.0:
		shares.append(1.0 + feather)
	var points := PackedVector2Array([center])
	var colors := PackedColorArray([shade.call(center, 0.0) as Color])
	for share: float in shares:
		for k: int in segments:
			var angle: float = TAU * float(k) / float(segments)
			var point: Vector2 = center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * share
			var color: Color = shade.call(point, minf(share, 1.0))
			colors.append(Color(color, 0.0) if share > 1.0 else color)
			points.append(point)
	var indices := PackedInt32Array()
	for k: int in segments:
		indices.append_array([0, 1 + k, 1 + (k + 1) % segments])
	for r: int in shares.size() - 1:
		var inner: int = 1 + r * segments
		var outer: int = inner + segments
		for k: int in segments:
			var next: int = (k + 1) % segments
			indices.append_array([inner + k, outer + k, outer + next, inner + k, outer + next, inner + next])
	_triangles(canvas, indices, points, colors)


## A ribbon along a centre line (stalks): width from start_width to end_width,
## with a rounded tip. Returns the outline (left side up, right side down), a
## simple polygon for mass(); its first line.size() points are the left side.
static func ribbon(line: PackedVector2Array, start_width: float, end_width: float) -> PackedVector2Array:
	var widths := PackedFloat32Array()
	for i: int in line.size():
		widths.append(lerpf(start_width, end_width, float(i) / float(maxi(line.size() - 1, 1))))
	return shaped_ribbon(line, widths)


## A ribbon along a centre line with its own width at every point (kelp
## blades: narrow at the root, widest low down, narrow at the tip).
static func shaped_ribbon(line: PackedVector2Array, widths: PackedFloat32Array) -> PackedVector2Array:
	var count: int = line.size()
	var normals: PackedVector2Array = edge_normals(line)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i: int in count:
		var half: float = widths[i] * 0.5
		left.append(line[i] - normals[i] * half)
		right.append(line[i] + normals[i] * half)
	var tip_dir: Vector2 = (line[count - 1] - line[count - 2]).normalized()
	var outline: PackedVector2Array = left.duplicate()
	outline.append(line[count - 1] + tip_dir * widths[count - 1] * 0.8)
	right.reverse()
	outline.append_array(right)
	return outline


## A smooth curve through points (Catmull-Rom), each span cut in steps: for
## natural outlines (rock shoulders, pinnacles) from a few control points.
static func smooth_path(points: PackedVector2Array, steps: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count: int = points.size()
	for i: int in count - 1:
		var before: Vector2 = points[maxi(i - 1, 0)]
		var after: Vector2 = points[mini(i + 2, count - 1)]
		for k: int in steps:
			result.append(points[i].cubic_interpolate(points[i + 1], before, after, float(k) / float(steps)))
	result.append(points[count - 1])
	return result


## The centre line of something tall that sways (kelp, stalks): from root
## up height px in segments, bending side to side in waves (wave_amount px)
## and swaying more towards the top (sway px at the tip; clock in radians,
## e.g. time * speed).
static func sway_line(root: Vector2, height: float, segments: int, sway: float, clock: float, phase: float,
		waves: float = 1.2, wave_amount: float = 0.0) -> PackedVector2Array:
	var line := PackedVector2Array()
	for k: int in segments + 1:
		var t: float = float(k) / float(segments)
		var side: float = sin(clock + phase + t * 2.4) * sway * t * t + sin(t * TAU * waves + phase) * wave_amount * t
		line.append(root + Vector2(side, -height * t))
	return line


## Kelp blade widths along a line of count points: narrow root, widest a
## third of the way up, a slim tip; width = the widest.
static func kelp_widths(count: int, width: float, phase: float) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for i: int in count:
		var t: float = float(i) / float(maxi(count - 1, 1))
		var body: float = lerpf(0.55, 1.0, smoothstep(0.0, 0.3, t)) * lerpf(1.0, 0.3, smoothstep(0.3, 1.0, t))
		widths.append(width * body * (1.0 + 0.12 * sin(t * 17.0 + phase)))
	return widths


# --- The rock under an island ----------------------------------------------------

## One layer of the jagged rock hanging under an island: from (-half_width,
## top_y) along a jagged bottom of teeth to (half_width, top_y). The longest
## tooth hangs depth px under top_y near tip_x; tooth_width = min / max px.
static func hanging_rock(rng: RandomNumberGenerator, half_width: float, top_y: float, depth: float, tip_x: float,
		tooth_width: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(-half_width, top_y)])
	var x: float = -half_width
	while x < half_width - 1.0:
		var step: float = rng.randf_range(tooth_width.x, tooth_width.y)
		var end: float = minf(x + step, half_width)
		var mid: float = (x + end) * 0.5 + rng.randf_range(-0.12, 0.12) * (end - x)
		var tip_length: float = rng.randf_range(0.9, 1.06)
		if absf(mid - tip_x) < tooth_width.y * 0.6:
			tip_length *= 1.12
		# A shoulder half-way down each flank, so a tooth is not a plain zigzag.
		var notch_y: float = points[points.size() - 1].y
		var tip := Vector2(mid, top_y + _hang_shape(mid, half_width, tip_x) * depth * tip_length)
		points.append(Vector2(lerpf(x, mid, 0.55), lerpf(notch_y, tip.y, 0.5) + rng.randf_range(-3.0, 3.0)))
		points.append(tip)
		if end < half_width - 1.0:
			var notch := Vector2(end, top_y + _hang_shape(end, half_width, tip_x) * depth * rng.randf_range(0.62, 0.84))
			points.append(Vector2(lerpf(mid, end, 0.45), lerpf(tip.y, notch.y, 0.5) + rng.randf_range(-3.0, 3.0)))
			points.append(notch)
		x = end
	points.append(Vector2(half_width, top_y))
	return points


## 0-1: the outline of the hanging rock, 0 at both ends and 1 at tip_x.
static func _hang_shape(x: float, half_width: float, tip_x: float) -> float:
	var share: float = (x + half_width) / (tip_x + half_width) if x < tip_x else (half_width - x) / (half_width - tip_x)
	return pow(clampf(share, 0.0, 1.0), 0.75)


## The rock of a floating island, cut for drawing: the body (top_edge closed
## by jagged rock hanging front_share of depth under it: one silhouette) and
## two layers hanging behind it, wider and deeper (far: the whole depth).
## top_edge runs left to right from (-half_width, top_y) to (half_width,
## top_y); crown_y is its highest point; tip_share moves the longest teeth
## sideways; tooth_width = the body's teeth (min / max px; narrow = long
## thin stalactites). Draw with draw_rock_layers, then draw_rock_body.
static func build_island_rock(rng: RandomNumberGenerator, top_edge: PackedVector2Array, half_width: float, top_y: float,
		crown_y: float, depth: float, tip_share: float, front_share: float = 0.62,
		tooth_width: Vector2 = Vector2(14.0, 28.0)) -> Dictionary:
	var front_depth: float = depth * front_share
	var rock: PackedVector2Array = hanging_rock(rng, half_width, top_y, front_depth, tip_share * half_width, tooth_width)
	var cuts := PackedFloat32Array([crown_y])
	cuts.append_array(hang_cuts(top_y, front_depth))
	var result: Dictionary = {"body": cut_bands(body_polygon(top_edge, rock), cuts)}
	# name, width scale, depth share, tip share, tooth widths (no wider than the
	# body: a wider layer shows as a flat ledge at its top corners)
	for spec: Array in [["far", 1.0, 1.0, -tip_share - 0.12, Vector2(22.0, 44.0)], ["mid", 0.98, 0.8, tip_share + 0.14, Vector2(18.0, 34.0)]]:
		var layer_depth: float = depth * float(spec[2])
		var layer: PackedVector2Array = hanging_rock(rng, half_width * float(spec[1]), top_y, layer_depth, half_width * float(spec[3]),
			spec[4] as Vector2)
		result[spec[0]] = cut_bands(layer, hang_cuts(top_y, layer_depth))
	return result


## The two layers behind an island's body (build_island_rock), far first,
## each fading into the dark.
static func draw_rock_layers(canvas: CanvasItem, rock: Dictionary, far_color: Color, mid_color: Color) -> void:
	draw_bands(canvas, rock.far, hang_colors(far_color))
	draw_bands(canvas, rock.mid, hang_colors(mid_color))


## An island's body (build_island_rock): top_color at its crown, base_color
## at its top corners, then fading into the dark down the hanging rock.
static func draw_rock_body(canvas: CanvasItem, rock: Dictionary, top_color: Color, base_color: Color) -> void:
	var colors := PackedColorArray([top_color])
	colors.append_array(hang_colors(base_color))
	draw_bands(canvas, rock.body, colors)


## One silhouette from an island's top edge (left to right, its ends at the
## rock's top corners) and the jagged rock under it (hanging_rock, same ends).
static func body_polygon(top_edge: PackedVector2Array, rock: PackedVector2Array) -> PackedVector2Array:
	var polygon: PackedVector2Array = top_edge.duplicate()
	for i: int in range(rock.size() - 2, 0, -1):
		polygon.append(rock[i])
	return polygon


## How hanging rock fades into the dark: (share of its depth, alpha), top down.
static func hang_fade() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.35, 0.95), Vector2(0.7, 0.4), Vector2(1.2, 0.0)])


## The heights of hang_fade's stops for rock hanging depth px under top_y.
static func hang_cuts(top_y: float, depth: float) -> PackedFloat32Array:
	var cuts := PackedFloat32Array()
	for stop: Vector2 in hang_fade():
		cuts.append(top_y + stop.x * depth)
	return cuts


## color at each of hang_fade's stops (fading out).
static func hang_colors(color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for stop: Vector2 in hang_fade():
		colors.append(Color(color, color.a * stop.y))
	return colors


## Cuts a polygon into horizontal bands at cuts (y, top down), so it can take
## a vertical gradient with several stops (draw_bands). Above the first cut
## and below the last belong to the first / last band. Each band:
## {polygons, top, bottom, index}.
static func cut_bands(polygon: PackedVector2Array, cuts: PackedFloat32Array) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	for i: int in cuts.size() - 1:
		var y0: float = cuts[i] - (1000.0 if i == 0 else 0.0)
		var y1: float = cuts[i + 1] + (1000.0 if i == cuts.size() - 2 else 0.0)
		var cut := PackedVector2Array([Vector2(-10000.0, y0), Vector2(10000.0, y0), Vector2(10000.0, y1), Vector2(-10000.0, y1)])
		var pieces: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(polygon, cut):
			if piece.size() >= 3:
				pieces.append(piece)
		bands.append({"polygons": pieces, "top": cuts[i], "bottom": cuts[i + 1], "index": i})
	return bands


## Draws cut_bands with one colour per cut (colors[i] at cuts[i]).
static func draw_bands(canvas: CanvasItem, bands: Array[Dictionary], colors: PackedColorArray) -> void:
	for band: Dictionary in bands:
		var index: int = band.index
		for piece: PackedVector2Array in band.polygons:
			mass(canvas, piece, band.top, band.bottom, colors[index], colors[index + 1])


static func _triangles(canvas: CanvasItem, indices: PackedInt32Array, points: PackedVector2Array, colors: PackedColorArray) -> void:
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
