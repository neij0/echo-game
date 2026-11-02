extends JourneyIsland
## Ocean island, style A "Reef Dome" (a proposal: tools/island_style_preview):
## a solid dark reef dome of rounded coral heads, tube sponges, a branching
## coral, tall kelp blades and two sea fans, rim-lit from the upper left in
## front of a soft glow. No outlines. Polyps, sponge mouths, kelp floats and
## the fans light up step by step; stage 3
## (the world's marker): the clam on the crown opens on a glowing pearl with a
## soft beam of light. Under it the layered jagged rock fades into the dark.

## Points along the dome's skyline every DOME_STEP px; kelp centre lines.
const DOME_STEP: float = 3.0
const KELP_SEGMENTS: int = 18

@export_group("Shape")
@export var dome_height: float = 86.0
## Coral heads on the dome: (x share of the half width, radius share).
@export var heads: PackedVector2Array = PackedVector2Array([Vector2(-0.74, 0.19), Vector2(-0.42, 0.26),
	Vector2(-0.04, 0.3), Vector2(0.34, 0.25), Vector2(0.69, 0.19)])
## How far the coral heads rise out of the dome (share of their radius).
@export var head_rise: float = 0.5
@export var underside_depth: float = 240.0
@export var kelp_sway: float = 10.0
@export var kelp_sway_speed: float = 0.7
@export var clam_size: Vector2 = Vector2(16.0, 6.5)
@export var clam_open_degrees: float = 38.0

@export_group("Light")
## The direction the rim light shines (from the upper left).
@export var light_dir: Vector2 = Vector2(0.5, 1.0)
@export var reef_top_color: Color = Color(0.04, 0.09, 0.11)
@export var reef_base_color: Color = Color(0.008, 0.014, 0.024)
@export var mid_rock_color: Color = Color(0.016, 0.034, 0.048)
@export var far_rock_color: Color = Color(0.03, 0.068, 0.09)
@export var locked_color: Color = Color(0.006, 0.009, 0.015)
@export var rim_color: Color = Color(0.55, 0.95, 1.0)
@export var polyp_color: Color = Color(0.35, 1.0, 0.85)
@export var polyp_alt_color: Color = Color(0.8, 0.55, 1.0)
@export var pearl_color: Color = Color(0.85, 1.0, 1.0)
@export var bubble_count: int = 22
@export var beam_height: float = 230.0

var _skyline := PackedVector2Array()
var _skyline_facing := PackedFloat32Array()
var _crown: Vector2 = Vector2.ZERO
## The dome and the rock under it (IslandArt.build_island_rock).
var _rock: Dictionary = {}
## {root, height, width, phase, back, step, order}
var _kelp: Array[Dictionary] = []
## {base, center, radius, from, to, color, phase, step, order}
var _fans: Array[Dictionary] = []
## {at, size, color, phase, step, order}
var _polyps: Array[Dictionary] = []
## Tube sponges: {base, height, width, lean, step, order}
var _tubes: Array[Dictionary] = []
## A branching coral's trunk and arms: {line, width, tip (glows), step, order}
var _branches: Array[Dictionary] = []
## {x, y, rise, speed, phase, size}
var _bubbles: Array[Dictionary] = []


func _build_shape(rng: RandomNumberGenerator) -> void:
	var count: int = int(half_width * 2.0 / DOME_STEP)
	for i: int in count + 1:
		var x: float = lerpf(-half_width, half_width, float(i) / float(count))
		var point := Vector2(x, _dome_y(x))
		_skyline.append(point)
		if point.y < _crown.y:
			_crown = point
	_skyline_facing = IslandArt.facing(_skyline, light_dir, 0.0)
	for i: int in _skyline_facing.size():
		_skyline_facing[i] = pow(_skyline_facing[i], 2.0)
	_rock = IslandArt.build_island_rock(rng, _skyline, half_width, 0.0, _crown.y, underside_depth, -0.03)


