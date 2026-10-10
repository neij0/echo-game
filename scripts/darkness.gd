class_name Darkness
extends CanvasModulate
## The base darkness of the world: everything not lit by a light is multiplied
## by this colour. Brighter = the floor shows a little inside lights, but areas
## far from any light also get less black. How much floor shows around the
## player depends mostly on the PlayerLight energy (player.tscn).

@export var ambient_color: Color = Color(0.06, 0.08, 0.14)


func _ready() -> void:
	color = ambient_color
