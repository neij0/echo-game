class_name JourneyIsland
extends Node2D
## One world on the Journey screen: a floating island drawn in code ("silhouette
## + glow", no images). The base is shared: a top surface seen in 3/4 view and a
## jagged rock hanging under it, dark, with a rim light in the world's colour.
## Each kind (JourneyIslandOcean, ...Caves, ...Forest, ...Desert, ...Snow) adds
## its own shapes and lights (_build_kind, _draw_kind, _draw_under_kind).
## light (0-3) is how lit it is: 0 = locked (a near-black silhouette with only a
## faint rim), 1 / 2 / 3 = the stage reached (a few lights, more, everything
## with the world's marker); each light fades in at its own point of its step
## (lit(step, order)), so raising light (JourneyTower tweens it) lights the
## island up one by one. The path across its top (from path_in to path_out) is
## drawn here too, so it lies on the island.

## Half the width of the top surface.
@export var half_width: float = 170.0
## Half the height of the top surface (3/4 view).
@export var top_depth: float = 40.0
## How far the rock hangs below the top surface.
@export var hang_depth: float = 190.0
@export var accent: Color = Color(0.45, 0.95, 1.0)
@export var top_color: Color = Color(0.05, 0.07, 0.1)
@export var rock_color: Color = Color(0.03, 0.04, 0.065)
## Rim strength of a locked island (0-1).
@export var locked_rim: float = 0.18
## HDR multiplier of the lights (they bloom with a GlowEnvironment).
@export var glow_energy: float = 2.6
@export var path_color: Color = Color(1.0, 0.86, 0.55)
@export var seed_value: int = 1

## 0 = locked, 1-3 = lit steps (fractions while it lights up).
var light: float = 0.0
## Where the path arrives on / leaves the top surface (local; set by the tower).
var path_in: Vector2 = Vector2.ZERO
var path_out: Vector2 = Vector2.ZERO
var has_path_in: bool = false
var has_path_out: bool = false
var _time: float = 0.0
var _top: PackedVector2Array = PackedVector2Array()
var _front: PackedVector2Array = PackedVector2Array()
var _back: PackedVector2Array = PackedVector2Array()
var _under: PackedVector2Array = PackedVector2Array()
var _under_colors: PackedColorArray = PackedColorArray()
var _sides: PackedVector2Array = PackedVector2Array()

static var _aura: GradientTexture2D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_build_shape(rng)
	_build_kind(rng)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Where the camera looks at this island (local to its parent).
func get_focus_point() -> Vector2:
	return position + Vector2(0.0, hang_depth * 0.2)


## 0-1: how far a light of this step (1-3) is on; order (0-1) is its place in
## the step (later ones come on later).
func lit(step: int, order: float = 0.0) -> float:
	return clampf((light - float(step - 1) - order * 0.6) / 0.4, 0.0, 1.0)


## 0-1: the island's overall brightness.
func overall() -> float:
	return clampf(light / 3.0, 0.0, 1.0)


## An over-bright colour (blooms) with an alpha.
func glow(color: Color, alpha: float, energy: float = -1.0) -> Color:
	var e: float = glow_energy if energy < 0.0 else energy
	return Color(color.r * e, color.g * e, color.b * e, alpha)


## A silhouette colour, lifted a little towards the accent as the island lights.
func shade(color: Color, lift: float = 1.0) -> Color:
	var on: float = clampf(light, 0.0, 1.0) * 0.5 + overall() * 0.5
	var locked: float = 0.55 + 0.45 * clampf(light, 0.0, 1.0)
	return Color(color.r * locked, color.g * locked, color.b * locked).lerp(accent * 0.35, 0.12 * on * lift)


## Alpha of the detail lines (outlines of rocks, ruins, crystals): very faint
## on a locked island, clear once it is lit.
func line_alpha() -> float:
	return lerpf(0.05, 0.35, clampf(light, 0.0, 1.0))


## 0-1: rim light strength.
func rim() -> float:
	return lerpf(locked_rim, 1.0, clampf(light, 0.0, 1.0) * 0.5 + overall() * 0.5)


func _build_shape(rng: RandomNumberGenerator) -> void:
	var count: int = 32
	for i: int in count:
		var angle: float = TAU * float(i) / float(count)
		var point := Vector2(cos(angle) * half_width, sin(angle) * top_depth)
		_top.append(point)
		if sin(angle) >= -0.01:
			_front.append(point)
		if sin(angle) <= 0.01:
			_back.append(point)
	# The hanging rock: the front arc (right to left), then down the left side
	# to the tip and back up the right side, jagged with a few drips.
	var tip := Vector2(rng.randf_range(-0.15, 0.15) * half_width, hang_depth)
	# Each side first goes straight down under the end of the top (the front
	# edge is steep there), then inwards to the tip.
	var left := PackedVector2Array([Vector2(-half_width + 2.0, top_depth * 0.35)])
	var right := PackedVector2Array([Vector2(half_width - 2.0, top_depth * 0.35)])
	var steps: int = 9
	for k: int in range(1, steps):
		var t: float = float(k) / float(steps)
		var share: float = pow(t, 0.75)
		# Less jitter where the rock gets narrow, so the sides never cross; each
		# point drops from the front edge above it, so it never rises over it.
		var jitter: float = minf(10.0, half_width * (1.0 - share) * 0.2)
		for side: float in [-1.0, 1.0]:
			var x: float = lerpf(side * half_width, tip.x, share) + rng.randf_range(-jitter, jitter)
			var edge: float = top_depth * sqrt(maxf(1.0 - pow(x / half_width, 2.0), 0.0))
			var point := Vector2(x, edge + (hang_depth - edge) * pow(t, 1.25) + rng.randf_range(2.0, 7.0))
			if side < 0.0:
				left.append(point)
			else:
				right.append(point)
	left = _with_drips(left, -1.0, rng)
	right = _with_drips(right, 1.0, rng)
	_under = _front.duplicate()
	right.reverse()
	_sides = PackedVector2Array([_front[_front.size() - 1]])
	_sides.append_array(left)
	_sides.append(tip)
	_sides.append_array(right)
	_sides.append(_front[0])
	_under.append_array(left)
	_under.append(tip)
	_under.append_array(right)
	for point: Vector2 in _under:
		var depth: float = clampf(point.y / hang_depth, 0.0, 1.0)
		_under_colors.append(rock_color * lerpf(1.3, 0.45, depth))


