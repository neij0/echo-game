class_name ShardPips
extends Control
## The Echo Shards on the HUD: one small diamond per shard of the level, a
## faint outline until it is collected, then filled and glowing (the shard
## colour; gold once all are in). A newly collected one flashes.

@export var pip_size: Vector2 = Vector2(10.0, 15.0)
@export var gap: float = 12.0
@export var empty_color: Color = Color(0.55, 0.75, 0.9, 0.35)
@export var shard_color: Color = Color(0.55, 1.1, 1.3)
@export var done_color: Color = Color(1.3, 1.0, 0.45)
@export var flash_time: float = 0.6

var collected: int = 0
var total: int = 0
var _flash_left: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_progress(new_collected: int, new_total: int) -> void:
	if new_collected > collected and new_total == total:
		_flash_left = flash_time
	collected = new_collected
	total = new_total
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(total * pip_size.x + maxi(total - 1, 0) * gap + pip_size.x, pip_size.y + 8.0)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	if total <= 0:
		return
	var done: bool = collected >= total
	var width: float = total * pip_size.x + (total - 1) * gap
	var start: float = (size.x - width) * 0.5 + pip_size.x * 0.5
	for i: int in total:
		var center := Vector2(start + i * (pip_size.x + gap), size.y * 0.5)
		var shape := PackedVector2Array([center + Vector2(0.0, -pip_size.y * 0.5), center + Vector2(pip_size.x * 0.5, 0.0),
			center + Vector2(0.0, pip_size.y * 0.5), center + Vector2(-pip_size.x * 0.5, 0.0)])
		if i < collected:
			var fill: Color = done_color if done else shard_color
			var flash: float = _flash_left / flash_time if i == collected - 1 else 0.0
			var halo := PackedVector2Array()
			for point: Vector2 in shape:
				halo.append(center + (point - center) * (1.7 + flash))
			draw_colored_polygon(halo, Color(fill, 0.14 + 0.3 * flash))
			draw_colored_polygon(shape, fill.lerp(Color(2.0, 2.0, 2.0), flash * 0.6))
		else:
			var outline: PackedVector2Array = shape.duplicate()
			outline.append(shape[0])
			draw_polyline(outline, empty_color, 1.2, true)