func _build_kind(rng: RandomNumberGenerator) -> void:
	# x share, height, width, behind the dome, step, order
	for spec: Array in [[-0.52, 150.0, 15.0, true, 1, 0.2], [0.44, 128.0, 14.0, true, 2, 0.5], [-0.8, 92.0, 11.0, false, 2, 0.1],
			[0.63, 104.0, 12.0, false, 1, 0.7]]:
		var x: float = float(spec[0]) * half_width
		var back: bool = spec[3]
		var surface: float = _dome_y(x)
		_kelp.append({"root": Vector2(x, surface + (14.0 if back else -surface * 0.3)), "height": float(spec[1]),
			"width": float(spec[2]), "phase": rng.randf() * TAU, "back": back, "step": spec[4], "order": spec[5]})
	# base x share, fan offset, radius, from / to (degrees), violet, step, order
	for spec: Array in [[-0.9, Vector2(-8.0, -30.0), 38.0, -170.0, -40.0, true, 2, 0.3],
			[0.9, Vector2(8.0, -24.0), 30.0, -142.0, -12.0, false, 1, 0.4]]:
		var base := Vector2(float(spec[0]) * half_width, _dome_y(float(spec[0]) * half_width) + 4.0)
		_fans.append({"base": base, "center": base + (spec[1] as Vector2), "radius": spec[2], "from": deg_to_rad(spec[3]),
			"to": deg_to_rad(spec[4]), "color": polyp_alt_color if spec[5] else polyp_color, "phase": rng.randf() * TAU,
			"step": spec[6], "order": spec[7]})
	# Tube sponges: x share, height, width, lean (degrees), step, order
	for spec: Array in [[-0.36, 44.0, 11.0, -12.0, 1, 0.3], [-0.28, 62.0, 13.0, 2.0, 2, 0.3], [-0.19, 34.0, 10.0, 14.0, 3, 0.1]]:
		var x: float = float(spec[0]) * half_width
		_tubes.append({"base": Vector2(x, _dome_y(x) + 10.0), "height": float(spec[1]), "width": float(spec[2]),
			"lean": deg_to_rad(spec[3]), "step": spec[4], "order": spec[5]})
	# A branching coral: a trunk splitting into three arms (angle from straight
	# up in degrees, length, step, order).
	var root := Vector2(0.27 * half_width, _dome_y(0.27 * half_width) + 8.0)
	var fork: Vector2 = root + Vector2(2.0, -26.0)
	_branches.append({"line": PackedVector2Array([root, root.lerp(fork, 0.5), fork]), "width": 10.0, "tip": false, "step": 1, "order": 0.0})
	for arm: Array in [[-34.0, 32.0, 1, 0.6], [4.0, 40.0, 2, 0.7], [38.0, 28.0, 2, 0.9]]:
		var direction: Vector2 = Vector2.UP.rotated(deg_to_rad(arm[0]))
		var middle: Vector2 = fork + direction * float(arm[1]) * 0.55
		var tip: Vector2 = middle + direction.rotated(deg_to_rad(float(arm[0]) * 0.4)) * float(arm[1]) * 0.45
		_branches.append({"line": PackedVector2Array([fork, middle, tip]), "width": 7.0, "tip": true, "step": arm[2], "order": arm[3]})
	# Polyp clusters: x share, px under the skyline, step, order
	for spec: Array in [[-0.58, 16.0, 1, 0.0], [0.42, 22.0, 1, 0.5], [-0.24, 40.0, 2, 0.1], [0.6, 14.0, 2, 0.4],
			[0.08, 28.0, 2, 0.8], [-0.78, 10.0, 3, 0.2], [0.2, 46.0, 3, 0.6], [-0.44, 56.0, 3, 0.9]]:
		var color: Color = polyp_alt_color if rng.randf() < 0.3 else polyp_color
		for k: int in rng.randi_range(3, 5):
			var x: float = float(spec[0]) * half_width + rng.randf_range(-11.0, 11.0)
			_polyps.append({"at": Vector2(x, _dome_y(x) + float(spec[1]) + rng.randf_range(-5.0, 5.0)), "size": rng.randf_range(0.7, 1.25),
				"color": color, "phase": rng.randf() * TAU, "step": spec[2], "order": float(spec[3]) + rng.randf() * 0.2})
	for i: int in bubble_count:
		var x: float = rng.randf_range(-0.7, 0.7) * half_width
		_bubbles.append({"x": x, "y": _dome_y(x) - 2.0, "rise": rng.randf_range(130.0, 220.0), "speed": rng.randf_range(0.1, 0.2),
			"phase": rng.randf(), "size": rng.randf_range(1.3, 2.5)})


