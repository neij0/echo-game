class_name SeaPlant
extends AmbientLife
## A small tuft at the foot of a rock: kelp strands or an anemone clump,
## swaying in the current and lit only by the real lights. When a pulse
## reaches it, it shrinks quickly (kelp bends down, anemones pull their
## tentacles in) and slowly grows back. Anemone tips glow very faintly.

enum Kind { KELP, ANEMONE }

@export var kind: Kind = Kind.KELP
## Strands (kelp) or anemones (clump), their height range, spread and width.
@export var stems_min: int = 3
@export var stems_max: int = 5
@export var height_min: float = 30.0
@export var height_max: float = 70.0
@export var spread: float = 16.0
@export var stem_width: float = 5.0
@export var sway_amount: float = 7.0
## Sway cycles per second.
@export var sway_speed: float = 0.25
@export var plant_color: Color = Color(0.2, 0.32, 0.28)
## Anemones: tentacles per crown, crown size, faint tip glow.
@export var tentacles: int = 7
@export var crown_radius: float = 9.0
@export var tip_color: Color = Color(0.75, 0.6, 1.0)
@export var glow_energy: float = 1.1
@export_range(0.0, 1.0) var glow_alpha: float = 0.35
## Shrunk to this share of its size, how fast, and the time to grow back.
@export_range(0.0, 1.0) var shrunk_share: float = 0.4
@export var shrink_time: float = 0.12
@export var regrow_time: float = 1.6

var _stems := PackedVector2Array()
var _heights := PackedFloat32Array()
var _shrink_start: float = -INF


func _ready() -> void:
	super._ready()
	add_to_group("sonar_targets")
	for i: int in randi_range(stems_min, stems_max):
		_stems.append(Vector2(randf_range(-spread, spread), randf_range(-spread * 0.4, spread * 0.4)))
		_heights.append(randf_range(height_min, height_max))


## Called by SonarOverlay when a pulse reaches it.
func on_sonar_hit(_origin: Vector2) -> void:
	_shrink_start = _time


## 1 = full size, shrunk_share = pulled in.
func get_size_share() -> float:
	var since: float = _time - _shrink_start
	if since < shrink_time:
		return lerpf(1.0, shrunk_share, since / shrink_time)
	var t: float = clampf((since - shrink_time) / regrow_time, 0.0, 1.0)
	return lerpf(shrunk_share, 1.0, t * t * (3.0 - 2.0 * t))


func _stem_line(i: int) -> PackedVector2Array:
	var size: float = get_size_share()
	var line := PackedVector2Array()
	var steps: int = 6
	for k: int in steps + 1:
		var t: float = float(k) / steps
		var sway: float = sin(_time * TAU * sway_speed + i * 1.7 + t * 2.0) * sway_amount * t * t
		# Shrinking kelp bends over; anemone stalks just get shorter.
		var bend: float = (1.0 - size) * 18.0 * t * t * (1.0 if i % 2 == 0 else -1.0) if kind == Kind.KELP else 0.0
		line.append(_stems[i] + Vector2(sway + bend, -_heights[i] * size * t))
	return line


func _draw() -> void:
	for i: int in _stems.size():
		var line: PackedVector2Array = _stem_line(i)
		if kind == Kind.KELP:
			_batch.add_band(line, stem_width, 1.0, plant_color.darkened(0.1 * (i % 3)))
		else:
			_batch.add_band(line, stem_width, stem_width * 0.8, plant_color)
			var crown: Vector2 = line[line.size() - 1]
			for tip: Vector2 in _tips(crown, i):
				_batch.add_line(crown, tip, plant_color.lightened(0.15), 1.5)
	_batch.draw(self)


func _tips(crown: Vector2, i: int) -> PackedVector2Array:
	var size: float = get_size_share()
	var tips := PackedVector2Array()
	for k: int in tentacles:
		var angle: float = lerpf(-PI * 0.95, -PI * 0.05, float(k) / maxf(tentacles - 1, 1))
		var sway: float = sin(_time * TAU * sway_speed + i + k * 0.5) * 2.0
		tips.append(crown + Vector2(cos(angle) * crown_radius + sway, sin(angle) * crown_radius * 0.8) * size)
	return tips


func _has_glow() -> bool:
	return kind == Kind.ANEMONE


func _draw_glow(canvas: Node2D) -> void:
	for i: int in _stems.size():
		var line: PackedVector2Array = _stem_line(i)
		for tip: Vector2 in _tips(line[line.size() - 1], i):
			_batch.add_dot(tip, 1.1, AmbientLife.hdr(tip_color, glow_energy, glow_alpha * get_size_share()), 5)
	_batch.draw(canvas)
