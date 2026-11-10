class_name JourneyIslandForest
extends JourneyIsland
## The Forest on the Journey screen: a grassy mound with two young firs and,
## in the middle, an ancient giant tree: a short, thick, twisted trunk flaring
## into buttress roots that grip the island, gnarled limbs spreading wide and
## nearly flat, and a crown of flat foliage tiers (wide pads with a lumpy top
## and a flat underside, a darker layer behind) with gaps between them. Its
## vessel of the Ancient Light: the tree's heart, a hollow in its trunk where
## the sap gathers. Everything is one dark silhouette (no outlines): trunk and
## limbs share one vertical gradient, so their overlaps never show.
##   stage 1: the hollow dark, a few fireflies;
##   stage 2: the sap glows softly in the hollow and rises up the trunk and
##            out along the limbs;
##   stage 3: the heart awakens with rays, the crown is lit from inside.

@export_group("Trunk")
@export var trunk_base: Vector2 = Vector2(-4.0, -24.0)
## From the foot to the fork where the limbs part.
@export var trunk_height: float = 66.0
## Width at the foot (before the flare) and at the fork.
@export var trunk_width: Vector2 = Vector2(50.0, 34.0)
## Extra width right at the foot: the buttress roots.
@export var trunk_flare: float = 30.0
## How far the trunk bends side to side (an S, px).
@export var trunk_twist: float = 7.0
## The spiralling bark ridges: how many, and their shades (0-1 of the lit rock).
@export var bark_ridges: int = 3
@export var bark_light_share: float = 0.95
@export var bark_dark_share: float = 0.25

@export_group("Limbs")
## Each limb: its centre line from the fork (x, y, ...), then its widths at the
## fork and at its tip as the last two values.
@export var limbs: Array[PackedFloat32Array] = [
	PackedFloat32Array([0.0, 2.0, -30.0, -6.0, -70.0, -6.0, -110.0, 0.0, -146.0, 6.0, 26.0, 6.0]),
	PackedFloat32Array([2.0, 0.0, 36.0, -14.0, 78.0, -24.0, 116.0, -22.0, 146.0, -16.0, 26.0, 6.0]),
	PackedFloat32Array([-3.0, -2.0, -18.0, -36.0, -46.0, -70.0, -80.0, -90.0, 19.0, 5.0]),
	PackedFloat32Array([3.0, -4.0, 22.0, -44.0, 50.0, -82.0, 82.0, -102.0, 19.0, 5.0]),
	PackedFloat32Array([0.0, -4.0, -8.0, -50.0, 2.0, -96.0, -6.0, -134.0, 17.0, 5.0]),
	PackedFloat32Array([-70.0, -6.0, -86.0, -28.0, -98.0, -40.0, 9.0, 3.0]),
	PackedFloat32Array([78.0, -24.0, 92.0, -46.0, 104.0, -58.0, 9.0, 3.0]),
	PackedFloat32Array([-46.0, -70.0, -30.0, -100.0, -22.0, -118.0, 8.0, 3.0])]
## How much the limbs' control points wander (px), so they read gnarled.
@export var limb_wobble: float = 4.0

@export_group("Crown")
## The front foliage tiers: (x, y from the fork, half width, thickness).
@export var front_pads: Array[Vector4] = [Vector4(-120.0, -8.0, 48.0, 20.0), Vector4(122.0, -30.0, 50.0, 21.0),
	Vector4(-78.0, -96.0, 56.0, 24.0), Vector4(78.0, -108.0, 58.0, 24.0), Vector4(-6.0, -142.0, 50.0, 26.0)]
## The darker tiers behind the limbs.
@export var back_pads: Array[Vector4] = [Vector4(-36.0, -58.0, 78.0, 26.0), Vector4(98.0, -68.0, 62.0, 24.0),
	Vector4(-108.0, -50.0, 52.0, 22.0), Vector4(16.0, -166.0, 40.0, 20.0)]
