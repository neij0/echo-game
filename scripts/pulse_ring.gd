class_name PulseRing
extends Node2D
## The sonar pulse: an expanding ring + light that reveals walls, then fades.
## Wakes up every Coral the ring passes over.

@export var max_radius: float = 650.0
@export var expand_time: float = 0.8
## How long the revealed area stays fully lit after the ring stops expanding.
@export var reveal_time: float = 2.0
@export var fade_time: float = 0.8
@export var ring_width: float = 4.0
@export var ring_color: Color = Color(0.4, 0.9, 1.0)
@export var light_energy: float = 0.9
@export var light_color: Color = Color(0.55, 0.75, 0.9)

var radius: float = 0.0
var _age: float = 0.0
var _light: PointLight2D
var _woken: Array[Coral] = []


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(256, 0.9)
	_light.color = light_color
	_light.energy = light_energy
	add_child(_light)
	_update_light()


func _process(delta: float) -> void:
	_age += delta
	radius = max_radius * clampf(_age / expand_time, 0.0, 1.0)

	var fade_start: float = expand_time + reveal_time
	var strength: float = 1.0 - clampf((_age - fade_start) / fade_time, 0.0, 1.0)
	_light.energy = light_energy * strength

	_update_light()
	_wake_corals()
	queue_redraw()

	if _age >= fade_start + fade_time:
		queue_free()


func _update_light() -> void:
	_light.texture_scale = maxf(LightTextures.scale_for_radius(_light.texture, radius), 0.01)


func _wake_corals() -> void:
	for node: Node in get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral == null or coral in _woken:
			continue
		if global_position.distance_to(coral.global_position) <= radius:
			_woken.append(coral)
			coral.wake()


func _draw() -> void:
	# Only draw the ring while it is still travelling outward.
	if _age <= expand_time and radius > ring_width:
		draw_arc(Vector2.ZERO, radius - ring_width, 0.0, TAU, 96, ring_color, ring_width, true)