## Adds a short spike hanging down and outwards (outward = -1 left, 1 right)
## from every third edge of a side, between its two points, so it stays outside
## the rock and never crosses another edge.
func _with_drips(points: PackedVector2Array, outward: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	for i: int in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		if i % 3 == 2:
			var depth: float = minf(rng.randf_range(10.0, 20.0), a.distance_to(b) * 0.7)
			result.append(a.lerp(b, 0.3))
			result.append(a.lerp(b, 0.45) + Vector2(outward * 0.5, 1.0).normalized() * depth)
			result.append(a.lerp(b, 0.6))
		result.append(b)
	return result


## Kinds place their shapes here (same seed every time).
func _build_kind(_rng: RandomNumberGenerator) -> void:
	pass


## Kinds draw on the hanging rock (cave mouths, glowing spots...).
func _draw_under_kind() -> void:
	pass


## Kinds draw on the top surface (and above it).
func _draw_kind() -> void:
	pass


func _draw() -> void:
	var on: float = overall()
	if _aura == null:
		_aura = _make_aura()
	if on > 0.0:
		var aura_size := Vector2(half_width * 3.4, half_width * 2.8)
		draw_texture_rect(_aura, Rect2(Vector2(-aura_size.x * 0.5, hang_depth * 0.15 - aura_size.y * 0.5), aura_size), false,
			Color(accent, 0.16 * on))
	var colors := PackedColorArray()
	var lift: Color = accent * 0.05 * on
	for color: Color in _under_colors:
		colors.append(Color(shade(color).r + lift.r, shade(color).g + lift.g, shade(color).b + lift.b))
	draw_polygon(_under, colors)
	draw_polyline(_sides, Color(accent, 0.1 * rim()), 1.5, true)
	_draw_under_kind()
	draw_colored_polygon(_top, shade(top_color))
	draw_polyline(_back, Color(accent, 0.18 * rim()), 1.2, true)
	draw_polyline(_front, Color(accent * (1.0 + on), 0.35 * rim()), 2.0, true)
	_draw_path()
	_draw_kind()


func _draw_path() -> void:
	if not (has_path_in or has_path_out):
		return
	var from_point: Vector2 = path_in if has_path_in else Vector2(-half_width * 0.3, top_depth * 0.3)
	var to_point: Vector2 = path_out if has_path_out else Vector2(half_width * 0.2, -top_depth * 0.2)
	var points := PackedVector2Array()
	for i: int in 17:
		var t: float = float(i) / 16.0
		var bend: Vector2 = Vector2(0.0, top_depth * 0.35 * sin(PI * t))
		points.append(from_point.lerp(to_point, t) + bend)
	var on: float = lit(1)
	if on > 0.0:
		GlowFx.glow_line(self, points, glow(path_color, 0.55 * on, 1.4), 1.3)
	else:
		for i: int in range(0, points.size() - 1, 2):
			draw_line(points[i], points[i + 1], Color(path_color, 0.1), 1.0, true)


static func _make_aura() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.4, Color(1, 1, 1, 0.35))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	texture.use_hdr = true
	return texture


# --- Helpers for the kinds ------------------------------------------------------

## A point on the top surface: share of the half width / depth (-1..1).
func on_top(x_share: float, y_share: float) -> Vector2:
	return Vector2(x_share * half_width, y_share * top_depth)


## An upright crystal (a long diamond) standing at base.
func draw_crystal(base: Vector2, height: float, width: float, color: Color, on: float, lean: float = 0.0) -> void:
	var tip: Vector2 = base + Vector2(lean, -height)
	var shape := PackedVector2Array([tip, base + Vector2(width, -height * 0.3), base + Vector2(0.0, height * 0.08),
		base + Vector2(-width, -height * 0.3)])
	draw_colored_polygon(shape, shade(Color(0.03, 0.05, 0.08)).lerp(glow(color, 1.0, 1.2), 0.55 * on))
	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, Color(color, line_alpha()).lerp(glow(color, 1.0), on), 1.2, true)
	if on > 0.0 and height < 60.0:
		GlowFx.dot(self, base + Vector2(lean * 0.5, -height * 0.45), minf(width * 0.6, 5.0), glow(color, 0.5 * on))


## A soft glowing light (a few fading circles round a bright core).
func draw_glow_dot(center: Vector2, radius: float, color: Color, on: float) -> void:
	if on <= 0.0:
		return
	GlowFx.dot(self, center, radius, glow(color, on))
