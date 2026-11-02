class_name JourneyIslandForest
extends JourneyIsland
## The Forest on the Journey screen: a grassy mound with two young firs and,
## in the middle, a giant tree whose roots grip the island. Its vessel of the
## Ancient Light: the tree's heart, a hollow in its trunk where the sap
## gathers. Crown, trunk and roots are one dark silhouette (no outlines).
##   stage 1: the hollow dark, a few fireflies;
##   stage 2: the sap glows softly in the hollow and rises up the trunk;
##   stage 3: the heart awakens with rays, the crown is lit from inside.

const CIRCLE_POINTS: int = 20

@export_group("Tree")
@export var trunk_base: Vector2 = Vector2(-4.0, -24.0)
@export var trunk_height: float = 118.0
@export var trunk_width: Vector2 = Vector2(34.0, 18.0)
## The crown: circles (x, y from the trunk's top, radius) merged into one shape.
@export var crown_circles: Array[Vector3] = [Vector3(0.0, -34.0, 52.0), Vector3(-52.0, -12.0, 40.0), Vector3(54.0, -14.0, 42.0),
	Vector3(-26.0, -66.0, 38.0), Vector3(30.0, -62.0, 40.0), Vector3(-82.0, 14.0, 26.0), Vector3(84.0, 12.0, 28.0),
	Vector3(0.0, 4.0, 40.0)]
## The heart: where it is up the trunk (share) and its size.
@export var heart_share: float = 0.42
@export var heart_size: Vector2 = Vector2(9.0, 26.0)
@export var sap_color: Color = Color(1.0, 0.85, 0.4)
@export var leaf_glow_color: Color = Color(0.7, 1.0, 0.45)
@export var firefly_color: Color = Color(0.85, 1.0, 0.45)
@export var firefly_count: int = 22
@export var sap_count: int = 10

var _trunk := PackedVector2Array()
var _trunk_left := PackedVector2Array()
var _trunk_top: Vector2 = Vector2.ZERO
var _crown := PackedVector2Array()
var _crown_top: float = 0.0
var _crown_edge := PackedVector2Array()
## Root shapes and the firs (polygons).
var _roots: Array[PackedVector2Array] = []
var _firs: Array[PackedVector2Array] = []
## {base, phase, radius, step, order}
var _fireflies: Array[Dictionary] = []
## {phase, speed, side}
var _sap: Array[Dictionary] = []


func _init() -> void:
	accent = Color(0.65, 1.0, 0.45)
	crown_height = 230.0


func _build_top(rng: RandomNumberGenerator) -> PackedVector2Array:
	var controls := PackedVector2Array()
	for spec: Vector2 in [Vector2(-1.0, 0.0), Vector2(-0.82, -14.0), Vector2(-0.56, -24.0), Vector2(-0.3, -28.0),
			Vector2(0.0, -26.0), Vector2(0.3, -27.0), Vector2(0.56, -22.0), Vector2(0.82, -13.0), Vector2(1.0, 0.0)]:
		var jitter: float = 0.0 if absf(spec.x) > 0.99 else rng.randf_range(-2.0, 2.0)
		controls.append(Vector2(spec.x * half_width, spec.y + jitter))
	return IslandArt.smooth_path(controls, 5)


