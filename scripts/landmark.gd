class_name Landmark
extends Node2D
## A hand-placed set-piece of a level (LevelDefinition.landmarks): a sunken
## wreck, an ancient statue, a whale skeleton... Memorable shapes that help
## the players find their way ("we're back at the wreck"). Built from vector
## shapes in the 3/4 view like the rocks:
## - Its solid parts are RockWall bases (footprints: collision, occluder,
##   navigation, sonar outline, drawn standing up by RockWall.build_faces).
##   get_footprints() works before the landmark enters the tree, so the
##   LevelBuilder can validate the level and bake the navigation with them.
## - Decorative parts (masts, ribs, branches, an arch...) are Node2D parts,
##   each y-sorted on its own base point (add_part), lit by the real lights
##   and dark far from them (TopLightFalloff).
## - Extra sonar lines (add_sonar_line) give it a distinct pulse outline.
## - Any glow is small and dim: an optional weak light (light_radius) and
##   small glowing dots drawn on the level's glow layer (_draw_glow).
## Subclasses override _footprint_shapes, _footprint_heights, _build_parts
## and, if they glow, _has_glow / _draw_glow. Never rotated as a node (3/4
## view: upright parts must stay upright).
## Variation (configure, from the LandmarkPlacement): mirrored and size_scale
## apply to everything (footprints, parts, sonar lines, glow); floor_turn,
## damage and variant are read by each kind (rand() mixes in the variant), so
## no two placements of a kind look the same.

## The rock colour is pulled towards this colour (wood, bone, pale stone...).
@export var tint: Color = Color(0.3, 0.36, 0.4)
@export_range(0.0, 1.0) var tint_strength: float = 0.4
## Colour accent of the floor around the landmark (AreaAccent; alpha = strength,
## 0 = none), e.g. warm amber near a vent. Overrides the room's own accent.
@export var accent_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var accent_radius: float = 420.0
## Footprint rock: a darker top than natural rock (RockWall.top_lift) and
## less top detail.
@export_range(0.0, 1.0) var top_lift: float = 0.16
@export_range(0.0, 1.0) var detail_chance: float = 0.08
@export_range(0.0, 1.0) var grain_strength: float = 0.22

## Redraws per second of the moving parts and the glow (0 = every frame):
## their motion is slow, so 30 looks the same and costs much less.
@export var redraw_rate: float = 30.0

@export_group("Glow")
## A small, weak light (0 = none), placed at light_offset.
@export var light_radius: float = 0.0
@export var light_energy: float = 0.3
@export var light_color: Color = Color(0.4, 0.9, 0.85)
@export var light_offset: Vector2 = Vector2.ZERO
## Colour and HDR energy of the glowing dots (_draw_glow); kept dim.
@export var glow_color: Color = Color(0.45, 0.95, 0.9)
@export var glow_energy: float = 1.2
@export_range(0.0, 1.0) var glow_alpha: float = 0.6

## The level's rock colour (set by the LevelBuilder before _ready).
var rock_color: Color = Color(0.27, 0.36, 0.42)
## Per placement (configure): mirrored left-right, size, a turn on the floor
## (radians, for kinds lying on the floor), damage 0 (intact) - 1 (wrecked),
## and the variant that picks the details.
var mirrored: bool = false
var size_scale: float = 1.0
var floor_turn: float = 0.0
var damage: float = 0.5
var variant: int = 0

var _time: float = 0.0
var _parts: Array[Node2D] = []
## Parts redrawn every frame (moving ones).
var _animated: Array[Node2D] = []
var _sonar_lines: Array[PackedVector2Array] = []
var _sonar_sights: Array[PackedVector2Array] = []
var _glow: Node2D
## Shapes of the current draw of a moving part or the glow, sent in one call.
var _batch := ShapeBatch.new()
var _redraw_wait: float = 0.0


## Takes the placement's variation (before the landmark enters the tree).
func configure(placement: LandmarkPlacement) -> void:
	mirrored = placement.mirrored
	size_scale = placement.size_scale
	floor_turn = deg_to_rad(placement.floor_turn_degrees)
	damage = placement.damage
	variant = placement.variant
	if placement.accent_color.a > 0.0:
		accent_color = placement.accent_color


