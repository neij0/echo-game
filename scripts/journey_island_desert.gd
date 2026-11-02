class_name JourneyIslandDesert
extends JourneyIsland
## The Desert on the Journey screen: dunes, a broken pillar and a fallen block
## of an old city, sand drifting in the wind. Its vessel of the Ancient Light:
## a great hourglass in a stone frame, half sunk in the dunes. Dark
## silhouettes, no outlines.
##   stage 1: dark glass, the sand still; a few embers in the ruin;
##   stage 2: the glass glows softly, a thin stream of light-sand falls;
##   stage 3: the core awakens at its neck with rays, the sand pours bright.

@export_group("Hourglass")
## Where the hourglass stands (the middle of its foot) and its size.
@export var glass_base: Vector2 = Vector2(6.0, -16.0)
@export var glass_height: float = 168.0
@export var bulb_size: Vector2 = Vector2(34.0, 36.0)
@export var plate_size: Vector2 = Vector2(104.0, 12.0)
@export var post_width: float = 9.0
@export var glass_color: Color = Color(1.0, 0.78, 0.45)
@export var sand_color: Color = Color(1.0, 0.86, 0.55)
@export var core_color: Color = Color(1.0, 0.92, 0.7)
@export var ember_color: Color = Color(1.0, 0.6, 0.25)
@export var drift_count: int = 16
@export var stream_count: int = 10

var _plates: Array[PackedVector2Array] = []
var _posts: Array[PackedVector2Array] = []
var _pillar := PackedVector2Array()
var _block := PackedVector2Array()
var _neck: Vector2 = Vector2.ZERO
var _upper: Vector2 = Vector2.ZERO
var _lower: Vector2 = Vector2.ZERO
## {y, phase, speed, length}
var _drifts: Array[Dictionary] = []
## {at, step, order, phase}
var _embers: Array[Dictionary] = []


func _init() -> void:
	accent = Color(1.0, 0.75, 0.42)
	crown_height = 200.0
	rock_top_color = Color(0.07, 0.055, 0.035)
	far_rock_color = Color(0.06, 0.05, 0.04)


func _build_top(rng: RandomNumberGenerator) -> PackedVector2Array:
	var controls := PackedVector2Array()
	for spec: Vector2 in [Vector2(-1.0, 0.0), Vector2(-0.8, -16.0), Vector2(-0.6, -32.0), Vector2(-0.44, -26.0),
			Vector2(-0.24, -18.0), Vector2(0.0, -16.0), Vector2(0.24, -22.0), Vector2(0.46, -36.0), Vector2(0.6, -44.0),
			Vector2(0.72, -30.0), Vector2(0.86, -16.0), Vector2(1.0, 0.0)]:
		var jitter: float = 0.0 if absf(spec.x) > 0.99 else rng.randf_range(-2.0, 2.0)
		controls.append(Vector2(spec.x * half_width, spec.y + jitter))
	return IslandArt.smooth_path(controls, 5)


func _build_kind(rng: RandomNumberGenerator) -> void:
	var top: float = glass_base.y - glass_height
	_neck = glass_base + Vector2(0.0, -glass_height * 0.5)
	_upper = _neck + Vector2(0.0, -bulb_size.y)
	_lower = _neck + Vector2(0.0, bulb_size.y)
	for y: float in [glass_base.y, top + plate_size.y]:
		_plates.append(PackedVector2Array([Vector2(glass_base.x - plate_size.x * 0.5, y), Vector2(glass_base.x + plate_size.x * 0.5, y),
			Vector2(glass_base.x + plate_size.x * 0.44, y - plate_size.y), Vector2(glass_base.x - plate_size.x * 0.44, y - plate_size.y)]))
	for side: float in [-1.0, 1.0]:
		var x: float = glass_base.x + side * (plate_size.x * 0.5 - post_width)
		var post := PackedVector2Array([Vector2(x - post_width * 0.5, glass_base.y - plate_size.y),
			Vector2(x + post_width * 0.5, glass_base.y - plate_size.y), Vector2(x + post_width * 0.42, top + plate_size.y),
			Vector2(x - post_width * 0.42, top + plate_size.y)])
		_posts.append(post)
	# A broken pillar on the left dune and a fallen block on the right.
	var foot := Vector2(-0.6 * half_width, top_y_at(-0.6 * half_width) + 6.0)
	_pillar = PackedVector2Array([foot + Vector2(-11.0, 0.0), foot + Vector2(11.0, 0.0), foot + Vector2(10.0, -70.0),
		foot + Vector2(4.0, -78.0), foot + Vector2(1.0, -70.0), foot + Vector2(-4.0, -86.0), foot + Vector2(-10.0, -80.0)])
	var block_foot := Vector2(0.74 * half_width, top_y_at(0.74 * half_width) + 4.0)
	_block = PackedVector2Array([block_foot + Vector2(-16.0, 0.0), block_foot + Vector2(18.0, 0.0), block_foot + Vector2(14.0, -20.0),
		block_foot + Vector2(-12.0, -24.0)])
	for i: int in drift_count:
		_drifts.append({"y": rng.randf_range(-60.0, 0.0), "phase": rng.randf(), "speed": rng.randf_range(0.08, 0.16),
			"length": rng.randf_range(10.0, 26.0)})
	for i: int in 6:
		_embers.append({"at": foot + Vector2(rng.randf_range(-8.0, 8.0), -rng.randf_range(10.0, 70.0)), "step": 1 + i % 3,
			"order": rng.randf(), "phase": rng.randf() * TAU})