func _build_kind(rng: RandomNumberGenerator) -> void:
	# The trunk: a slightly bending column, wide at its foot.
	var line := PackedVector2Array()
	for k: int in 9:
		var t: float = float(k) / 8.0
		line.append(trunk_base + Vector2(sin(t * 2.2) * 7.0, -trunk_height * t))
	_trunk_top = line[line.size() - 1]
	_trunk = IslandArt.ribbon(line, trunk_width.x, trunk_width.y)
	_trunk_left = _trunk.slice(0, line.size())
	# The crown: circles merged into one silhouette.
	var merged := PackedVector2Array()
	for spec: Vector3 in crown_circles:
		var circle := PackedVector2Array()
		for k: int in CIRCLE_POINTS:
			var angle: float = TAU * float(k) / float(CIRCLE_POINTS)
			var bump: float = 1.0 + rng.randf_range(-0.05, 0.05)
			circle.append(_trunk_top + Vector2(spec.x, spec.y) + Vector2.from_angle(angle) * spec.z * bump)
		if merged.is_empty():
			merged = circle
		else:
			var result: Array[PackedVector2Array] = Geometry2D.merge_polygons(merged, circle)
			for polygon: PackedVector2Array in result:
				if not Geometry2D.is_polygon_clockwise(polygon) or result.size() == 1:
					merged = polygon
					break
	_crown = merged
	for point: Vector2 in _crown:
		_crown_top = minf(_crown_top, point.y)
	# The crown's lit edge: its points facing up, in order, walked with the crown on their right.
	_crown_edge = _upper_edge(_crown)
	# Roots: thick ribbons curving from the trunk's foot down over the mound.
	for spec: Vector2 in [Vector2(-1.0, 46.0), Vector2(-1.0, 26.0), Vector2(1.0, 44.0), Vector2(1.0, 24.0)]:
		var reach: float = spec.y
		var root_line := PackedVector2Array()
		for k: int in 7:
			var t: float = float(k) / 6.0
			var x: float = trunk_base.x + spec.x * (trunk_width.x * 0.3 + reach * t)
			root_line.append(Vector2(x, lerpf(trunk_base.y - 16.0, top_y_at(x) + 4.0, pow(t, 0.7))))
		_roots.append(IslandArt.ribbon(root_line, 13.0, 3.0))
	# Two young firs on the mound.
	for spec: Vector3 in [Vector3(-0.68, 58.0, 26.0), Vector3(0.64, 46.0, 22.0)]:
		var foot := Vector2(spec.x * half_width, top_y_at(spec.x * half_width) + 4.0)
		var fir := PackedVector2Array([foot + Vector2(-spec.z * 0.5, 0.0)])
		for tier: int in 3:
			var y: float = -spec.y * (0.3 + 0.28 * float(tier))
			var width: float = spec.z * (0.5 - 0.13 * float(tier))
			fir.append(foot + Vector2(-width * 0.55, y))
			fir.append(foot + Vector2(-width, y + 4.0))
		fir.append(foot + Vector2(0.0, -spec.y))
		for tier: int in range(2, -1, -1):
			var y: float = -spec.y * (0.3 + 0.28 * float(tier))
			var width: float = spec.z * (0.5 - 0.13 * float(tier))
			fir.append(foot + Vector2(width, y + 4.0))
			fir.append(foot + Vector2(width * 0.55, y))
		fir.append(foot + Vector2(spec.z * 0.5, 0.0))
		_firs.append(fir)
	for i: int in firefly_count:
		var base := Vector2(rng.randf_range(-0.9, 0.9) * half_width, rng.randf_range(-150.0, -30.0))
		_fireflies.append({"base": base, "phase": rng.randf() * TAU, "radius": rng.randf_range(6.0, 16.0),
			"step": 1 if i < 6 else (2 if i < 14 else 3), "order": rng.randf()})
	for i: int in sap_count:
		_sap.append({"phase": rng.randf(), "speed": rng.randf_range(0.15, 0.3), "side": rng.randf_range(-0.3, 0.3)})


## The part of a closed outline that faces up (no point of the outline
## right above it), as one run walked left to right.
func _upper_edge(outline: PackedVector2Array) -> PackedVector2Array:
	var left: int = 0
	var right: int = 0
	for i: int in outline.size():
		if outline[i].x < outline[left].x:
			left = i
		if outline[i].x > outline[right].x:
			right = i
	var forward := PackedVector2Array()
	var i: int = left
	while true:
		forward.append(outline[i])
		if i == right:
			break
		i = (i + 1) % outline.size()
	var backward := PackedVector2Array()
	i = left
	while true:
		backward.append(outline[i])
		if i == right:
			break
		i = (i - 1 + outline.size()) % outline.size()
	var forward_y: float = 0.0
	for point: Vector2 in forward:
		forward_y += point.y
	var backward_y: float = 0.0
	for point: Vector2 in backward:
		backward_y += point.y
	return forward if forward_y / float(forward.size()) < backward_y / float(backward.size()) else backward


