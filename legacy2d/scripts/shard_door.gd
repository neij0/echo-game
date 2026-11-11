class_name ShardDoor
extends RockWall
## The sealed doorway of a boss arena: rock like any wall (collision, shadow,
## sonar edge), with a faint golden seam and one socket per Echo Shard. Each
## collected shard lights a socket (StageManager calls set_shard_progress);
## when all are lit, open() fades the rock away and the arena can be entered.
## The LevelBuilder places it on the arena's only doorway (the polygon of a
## seal) and rebakes the creatures' navigation once it is open.

signal opened

@export_group("Seam")
@export var seam_color: Color = Color(1.0, 0.8, 0.35)
@export var seam_energy: float = 1.6
@export_range(0.0, 1.0) var seam_alpha: float = 0.35
@export var seam_width: float = 2.0
## The glow shows when a player is this close (it is a glowing part, but it
## must not give the arena away from across the level).
@export var show_distance: float = 520.0

@export_group("Sockets")
@export var socket_color: Color = Color(0.55, 0.95, 1.0)
@export var socket_energy: float = 2.4
@export var socket_radius: float = 6.0
@export var socket_spacing: float = 34.0
@export_range(0.0, 1.0) var empty_socket_alpha: float = 0.4

@export_group("Opening")
## Seconds for the rock to fade away.
@export var open_time: float = 1.2
@export var open_stream: AudioStream
@export var open_volume_db: float = -4.0

var shards_needed: int = 0
var shards_have: int = 0
var is_open: bool = false
var _open_left: float = 0.0
var _center: Vector2
## Direction along the door (the long side of its rectangle).
var _along: Vector2 = Vector2.RIGHT
var _half_length: float = 0.0
var _rock_visual: Polygon2D
var _visual: Node2D
var _audio: AudioStreamPlayer


func _ready() -> void:
	super()
	add_to_group("level_exit")
	_rock_visual = _find_child_of_type("Polygon2D") as Polygon2D
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	_center = bounds.get_center()
	_along = Vector2.RIGHT if bounds.size.x >= bounds.size.y else Vector2.DOWN
	_half_length = maxf(bounds.size.x, bounds.size.y) * 0.5

	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	_visual = Node2D.new()
	layer.add_child(_visual)
	_visual.draw.connect(_draw_visual)

	_audio = AudioStreamPlayer.new()
	_audio.stream = open_stream
	_audio.volume_db = open_volume_db
	_audio.bus = &"SFX"
	add_child(_audio)


func _process(delta: float) -> void:
	_visual.global_position = to_global(_center)
	if is_open and _open_left > 0.0:
		_open_left = maxf(_open_left - delta, 0.0)
		if _rock_visual:
			_rock_visual.modulate.a = _open_left / open_time
	_visual.queue_redraw()


## Called by the StageManager whenever a shard is collected.
func set_shard_progress(have: int, needed: int) -> void:
	shards_have = have
	shards_needed = needed


## Fades the rock away: no collision, no shadow, no sonar edge any more.
func open() -> void:
	if is_open:
		return
	is_open = true
	_open_left = open_time
	remove_from_group("rock_walls")
	remove_from_group("level_exit")
	for child: Node in get_children():
		if child is CollisionPolygon2D:
			(child as CollisionPolygon2D).set_deferred("disabled", true)
		elif child is LightOccluder2D:
			child.queue_free()
	if open_stream:
		_audio.play()
	get_tree().call_group("sonar_overlay", "rebuild_samples")
	opened.emit()


func _find_child_of_type(type_name: String) -> Node:
	for child: Node in get_children():
		if child.is_class(type_name):
			return child
	return null


static func _hdr(base: Color, boost: float, alpha: float) -> Color:
	return Color(base.r * boost, base.g * boost, base.b * boost, alpha)


func _draw_visual() -> void:
	var fade: float = _open_left / open_time if is_open else 1.0
	var player: Player = Players.nearest(get_tree(), to_global(_center))
	if player == null or fade <= 0.0:
		return
	var distance: float = player.global_position.distance_to(to_global(_center))
	var near: float = clampf(1.0 - distance / show_distance, 0.0, 1.0)
	var alpha: float = minf(near * 2.0, 1.0) * fade
	if alpha <= 0.0:
		return
	var seam := _hdr(seam_color, seam_energy * (1.0 + (1.0 - fade) * 2.0), seam_alpha * alpha)
	_visual.draw_line(-_along * _half_length, _along * _half_length, seam, seam_width, true)
	var first: float = -socket_spacing * (shards_needed - 1) * 0.5
	for i: int in shards_needed:
		var at: Vector2 = _along * (first + socket_spacing * i)
		if i < shards_have or is_open:
			_visual.draw_circle(at, socket_radius, _hdr(socket_color, socket_energy, alpha))
		else:
			_visual.draw_arc(at, socket_radius, 0.0, TAU, 20, _hdr(socket_color, 1.0, empty_socket_alpha * alpha), 1.5, true)
