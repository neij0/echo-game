class_name SurfaceTextures
## Procedural, seamless greyscale textures (no art) that are multiplied over a
## surface's colour: rock grain for the rock tops and faces, sand ripples and
## pebbles for the floor. Built once per set of values and shared.

static var _cache: Dictionary = {}


## Fine grain with faint horizontal streaks (strata). Values from
## 1 - strength (darkest) to 1, so the surface colour is the brightest it gets.
static func rock_grain(size: int, strength: float, grain_frequency: float, streak_share: float, seed_value: int) -> Texture2D:
	var key: String = "rock %d %.3f %.3f %.3f %d" % [size, strength, grain_frequency, streak_share, seed_value]
	if _cache.has(key):
		return _cache[key]
	var grain := FastNoiseLite.new()
	grain.seed = seed_value
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = grain_frequency
	grain.fractal_octaves = 3
	var streaks := FastNoiseLite.new()
	streaks.seed = seed_value + 1
	streaks.noise_type = FastNoiseLite.TYPE_SIMPLEX
	streaks.frequency = grain_frequency * 0.35
	# The seamless images wrap, so the texture repeats without a seam.
	var grain_image: Image = grain.get_seamless_image(size, size)
	var streak_image: Image = streaks.get_seamless_image(size, size / 8)
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y: int in size:
		for x: int in size:
			var g: float = grain_image.get_pixel(x, y).r
			# Streaks: the noise stretched 8x along x, so it runs in bands.
			var s: float = streak_image.get_pixel(x, int(y / 8.0) % streak_image.get_height()).r
			var dark: float = clampf(lerpf(g, s, streak_share), 0.0, 1.0)
			var v: float = 1.0 - strength * dark
			image.set_pixel(x, y, Color(v, v, v))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Sand ripples (wavy bands) and a few pebbles, low contrast. Values from
## 1 - ripple_strength - pebble_strength to 1.
static func floor_detail(size: int, ripple_strength: float, ripple_period: float, pebble_strength: float, pebble_count: int, seed_value: int) -> Texture2D:
	var key: String = "floor %d %.3f %.1f %.3f %d %d" % [size, ripple_strength, ripple_period, pebble_strength, pebble_count, seed_value]
	if _cache.has(key):
		return _cache[key]
	var warp := FastNoiseLite.new()
	warp.seed = seed_value
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp.frequency = 4.0 / size
	var warp_image: Image = warp.get_seamless_image(size, size)
	# A whole number of ripples across the texture, so it tiles.
	var periods: float = maxf(1.0, roundf(size / ripple_period))
	var values := PackedFloat32Array()
	values.resize(size * size)
	for y: int in size:
		for x: int in size:
			var bend: float = (warp_image.get_pixel(x, y).r - 0.5) * 2.0
			var phase: float = TAU * periods * (float(y) / size) + bend * 2.2
			values[y * size + x] = 1.0 - ripple_strength * (0.5 + 0.5 * sin(phase))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in pebble_count:
		var center := Vector2(rng.randf() * size, rng.randf() * size)
		var radius: float = rng.randf_range(1.2, 3.2)
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				var d: float = Vector2(dx, dy).length() / radius
				if d > 1.0:
					continue
				var px: int = posmod(int(center.x) + dx, size)
				var py: int = posmod(int(center.y) + dy, size)
				values[py * size + px] -= pebble_strength * (1.0 - d * d)
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y: int in size:
		for x: int in size:
			var v: float = clampf(values[y * size + x], 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