func _draw_back() -> void:
	var core: float = core_level()
	if core > 0.0:
		rays(_neck, 8, 190.0, 0.045, core_color, core, 0.035)
		IslandArt.soft_glow(self, _neck, Vector2(140.0, 140.0), Color(glass_color, 0.25 * core))


func _draw_front() -> void:
	var soft: float = soft_level()
	var core: float = core_level()
	IslandArt.mass(self, _pillar, _pillar[5].y, _pillar[0].y, lifted(rock_top_color), dark())
	rim_edge(PackedVector2Array([_pillar[0], _pillar[6], _pillar[5]]), 4.0)
	IslandArt.mass(self, _block, _block[3].y, _block[0].y, lifted(rock_top_color), dark())
	for ember: Dictionary in _embers:
		spark(ember.at, 0.9, ember_color, lit(ember.step, ember.order) * (0.5 + 0.5 * sin(_time * 2.3 + float(ember.phase))))
	# The glass: two bulbs, dark, then glowing from inside.
	var glass_on: float = soft * 0.6 + core * 0.4
	for bulb: Vector2 in [_upper, _lower]:
		IslandArt.shaded_disc(self, bulb, bulb_size, _glass_shade.bind(glass_on), 32)
	# The sand: a heap in the lower bulb, less in the upper one.
	var sand_dark: Color = dark()
	var sand_lit: Color = IslandArt.hdr(sand_color, 1.4)
	var heap := PackedVector2Array()
	var cap := PackedVector2Array()
	for k: int in 13:
		var t: float = float(k) / 12.0
		var x: float = lerpf(-bulb_size.x * 0.86, bulb_size.x * 0.86, t)
		var floor_y: float = sqrt(maxf(1.0 - pow(x / bulb_size.x, 2.0), 0.0)) * bulb_size.y * 0.92
		heap.append(_lower + Vector2(x, minf(bulb_size.y * 0.15 + absf(x) * 0.5, floor_y - 3.0)))
		cap.append(_upper + Vector2(x * 0.8, -bulb_size.y * 0.05 + absf(x) * 0.35))
	for k: int in range(12, -1, -1):
		var t: float = float(k) / 12.0
		var x: float = lerpf(-bulb_size.x * 0.86, bulb_size.x * 0.86, t)
		heap.append(_lower + Vector2(x, sqrt(maxf(1.0 - pow(x / bulb_size.x, 2.0), 0.0)) * bulb_size.y * 0.92))
		cap.append(_upper + Vector2(x * 0.62, bulb_size.y * 0.74 - absf(x) * 0.2))
	IslandArt.mass(self, heap, _lower.y, _lower.y + bulb_size.y, sand_dark.lerp(sand_lit, 0.55 * glass_on), sand_dark)
	IslandArt.mass(self, cap, _upper.y, _upper.y + bulb_size.y, sand_dark.lerp(sand_lit, 0.45 * glass_on), sand_dark)
	# The stream of light-sand through the neck.
	if soft > 0.0:
		for k: int in stream_count:
			var t: float = fposmod(_time * 0.9 + float(k) / float(stream_count), 1.0)
			var at: Vector2 = _neck + Vector2(sin(t * 20.0) * 0.6, lerpf(-bulb_size.y * 0.2, bulb_size.y * 0.75, t))
			spark(at, 0.8 + 0.6 * core, sand_color, soft * (1.0 - t * 0.6))
	if core > 0.0:
		draw_circle(_neck, 4.5, IslandArt.hdr(core_color, 3.0, core))
		IslandArt.soft_glow(self, _neck, Vector2(26.0, 26.0), IslandArt.hdr(core_color, 1.5, 0.85 * core))
	# The stone frame over the glass.
	for post: PackedVector2Array in _posts:
		IslandArt.mass(self, post, post[3].y, post[0].y, lifted(rock_top_color), dark())
		rim_edge(PackedVector2Array([post[0], post[3]]), 3.0)
	for plate: PackedVector2Array in _plates:
		IslandArt.mass(self, plate, plate[3].y, plate[0].y, lifted(rock_top_color), dark())
		rim_edge(PackedVector2Array([plate[0], plate[3], plate[2]]), 4.0)
	IslandArt.soft_glow(self, glass_base, Vector2(80.0, 16.0), Color(glass_color, 0.25 * glass_on))
	# Sand drifting in the wind over the dunes.
	var drift_on: float = unlocked() * (0.3 + 0.7 * overall())
	if drift_on > 0.0:
		for drift: Dictionary in _drifts:
			var t: float = fposmod(_time * float(drift.speed) + float(drift.phase), 1.0)
			var x: float = lerpf(-half_width, half_width, t)
			var at := Vector2(x, top_y_at(x) + float(drift.y) * 0.4 - 6.0)
			IslandArt.soft_glow(self, at, Vector2(float(drift.length), 2.5), Color(sand_color, 0.18 * drift_on * sin(PI * t)))


func _glass_shade(point: Vector2, share: float, on: float) -> Color:
	var lit_glass: Color = IslandArt.hdr(glass_color, 0.55).lerp(IslandArt.hdr(core_color, 1.0), clampf(1.0 - point.distance_to(_neck) / 60.0, 0.0, 1.0) * 0.6)
	var edge: float = pow(share, 3.0)
	var dark_glass: Color = locked_color.lerp(Color(0.03, 0.025, 0.02), unlocked()).lerp(rim_color() * 0.3, edge * rim_level() * 0.4)
	return dark_glass.lerp(Color(lit_glass, 1.0), on * (0.55 + 0.45 * edge))
