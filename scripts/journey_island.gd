class_name JourneyIsland
extends Node2D
## One world on the Journey screen: a floating island drawn in code in the
## "silhouette + glow" look, no outlines. Every island is one dark silhouette
## (its top closed by the jagged rock hanging under it, IslandArt) with two
## wider, lighter rock layers behind it, all fading into the dark, a soft rim
## light and a glow behind it. Each world holds its own vessel of the Ancient
## Light (Ocean a sea globe, Caves a geode, Forest a great tree, Desert an
## hourglass, Snow an ice star) that wakes as its stages are cleared:
##   light 0 = locked: a near-black silhouette with a faint rim only;
##   stage 1 = the vessel still dark, a few small lights of life;
##   stage 2 = the vessel glows softly (soft_level);
##   stage 3 = its core awakens with rays (core_level).
## Fractions while it lights up (JourneyTower tweens light). Each kind
## (JourneyIslandOcean, ...Caves, ...Forest, ...Desert, ...Snow) builds its top
## edge (_build_top) and draws its vessel and life behind (_draw_back) and in
## front of (_draw_front) the island's body.

@export var half_width: float = 170.0
## How far the jagged rock hangs under the top's corners (its farthest teeth).
@export var underside_depth: float = 230.0
## Share of underside_depth the body's own teeth reach (the layers behind go deeper).
@export var front_share: float = 0.62
## The body's teeth: min / max width (narrow = long, thin stalactites).
@export var tooth_width: Vector2 = Vector2(14.0, 28.0)
## The world's colour: rim light, glows, the tint of the far rock.
@export var accent: Color = Color(0.45, 0.95, 1.0)
@export var seed_value: int = 1
## How far its shapes rise above the top's corners at most (the vessel's top);
## with it get_visual_rect knows the whole island.
@export var crown_height: float = 200.0
## Room kept round the island when the Journey screen frames it.
@export var frame_margin: float = 14.0

@export_group("Light")
## The direction the rim light shines (from the upper left).
@export var light_dir: Vector2 = Vector2(0.5, 1.0)
## Rim strength of a locked island (0-1).
@export var locked_rim: float = 0.2
@export var rim_strength: float = 0.24
@export var rock_top_color: Color = Color(0.028, 0.06, 0.078)
@export var rock_base_color: Color = Color(0.008, 0.014, 0.024)
@export var mid_rock_color: Color = Color(0.016, 0.034, 0.048)
@export var far_rock_color: Color = Color(0.03, 0.068, 0.09)
## How much the far rock takes the world's colour.
@export var far_rock_tint: float = 0.3
@export var locked_color: Color = Color(0.006, 0.009, 0.015)
## The glow behind a fully lit island (alpha).
@export var aura_strength: float = 0.17

## 0 = locked, 1-3 = lit steps (fractions while it lights up).
var light: float = 0.0
var _time: float = 0.0
var _top_edge := PackedVector2Array()
var _top_facing := PackedFloat32Array()
## The y of the top edge's corners and of its highest point.
var _top_y: float = 0.0
var _crown_y: float = 0.0
var _rock: Dictionary = {}


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_top_edge = _build_top(rng)
	_top_y = _top_edge[0].y
	for point: Vector2 in _top_edge:
		_crown_y = minf(_crown_y, point.y)
	_top_facing = IslandArt.facing(_top_edge, light_dir, 0.0)
	for i: int in _top_facing.size():
		_top_facing[i] = _top_facing[i] * _top_facing[i]
	_rock = IslandArt.build_island_rock(rng, _top_edge, half_width, _top_y, _crown_y, underside_depth, 0.0, front_share, tooth_width)
	_build_kind(rng)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## The island's drawn area (local): its vessel, its top and the rock hanging
## under it (the faded tips left out). The Journey screen centres on it.
func get_visual_rect() -> Rect2:
	var top: float = minf(_crown_y, _top_y - crown_height) - frame_margin
	var bottom: float = _top_y + underside_depth * 0.8
	return Rect2(-half_width - frame_margin, top, (half_width + frame_margin) * 2.0, bottom - top)


## Where the camera looks at this island (local to its parent).
func get_focus_point() -> Vector2:
	return position + get_visual_rect().get_center()


## Where the path between islands meets this one (local to its parent):
## side -1 = its left shoulder, 1 = its right shoulder.
func get_path_anchor(side: float) -> Vector2:
	return position + Vector2(side * half_width * 0.86, _top_y + 10.0)


# --- How lit it is ---------------------------------------------------------------

## 0-1: how far a light of this step (1-3) is on; order (0-1) is its place in
## the step (later ones come on later).
func lit(step: int, order: float = 0.0) -> float:
	return clampf((light - float(step - 1) - order * 0.6) / 0.4, 0.0, 1.0)


## 0-1: the island's overall brightness.
func overall() -> float:
	return clampf(light / 3.0, 0.0, 1.0)


## 0 locked .. 1 from stage 1 on.
func unlocked() -> float:
	return clampf(light, 0.0, 1.0)


## 0-1: the vessel's soft glow (stage 2).
func soft_level() -> float:
	return clampf(light - 1.0, 0.0, 1.0)


## 0-1: the vessel's core awakening (stage 3).
func core_level() -> float:
	return clampf(light - 2.0, 0.0, 1.0)


func rim_level() -> float:
	return lerpf(locked_rim, 1.0, unlocked() * 0.5 + overall() * 0.5)


func rim_color() -> Color:
	return accent.lerp(Color.WHITE, 0.3)