func _draw_back() -> void:
	var core: float = core_level()
	var heart: Vector2 = trunk_base.lerp(_trunk_top, heart_share)
	if core > 0.0:
		rays(heart, 9, 200.0, 0.045, sap_color, core, 0.03)
		IslandArt.soft_glow(self, heart, Vector2(150.0, 150.0), Color(sap_color, 0.25 * core))


func _draw_front() -> void:
	var soft: float = soft_level()
	var core: float = core_level()
	for fir: PackedVector2Array in _firs:
		IslandArt.mass(self, fir, fir[0].y - 60.0, fir[0].y, lifted(rock_top_color, 0.8), dark())
	for root: PackedVector2Array in _roots:
		IslandArt.mass(self, root, trunk_base.y - 16.0, trunk_base.y + 20.0, lifted(rock_top_color, 0.6), dark())
	IslandArt.mass(self, _trunk, _trunk_top.y, trunk_base.y, lifted(rock_top_color, 0.7), dark())
	rim_edge(_trunk_left, 5.0)
	# The crown, lit from inside once the heart awakens.
	var crown_light: Color = lifted(rock_top_color).lerp(IslandArt.hdr(leaf_glow_color, 0.5), 0.35 * core)
	IslandArt.mass(self, _crown, _crown_top, _trunk_top.y + 50.0, crown_light, dark().lerp(IslandArt.hdr(leaf_glow_color, 0.3), 0.2 * core))
	IslandArt.rim(self, _crown_edge, 10.0, Color(rim_color(), rim_strength * rim_level()), IslandArt.facing(_crown_edge, light_dir, 0.0))
	if core > 0.0:
		IslandArt.soft_glow(self, _trunk_top + Vector2(0.0, -30.0), Vector2(110.0, 70.0), Color(leaf_glow_color, 0.16 * core))
	# The heart: a hollow in the trunk, dark, then glowing sap.
	var heart: Vector2 = trunk_base.lerp(_trunk_top, heart_share)
	var ring := PackedVector2Array()
	var colors := PackedColorArray()
	for k: int in 16:
		var angle: float = TAU * float(k) / 16.0
		ring.append(heart + Vector2(cos(angle) * heart_size.x * (1.0 - 0.3 * absf(sin(angle))), sin(angle) * heart_size.y))
		colors.append(locked_color.lerp(IslandArt.hdr(sap_color, 1.2), 0.5 * soft + 0.5 * core))
	IslandArt.fan(self, heart, locked_color.lerp(IslandArt.hdr(sap_color, 2.4), soft * 0.7 + core * 0.3), ring, colors, true, 3.0)
	if soft > 0.0:
		IslandArt.soft_glow(self, heart, Vector2(30.0, 50.0), Color(sap_color, 0.35 * soft + 0.3 * core))
		# Sap rising up the trunk into the crown.
		for sap: Dictionary in _sap:
			var t: float = fposmod(_time * float(sap.speed) + float(sap.phase), 1.0)
			var at: Vector2 = heart.lerp(_trunk_top + Vector2(0.0, -20.0), t) + Vector2(float(sap.side) * trunk_width.y, 0.0)
			spark(at, 1.1, sap_color, soft * sin(PI * t))
	if core > 0.0:
		draw_circle(heart, 4.0, IslandArt.hdr(sap_color, 3.0, core))
	for firefly: Dictionary in _fireflies:
		var phase: float = firefly.phase
		var at: Vector2 = firefly.base + Vector2(sin(_time * 0.7 + phase) * float(firefly.radius),
			cos(_time * 0.5 + phase * 1.3) * float(firefly.radius) * 0.6)
		spark(at, 1.0, firefly_color, lit(firefly.step, firefly.order) * maxf(sin(_time * 1.8 + phase * 3.0), 0.0))