## Mirror and size of this placement (local design space -> node space).
func variation() -> Transform2D:
	return Transform2D.IDENTITY.scaled(variation_scale())


## The same as a scale (x negative when mirrored; Transform2D.get_scale()
## would put the sign on y).
func variation_scale() -> Vector2:
	return Vector2(-size_scale if mirrored else size_scale, size_scale)


## The solid footprints (node space, pixels around the landmark's base point).
func get_footprints() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for shape: PackedVector2Array in _footprint_shapes():
		result.append(variation() * shape)
	return result


## The footprints in the parent's space (works before entering the tree).
func get_placed_footprints() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for shape: PackedVector2Array in get_footprints():
		result.append(transform * shape)
	return result


## Stable value in [0, 1) for key, different for every variant.
func rand(key: float) -> float:
	return Landmark.hash01(key * 1.37 + variant * 31.71 + 0.53)


## A point of the 3/4 view: a floor point raised by z pixels.
static func project(floor_point: Vector2, z: float) -> Vector2:
	return floor_point - Vector2(0.0, z)


## The colour of this landmark's material (rock colour pulled to the tint).
func material_color() -> Color:
	return rock_color.lerp(tint, tint_strength)


func _ready() -> void:
	add_to_group("landmarks")
	y_sort_enabled = true
	var shapes: Array[PackedVector2Array] = get_footprints()
	var heights: PackedFloat32Array = _footprint_heights()
	var slopes: PackedVector2Array = _footprint_slopes()
	for i: int in shapes.size():
		var wall := RockWall.new()
		wall.polygon = shapes[i]
		wall.color = material_color()
		wall.height = (heights[i] if i < heights.size() else 40.0) * size_scale
		# Height 0: collision only, the landmark draws that part itself.
		wall.draw_flat = wall.height > 0.0
		if i < slopes.size():
			# Per local pixel = per global pixel (the size scales both); a
			# mirror turns the x tilt around.
			wall.height_slope = Vector2(-slopes[i].x if mirrored else slopes[i].x, slopes[i].y)
			wall.slope_origin = global_position
		wall.top_lift = top_lift
		wall.detail_chance = detail_chance
		wall.grain_strength = grain_strength
		add_child(wall)
	_build_parts()
	if light_radius > 0.0:
		var light := PointLight2D.new()
		light.texture = LightTextures.radial_smooth(256, 0.0)
		light.texture_scale = LightTextures.scale_for_radius(light.texture, light_radius)
		light.color = light_color
		light.energy = light_energy
		light.position = variation() * light_offset
		light.add_to_group("falloff_lights")
		add_child(light)
	if _has_glow():
		_glow = Node2D.new()
		_glow.position = global_position
		_glow.scale = variation_scale()
		GlowLayer.add(self, _glow)
		_glow.draw.connect(func() -> void: _draw_glow(_glow))
	if not _sonar_lines.is_empty():
		add_to_group("sonar_shapes")


func _exit_tree() -> void:
	if is_instance_valid(_glow):
		_glow.queue_free()


func _process(delta: float) -> void:
	_time += delta
	if not GlowLayer.near_camera(self, 1400.0):
		return
	_redraw_wait -= delta
	if _redraw_wait > 0.0:
		return
	_redraw_wait = 1.0 / redraw_rate if redraw_rate > 0.0 else 0.0
	for part: Node2D in _animated:
		part.queue_redraw()
	if _glow:
		_glow.queue_redraw()


## Sonar lines beyond the footprints' outlines (global, open lines).
func get_sonar_shape_lines() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for line: PackedVector2Array in _sonar_lines:
		result.append(global_transform * (variation() * line))
	return result


## The landmark's own solid parts: the sonar's line of sight to its shape
## lines may pass through them (they are seen from above).
func get_sonar_exclude() -> Array:
	var result: Array = []
	for child: Node in get_children():
		if child is RockWall:
			result.append((child as RockWall).get_rid())
	return result


