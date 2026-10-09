class_name PulseRing
extends Node2D
## The sonar pulse: a faint, shadow-casting glow that expands and fades, and wakes
## every Coral the front passes over. The visible wave front and the edge reveal
## are drawn by SonarOverlay, which this pulse notifies when it starts.

@export var max_radius: float = 650.0
@export var expand_time: float = 0.8
## How long the faint glow stays after the front stops expanding.
@export var reveal_time: float = 2.0
@export var fade_time: float = 0.8

@export_group("Glow")
## Kept low on purpose: the glowing outlines carry the reveal, not this light.
@export var light_energy: float = 0.15
@export var light_color: Color = Color(0.55, 0.75, 0.9)
## 0-1: where the glow starts fading towards its edge (lower = softer).
@export_range(0.0, 1.0) var glow_hard_edge: float = 0.2
@export var cast_shadows: bool = true
@export var shadow_smooth: float = 2.0

var radius: float = 0.0
var _age: float = 0.0
var _light: PointLight2D
var _woken: Array[Coral] = []


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = LightTextures.radial(256, glow_hard_edge)
	_light.color = light_color
	_light.energy = light_energy
	_light.shadow_enabled = cast_shadows
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_filter_smooth = shadow_smooth
	add_child(_light)
	_update_light()
	get_tree().call_group("sonar_overlay", "add_pulse", global_position, max_radius, expand_time)


func _process(delta: float) -> void:
	_age += delta
	radius = max_radius * clampf(_age / expand_time, 0.0, 1.0)

	var fade_start: float = expand_time + reveal_time
	var strength: float = 1.0 - clampf((_age - fade_start) / fade_time, 0.0, 1.0)
	_light.energy = light_energy * strength

	_update_light()
	_wake_corals()

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
