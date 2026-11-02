class_name JourneyIslandCaves
extends JourneyIsland
## The Caves on the Journey screen: a heavy rock mass with stalagmite spikes,
## long thin stalactites hanging under it, glow-worms among them. Its vessel of
## the Ancient Light: a hollow geode broken open, a bowl of stone with a
## jagged rim, its crystal lining seen from a little above and a cluster of
## crystals rising out of it (crystals growing up out of a bowl: never a face).
##   stage 1: the crystals dark, a few glow-worms under the rock;
##   stage 2: the geode's lining and the crystals glow softly;
##   stage 3: the great crystal's core awakens with rays, sparks rise.

@export_group("Geode")
## The geode's foot and its size (half width, height of the bowl).
@export var geode_base: Vector2 = Vector2(0.0, -22.0)
@export var geode_size: Vector2 = Vector2(90.0, 66.0)
## Height of the inside seen from above (share of the half width) and of the rim's shards.
@export var opening_depth: float = 0.28
@export var shard_height: Vector2 = Vector2(6.0, 20.0)
## Crystals: (x offset from the geode's foot, height, width, lean).
@export var crystals: Array[Vector4] = [Vector4(0.0, 112.0, 24.0, 2.0), Vector4(-20.0, 76.0, 17.0, -9.0),
	Vector4(21.0, 82.0, 18.0, 10.0), Vector4(-38.0, 50.0, 13.0, -12.0), Vector4(39.0, 54.0, 13.0, 14.0),
	Vector4(-8.0, 60.0, 12.0, -3.0)]
@export var crystal_color: Color = Color(1.0, 0.62, 0.28)
@export var crystal_alt_color: Color = Color(0.78, 0.55, 1.0)
@export var core_color: Color = Color(1.0, 0.85, 0.6)
@export var glow_worm_color: Color = Color(0.55, 0.95, 0.85)
@export var glow_worm_count: int = 14
@export var spark_count: int = 14

## The bowl's front (polygon), its outer edge (walked with the bowl on its
## right) and the opening seen from above (its centre and radii).
var _bowl := PackedVector2Array()
var _bowl_edge := PackedVector2Array()
var _rim_y: float = 0.0
## {at, step, order, phase}
var _worms: Array[Dictionary] = []
## {x, phase, speed}
var _sparks: Array[Dictionary] = []


func _init() -> void:
	tooth_width = Vector2(8.0, 18.0)
	front_share = 0.72
	accent = Color(1.0, 0.62, 0.3)
	crown_height = 150.0


func _build_top(rng: RandomNumberGenerator) -> PackedVector2Array:
	var controls := PackedVector2Array()
	for spec: Vector2 in [Vector2(-1.0, 0.0), Vector2(-0.93, -20.0), Vector2(-0.86, -30.0), Vector2(-0.82, -62.0),
			Vector2(-0.77, -30.0), Vector2(-0.62, -34.0), Vector2(-0.42, -24.0), Vector2(-0.2, -20.0), Vector2(0.0, -18.0),
			Vector2(0.22, -22.0), Vector2(0.44, -28.0), Vector2(0.6, -38.0), Vector2(0.68, -78.0), Vector2(0.75, -36.0),
			Vector2(0.86, -26.0), Vector2(0.94, -16.0), Vector2(1.0, 0.0)]:
		var jitter: float = 0.0 if absf(spec.x) > 0.99 else rng.randf_range(-3.0, 3.0)
		controls.append(Vector2(spec.x * half_width, spec.y + jitter))
	return IslandArt.smooth_path(controls, 3)


func _build_kind(rng: RandomNumberGenerator) -> void:
	_build_bowl(rng)
	for i: int in glow_worm_count:
		var x: float = rng.randf_range(-0.7, 0.7) * half_width
		_worms.append({"at": Vector2(x, _top_y + rng.randf_range(30.0, underside_depth * 0.55) * (1.0 - absf(x) / half_width * 0.6)),
			"step": 1 if i < 5 else (2 if i < 10 else 3), "order": rng.randf(), "phase": rng.randf() * TAU})
	for i: int in spark_count:
		_sparks.append({"x": rng.randf_range(-24.0, 24.0), "phase": rng.randf(), "speed": rng.randf_range(0.12, 0.22)})


