class_name JourneyIslandSnow
extends JourneyIsland
## Snow on the Journey screen: sharp peaks with pale snow caps (lighter
## shapes, no outlines), snow falling round them. Its vessel of the Ancient
## Light: an ice star standing on the summit.
##   stage 1: the star dark ice, a few glints on the snow;
##   stage 2: the ice glows softly from inside;
##   stage 3: its core awakens with long twinkling rays.

@export_group("Peaks")
## The skyline's control points (x share of the half width, y); straight
## between them, so the peaks stay sharp.
@export var peaks: PackedVector2Array = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(-0.9, -26.0), Vector2(-0.74, -62.0),
	Vector2(-0.6, -104.0), Vector2(-0.5, -70.0), Vector2(-0.38, -92.0), Vector2(-0.16, -150.0), Vector2(0.02, -196.0),
	Vector2(0.2, -138.0), Vector2(0.34, -96.0), Vector2(0.5, -122.0), Vector2(0.66, -70.0), Vector2(0.82, -40.0),
	Vector2(0.92, -22.0), Vector2(1.0, 0.0)])
## How far down from each peak its snow cap reaches (share of the peak's height).
@export var cap_share: float = 0.32
@export var snow_color: Color = Color(0.13, 0.16, 0.21)
@export var star_radius: float = 28.0
## The star's height above the summit.
@export var star_lift: float = 30.0
@export var ice_color: Color = Color(0.6, 0.85, 1.0)
@export var star_color: Color = Color(0.85, 0.95, 1.0)
@export var flake_count: int = 30

var _summit: Vector2 = Vector2.ZERO
var _star := PackedVector2Array()
var _star_center: Vector2 = Vector2.ZERO
## Snow caps (polygons) under the peaks.
var _caps: Array[PackedVector2Array] = []
## {x, y, phase, speed}
var _flakes: Array[Dictionary] = []
## {at, step, order}
var _glints: Array[Dictionary] = []


func _init() -> void:
	accent = Color(0.8, 0.9, 1.0)
	crown_height = 270.0
	rock_top_color = Color(0.05, 0.06, 0.08)


func _build_top(rng: RandomNumberGenerator) -> PackedVector2Array:
	var edge := PackedVector2Array()
	for i: int in peaks.size():
		var spec: Vector2 = peaks[i]
		var jitter: float = 0.0 if i == 0 or i == peaks.size() - 1 else rng.randf_range(-3.0, 3.0)
		edge.append(Vector2(spec.x * half_width, spec.y + jitter))
		if edge[i].y < _summit.y:
			_summit = edge[i]
	# Split each straight span so the rim light follows it smoothly.
	var fine := PackedVector2Array()
	for i: int in edge.size() - 1:
		for k: int in 6:
			fine.append(edge[i].lerp(edge[i + 1], float(k) / 6.0))
	fine.append(edge[edge.size() - 1])
	return fine


