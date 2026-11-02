class_name PulseReveal
extends MarginContainer
## Wraps a panel so it is uncovered by a sonar wipe instead of popping in:
## reveal() grows a circle from an origin (a share of the size) over
## reveal_time; only what is inside the circle shows, with a glowing ring on
## its edge. The mask is a small shader in screen space (FRAGCOORD) on this
## control, shared by every node inside it (use_parent_material while it runs;
## restored when done), so it works over any background and with the bloom.

signal revealed

const SHADER_CODE: String = """
shader_type canvas_item;

uniform vec2 origin;
uniform float radius = 0.0;
uniform float softness = 14.0;

void fragment() {
	float d = distance(FRAGCOORD.xy, origin);
	COLOR.a *= 1.0 - smoothstep(radius - softness, radius, d);
}
"""

@export var reveal_time: float = 0.6
@export var ring_color: Color = Color(0.5, 1.1, 1.3, 0.9)
@export var ring_width: float = 2.0
## Pixels over which the content fades in at the circle's edge.
@export var softness: float = 14.0

## 0 = hidden, 1 = fully shown.
var progress: float = 1.0
var _origin_share: Vector2 = Vector2(0.5, 0.5)
var _ring: Control
var _material: ShaderMaterial
## Nodes switched to use_parent_material for the wipe (switched back after).
var _masked: Array[CanvasItem] = []

static var _shader: Shader


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = _shader
	# Drawn over the content, outside the mask (a top-level item does not use
	# this material); clipped to this panel's rect.
	_ring = Control.new()
	_ring.top_level = true
	_ring.clip_contents = true
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring, false, Node.INTERNAL_MODE_BACK)
	set_process(false)


## Hides the content until reveal().
func cover() -> void:
	_start(_origin_share)
	set_process(false)


## Uncovers the content from origin_share (0-1 of the size, e.g. (0, 0.5) =
## the middle of the left edge).
func reveal(origin_share: Vector2 = Vector2(0.5, 0.5)) -> void:
	_start(origin_share)
	set_process(true)


func is_revealing() -> bool:
	return progress < 1.0


func _start(origin_share: Vector2) -> void:
	_origin_share = origin_share
	progress = 0.0
	material = _material
	_mask_children(self)
	_update_mask()


func _process(delta: float) -> void:
	progress = minf(progress + delta / reveal_time, 1.0)
	_update_mask()
	if progress >= 1.0:
		_finish()


func _finish() -> void:
	material = null
	for item: CanvasItem in _masked:
		if is_instance_valid(item):
			item.use_parent_material = false
	_masked.clear()
	set_process(false)
	_ring.queue_redraw()
	revealed.emit()


func _mask_children(node: Node) -> void:
	for child: Node in node.get_children():
		var item := child as CanvasItem
		if item == null or item == _ring:
			continue
		if not item.use_parent_material:
			item.use_parent_material = true
			_masked.append(item)
		_mask_children(item)


func _update_mask() -> void:
	var to_screen: Transform2D = get_global_transform_with_canvas()
	_material.set_shader_parameter("origin", to_screen * _origin())
	_material.set_shader_parameter("radius", _radius() * to_screen.get_scale().x)
	_material.set_shader_parameter("softness", softness)
	_ring.global_position = global_position
	_ring.size = size
	_ring.queue_redraw()


func _origin() -> Vector2:
	return size * _origin_share


## The circle's radius: grows (fast, then slower) until it covers the far corner.
func _radius() -> float:
	var origin: Vector2 = _origin()
	var reach: float = 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		reach = maxf(reach, origin.distance_to(corner))
	return (reach + softness + ring_width * 4.0) * (1.0 - pow(1.0 - progress, 2.2))


func _draw_ring() -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var color := Color(ring_color, ring_color.a * (1.0 - progress * progress))
	_ring.draw_arc(_origin(), _radius(), 0.0, TAU, 96, Color(color, color.a * 0.25), ring_width * 4.0, true)
	_ring.draw_arc(_origin(), _radius(), 0.0, TAU, 96, color, ring_width, true)
