class_name HitboxDebugDraw
extends Node2D
## Debug view (toggle_key, F2; only when running from the editor): every
## hurtbox (blue) and attack hitbox (red; bright while it can hit, faint
## otherwise) of the nodes in HitShapes.DEBUG_GROUP (creatures, bosses, the
## sword's last swing, orbs), and each player's body circle. Must live on a
## CanvasLayer with follow_viewport_enabled at the origin (world coordinates,
## unlit).

@export var toggle_key: Key = KEY_F2
@export var hurt_color: Color = Color(0.3, 0.6, 1.0, 0.9)
@export var hit_color: Color = Color(1.0, 0.25, 0.2, 0.95)
@export var player_color: Color = Color(0.4, 1.0, 0.5, 0.9)
## Share of the colour's alpha for a hitbox that cannot hit right now.
@export_range(0.0, 1.0) var idle_alpha: float = 0.25
## Share of the alpha for the fill (the outline is drawn at full alpha).
@export_range(0.0, 1.0) var fill_alpha: float = 0.15
@export var line_width: float = 2.0
@export var font_size: int = 12

var enabled: bool = false


func _ready() -> void:
	# Only in editor runs: never in an exported game.
	if not OS.has_feature("editor"):
		set_process(false)
		set_process_unhandled_key_input(false)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == toggle_key:
		enabled = not enabled
		queue_redraw()


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var font: Font = ThemeDB.fallback_font
	for node: Node in get_tree().get_nodes_in_group(HitShapes.DEBUG_GROUP):
		if not node.has_method("get_debug_shapes"):
			continue
		var shapes: Array[Dictionary] = node.call("get_debug_shapes")
		for shape: Dictionary in shapes:
			var polygon: PackedVector2Array = shape["polygon"]
			if polygon.size() < 3:
				continue
			var color: Color = hurt_color if shape["kind"] == HitShapes.Kind.HURT else hit_color
			if not shape["active"]:
				color.a *= idle_alpha
			_draw_shape(polygon, color)
			var label: String = shape["label"]
			if label != "":
				draw_string(font, _top(polygon) + Vector2(-20.0, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
	for player: Player in Players.all(get_tree()):
		var body := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var radius: float = (body.shape as CircleShape2D).radius if body and body.shape is CircleShape2D else 14.0
		_draw_shape(HitShapes.circle(player.global_position, radius, 16), player_color)


func _draw_shape(polygon: PackedVector2Array, color: Color) -> void:
	if not Geometry2D.triangulate_polygon(polygon).is_empty():
		draw_colored_polygon(polygon, Color(color, color.a * fill_alpha))
	var closed: PackedVector2Array = polygon.duplicate()
	closed.append(polygon[0])
	draw_polyline(closed, color, line_width, true)


func _top(polygon: PackedVector2Array) -> Vector2:
	var top: Vector2 = polygon[0]
	for point: Vector2 in polygon:
		if point.y < top.y:
			top = point
	return top