## The dome's skyline at x: a mound with big rounded coral heads on it.
func _dome_y(x: float) -> float:
	var y: float = _mound_y(x)
	for head: Vector2 in heads:
		var center_x: float = head.x * half_width
		var radius: float = head.y * half_width
		var dx: float = x - center_x
		if absf(dx) < radius:
			var center_y: float = _mound_y(center_x) + radius * (1.0 - head_rise)
			y = minf(y, center_y - sqrt(radius * radius - dx * dx))
	return y


func _mound_y(x: float) -> float:
	var share: float = clampf(x / half_width, -1.0, 1.0)
	return -dome_height * pow(maxf(1.0 - share * share, 0.0), 0.6)


func get_visual_rect() -> Rect2:
	var top: float = 0.0
	for kelp: Dictionary in _kelp:
		top = minf(top, (kelp.root as Vector2).y - float(kelp.height))
	top -= frame_margin
	return Rect2(-half_width - frame_margin * 2.0, top, (half_width + frame_margin * 2.0) * 2.0, underside_depth * 0.8 - top)


func _draw() -> void:
	var unlock: float = clampf(light, 0.0, 1.0)
	var on: float = overall()
	var rim_k: float = lerpf(locked_rim, 1.0, unlock * 0.45 + on * 0.55)
	var dark: Color = locked_color.lerp(reef_base_color, unlock)
	# Backlight: a soft glow behind the island, a fainter one behind its rock.
	IslandArt.soft_glow(self, Vector2(0.0, -70.0), Vector2(half_width * 1.9, half_width * 1.7), Color(accent, 0.16 * on))
	IslandArt.soft_glow(self, Vector2(0.0, 70.0), Vector2(half_width * 1.5, half_width * 1.1), Color(accent, 0.07 * on))
	var layer_on: float = unlock * (0.6 + 0.4 * on)
	IslandArt.draw_rock_layers(self, _rock, locked_color.lerp(far_rock_color, layer_on), locked_color.lerp(mid_rock_color, layer_on))
	for kelp: Dictionary in _kelp:
		if kelp.back:
			_draw_kelp(kelp, dark.lerp(reef_top_color, 0.35 * unlock), unlock, rim_k)
	var top: Color = locked_color.lerp(reef_top_color, unlock * (0.55 + 0.45 * on))
	IslandArt.draw_rock_body(self, _rock, top, dark)
	IslandArt.rim(self, _skyline, 11.0, Color(rim_color, 0.26 * rim_k), _skyline_facing)
	IslandArt.haze(self, _skyline, 16.0, Color(rim_color, 0.05 * rim_k), _skyline_facing)
	for polyp: Dictionary in _polyps:
		var polyp_on: float = lit(polyp.step, polyp.order) * (0.75 + 0.25 * sin(_time * 1.6 + float(polyp.phase)))
		if polyp_on > 0.0:
			IslandArt.soft_glow(self, polyp.at, Vector2(10.0, 10.0) * float(polyp.size), Color(polyp.color, 0.45 * polyp_on))
			draw_circle(polyp.at, 1.6 * float(polyp.size), IslandArt.hdr(polyp.color, 2.4, polyp_on))
	for fan: Dictionary in _fans:
		_draw_fan(fan, dark, rim_k)
	for tube: Dictionary in _tubes:
		_draw_tube(tube, dark, unlock, rim_k)
	for branch: Dictionary in _branches:
		_draw_branch(branch, dark, unlock, rim_k)
	_draw_clam(dark, unlock, rim_k)
	for kelp: Dictionary in _kelp:
		if not kelp.back:
			_draw_kelp(kelp, dark, unlock, rim_k)
	_draw_bubbles(on)