## Every tier's thickness is scaled by this.
@export var pad_thickness_scale: float = 1.35
## Lumps along a tier's top (min / max) and how deep the dips between them go (share).
@export var pad_lobes: Vector2i = Vector2i(4, 7)
@export var pad_dip: float = 0.72
## A tier's dome: the profile's power (below 1 = fuller shoulders).
@export var pad_fullness: float = 0.6
## How far a tier's underside sags below its centre (share of its thickness).
@export var pad_sag: float = 0.22
## Lit shade of the front / back tiers (share of the lit rock) and their undersides.
@export var front_pad_share: float = 0.9
@export var back_pad_share: float = 0.5
@export var pad_underside_share: float = 0.25

@export_group("Light")
## The heart: where it is up the trunk (share) and its size.
@export var heart_share: float = 0.4
@export var heart_size: Vector2 = Vector2(9.0, 20.0)
@export var sap_color: Color = Color(1.0, 0.85, 0.4)
@export var leaf_glow_color: Color = Color(0.7, 1.0, 0.45)
@export var firefly_color: Color = Color(0.85, 1.0, 0.45)
@export var firefly_count: int = 22
@export var sap_count: int = 16
## Glowing leaves on the tiers' tops once the heart awakens.
@export var leaf_light_count: int = 18

var _fork: Vector2 = Vector2.ZERO
var _trunk := PackedVector2Array()
var _trunk_left := PackedVector2Array()
var _bark: Array[Dictionary] = []
## {outline, edge} per limb; _limb_lines: their centre lines (sap paths).
var _limbs: Array[Dictionary] = []
var _limb_lines: Array[PackedVector2Array] = []
## {outline, top, center, half_width, thickness} per tier.
var _front_pads: Array[Dictionary] = []
var _back_pads: Array[Dictionary] = []
var _crown_top: float = 0.0
## Root shapes and the firs (polygons).
var _roots: Array[PackedVector2Array] = []
var _firs: Array[PackedVector2Array] = []
## {base, phase, radius, step, order}
var _fireflies: Array[Dictionary] = []
## {phase, speed, side, limb}
var _sap: Array[Dictionary] = []
## {at, phase, order}
var _leaf_lights: Array[Dictionary] = []


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
	_build_trunk(rng)
	_build_limbs(rng)
	_crown_top = _fork.y
	for spec: Vector4 in back_pads:
		_back_pads.append(_pad(rng, spec))
	for spec: Vector4 in front_pads:
		_front_pads.append(_pad(rng, spec))
	# The whole tree must fit the frame the Journey screen keeps for it.
	crown_height = maxf(crown_height, _top_y - _crown_top + 4.0)
	_build_roots()
	_build_firs()
	for i: int in firefly_count:
		var base := Vector2(rng.randf_range(-0.9, 0.9) * half_width, rng.randf_range(_crown_top + 30.0, -30.0))
		_fireflies.append({"base": base, "phase": rng.randf() * TAU, "radius": rng.randf_range(6.0, 16.0),
			"step": 1 if i < 6 else (2 if i < 14 else 3), "order": rng.randf()})
	for i: int in sap_count:
		_sap.append({"phase": rng.randf(), "speed": rng.randf_range(0.12, 0.22), "side": rng.randf_range(-0.3, 0.3),
			"limb": rng.randi_range(0, mini(4, _limb_lines.size() - 1))})
	for i: int in leaf_light_count:
		var pad: Dictionary = _front_pads[rng.randi_range(0, _front_pads.size() - 1)]
		var top: PackedVector2Array = pad.top
		var at: Vector2 = top[rng.randi_range(2, top.size() - 3)] + Vector2(0.0, rng.randf_range(3.0, 9.0))
		_leaf_lights.append({"at": at, "phase": rng.randf() * TAU, "order": rng.randf()})


