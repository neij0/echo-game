class_name AnglerGlow
extends Node2D
## Everything glowing on the Angler, drawn unlit on its own CanvasLayer
## (follow_viewport_enabled, world coordinates; HDR colours bloom):
## - the lure orb (core + soft halos) in the state's colour;
## - two small cold eyes;
## - Exposed: a sonar outline on its armour plates and pulsing weak spots;
## - hit: a brief rim flash round the body; bite: the teeth flash;
## - charge: fading afterimage outlines behind it;
## - stunned: glints of sediment circling above its head;
## - phase change / reveal: a light ring growing out of the lure;
## - death: bubbles rising off the body.
## Values are set by AnglerVisual each frame; this only draws.

@export_group("Orb")
@export var orb_radius: float = 7.0
@export var halo_radius: float = 22.0
@export_range(0.0, 1.0) var halo_alpha: float = 0.22
@export var outer_halo_radius: float = 46.0
@export_range(0.0, 1.0) var outer_halo_alpha: float = 0.07

@export_group("Eyes")
@export var eye_color: Color = Color(0.75, 0.9, 1.0)
@export var eye_energy: float = 1.8
@export var eye_radius: float = 2.6

@export_group("Exposed")
@export var plate_outline_color: Color = Color(0.45, 0.95, 1.0)
@export var plate_outline_energy: float = 1.6
@export_range(0.0, 1.0) var plate_outline_alpha: float = 0.7
@export var plate_outline_width: float = 1.6
## Opacity of the plates' front edges compared to the silhouette outline.
@export_range(0.0, 1.0) var plate_edge_share: float = 0.45
@export var weak_spot_color: Color = Color(1.0, 0.78, 0.25)
@export var weak_spot_energy: float = 3.0
@export var weak_spot_radius: float = 7.0
@export var weak_spot_pulse_speed: float = 2.2

@export_group("Flashes")
@export var rim_flash_color: Color = Color(1.0, 0.95, 0.9)
@export var rim_flash_energy: float = 2.5
@export var teeth_flash_color: Color = Color(1.0, 1.0, 0.95)
@export var teeth_flash_energy: float = 4.0

@export_group("Charge Trail")
@export var trail_color: Color = Color(0.75, 0.95, 1.0)
@export var trail_energy: float = 1.1
@export_range(0.0, 1.0) var trail_alpha: float = 0.22
## The newest afterimages are skipped (they sit on the body itself).
@export var trail_min_age: float = 0.07
@export var trail_life: float = 0.35

@export_group("Stunned")
@export var star_color: Color = Color(0.85, 0.78, 0.55)
@export var star_energy: float = 2.0
@export var star_count: int = 6
@export var star_orbit: Vector2 = Vector2(40.0, 14.0)
@export var star_speed: float = 0.6
@export var star_size: float = 3.2

@export_group("Light Ring")
## A brief reveal wave: it grows and is gone quickly (never a lasting circle).
@export var ring_max_radius: float = 460.0
@export var ring_time: float = 0.5
@export var ring_width: float = 9.0
## The band: arcs stacked inwards over ring_band_width, fading.
@export var ring_bands: int = 12
@export var ring_band_width: float = 70.0
@export_range(0.0, 1.0) var ring_alpha: float = 0.07

@export_group("Bubbles")
@export var bubble_color: Color = Color(0.6, 0.8, 0.95)
@export var bubble_energy: float = 1.2
@export var bubble_rise_speed: float = 55.0
@export var bubble_life: float = 1.8

var body: AnglerBody
var lure: AnglerLure
## Set by AnglerVisual each frame.
var orb_color: Color = Color.WHITE
var orb_energy: float = 0.0
var eye_level: float = 1.0
var exposed: float = 0.0
var rim_flash: float = 0.0
var teeth_flash: float = 0.0
var stun: float = 0.0
## Share of the whole glow kept (death, intro).
var body_glow: float = 1.0
var _time: float = 0.0
var _trail: Array[PackedVector2Array] = []
var _trail_ages: PackedFloat32Array = PackedFloat32Array()
var _ring_ages: PackedFloat32Array = PackedFloat32Array()
var _ring_centers: PackedVector2Array = PackedVector2Array()
var _bubbles: PackedVector3Array = PackedVector3Array()
var _bubble_ages: PackedFloat32Array = PackedFloat32Array()