func _draw_kelp(kelp: Dictionary, color: Color, unlock: float, rim_k: float) -> void:
	var line: PackedVector2Array = IslandArt.sway_line(kelp.root, kelp.height, KELP_SEGMENTS, kelp_sway, _time * kelp_sway_speed,
		kelp.phase, 1.1, 5.0)
	var outline: PackedVector2Array = IslandArt.shaped_ribbon(line, IslandArt.kelp_widths(line.size(), kelp.width, kelp.phase))
	IslandArt.mass(self, outline, line[line.size() - 1].y, line[0].y, color.lerp(reef_top_color, 0.3 * unlock), color)
	var left: PackedVector2Array = outline.slice(0, line.size())
	IslandArt.rim(self, left, 4.0, Color(rim_color, 0.32 * rim_k), IslandArt.facing(left, light_dir, 0.1))
	# The floats: dark, glowing once lit.
	var float_on: float = lit(kelp.step, kelp.order) * (0.8 + 0.2 * sin(_time * 2.0 + float(kelp.phase)))
	for share: float in [0.5, 0.94]:
		var at: Vector2 = line[int(round(share * float(KELP_SEGMENTS)))]
		if float_on > 0.0:
			IslandArt.soft_glow(self, at, Vector2(14.0, 14.0), Color(polyp_color, 0.5 * float_on))
		draw_circle(at, 3.2, color.lerp(IslandArt.hdr(polyp_color, 2.2), float_on))


func _draw_fan(fan: Dictionary, dark: Color, rim_k: float) -> void:
	var fan_on: float = lit(fan.step, fan.order)
	var center: Vector2 = fan.center + Vector2(sin(_time * 0.5 + float(fan.phase)) * 1.5, 0.0)
	var base: Vector2 = fan.base
	var stalk: PackedVector2Array = IslandArt.ribbon(PackedVector2Array([base, base.lerp(center, 0.5), center]), 7.0, 4.0)
	IslandArt.mass(self, stalk, center.y, base.y, dark, dark)
	var color: Color = fan.color
	var radius: float = fan.radius
	var ring := PackedVector2Array()
	var colors := PackedColorArray()
	var edge: Color = dark.lerp(rim_color, 0.14 * rim_k)
	for k: int in 29:
		var t: float = float(k) / 28.0
		var angle: float = lerpf(fan.from, fan.to, t)
		ring.append(center + Vector2.from_angle(angle) * radius * (1.0 + 0.06 * sin(t * 30.0 + float(fan.phase))))
		colors.append(edge.lerp(IslandArt.hdr(color, 1.7), 0.85 * fan_on))
	IslandArt.fan(self, center, dark, ring, colors, false, 4.0)
	if fan_on > 0.0:
		var middle: float = (float(fan.from) + float(fan.to)) * 0.5
		IslandArt.soft_glow(self, center + Vector2.from_angle(middle) * radius * 0.6, Vector2(radius, radius) * 1.4,
			Color(color, 0.22 * fan_on))


## A tube sponge: a slightly flared dark tube whose mouth glows once lit.
func _draw_tube(tube: Dictionary, dark: Color, unlock: float, rim_k: float) -> void:
	var up: Vector2 = Vector2.UP.rotated(float(tube.lean))
	var side: Vector2 = up.orthogonal()
	var base: Vector2 = tube.base
	var width: float = tube.width
	var top: Vector2 = base + up * float(tube.height)
	var shape := PackedVector2Array([base + side * width * 0.5, base - side * width * 0.5, top - side * width * 0.58,
		top + side * width * 0.58])
	IslandArt.mass(self, shape, top.y, base.y, dark.lerp(reef_top_color, 0.55 * unlock), dark)
	var left := PackedVector2Array([base + side * width * 0.5, top + side * width * 0.58])
	if side.x > 0.0:
		left = PackedVector2Array([base - side * width * 0.5, top - side * width * 0.58])
	IslandArt.rim(self, left, 3.5, Color(rim_color, 0.3 * rim_k), IslandArt.facing(left, light_dir, 0.1))
	var mouth_on: float = lit(tube.step, tube.order) * (0.8 + 0.2 * sin(_time * 1.8 + float(tube.order) * 7.0))
	if mouth_on > 0.0:
		IslandArt.soft_glow(self, top, Vector2(width, width) * 1.5, Color(polyp_color, 0.5 * mouth_on))
	var mouth := PackedVector2Array()
	for k: int in 12:
		var angle: float = TAU * float(k) / 12.0
		mouth.append(top + side * cos(angle) * width * 0.42 + up * sin(angle) * width * 0.16)
	draw_colored_polygon(mouth, dark.lerp(IslandArt.hdr(polyp_color, 2.0), mouth_on))