## A short, thick column bending in an S, flaring into buttresses at its foot
## and widening a little at the fork; uneven edges.
func _build_trunk(rng: RandomNumberGenerator) -> void:
	var count: int = 16
	var line := PackedVector2Array()
	var widths := PackedFloat32Array()
	var phase: float = rng.randf() * TAU
	for k: int in count:
		var t: float = float(k) / float(count - 1)
		line.append(trunk_base + Vector2(sin(t * PI * 1.3) * trunk_twist - t * 4.0, -trunk_height * t))
		var width: float = lerpf(trunk_width.x, trunk_width.y, smoothstep(0.0, 1.0, t))
		width += trunk_flare * exp(-t * 9.0) + 8.0 * smoothstep(0.8, 1.0, t)
		widths.append(width * (1.0 + 0.06 * sin(t * 11.0 + phase)))
	_fork = line[count - 1]
	_trunk = IslandArt.shaped_ribbon(line, widths)
	_trunk_left = _trunk.slice(0, count)
	var right := PackedVector2Array()
	for k: int in count:
		right.append(_trunk[_trunk.size() - 1 - k])
	# Bark ridges spiralling up across the trunk: a lit ridge with a dark groove under it.
	for r: int in bark_ridges:
		var start: int = int(float(count) * (0.08 + 0.26 * float(r)))
		var span: int = 6
		var ridge := PackedVector2Array()
		var groove := PackedVector2Array()
		for k: int in span:
			var i: int = mini(start + k, count - 1)
			var s: float = float(k) / float(span - 1)
			var across: float = lerpf(0.12, 0.88, s)
			ridge.append(_trunk_left[i].lerp(right[i], across))
			groove.append(_trunk_left[i].lerp(right[i], across) + Vector2(0.0, 3.0))
		_bark.append({"ridge": IslandArt.ribbon(ridge, 3.0, 1.2), "groove": IslandArt.ribbon(groove, 2.6, 1.0)})


func _build_limbs(rng: RandomNumberGenerator) -> void:
	for spec: PackedFloat32Array in limbs:
		var controls := PackedVector2Array()
		var pairs: int = int((spec.size() - 2) / 2.0)
		for p: int in pairs:
			var wobble: Vector2 = Vector2.ZERO if p == 0 else Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * limb_wobble
			controls.append(_fork + Vector2(spec[p * 2], spec[p * 2 + 1]) + wobble)
		var line: PackedVector2Array = IslandArt.smooth_path(controls, 4)
		var outline: PackedVector2Array = IslandArt.ribbon(line, spec[spec.size() - 2], spec[spec.size() - 1])
		_limbs.append({"outline": outline, "edge": _upper_edge(outline)})
		_limb_lines.append(line)


## A foliage tier: wide and flat, a lumpy domed top, a flat underside that
## sags a little, both tips drooping. spec = (x, y from the fork, half width, thickness).
func _pad(rng: RandomNumberGenerator, spec: Vector4) -> Dictionary:
	var center: Vector2 = _fork + Vector2(spec.x, spec.y)
	var half: float = spec.z
	var thick: float = spec.w * pad_thickness_scale
	# Never narrower than the tier is thick (narrow lumps read as spikes).
	var lobes: int = mini(rng.randi_range(pad_lobes.x, pad_lobes.y), maxi(int(1.8 * half / thick), 2))
	# Lumps of uneven width and height, so the top never reads as a regular wave.
	var lobe_widths := PackedFloat32Array()
	var total: float = 0.0
	for i: int in lobes:
		lobe_widths.append(rng.randf_range(0.85, 1.6))
		total += lobe_widths[i]
	var inner: float = half * 0.9
	# Rounded tips that droop a little.
	var controls := PackedVector2Array([center + Vector2(-half, thick * 0.12), center + Vector2(-half * 0.97, -thick * 0.22)])
	var x: float = -inner
	for i: int in lobes:
		var width: float = 2.0 * inner * lobe_widths[i] / total
		var mid: float = x + width * rng.randf_range(0.35, 0.65)
		var lift: float = rng.randf_range(0.75, 1.1) * lerpf(0.85, 1.15, clampf(lobe_widths[i] - 0.6, 0.0, 1.0))
		controls.append(center + Vector2(mid, -_pad_profile(mid, half) * thick * lift))
		x += width
		if i < lobes - 1:
			controls.append(center + Vector2(x, -_pad_profile(x, half) * thick * pad_dip * rng.randf_range(0.85, 1.12)))
	controls.append(center + Vector2(half * 0.97, -thick * 0.22))
	controls.append(center + Vector2(half, thick * 0.12))
	var top: PackedVector2Array = IslandArt.smooth_path(controls, 4)
	var bottom_controls := PackedVector2Array()
	for k: int in range(5, 0, -1):
		var bx: float = -half + 2.0 * half * float(k) / 6.0
		var hang: float = rng.randf_range(0.0, 0.18)
		bottom_controls.append(center + Vector2(bx, thick * (pad_sag * _pad_profile(bx, half) + hang)))
	var outline: PackedVector2Array = top.duplicate()
	var bottom: PackedVector2Array = IslandArt.smooth_path(bottom_controls, 3)
	outline.append_array(bottom)
	var highest: float = center.y
	for point: Vector2 in top:
		highest = minf(highest, point.y)
	_crown_top = minf(_crown_top, highest)
	return {"outline": outline, "top": top, "center": center, "half_width": half, "thickness": thick, "highest": highest}


