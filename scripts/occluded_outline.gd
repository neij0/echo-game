class_name OccludedOutline
extends Node
## A player's outline shown through a tall rock (3/4 view): only the parts of
## the outline a rock covers are drawn, soft and semi-transparent in the
## player's colour, on an own CanvasLayer (the darkness does not dim it).
## Child of the player's visual, which provides get_outline_lines(): closed
## or open polylines in its own space. Creatures do not get this.

@export var color: Color = Color(0.3, 0.95, 1.0)
## HDR energy of the line (> 1 glows a little).
@export var energy: float = 1.0
## Opacity of the thin line and of the soft wide line under it.
@export_range(0.0, 1.0) var line_alpha: float = 0.35
@export_range(0.0, 1.0) var halo_alpha: float = 0.1
@export var line_width: float = 1.2
@export var halo_width: float = 4.0
## How fast the outline fades in and out (per second).
@export var fade_speed: float = 8.0

var _visual: Node2D
var _drawer: Node2D
## Covered segments as pairs of global points (for draw_multiline).
var _segments := PackedVector2Array()
var _shown: float = 0.0


func _ready() -> void:
	_visual = get_parent() as Node2D
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_drawer = Node2D.new()
	layer.add_child(_drawer)
	_drawer.draw.connect(_draw_outline)


func _process(delta: float) -> void:
	var lines: Array = _visual.call("get_outline_lines")
	var covered := PackedVector2Array()
	var sort_y: float = _visual.global_position.y
	var pieces: Array[RockFace] = RockFace.pieces_near(get_tree(), _bounds_of(lines), sort_y)
	if not pieces.is_empty():
		for line: PackedVector2Array in lines:
			for i: int in line.size() - 1:
				var a: Vector2 = _visual.to_global(line[i])
				var b: Vector2 = _visual.to_global(line[i + 1])
				var middle: Vector2 = (a + b) * 0.5
				for piece: RockFace in pieces:
					if piece.covers(middle, sort_y):
						covered.append(a)
						covered.append(b)
						break
	# Keep the last outline while it fades out.
	if not covered.is_empty():
		_segments = covered
	_shown = move_toward(_shown, 1.0 if not covered.is_empty() else 0.0, fade_speed * delta)
	_drawer.queue_redraw()


func _bounds_of(lines: Array) -> Rect2:
	var bounds := Rect2(_visual.global_position, Vector2.ZERO)
	for line: PackedVector2Array in lines:
		for point: Vector2 in line:
			bounds = bounds.expand(_visual.to_global(point))
	return bounds


func _draw_outline() -> void:
	if _shown <= 0.0 or _segments.is_empty():
		return
	var glow := Color(color.r * energy, color.g * energy, color.b * energy)
	_drawer.draw_multiline(_segments, Color(glow, halo_alpha * _shown), halo_width, true)
	_drawer.draw_multiline(_segments, Color(glow, line_alpha * _shown), line_width, true)