## One part of the branching coral (the trunk or an arm, its tip glowing).
func _draw_branch(branch: Dictionary, dark: Color, unlock: float, rim_k: float) -> void:
	var line: PackedVector2Array = branch.line
	var width: float = branch.width
	var outline: PackedVector2Array = IslandArt.ribbon(line, width, width * 0.75)
	IslandArt.mass(self, outline, line[line.size() - 1].y, line[0].y, dark.lerp(reef_top_color, 0.5 * unlock), dark)
	var left: PackedVector2Array = outline.slice(0, line.size())
	IslandArt.rim(self, left, 3.0, Color(rim_color, 0.28 * rim_k), IslandArt.facing(left, light_dir, 0.1))
	if branch.tip:
		var tip_on: float = lit(branch.step, branch.order)
		var tip: Vector2 = line[line.size() - 1]
		if tip_on > 0.0:
			IslandArt.soft_glow(self, tip, Vector2(13.0, 13.0), Color(polyp_alt_color, 0.5 * tip_on))
		draw_circle(tip, width * 0.45, dark.lerp(IslandArt.hdr(polyp_alt_color, 2.0), tip_on))


## The clam on the crown: closed (a faint glow at its seam once lit) until
## stage 3, then open on the glowing pearl with its beam of light.
func _draw_clam(dark: Color, unlock: float, rim_k: float) -> void:
	var open: float = lit(3, 0.3)
	var center: Vector2 = _crown + Vector2(0.0, -1.0)
	var pearl: Vector2 = center + Vector2(0.0, -clam_size.y * 0.3)
	if open > 0.0:
		IslandArt.soft_glow(self, pearl, Vector2(80.0, 80.0), Color(pearl_color, 0.3 * open))
		IslandArt.beam(self, pearl, beam_height, 5.0, 40.0, IslandArt.hdr(pearl_color, 1.6, 0.42 * open))
	var bottom := PackedVector2Array()
	var top := PackedVector2Array()
	var hinge: Vector2 = center + Vector2(-clam_size.x, 0.0)
	var turn: float = -deg_to_rad(clam_open_degrees) * open
	for k: int in 13:
		var angle: float = PI * float(k) / 12.0
		bottom.append(center + Vector2(cos(angle) * clam_size.x, sin(angle) * clam_size.y))
		var upper: Vector2 = center + Vector2(cos(PI + angle) * clam_size.x, sin(PI + angle) * clam_size.y * 1.3)
		top.append(hinge + (upper - hinge).rotated(turn))
	IslandArt.mass(self, bottom, center.y, center.y + clam_size.y, dark, dark)
	if open > 0.0:
		draw_circle(pearl, 4.6, IslandArt.hdr(pearl_color, 3.0, open))
		IslandArt.soft_glow(self, pearl, Vector2(26.0, 26.0), IslandArt.hdr(pearl_color, 1.5, 0.8 * open))
	elif unlock > 0.0:
		IslandArt.soft_glow(self, center, Vector2(18.0, 8.0), Color(pearl_color, 0.28 * unlock))
	IslandArt.mass(self, top, center.y - clam_size.y * 1.3, center.y, dark.lerp(reef_top_color, 0.6 * unlock), dark)
	IslandArt.rim(self, top, 2.5, Color(rim_color, 0.45 * rim_k), IslandArt.facing(top, light_dir, 0.1))


func _draw_bubbles(on: float) -> void:
	if light <= 0.0:
		return
	var shown: int = int(round(float(bubble_count) * (0.3 + 0.7 * on)))
	for i: int in mini(shown, _bubbles.size()):
		var bubble: Dictionary = _bubbles[i]
		var t: float = fposmod(_time * float(bubble.speed) + float(bubble.phase), 1.0)
		var at := Vector2(float(bubble.x) + sin(t * TAU * 1.3 + float(bubble.phase) * 6.0) * 4.0, float(bubble.y) - t * float(bubble.rise))
		var alpha: float = (1.0 - t) * smoothstep(0.0, 0.12, t)
		IslandArt.soft_glow(self, at, Vector2.ONE * float(bubble.size) * 3.5, IslandArt.hdr(accent, 1.4, 0.5 * alpha))
		draw_circle(at, float(bubble.size) * 0.55, IslandArt.hdr(accent, 1.8, 0.7 * alpha))