## 0-1: a tier's height across it (1 in the middle, 0 at its tips).
func _pad_profile(x: float, half: float) -> float:
	return pow(maxf(1.0 - pow(x / half, 2.0), 0.0), pad_fullness)


## Thick roots curving from the trunk's foot down over the mound.
func _build_roots() -> void:
	for spec: Vector3 in [Vector3(-1.0, 58.0, 18.0), Vector3(-1.0, 32.0, 14.0), Vector3(1.0, 54.0, 18.0),
			Vector3(1.0, 30.0, 14.0), Vector3(-1.0, 14.0, 10.0)]:
		var reach: float = spec.y
		var root_line := PackedVector2Array()
		for k: int in 7:
			var t: float = float(k) / 6.0
			var x: float = trunk_base.x + spec.x * (trunk_width.x * 0.3 + reach * t)
			root_line.append(Vector2(x, lerpf(trunk_base.y - 18.0, top_y_at(x) + 4.0, pow(t, 0.7))))
		_roots.append(IslandArt.ribbon(root_line, spec.z, 3.0))


## Two young firs on the mound.
func _build_firs() -> void:
	for spec: Vector3 in [Vector3(-0.78, 50.0, 22.0), Vector3(0.74, 40.0, 19.0)]:
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


## A point along a polyline, t = 0-1 of its length.
static func _along(line: PackedVector2Array, t: float) -> Vector2:
	var total: float = 0.0
	for i: int in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	var target: float = total * clampf(t, 0.0, 1.0)
	for i: int in range(1, line.size()):
		var length: float = line[i].distance_to(line[i - 1])
		if target <= length:
			return line[i - 1].lerp(line[i], target / maxf(length, 0.001))
		target -= length
	return line[line.size() - 1]


func _heart() -> Vector2:
	return trunk_base.lerp(_fork, heart_share)


func _draw_back() -> void:
	var core: float = core_level()
	if core > 0.0:
		rays(_heart(), 9, 200.0, 0.045, sap_color, core, 0.03)
		IslandArt.soft_glow(self, _heart(), Vector2(150.0, 150.0), Color(sap_color, 0.25 * core))


