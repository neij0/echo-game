class_name NavDebugDraw
extends Node2D
## Debug view (toggle_key, F3): every creature's navigation path, the point it
## steers to, its target, and a red ring while its CreatureStuckWatch reports
## it stuck. Must live on a CanvasLayer with follow_viewport_enabled at the
## origin (world coordinates, unlit).

@export var toggle_key: Key = KEY_F3
@export var path_color: Color = Color(0.3, 1.0, 0.6, 0.8)
## Path colour for creatures on the large-creature map (the boss).
@export var large_path_color: Color = Color(1.0, 0.6, 0.2, 0.8)
@export var next_point_color: Color = Color(1.0, 1.0, 0.3, 0.9)
@export var target_color: Color = Color(0.6, 0.8, 1.0, 0.8)
@export var stuck_color: Color = Color(1.0, 0.2, 0.2, 0.9)
@export var line_width: float = 2.0
@export var font_size: int = 12

var enabled: bool = false


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
	var default_map: RID = get_world_2d().navigation_map
	for node: Node in get_tree().get_nodes_in_group("creatures"):
		var creature := node as Creature
		if creature == null:
			continue
		var path: PackedVector2Array = creature.get_path_points()
		var color: Color = path_color if creature.get_navigation_map() == default_map else large_path_color
		if path.size() >= 2:
			draw_polyline(path, color, line_width, true)
		draw_circle(creature.get_next_path_point(), 4.0, next_point_color)
		var cross: float = 6.0
		draw_line(creature.target - Vector2(cross, cross), creature.target + Vector2(cross, cross), target_color, line_width)
		draw_line(creature.target - Vector2(cross, -cross), creature.target + Vector2(cross, -cross), target_color, line_width)
		var watch := creature.get_node_or_null("StuckWatch") as CreatureStuckWatch
		if watch and watch.stuck_windows > 0:
			draw_arc(creature.global_position, creature.body_radius + 8.0, 0.0, TAU, 24, stuck_color, line_width * 1.5, true)
		draw_string(font, creature.global_position + Vector2(-30.0, -creature.body_radius - 10.0), creature.get_state_name(),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
