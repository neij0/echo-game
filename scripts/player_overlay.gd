class_name PlayerOverlay
extends Node2D
## Unlit markers for one player, so they stay readable in the dark: an optional
## faint outline (the Guardian's cold blue glow), a pulsing ring while downed,
## and the revive progress ring while the partner is reviving them.
## Lives on a CanvasLayer with follow_viewport_enabled; follows the player.

@export var player: Player

@export_group("Outline")
@export var outline_enabled: bool = false
@export var outline_color: Color = Color(0.35, 0.6, 1.0)
@export var outline_energy: float = 1.2
@export_range(0.0, 1.0) var outline_alpha: float = 0.5
@export var outline_width: float = 1.5
## Size of the outline: x = width, y = height (a capsule; equal = circle).
@export var outline_size: Vector2 = Vector2(30.0, 30.0)

@export_group("Downed")
@export var downed_color: Color = Color(1.0, 0.3, 0.25)
@export var downed_energy: float = 2.0
@export var downed_radius: float = 30.0
## Pulses per second of the downed ring.
@export var downed_pulse_speed: float = 1.2

@export_group("Revive")
@export var revive_color: Color = Color(0.6, 1.0, 0.7)
@export var revive_energy: float = 2.5
@export var revive_radius: float = 38.0
@export var revive_width: float = 4.0

var _time: float = 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	global_position = player.global_position
	queue_redraw()


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)


func _draw() -> void:
	if player == null:
		return
	if outline_enabled:
		_draw_capsule_outline(_hdr(outline_color, outline_energy, outline_alpha))

	if player.health.is_downed:
		var pulse: float = 0.5 + 0.5 * sin(_time * TAU * downed_pulse_speed)
		var color: Color = _hdr(downed_color, downed_energy, lerpf(0.35, 0.9, pulse))
		draw_arc(Vector2.ZERO, downed_radius * lerpf(0.9, 1.1, pulse), 0.0, TAU, 40, color, 2.0, true)
		var reviver: ReviveHelper = _find_reviver()
		if reviver and reviver.progress > 0.0:
			var ring: Color = _hdr(revive_color, revive_energy, 1.0)
			draw_arc(Vector2.ZERO, revive_radius, -PI * 0.5, -PI * 0.5 + TAU * reviver.get_progress_ratio(), 48, ring, revive_width, true)


func _draw_capsule_outline(color: Color) -> void:
	var radius: float = outline_size.x * 0.5
	var straight: float = maxf(outline_size.y * 0.5 - radius, 0.0)
	draw_arc(Vector2(0.0, -straight), radius, PI, TAU, 16, color, outline_width, true)
	draw_arc(Vector2(0.0, straight), radius, 0.0, PI, 16, color, outline_width, true)
	if straight > 0.0:
		draw_line(Vector2(-radius, -straight), Vector2(-radius, straight), color, outline_width, true)
		draw_line(Vector2(radius, -straight), Vector2(radius, straight), color, outline_width, true)


## The partner's ReviveHelper if it is currently reviving this player.
func _find_reviver() -> ReviveHelper:
	var partner: Player = player.get_partner()
	if partner == null:
		return null
	var helper := partner.get_node_or_null("Revive") as ReviveHelper
	if helper and helper.get_target() == player:
		return helper
	return null