func _draw_front() -> void:
	var soft: float = soft_level()
	var core: float = core_level()
	for fir: PackedVector2Array in _firs:
		IslandArt.mass(self, fir, fir[0].y - 60.0, fir[0].y, lifted(rock_top_color, 0.8), dark())
	# The tiers behind the limbs, then the crown's inner light between the layers.
	for pad: Dictionary in _back_pads:
		_draw_pad(pad, back_pad_share, core, 0.4)
	if core > 0.0:
		IslandArt.soft_glow(self, _fork + Vector2(0.0, -80.0), Vector2(190.0, 120.0), Color(leaf_glow_color, 0.14 * core))
	# Roots, trunk and limbs: one gradient, so they merge into one silhouette.
	var wood_top: Color = lifted(rock_top_color, 0.7)
	for root: PackedVector2Array in _roots:
		IslandArt.mass(self, root, _crown_top, trunk_base.y + 20.0, wood_top, dark())
	for limb: Dictionary in _limbs:
		IslandArt.mass(self, limb.outline, _crown_top, trunk_base.y + 20.0, wood_top, dark())
	IslandArt.mass(self, _trunk, _crown_top, trunk_base.y + 20.0, wood_top, dark())
	for bark: Dictionary in _bark:
		var groove: PackedVector2Array = bark.groove
		var ridge: PackedVector2Array = bark.ridge
		IslandArt.mass(self, groove, _fork.y, trunk_base.y, dark().lerp(wood_top, bark_dark_share), dark())
		IslandArt.mass(self, ridge, _fork.y, trunk_base.y, lifted(rock_top_color, bark_light_share), lifted(rock_top_color, 0.5))
	rim_edge(_trunk_left, 5.0)
	for limb: Dictionary in _limbs:
		rim_edge(limb.edge, 3.0, 0.6)
	# Sap rising up the trunk and out along the limbs.
	var heart: Vector2 = _heart()
	if soft > 0.0:
		for sap: Dictionary in _sap:
			var t: float = fposmod(_time * float(sap.speed) + float(sap.phase), 1.0)
			var at: Vector2
			if t < 0.35:
				at = heart.lerp(_fork, t / 0.35) + Vector2(float(sap.side) * trunk_width.y, 0.0)
			else:
				at = _along(_limb_lines[int(sap.limb)], (t - 0.35) / 0.65)
			spark(at, 1.1, sap_color, soft * sin(PI * t))
	# The front tiers, lit from inside once the heart awakens.
	for pad: Dictionary in _front_pads:
		if core > 0.0:
			IslandArt.soft_glow(self, pad.center + Vector2(0.0, float(pad.thickness) * 0.4),
				Vector2(float(pad.half_width) * 1.3, float(pad.thickness) * 2.0), Color(leaf_glow_color, 0.2 * core))
		_draw_pad(pad, front_pad_share, core, 1.0)
	for leaf: Dictionary in _leaf_lights:
		var phase: float = leaf.phase
		spark(leaf.at, 0.9, leaf_glow_color, lit(3, leaf.order) * (0.55 + 0.45 * sin(_time * 1.3 + phase)))
	# The heart: a hollow in the trunk, dark, then glowing sap.
	var ring := PackedVector2Array()
	var colors := PackedColorArray()
	for k: int in 16:
		var angle: float = TAU * float(k) / 16.0
		ring.append(heart + Vector2(cos(angle) * heart_size.x * (1.0 - 0.3 * absf(sin(angle))), sin(angle) * heart_size.y))
		colors.append(locked_color.lerp(IslandArt.hdr(sap_color, 1.2), 0.5 * soft + 0.5 * core))
	IslandArt.fan(self, heart, locked_color.lerp(IslandArt.hdr(sap_color, 2.4), soft * 0.7 + core * 0.3), ring, colors, true, 3.0)
	if soft > 0.0:
		IslandArt.soft_glow(self, heart, Vector2(30.0, 50.0), Color(sap_color, 0.35 * soft + 0.3 * core))
	if core > 0.0:
		draw_circle(heart, 4.0, IslandArt.hdr(sap_color, 3.0, core))
	for firefly: Dictionary in _fireflies:
		var phase: float = firefly.phase
		var at: Vector2 = firefly.base + Vector2(sin(_time * 0.7 + phase) * float(firefly.radius),
			cos(_time * 0.5 + phase * 1.3) * float(firefly.radius) * 0.6)
		spark(at, 1.0, firefly_color, lit(firefly.step, firefly.order) * maxf(sin(_time * 1.8 + phase * 3.0), 0.0))


## One foliage tier: lit on its lumpy top, dark underneath; share = how lit
## (back tiers darker); rim_share = its rim light.
func _draw_pad(pad: Dictionary, share: float, core: float, rim_share: float) -> void:
	var top_color: Color = lifted(rock_top_color, share).lerp(IslandArt.hdr(leaf_glow_color, 0.5), 0.35 * core * share)
	var under: Color = dark().lerp(lifted(rock_top_color, pad_underside_share), 0.6)
	under = under.lerp(IslandArt.hdr(leaf_glow_color, 0.3), 0.2 * core * share)
	var center: Vector2 = pad.center
	IslandArt.mass(self, pad.outline, float(pad.highest), center.y + float(pad.thickness) * 0.4, top_color, under)
	var top: PackedVector2Array = pad.top
	IslandArt.rim(self, top, 7.0, Color(rim_color(), rim_strength * rim_level() * rim_share),
		IslandArt.facing(top, light_dir, 0.0))
