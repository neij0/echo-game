class_name JourneyIslandSnow
extends JourneyIsland
## Snow on the Journey screen: sharp peaks with snow caps rising from a pale
## top, snow falling, ice glinting. Step 1: a few glints; step 2: more, and the
## caps catch the light; step 3: a star shines above the summit (the marker).

@export var star_color: Color = Color(0.85, 0.95, 1.0)
@export var ice_color: Color = Color(0.6, 0.85, 1.0)
@export var peak_color: Color = Color(0.035, 0.045, 0.065)
@export var snow_color: Color = Color(0.2, 0.24, 0.3)
@export var star_height: float = 70.0
@export var flake_count: int = 30

## Each peak: [outline (base left, ridge points, base right), cap polygon].
var _peaks: Array[Array] = []
var _summit: Vector2 = Vector2.ZERO
## {at, step, order}
var _glints: Array[Dictionary] = []
## {x, y, phase, speed}
var _flakes: Array[Dictionary] = []


func _init() -> void:
	# The highest peak and the star above it.
	crown_height = 162.0 + star_height + 12.0


func _build_kind(rng: RandomNumberGenerator) -> void:
	for p: Array in [[-0.5, -0.15, 0.42, 92.0], [0.48, -0.2, 0.4, 78.0], [0.0, -0.3, 0.55, 150.0]]:
		var base: Vector2 = on_top(p[0], p[1])
		var half: float = float(p[2]) * half_width
		var height: float = p[3]
		var ridge := PackedVector2Array([base + Vector2(-half, 0.0)])
		var count: int = 7
		for k: int in range(1, count):
			var t: float = float(k) / float(count)
			var up: float = (1.0 - absf(t - 0.5) * 2.0) * height
			ridge.append(base + Vector2(lerpf(-half, half, t) + rng.randf_range(-4.0, 4.0), -up + rng.randf_range(-6.0, 6.0) * (1.0 - up / height)))
		ridge.append(base + Vector2(half, 0.0))
		var peak_top: Vector2 = base + Vector2(0.0, -height)
		ridge[count / 2] = peak_top
		var cap := PackedVector2Array([peak_top, base + Vector2(half * 0.28, -height * 0.7), base + Vector2(half * 0.1, -height * 0.62),
			base + Vector2(-half * 0.08, -height * 0.68), base + Vector2(-half * 0.3, -height * 0.66)])
		_peaks.append([ridge, cap])
		_summit = peak_top
	for i: int in 10:
		_glints.append({"at": on_top(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 0.7)) + Vector2(0.0, -rng.randf_range(0.0, 40.0)),
			"step": 1 if i < 3 else 2, "order": rng.randf()})
	for i: int in flake_count:
		_flakes.append({"x": rng.randf_range(-1.0, 1.0) * half_width, "y": rng.randf(), "phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.05, 0.1)})


func _draw_kind() -> void:
	var on: float = overall()
	var caps_on: float = lit(2, 0.2)
	for peak: Array in _peaks:
		var ridge: PackedVector2Array = peak[0]
		draw_colored_polygon(ridge, shade(peak_color))
		draw_colored_polygon(peak[1], shade(snow_color).lerp(Color(ice_color, 1.0) * 0.6, caps_on * 0.5))
		draw_polyline(ridge, Color(accent, line_alpha()), 1.2, true)
	for glint: Dictionary in _glints:
		var glint_on: float = lit(glint.step, glint.order) * (0.4 + 0.6 * maxf(sin(_time * 1.5 + float(glint.order) * 20.0), 0.0))
		_draw_sparkle(glint.at, 4.0, ice_color, glint_on)
	# The marker: a star above the summit.
	var star_on: float = lit(3, 0.4)
	if star_on > 0.0:
		var star: Vector2 = _summit + Vector2(0.0, -star_height)
		var twinkle: float = 0.85 + 0.15 * sin(_time * 3.1)
		draw_circle(star, 30.0, Color(star_color, 0.05 * star_on))
		_draw_sparkle(star, 22.0 * twinkle, star_color, star_on)
		draw_glow_dot(star, 3.5, star_color, star_on)
	# Snow falling round the peaks.
	if light > 0.0:
		for flake: Dictionary in _flakes:
			var t: float = fposmod(float(flake.y) + _time * float(flake.speed), 1.0)
			var at := Vector2(float(flake.x) + sin(_time * 0.7 + float(flake.phase)) * 6.0, lerpf(-170.0, top_depth, t))
			draw_circle(at, 1.0, Color(star_color, 0.35 * on * sin(PI * t)))


## A four-pointed sparkle (long thin rays and a soft core).
func _draw_sparkle(center: Vector2, length: float, color: Color, on: float) -> void:
	if on <= 0.0:
		return
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT]:
		var side: Vector2 = direction.orthogonal() * length * 0.08
		draw_colored_polygon(PackedVector2Array([center + direction * length, center + side, center - direction * length, center - side]),
			glow(color, on, 2.0))
	draw_glow_dot(center, length * 0.08, color, on)
