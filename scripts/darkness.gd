class_name Darkness
extends CanvasModulate
## The base darkness of the world: everything not lit by a light is multiplied
## by this colour. Brighter = the floor shows a little inside lights, but areas
## far from any light also get less black. How much floor shows around the
## player depends mostly on the PlayerLight energy (player.tscn).
## Gets darker as the players go deeper (shared screen: uses their average depth).

@export var level: DescentLevel
@export var ambient_color: Color = Color(0.06, 0.08, 0.14)
## Ambient colour in the deepest part of the level.
@export var deep_ambient_color: Color = Color(0.02, 0.025, 0.05)
## 0-1 depth ratio where darkening starts...
@export_range(0.0, 1.0) var darken_start_ratio: float = 0.6
## ...and where it reaches deep_ambient_color.
@export_range(0.0, 1.0) var darken_end_ratio: float = 0.72


func _ready() -> void:
	color = ambient_color


func _process(_delta: float) -> void:
	if level == null:
		return
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return
	var total: float = 0.0
	for player: Player in players:
		total += level.depth_ratio_at(player.global_position.y)
	var ratio: float = total / players.size()
	var t: float = clampf((ratio - darken_start_ratio) / (darken_end_ratio - darken_start_ratio), 0.0, 1.0)
	color = ambient_color.lerp(deep_ambient_color, t)