func step(delta: float) -> void:
	_time += delta
	for i: int in range(_trail_ages.size() - 1, -1, -1):
		_trail_ages[i] += delta
		if _trail_ages[i] >= trail_life:
			_trail_ages.remove_at(i)
			_trail.remove_at(i)
	for i: int in range(_ring_ages.size() - 1, -1, -1):
		_ring_ages[i] += delta
		if _ring_ages[i] >= ring_time:
			_ring_ages.remove_at(i)
			_ring_centers.remove_at(i)
	for i: int in range(_bubble_ages.size() - 1, -1, -1):
		_bubble_ages[i] += delta
		var bubble: Vector3 = _bubbles[i]
		bubble.y -= bubble_rise_speed * delta
		bubble.x += sin(_bubble_ages[i] * 5.0 + float(i)) * 12.0 * delta
		_bubbles[i] = bubble
		if _bubble_ages[i] >= bubble_life:
			_bubble_ages.remove_at(i)
			_bubbles.remove_at(i)
	queue_redraw()


func add_trail_snapshot(outline: PackedVector2Array) -> void:
	_trail.append(outline)
	_trail_ages.append(0.0)


func add_ring(center: Vector2) -> void:
	_ring_centers.append(center)
	_ring_ages.append(0.0)


func add_bubble(at: Vector2, radius: float) -> void:
	_bubbles.append(Vector3(at.x, at.y, radius))
	_bubble_ages.append(0.0)


func is_ring_active() -> bool:
	return not _ring_ages.is_empty()


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw() -> void:
	if body == null or lure == null:
		return
	_draw_trail()
	if body_glow > 0.0:
		_draw_eyes()
		_draw_exposed()
		_draw_flashes()
		_draw_stars()
	_draw_bubbles()
	_draw_rings()
	_draw_orb()


func _draw_orb() -> void:
	if orb_energy <= 0.001:
		return
	var center: Vector2 = lure.get_orb_position()
	var strength: float = clampf(orb_energy, 0.0, 6.0)
	_soft_disc(center, outer_halo_radius, _hdr(orb_color, 1.0, 1.0), outer_halo_alpha * minf(strength, 1.5))
	_soft_disc(center, halo_radius, _hdr(orb_color, 1.2, 1.0), halo_alpha * minf(strength, 1.5))
	draw_circle(center, orb_radius, _hdr(orb_color, 1.5 + strength * 1.2, 1.0))
	draw_circle(center, orb_radius * 0.45, _hdr(Color.WHITE, 1.0 + strength, 1.0))


## A soft round glow: stacked discs, so the alpha falls off towards the edge.
func _soft_disc(center: Vector2, radius: float, color: Color, alpha: float, rings: int = 10) -> void:
	for k: int in rings:
		var r: float = radius * (1.0 - float(k) / float(rings))
		draw_circle(center, r, Color(color, alpha * 2.0 / float(rings)))


func _draw_eyes() -> void:
	if eye_level <= 0.01:
		return
	for side: float in [-1.0, 1.0]:
		var at: Vector2 = body.get_eye(side)
		draw_circle(at, eye_radius * 2.2, _hdr(eye_color, 1.0, 0.12 * eye_level * body_glow))
		draw_circle(at, eye_radius, _hdr(eye_color, eye_energy * eye_level, body_glow))


