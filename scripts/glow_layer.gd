class_name GlowLayer
extends CanvasLayer
## One shared unlit layer (follow_viewport_enabled) for the small glowing
## details of a level's landmarks and harmless life, instead of one
## CanvasLayer per node. The LevelBuilder puts one in every level (group
## "glow_layer"); without one (tools, tests) a node gets its own.


func _ready() -> void:
	follow_viewport_enabled = true
	add_to_group("glow_layer")


## Puts drawer on the level's glow layer (drawer.position = a global position).
## The caller frees drawer when it leaves the tree.
static func add(owner: Node, drawer: Node2D) -> void:
	var layer := owner.get_tree().get_first_node_in_group("glow_layer") as GlowLayer
	if layer == null:
		layer = GlowLayer.new()
		owner.add_child(layer)
	layer.add_child(drawer)


## True if node is on screen or within margin pixels of it (things far from
## the camera skip their per-frame redraws).
static func near_camera(node: Node2D, margin: float) -> bool:
	var camera: Camera2D = node.get_viewport().get_camera_2d()
	if camera == null:
		return true
	var half: Vector2 = node.get_viewport_rect().size * 0.5 / camera.zoom
	var center: Vector2 = camera.get_screen_center_position()
	var offset: Vector2 = node.global_position - center
	return absf(offset.x) < half.x + margin and absf(offset.y) < half.y + margin
