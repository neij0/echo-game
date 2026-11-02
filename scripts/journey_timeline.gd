class_name JourneyTimeline
extends VBoxContainer
## The list beside the Journey tower, like a vertical timeline: the worlds from
## the top (Snow) down to the Ocean on a thin line, each with a marker and its
## state: restored, "Stage 2" (the current one) or locked (a padlock). The line
## glows from the bottom up to the current world, whose marker glows in its
## colour; the selected world (the one the camera looks at) is bright and
## underlined with a glowing wave. Clicking a row selects it. Mirrors in Arabic.

signal row_clicked(index: int)

enum State { LOCKED, CURRENT, RESTORED }

@export var marker_column: float = 30.0
@export var row_height: float = 64.0
@export var line_color: Color = Color(0.4, 0.6, 0.75, 0.3)
@export var lit_line_color: Color = Color(1.0, 0.86, 0.55)
@export var locked_color: Color = Color(0.4, 0.45, 0.55)
@export var name_font_size: int = 24
@export var status_font_size: int = 15

var selected: int = 0
## {index, row, marker, name, status, lock, state, accent}
var _rows: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	for row: Dictionary in _rows:
		(row.marker as Control).queue_redraw()


## names / states / accents: one per world, in play order (Ocean first);
## stage_text: what the current world shows (e.g. "Stage 2").
func setup(names: PackedStringArray, states: Array[State], accents: Array[Color], stage_text: String) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	for index: int in range(names.size() - 1, -1, -1):
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = row_height
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(_on_row_input.bind(index))
		add_child(row)
		var marker := Control.new()
		marker.custom_minimum_size = Vector2(marker_column, row_height)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.draw.connect(_draw_marker.bind(_rows.size()))
		row.add_child(marker)
		var texts := VBoxContainer.new()
		texts.alignment = BoxContainer.ALIGNMENT_CENTER
		texts.add_theme_constant_override("separation", 0)
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(texts)
		var name_label := Label.new()
		name_label.text = names[index]
		name_label.add_theme_font_size_override("font_size", name_font_size)
		texts.add_child(name_label)
		var status_row := HBoxContainer.new()
		status_row.add_theme_constant_override("separation", 6)
		texts.add_child(status_row)
		var status := Label.new()
		status.add_theme_font_size_override("font_size", status_font_size)
		status_row.add_child(status)
		var lock := LockIcon.new()
		lock.color = locked_color
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_row.add_child(lock)
		var state: State = states[index]
		match state:
			State.LOCKED:
				status.text = Game.text("journey_locked")
			State.CURRENT:
				status.text = stage_text
			State.RESTORED:
				status.text = Game.text("journey_restored")
		lock.visible = state == State.LOCKED
		_rows.append({"index": index, "row": row, "marker": marker, "name": name_label, "status": status, "state": state,
			"accent": accents[index]})
	set_selected(selected)


func set_selected(index: int) -> void:
	selected = index
	for row: Dictionary in _rows:
		var is_selected: bool = row.index == index
		var name_label: Label = row.name
		var status: Label = row.status
		var accent: Color = row.accent
		var locked: bool = row.state == State.LOCKED
		var name_color: Color = locked_color if locked else Color(0.78, 0.84, 0.92)
		if is_selected:
			name_color = Color(0.7, 0.75, 0.85) if locked else Color(accent * 1.25, 1.0)
		name_label.add_theme_color_override("font_color", name_color)
		status.add_theme_color_override("font_color", locked_color if locked else Color(accent, 0.85))


func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		row_clicked.emit(index)


## The marker centre of a row, in this control's coordinates.
func _marker_center(row: Dictionary) -> Vector2:
	var marker: Control = row.marker
	return marker.get_global_rect().get_center() - global_position


func _draw() -> void:
	if _rows.size() < 2:
		return
	var top: Vector2 = _marker_center(_rows[0])
	var bottom: Vector2 = _marker_center(_rows[_rows.size() - 1])
	draw_line(top, bottom, line_color, 1.0, true)
	# Lit from the Ocean up to the current world.
	for row: Dictionary in _rows:
		if row.state == State.CURRENT:
			var hdr := Color(lit_line_color.r * 1.4, lit_line_color.g * 1.4, lit_line_color.b * 1.4, 0.8)
			GlowFx.glow_line(self, PackedVector2Array([bottom, _marker_center(row)]), hdr, 1.2)
	# The selected world's name gets the glowing wave.
	for row: Dictionary in _rows:
		if row.index != selected:
			continue
		var name_label: Label = row.name
		var rect: Rect2 = name_label.get_global_rect()
		var font: Font = name_label.get_theme_font("font")
		var width: float = font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_font_size).x
		var rtl: bool = is_layout_rtl()
		var start_x: float = (rect.end.x - width if rtl else rect.position.x) - global_position.x
		var y: float = rect.get_center().y - global_position.y + font.get_ascent(name_font_size) * 0.55
		var color: Color = locked_color if row.state == State.LOCKED else Color(row.accent * 1.3, 0.9)
		GlowFx.glow_line(self, GlowFx.wave_points(Vector2(start_x, y), Vector2(start_x + width, y), _time * 1.1, 24.0, 1.5), color, 1.3)


func _draw_marker(row_index: int) -> void:
	var row: Dictionary = _rows[row_index]
	var marker: Control = row.marker
	var center: Vector2 = marker.size * 0.5
	var accent: Color = row.accent
	match row.state:
		State.LOCKED:
			marker.draw_arc(center, 4.0, 0.0, TAU, 16, Color(locked_color, 0.8), 1.2, true)
		State.RESTORED:
			_diamond(marker, center, 5.0, Color(accent, 0.9))
		State.CURRENT:
			var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
			GlowFx.dot(marker, center, 3.0, Color(accent * 1.8, 0.5 + 0.3 * pulse))
			_diamond(marker, center, 7.0, Color(accent * 1.6, 1.0))
			marker.draw_arc(center, 11.0 + 3.0 * pulse, 0.0, TAU, 24, Color(accent, 0.35 * (1.0 - pulse)), 1.0, true)
	if row.index == selected:
		marker.draw_arc(center, 14.0, 0.0, TAU, 28, Color(accent if row.state != State.LOCKED else locked_color, 0.6), 1.2, true)


func _diamond(canvas: Control, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0)]), color)