## The silhouette's darkest colour now (near-black when locked).
func dark() -> Color:
	return locked_color.lerp(rock_base_color, unlocked())


## A silhouette colour lifted towards lit_color as the island wakes.
func lifted(lit_color: Color, share: float = 1.0) -> Color:
	return dark().lerp(lit_color, unlocked() * (0.55 + 0.45 * overall()) * share)


# --- Kinds ---------------------------------------------------------------------------

## The island's top edge, left to right, from (-half_width, y) to
## (half_width, y) with the same y at both ends.
func _build_top(_rng: RandomNumberGenerator) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half_width, 0.0), Vector2(0.0, -30.0), Vector2(half_width, 0.0)])


## Kinds place their vessel and life here (same seed every time).
func _build_kind(_rng: RandomNumberGenerator) -> void:
	pass


## Drawn between the rock layers and the body (things the body hides a part of).
func _draw_back() -> void:
	pass


## Drawn over the body.
func _draw_front() -> void:
	pass


func _draw() -> void:
	var unlock: float = unlocked()
	var glow_on: float = unlock * 0.3 + soft_level() * 0.35 + core_level() * 0.35
	var rect: Rect2 = get_visual_rect()
	IslandArt.soft_glow(self, Vector2(0.0, rect.position.y + rect.size.y * 0.35), Vector2(half_width * 1.9, rect.size.y * 0.75),
		Color(accent, aura_strength * glow_on))
	IslandArt.soft_glow(self, Vector2(0.0, _top_y + 80.0), Vector2(half_width * 1.5, half_width * 1.1), Color(accent, 0.07 * glow_on))
	var layer_on: float = unlock * (0.6 + 0.4 * overall())
	var far: Color = far_rock_color.lerp(accent * 0.12, far_rock_tint)
	IslandArt.draw_rock_layers(self, _rock, locked_color.lerp(far, layer_on), locked_color.lerp(mid_rock_color, layer_on))
	_draw_back()
	IslandArt.draw_rock_body(self, _rock, lifted(rock_top_color), dark())
	var rim: float = rim_level()
	IslandArt.rim(self, _top_edge, 11.0, Color(rim_color(), rim_strength * rim), _top_facing)
	IslandArt.haze(self, _top_edge, 16.0, Color(rim_color(), 0.05 * rim), _top_facing)
	_draw_front()


# --- Helpers for the kinds ------------------------------------------------------------

## The top edge's y at x (between its points).
func top_y_at(x: float) -> float:
	for i: int in range(1, _top_edge.size()):
		if _top_edge[i].x >= x and _top_edge[i - 1].x <= x:
			return lerpf(_top_edge[i - 1].y, _top_edge[i].y, inverse_lerp(_top_edge[i - 1].x, _top_edge[i].x, x))
	return _top_y


## A rim light on a shape's lit edge (the edge walked with the shape on its right).
func rim_edge(edge: PackedVector2Array, width: float, strength: float = 1.0) -> void:
	IslandArt.rim(self, edge, width, Color(rim_color(), rim_strength * rim_level() * strength),
		IslandArt.facing(edge, light_dir, 0.1))


## A small glowing point of life (polyps, fireflies...): a bright core in a soft halo.
func spark(at: Vector2, size: float, color: Color, on: float) -> void:
	if on <= 0.0:
		return
	IslandArt.soft_glow(self, at, Vector2.ONE * size * 6.0, Color(color, 0.45 * on))
	draw_circle(at, size, IslandArt.hdr(color, 2.4, on))


## Rays out of an awakened core: thin soft wedges turning slowly.
func rays(center: Vector2, count: int, length: float, spread: float, color: Color, on: float, turn_speed: float = 0.06) -> void:
	if on <= 0.0:
		return
	for k: int in count:
		var angle: float = TAU * float(k) / float(count) + _time * turn_speed
		var reach: float = length * (0.75 + 0.25 * sin(_time * 0.7 + float(k) * 1.7))
		draw_polygon(PackedVector2Array([center, center + Vector2.from_angle(angle - spread) * reach,
			center + Vector2.from_angle(angle + spread) * reach]),
			PackedColorArray([IslandArt.hdr(color, 1.4, 0.2 * on), Color(color, 0.0), Color(color, 0.0)]))


## A crystal standing on base: a long six-sided prism seen from the side,
## pointed at the top; lean moves its tip sideways (px).
static func crystal_shape(base: Vector2, height: float, width: float, lean: float) -> PackedVector2Array:
	var half: float = width * 0.5
	return PackedVector2Array([base + Vector2(-half, 0.0), base + Vector2(half, 0.0),
		base + Vector2(half + lean * 0.75, -height * 0.78), base + Vector2(lean, -height),
		base + Vector2(-half + lean * 0.75, -height * 0.78)])


## A silhouette lit from inside: the island's dark at its foot (bottom_y)
## turning to glow_color (over-bright, it blooms) towards its top as on
## grows, with a rim on its lit side.
func glowing_shape(shape: PackedVector2Array, top_y: float, bottom_y: float, glow_color: Color, on: float,
		rim_share: float = 1.0) -> void:
	var foot: Color = dark()
	var head: Color = lifted(rock_top_color).lerp(IslandArt.hdr(glow_color, 1.6), 0.85 * on)
	IslandArt.mass(self, shape, top_y, bottom_y, head, foot.lerp(IslandArt.hdr(glow_color, 1.0), 0.25 * on))
	if rim_share > 0.0:
		var edge := PackedVector2Array([shape[0], shape[shape.size() - 1], shape[shape.size() - 2]])
		rim_edge(edge, 3.0, rim_share)
