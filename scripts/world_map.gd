class_name WorldMap
extends Control
## Grey-box World Map: the 5 worlds stacked from bottom (Ocean) to top (Snow).
## Completed worlds glow, the next one is unlocked and highlighted, the rest are
## dark with a lock icon. One star shines in the sky above for every completed
## world. Continue starts the next world (or shows "coming soon" if it has no
## content yet); Main Menu goes back.

@export var background_color: Color = Color(0.01, 0.015, 0.035)
@export var sky_color: Color = Color(0.03, 0.05, 0.12)
## One colour per world, bottom to top (Ocean, Caves, Forest, Desert, Snow).
@export var region_colors: Array[Color] = [
	Color(0.1, 0.35, 0.55), Color(0.35, 0.3, 0.25), Color(0.15, 0.4, 0.2),
	Color(0.6, 0.45, 0.2), Color(0.75, 0.85, 0.95),
]
@export var locked_color: Color = Color(0.1, 0.11, 0.14)
@export var glow_color: Color = Color(1.0, 0.9, 0.55)
@export var highlight_color: Color = Color(0.45, 0.95, 1.0)
@export var lock_color: Color = Color(0.45, 0.47, 0.52)
@export var star_color: Color = Color(1.0, 0.95, 0.75)
@export var text_color: Color = Color(0.85, 0.9, 1.0)

@export_group("Layout")
## Screen margin around the map.
@export var margin: float = 30.0
## Width of the button panel on the side.
@export var panel_width: float = 320.0
@export var sky_height: float = 110.0
@export var region_gap: float = 8.0
@export var glow_width: float = 6.0
## Glow / highlight pulses this many times per second.
@export var pulse_speed: float = 0.6
@export var lock_size: float = 22.0
@export var star_size: float = 12.0
@export var name_font_size: int = 26
@export var title_font_size: int = 36
@export var button_font_size: int = 22
@export var button_width: float = 260.0

var _region_labels: Array[Label] = []
var _message: Label
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for world_id: String in Game.world_ids:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", name_font_size)
		label.add_theme_color_override("font_color", text_color)
		label.text = _region_text(world_id)
		add_child(label)
		_region_labels.append(label)
	_build_panel()
	resized.connect(_layout_labels)
	_layout_labels()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _build_panel() -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_width - margin
	panel.offset_right = -margin
	panel.offset_top = -150.0
	panel.offset_bottom = 150.0
	# Only the panel follows the language direction (the map is drawn by hand).
	# In Arabic, Godot mirrors its anchors, so it moves to the left side.
	Game.apply_direction(panel)
	add_child(panel)

	var title := Label.new()
	title.text = Game.text("world_map")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", text_color)
	panel.add_child(title)

	var continue_button := _make_button(Game.text("continue"), _on_continue_pressed)
	panel.add_child(continue_button)
	panel.add_child(_make_button(Game.text("main_menu"), Game.go_to_main_menu))

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", highlight_color)
	panel.add_child(_message)
	continue_button.grab_focus()


func _make_button(text_value: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.x = button_width
	button.add_theme_font_size_override("font_size", button_font_size)
	button.pressed.connect(on_pressed)
	return button


func _on_continue_pressed() -> void:
	var world: WorldConfig = Game.get_current_world()
	if world and Game.save.stage_index < world.get_stage_count():
		Game.play_current()
	else:
		_message.text = Game.text("coming_soon") % Game.world_display_name(Game.save.world_id)


# --- Layout and drawing -----------------------------------------------------

## The map area (everything except the side panel).
func _map_rect() -> Rect2:
	var left: float = margin + (panel_width + margin if Game.is_rtl() else 0.0)
	return Rect2(left, margin, size.x - panel_width - margin * 3.0, size.y - margin * 2.0)


func _sky_rect() -> Rect2:
	var map: Rect2 = _map_rect()
	return Rect2(map.position, Vector2(map.size.x, sky_height))


## Region of world index (0 = Ocean at the bottom).
func _region_rect(index: int) -> Rect2:
	var map: Rect2 = _map_rect()
	var count: int = Game.world_ids.size()
	var area_top: float = map.position.y + sky_height + region_gap
	var area_height: float = map.end.y - area_top
	var height: float = (area_height - region_gap * (count - 1)) / count
	var row: int = count - 1 - index
	return Rect2(map.position.x, area_top + row * (height + region_gap), map.size.x, height)


func _layout_labels() -> void:
	for i: int in _region_labels.size():
		var rect: Rect2 = _region_rect(i)
		_region_labels[i].position = rect.position
		_region_labels[i].size = rect.size


func _region_text(world_id: String) -> String:
	var world_name: String = Game.world_display_name(world_id)
	if Game.is_world_completed(world_id):
		return "%s  -  %s" % [world_name, Game.text("completed")]
	if Game.is_world_unlocked(world_id):
		return "%s  -  %s" % [world_name, Game.text("next_world")]
	return world_name


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	var sky: Rect2 = _sky_rect()
	draw_rect(sky, sky_color)
	var pulse: float = 0.5 + 0.5 * sin(_time * TAU * pulse_speed)

	# One star per completed world, spread across the sky.
	var stars: int = Game.get_completed_world_count()
	for i: int in stars:
		var x: float = sky.position.x + sky.size.x * (i + 1) / (Game.world_ids.size() + 1)
		var y: float = sky.position.y + sky.size.y * (0.35 if i % 2 == 0 else 0.6)
		_draw_star(Vector2(x, y), star_size * (0.9 + 0.2 * pulse))

	for i: int in Game.world_ids.size():
		var world_id: String = Game.world_ids[i]
		var rect: Rect2 = _region_rect(i)
		var base: Color = region_colors[i] if i < region_colors.size() else locked_color
		if Game.is_world_completed(world_id):
			draw_rect(rect.grow(glow_width * pulse), Color(glow_color, 0.35))
			draw_rect(rect, base.lightened(0.25))
			draw_rect(rect, glow_color, false, 2.0)
			_region_labels[i].modulate = Color.WHITE
		elif Game.is_world_unlocked(world_id):
			draw_rect(rect, base)
			draw_rect(rect, Color(highlight_color, 0.5 + 0.5 * pulse), false, 3.0 + 2.0 * pulse)
			_region_labels[i].modulate = Color.WHITE
		else:
			draw_rect(rect, locked_color)
			_draw_lock(Vector2(rect.position.x + rect.size.x * (0.9 if not Game.is_rtl() else 0.1), rect.get_center().y))
			_region_labels[i].modulate = Color(1.0, 1.0, 1.0, 0.35)


func _draw_star(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 1.8, Color(star_color, 0.15))
	var points := PackedVector2Array()
	for i: int in 8:
		var length: float = radius if i % 2 == 0 else radius * 0.35
		points.append(center + Vector2.from_angle(TAU * i / 8.0 - PI * 0.5) * length)
	draw_colored_polygon(points, star_color)


func _draw_lock(center: Vector2) -> void:
	var body := Rect2(center - Vector2(lock_size * 0.6, lock_size * 0.1), Vector2(lock_size * 1.2, lock_size * 0.9))
	draw_arc(center - Vector2(0.0, lock_size * 0.1), lock_size * 0.4, PI, TAU, 16, lock_color, lock_size * 0.15)
	draw_rect(body, lock_color)
	draw_circle(body.get_center(), lock_size * 0.12, locked_color)
