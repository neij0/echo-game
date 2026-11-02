class_name NightSky
extends Control
## The dark backdrop of the menus (title, main menu, Journey): a deep navy
## gradient, faint twinkling stars, slow drifting motes (like marine snow) and
## a soft vignette. scroll moves the stars a little (parallax with a camera).
## Fills its parent; draws behind everything else of the screen.

@export var top_color: Color = Color(0.012, 0.022, 0.05)
@export var bottom_color: Color = Color(0.03, 0.055, 0.095)
@export var star_color: Color = Color(0.75, 0.85, 1.0)
@export var star_count: int = 110
@export var mote_count: int = 45
@export var mote_color: Color = Color(0.55, 0.8, 1.0)
## How far the stars move with scroll (share).
@export var parallax: float = 0.08
@export var vignette_strength: float = 0.75
@export var seed_value: int = 3

## Camera offset (pixels): the stars follow it a little.
var scroll: Vector2 = Vector2.ZERO
## {at (0-1), size, phase, alpha}
var _stars: Array[Dictionary] = []
## {at (0-1), phase, speed, size}
var _motes: Array[Dictionary] = []
var _time: float = 0.0
var _vignette: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	# Fill the parent (in _ready the plain preset would keep the current size).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in star_count:
		_stars.append({"at": Vector2(rng.randf(), rng.randf()), "size": rng.randf_range(0.6, 1.6), "phase": rng.randf() * TAU,
			"alpha": rng.randf_range(0.15, 0.7)})
	for i: int in mote_count:
		_motes.append({"at": Vector2(rng.randf(), rng.randf()), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.004, 0.012),
			"size": rng.randf_range(0.8, 1.8)})
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, vignette_strength))
	gradient.add_point(0.55, Color(0, 0, 0, 0))
	_vignette = GradientTexture2D.new()
	_vignette.gradient = gradient
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.05, 0.5)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]),
		PackedColorArray([top_color, top_color, bottom_color, bottom_color]))
	var shift: Vector2 = -scroll * parallax
	for star: Dictionary in _stars:
		var at: Vector2 = Vector2(fposmod((star.at as Vector2).x * size.x + shift.x, size.x), fposmod((star.at as Vector2).y * size.y + shift.y, size.y))
		var twinkle: float = 0.6 + 0.4 * sin(_time * 0.9 + float(star.phase))
		draw_circle(at, star.size, Color(star_color, float(star.alpha) * twinkle))
	for mote: Dictionary in _motes:
		var y: float = fposmod((mote.at as Vector2).y - _time * float(mote.speed), 1.0)
		var x: float = (mote.at as Vector2).x + sin(_time * 0.2 + float(mote.phase)) * 0.01
		draw_circle(Vector2(x * size.x, y * size.y) + shift * 2.0, mote.size, Color(mote_color, 0.12 + 0.08 * sin(_time + float(mote.phase))))
	draw_texture_rect(_vignette, area, false)