## For each point of get_sonar_shape_lines(): where its line of sight is
## checked (on the floor below it).
func get_sonar_shape_sights() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for sights: PackedVector2Array in _sonar_sights:
		result.append(global_transform * (variation() * sights))
	return result


# --- For subclasses ----------------------------------------------------------

func _footprint_shapes() -> Array[PackedVector2Array]:
	return []


func _footprint_heights() -> PackedFloat32Array:
	return PackedFloat32Array()


## Optional tilt per footprint (height change per local pixel, x / y).
func _footprint_slopes() -> PackedVector2Array:
	return PackedVector2Array()


func _build_parts() -> void:
	pass


func _has_glow() -> bool:
	return false


## Draws the glowing dots on canvas (the level's glow layer, at this landmark's
## base point: local coordinates as in the parts).
func _draw_glow(_canvas: Node2D) -> void:
	pass


## A decorative part sorted on base (local design space): drawer(part) draws
## it in the part's space (base = origin, mirrored and scaled with the
## landmark). animated = redrawn every frame.
func add_part(base: Vector2, drawer: Callable, animated: bool = false) -> Node2D:
	var part := Node2D.new()
	part.position = variation() * base
	part.scale = variation_scale()
	part.material = TopLightFalloff.material()
	part.draw.connect(func() -> void: drawer.call(part))
	add_child(part)
	_parts.append(part)
	if animated:
		_animated.append(part)
	return part


## An extra sonar line (local); sights = the floor points below each point
## (empty = straight down by drop pixels).
func add_sonar_line(points: PackedVector2Array, sights: PackedVector2Array = PackedVector2Array(), drop: float = 0.0) -> void:
	if points.size() < 2:
		return
	if sights.size() != points.size():
		sights = PackedVector2Array()
		for point: Vector2 in points:
			sights.append(point + Vector2(0.0, drop))
	_sonar_lines.append(points)
	_sonar_sights.append(sights)


## HDR glow colour with the given alpha share.
func glow(share: float = 1.0, color_value: Color = Color(0, 0, 0, 0)) -> Color:
	var c: Color = glow_color if color_value.a == 0.0 else color_value
	return Color(c.r * glow_energy, c.g * glow_energy, c.b * glow_energy, glow_alpha * share)


# --- Shape helpers -----------------------------------------------------------

## An ellipse of count points, its radius wobbling softly (same key = same shape).
static func ellipse(center: Vector2, radii: Vector2, count: int = 16, wobble: float = 0.0, key: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k: int in count:
		var angle: float = TAU * k / count
		var r: float = 1.0 + wobble * sin(angle * 3.0 + key) * 0.5 + wobble * sin(angle * 5.0 + key * 1.7) * 0.5
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * r)
	return points


## Points of a quadratic curve a -> b bent towards control.
static func curve(a: Vector2, control: Vector2, b: Vector2, count: int = 10) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k: int in count + 1:
		var t: float = float(k) / count
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points


## Draws a band along a centre line on canvas, its width going from
## start_width to end_width: one quad per segment plus round joints, so a
## tight bend never makes a shape that cannot be triangulated.
static func draw_band(canvas: CanvasItem, line: PackedVector2Array, start_width: float, end_width: float, color_value: Color) -> void:
	var count: int = line.size()
	for k: int in count - 1:
		var a: Vector2 = line[k]
		var b: Vector2 = line[k + 1]
		if a.distance_squared_to(b) < 0.01:
			continue
		var normal: Vector2 = (b - a).normalized().orthogonal()
		var wa: float = lerpf(start_width, end_width, float(k) / maxf(count - 1, 1)) * 0.5
		var wb: float = lerpf(start_width, end_width, float(k + 1) / maxf(count - 1, 1)) * 0.5
		canvas.draw_colored_polygon(PackedVector2Array([a + normal * wa, b + normal * wb, b - normal * wb, a - normal * wa]), color_value)
		if k > 0 and wa > 0.75:
			canvas.draw_circle(a, wa, color_value)


## Stable pseudo-random value in [0, 1).
static func hash01(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)
