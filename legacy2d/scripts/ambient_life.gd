class_name AmbientLife
extends Node2D
## Base of the harmless life of a level (fish schools, jellyfish, crabs, sea
## plants), placed by the LevelBuilder on open floor (WorldConfig.ambient_life).
## Never creature-like: no eyes, soft cool colours, gentle motion, no sounds.
## Not in the "creatures" group: creatures ignore it, it never alerts anything
## and never touches the music; no collision. Its small glows are drawn on
## the level's glow layer (GlowLayer). Far from the camera it only keeps time.

## Things farther than this from the screen skip their updates.
@export var active_margin: float = 600.0
## Redraws per second (0 = every frame). Slow motion (swaying plants, a
## drifting jellyfish) looks the same at 30 and costs much less.
@export var redraw_rate: float = 0.0

var _time: float = 0.0
var _glow: Node2D
## Shapes of the current draw, sent in one call (ShapeBatch).
var _batch := ShapeBatch.new()
var _redraw_wait: float = 0.0


func _ready() -> void:
	add_to_group("ambient_life")
	if _has_glow():
		_glow = Node2D.new()
		GlowLayer.add(self, _glow)
		_glow.draw.connect(func() -> void: _draw_glow(_glow))


func _exit_tree() -> void:
	if is_instance_valid(_glow):
		_glow.queue_free()


func _process(delta: float) -> void:
	_time += delta
	if not GlowLayer.near_camera(self, active_margin):
		return
	_update(delta)
	_redraw_wait -= delta
	if _redraw_wait > 0.0:
		return
	_redraw_wait = 1.0 / redraw_rate if redraw_rate > 0.0 else 0.0
	if _is_moving():
		queue_redraw()
	if _glow:
		_glow.position = global_position
		_glow.queue_redraw()


## The players (to keep away from).
func players() -> Array[Player]:
	return Players.all(get_tree())


## The nearest player within distance (null = none).
func nearest_player_within(distance: float) -> Player:
	var best: Player = null
	var best_distance: float = distance
	for player: Player in players():
		var d: float = player.global_position.distance_to(global_position)
		if d < best_distance:
			best_distance = d
			best = player
	return best


# --- For subclasses ----------------------------------------------------------

func _update(_delta: float) -> void:
	pass


## False while nothing in the world-drawn part changes (skips its redraw).
func _is_moving() -> bool:
	return true


func _has_glow() -> bool:
	return false


## Draws the small glows in the glow drawer's space (= this node's position).
func _draw_glow(_canvas: Node2D) -> void:
	pass


## HDR colour with alpha (above 1.0 blooms a little).
static func hdr(color_value: Color, energy: float, alpha: float) -> Color:
	return Color(color_value.r * energy, color_value.g * energy, color_value.b * energy, alpha)