func _draw_exposed() -> void:
	if exposed <= 0.01:
		return
	# The armoured silhouette in sonar colour, and faint front edges of the plates.
	var outline_color: Color = _hdr(plate_outline_color, plate_outline_energy, plate_outline_alpha * exposed * body_glow)
	var outline: PackedVector2Array = body.get_outline()
	if outline.size() > 2:
		var closed: PackedVector2Array = outline.duplicate()
		closed.append(outline[0])
		draw_polyline(closed, outline_color, plate_outline_width, true)
	var edge_color: Color = Color(outline_color, outline_color.a * plate_edge_share)
	for plate: PackedVector2Array in body.get_plates():
		draw_polyline(plate.slice(0, plate.size() / 2), edge_color, plate_outline_width * 0.8, true)
	var pulse: float = 0.6 + 0.4 * sin(_time * TAU * weak_spot_pulse_speed)
	for spot: Vector2 in body.get_weak_spots():
		draw_circle(spot, weak_spot_radius * 1.9, _hdr(weak_spot_color, 1.0, 0.18 * exposed * pulse))
		draw_circle(spot, weak_spot_radius * (0.7 + 0.3 * pulse), _hdr(weak_spot_color, weak_spot_energy, exposed))


func _draw_flashes() -> void:
	if rim_flash > 0.01:
		var outline: PackedVector2Array = body.get_silhouette()
		outline.append(outline[0])
		draw_polyline(outline, _hdr(rim_flash_color, rim_flash_energy, rim_flash), 2.5, true)
	if teeth_flash > 0.01:
		for tooth: PackedVector2Array in body.get_teeth():
			draw_colored_polygon(tooth, _hdr(teeth_flash_color, teeth_flash_energy, teeth_flash))


func _draw_trail() -> void:
	for i: int in _trail.size():
		if _trail_ages[i] < trail_min_age:
			continue
		var t: float = _trail_ages[i] / trail_life
		var outline: PackedVector2Array = _trail[i].duplicate()
		outline.append(outline[0])
		draw_polyline(outline, _hdr(trail_color, trail_energy, trail_alpha * (1.0 - t)), 2.0 * (1.0 - t) + 0.5, false)


func _draw_stars() -> void:
	if stun <= 0.01:
		return
	var center: Vector2 = body.get_head_center() + Vector2(0.0, -34.0)
	for i: int in star_count:
		var angle: float = _time * TAU * star_speed + TAU * float(i) / float(star_count)
		var at: Vector2 = center + Vector2(cos(angle) * star_orbit.x, sin(angle) * star_orbit.y)
		# Glints in front of the head are brighter (the orbit is seen at an angle).
		var front: float = 0.55 + 0.45 * sin(angle)
		var twinkle: float = 0.6 + 0.4 * sin(_time * 9.0 + float(i) * 2.1)
		draw_circle(at, star_size, _hdr(star_color, star_energy * twinkle, stun * front))
		draw_line(at - Vector2(star_size * 2.5, 0.0), at + Vector2(star_size * 2.5, 0.0), _hdr(star_color, star_energy, stun * front * 0.5), 1.2, false)
		draw_line(at - Vector2(0.0, star_size * 1.6), at + Vector2(0.0, star_size * 1.6), _hdr(star_color, star_energy, stun * front * 0.4), 1.0, false)


func _draw_rings() -> void:
	for i: int in _ring_ages.size():
		var t: float = _ring_ages[i] / ring_time
		var radius: float = ring_max_radius * (1.0 - (1.0 - t) * (1.0 - t))
		# A soft wide band (not a crisp line: that is the Echo's sonar front).
		var fade: float = pow(1.0 - t, 3.0)
		for k: int in ring_bands:
			var band: float = float(k) / float(maxi(ring_bands - 1, 1))
			draw_arc(_ring_centers[i], maxf(radius - band * ring_band_width, 1.0), 0.0, TAU, 64,
				_hdr(orb_color, 1.4, ring_alpha * fade * (1.0 - band)), ring_width, false)


func _draw_bubbles() -> void:
	for i: int in _bubbles.size():
		var t: float = _bubble_ages[i] / bubble_life
		var bubble: Vector3 = _bubbles[i]
		draw_arc(Vector2(bubble.x, bubble.y), bubble.z * (1.0 + 0.4 * t), 0.0, TAU, 12, _hdr(bubble_color, bubble_energy, 0.6 * (1.0 - t)), 1.2, false)