## The bowl: from its rim on the left round the bottom to the rim on the
## right, then back along a jagged rim of shards.
func _build_bowl(rng: RandomNumberGenerator) -> void:
	_rim_y = geode_base.y - geode_size.y
	var count: int = 20
	for k: int in count + 1:
		var angle: float = PI - PI * float(k) / float(count)
		var bump: float = 1.0 + rng.randf_range(-0.03, 0.03)
		_bowl.append(Vector2(geode_base.x + cos(angle) * geode_size.x * bump, _rim_y + sin(angle) * geode_size.y * bump))
	_bowl_edge = _bowl.duplicate()
	_bowl_edge.reverse()
	var shards: int = 9
	for k: int in range(shards - 1, 0, -1):
		var x: float = geode_base.x + lerpf(-geode_size.x, geode_size.x, float(k) / float(shards))
		var up: float = rng.randf_range(shard_height.x, shard_height.y) if k % 2 == 0 else rng.randf_range(0.0, 4.0)
		_bowl.append(Vector2(x, _rim_y - up + geode_size.x * opening_depth * 0.3))


func _draw_back() -> void:
	var soft: float = soft_level()
	var core: float = core_level()
	var heart: Vector2 = _crystal_foot() + Vector2(crystals[0].w, -crystals[0].y + 18.0)
	if core > 0.0:
		rays(heart, 8, 170.0, 0.05, core_color, core, 0.04)
		IslandArt.soft_glow(self, heart, Vector2(130.0, 130.0), Color(crystal_color, 0.3 * core))
	IslandArt.soft_glow(self, geode_base + Vector2(0.0, -geode_size.y), Vector2(geode_size.x, geode_size.y) * 1.3,
		Color(crystal_color, 0.22 * soft))
	# The inside, seen from a little above: dark, then its crystal lining glows.
	var lining_on: float = soft * 0.7 + core * 0.3
	IslandArt.shaded_disc(self, Vector2(geode_base.x, _rim_y), Vector2(geode_size.x * 0.94, geode_size.x * opening_depth),
		_lining_shade.bind(lining_on), 40)


func _draw_front() -> void:
	var soft: float = soft_level()
	var core: float = core_level()
	for i: int in crystals.size():
		var spec: Vector4 = crystals[i]
		var foot: Vector2 = _crystal_foot() + Vector2(spec.x, 0.0)
		var shape: PackedVector2Array = crystal_shape(foot, spec.y, spec.z, spec.w)
		var color: Color = crystal_color if i % 3 != 2 else crystal_alt_color
		var on: float = soft * 0.6 + (core if i == 0 else core * 0.4)
		glowing_shape(shape, foot.y - spec.y, foot.y, color, on)
	IslandArt.mass(self, _bowl, _rim_y - shard_height.y, geode_base.y, lifted(rock_top_color), dark())
	rim_edge(_bowl_edge.slice(0, _bowl_edge.size() / 2 + 1), 7.0)
	var tip: Vector2 = _crystal_foot() + Vector2(crystals[0].w, -crystals[0].y)
	if core > 0.0:
		draw_circle(tip + Vector2(0.0, 18.0), 4.5, IslandArt.hdr(core_color, 3.0, core))
		IslandArt.soft_glow(self, tip + Vector2(0.0, 18.0), Vector2(28.0, 28.0), IslandArt.hdr(core_color, 1.5, 0.8 * core))
		for spark_info: Dictionary in _sparks:
			var t: float = fposmod(_time * float(spark_info.speed) + float(spark_info.phase), 1.0)
			var at := Vector2(float(spark_info.x) * (1.0 + t), tip.y + 10.0 - t * 110.0)
			spark(at, 1.1, core_color, core * (1.0 - t) * smoothstep(0.0, 0.1, t))
	for worm: Dictionary in _worms:
		spark(worm.at, 1.2, glow_worm_color, lit(worm.step, worm.order) * (0.6 + 0.4 * sin(_time * 1.3 + float(worm.phase))))


## The geode's inside: crystal lining, brightest at the far wall.
func _lining_shade(point: Vector2, share: float, on: float) -> Color:
	var far: float = clampf((_rim_y - point.y) / (geode_size.x * opening_depth) * 0.5 + 0.5, 0.0, 1.0)
	var lit_lining: Color = IslandArt.hdr(crystal_alt_color, 0.9).lerp(IslandArt.hdr(crystal_color, 1.3), far * 0.6)
	return locked_color.lerp(lit_lining, on * (0.35 + 0.65 * share))


## Where the crystals stand: inside the bowl, a little under its rim.
func _crystal_foot() -> Vector2:
	return Vector2(geode_base.x, _rim_y + geode_size.y * 0.45)
