class_name LandmarkAnemones
extends Landmark
## A field of sea anemones on the floor (no collision: the players swim over
## it). Each one is a short stalk with a crown of soft tentacles swaying in
## the current, in a muted violet with faintly glowing tips. When a pulse
## reaches the field they pull their tentacles in, one after the other from
## the pulse's side, and slowly open again.

@export var field_radii: Vector2 = Vector2(150.0, 80.0)
@export var anemone_count: int = 16
@export var stalk_height_min: float = 10.0
@export var stalk_height_max: float = 24.0
@export var crown_radius: float = 14.0
@export var tentacles: int = 9
@export var sway_amount: float = 3.0
@export var sway_speed: float = 0.35
## Pulled in to this share of the size, how fast (seconds), and the time to open again.
@export_range(0.0, 1.0) var shrunk_share: float = 0.35
@export var shrink_time: float = 0.15
@export var reopen_time: float = 1.8
## Extra delay per pixel from the pulse origin (the wave passing through).
@export var delay_per_pixel: float = 0.0012
@export var flesh_color: Color = Color(0.42, 0.32, 0.5)

var _spots := PackedVector2Array()
var _heights := PackedFloat32Array()
## Per anemone: the time its retraction starts (-INF = open).
var _shrink_start := PackedFloat32Array()


func _footprint_shapes() -> Array[PackedVector2Array]:
	return []


func _ready() -> void:
	super._ready()
	add_to_group("sonar_targets")


func _build_parts() -> void:
	_spots.clear()
	_heights.clear()
	# Every variant has its own field (no footprint, parts only).
	anemone_count = roundi(anemone_count * lerpf(0.7, 1.3, rand(1.0)))
	field_radii *= lerpf(0.85, 1.15, rand(2.0))
	for i: int in anemone_count:
		# Spread over the ellipse (square root: even density).
		var angle: float = TAU * rand(i * 3.17 + 0.5)
		var distance: float = sqrt(rand(i * 7.31 + 1.1))
		_spots.append(Vector2(cos(angle) * field_radii.x, sin(angle) * field_radii.y) * distance)
		_heights.append(lerpf(stalk_height_min, stalk_height_max, rand(i * 1.93)))
	_shrink_start.resize(anemone_count)
	_shrink_start.fill(-INF)
	for i: int in anemone_count:
		add_part(_spots[i], _draw_anemone.bind(i), true)
		var crown: Vector2 = _spots[i] - Vector2(0.0, _heights[i])
		add_sonar_line(Landmark.curve(crown + Vector2(-crown_radius, 0.0), crown + Vector2(0.0, -crown_radius * 1.4), crown + Vector2(crown_radius, 0.0), 4), PackedVector2Array(), _heights[i])


## Called by SonarOverlay when a pulse reaches the field.
func on_sonar_hit(origin: Vector2) -> void:
	for i: int in anemone_count:
		var delay: float = to_global(_spots[i]).distance_to(origin) * delay_per_pixel
		_shrink_start[i] = _time + delay


## 1 = open, shrunk_share = pulled in.
func get_openness(i: int) -> float:
	var since: float = _time - _shrink_start[i]
	if since < 0.0:
		return 1.0
	if since < shrink_time:
		return lerpf(1.0, shrunk_share, since / shrink_time)
	var t: float = clampf((since - shrink_time) / reopen_time, 0.0, 1.0)
	return lerpf(shrunk_share, 1.0, t * t * (3.0 - 2.0 * t))


func _tips(i: int, crown: Vector2) -> PackedVector2Array:
	var open: float = get_openness(i)
	var tips := PackedVector2Array()
	for k: int in tentacles:
		var angle: float = lerpf(-PI * 0.95, -PI * 0.05, float(k) / maxf(tentacles - 1, 1))
		var sway: float = sin(_time * TAU * sway_speed + i * 1.3 + k * 0.4) * sway_amount
		tips.append(crown + Vector2(cos(angle) * crown_radius * 1.1 + sway, sin(angle) * crown_radius * 0.9) * open)
	return tips


func _draw_anemone(part: Node2D, i: int) -> void:
	var open: float = get_openness(i)
	var h: float = _heights[i] * lerpf(0.6, 1.0, open)
	var crown := Vector2(sin(_time * TAU * sway_speed + i) * sway_amount * 0.4, -h)
	var color_value: Color = flesh_color.lerp(rock_color, 0.25)
	_batch.add_band(PackedVector2Array([Vector2.ZERO, crown]), 8.0, 6.0, color_value.darkened(0.3))
	for tip: Vector2 in _tips(i, crown):
		_batch.add_polyline(Landmark.curve(crown, crown.lerp(tip, 0.5) + Vector2(0.0, -3.0), tip, 3), color_value, 2.0)
	_batch.draw(part)


func _has_glow() -> bool:
	return true


func _draw_glow(canvas: Node2D) -> void:
	for i: int in anemone_count:
		var h: float = _heights[i] * lerpf(0.6, 1.0, get_openness(i))
		var crown: Vector2 = _spots[i] + Vector2(sin(_time * TAU * sway_speed + i) * sway_amount * 0.4, -h)
		for tip: Vector2 in _tips(i, crown):
			_batch.add_dot(tip, 1.3, glow(0.45 * get_openness(i)), 5)
	_batch.draw(canvas)