func _build_kind(rng: RandomNumberGenerator) -> void:
	# A snow cap under every peak higher than its neighbours: from the peak
	# down both slopes, its lower edge ragged.
	for i: int in range(1, peaks.size() - 1):
		var peak: Vector2 = Vector2(peaks[i].x * half_width, peaks[i].y)
		if peaks[i].y >= peaks[i - 1].y or peaks[i].y >= peaks[i + 1].y or peaks[i].y > -60.0:
			continue
		var drop: float = -peaks[i].y * cap_share
		var left: Vector2 = Vector2(peaks[i - 1].x * half_width, peaks[i - 1].y)
		var right: Vector2 = Vector2(peaks[i + 1].x * half_width, peaks[i + 1].y)
		var down_left: Vector2 = peak.lerp(left, minf(drop / (left.y - peak.y), 1.0))
		var down_right: Vector2 = peak.lerp(right, minf(drop / (right.y - peak.y), 1.0))
		var cap := PackedVector2Array([down_left, peak + Vector2(0.0, -1.0), down_right])
		for k: int in range(1, 5):
			var t: float = float(k) / 5.0
			cap.append(down_right.lerp(down_left, t) + Vector2(0.0, rng.randf_range(-4.0, 8.0) * (1.0 if k % 2 == 0 else -0.5)))
		_caps.append(cap)
	_star_center = _summit + Vector2(0.0, -star_lift)
	for k: int in 12:
		var angle: float = -PI * 0.5 + TAU * float(k) / 12.0
		var reach: float = star_radius if k % 2 == 0 else star_radius * 0.38
		if k % 4 == 2:
			reach *= 0.72
		_star.append(_star_center + Vector2.from_angle(angle) * reach)
	for i: int in flake_count:
		_flakes.append({"x": rng.randf_range(-1.0, 1.0) * half_width, "y": rng.randf(), "phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.05, 0.1)})
	for i: int in 10:
		var x: float = rng.randf_range(-0.8, 0.8) * half_width
		_glints.append({"at": Vector2(x, top_y_at(x) + rng.randf_range(6.0, 30.0)), "step": 1 if i < 3 else (2 if i < 7 else 3),
			"order": rng.randf()})


func _draw_back() -> void:
	var core: float = core_level()
	if core > 0.0:
		rays(_star_center, 10, 160.0, 0.03, star_color, core, 0.02)
		IslandArt.soft_glow(self, _star_center, Vector2(120.0, 120.0), Color(ice_color, 0.28 * core))


func _draw_front() -> void:
	var soft: float = soft_level()
	var core: float = core_level()
	var snow: Color = dark().lerp(snow_color, unlocked() * (0.6 + 0.4 * overall()))
	for cap: PackedVector2Array in _caps:
		IslandArt.mass(self, cap, cap[1].y, cap[0].y + 10.0, snow.lerp(IslandArt.hdr(ice_color, 0.5), 0.2 * soft), snow)
	for glint: Dictionary in _glints:
		spark(glint.at, 0.9, ice_color, lit(glint.step, glint.order) * (0.4 + 0.6 * maxf(sin(_time * 1.5 + float(glint.order) * 20.0), 0.0)))
	# The ice star on the summit: a short stem of ice, then the star.
	var stem := PackedVector2Array([_summit + Vector2(-5.0, 4.0), _summit + Vector2(5.0, 4.0), _star_center + Vector2(3.0, 6.0),
		_star_center + Vector2(-3.0, 6.0)])
	IslandArt.mass(self, stem, _star_center.y, _summit.y, lifted(rock_top_color), dark())
	var glow_on: float = soft * 0.6 + core * 0.4
	var colors := PackedColorArray()
	for point: Vector2 in _star:
		colors.append(lifted(rock_top_color).lerp(IslandArt.hdr(ice_color, 1.3), 0.7 * glow_on))
	IslandArt.fan(self, _star_center, dark().lerp(IslandArt.hdr(star_color, 2.2), glow_on), _star, colors, true, 2.0)
	var upper := PackedVector2Array()
	for k: int in [9, 10, 11, 0, 1]:
		upper.append(_star[k])
	rim_edge(upper, 4.0)
	if soft > 0.0:
		IslandArt.soft_glow(self, _star_center, Vector2(star_radius, star_radius) * 2.2, Color(ice_color, 0.3 * soft))
	if core > 0.0:
		# Long twinkling cross rays.
		var twinkle: float = 0.85 + 0.15 * sin(_time * 3.1)
		for angle: float in [0.0, PI * 0.5]:
			IslandArt.soft_glow(self, _star_center, Vector2(90.0, 3.5).rotated(angle).abs() + Vector2.ONE * 3.0,
				IslandArt.hdr(star_color, 1.6, 0.7 * core * twinkle))
		draw_circle(_star_center, 5.0, IslandArt.hdr(star_color, 3.2, core))
	# Snow falling round the peaks.
	var fall_on: float = unlocked() * (0.4 + 0.6 * overall())
	if fall_on > 0.0:
		for flake: Dictionary in _flakes:
			var t: float = fposmod(float(flake.y) + _time * float(flake.speed), 1.0)
			var at := Vector2(float(flake.x) + sin(_time * 0.8 + float(flake.phase)) * 6.0, lerpf(-260.0, 40.0, t))
			IslandArt.soft_glow(self, at, Vector2(3.0, 3.0), IslandArt.hdr(star_color, 1.2, 0.5 * fall_on * sin(PI * t)))
