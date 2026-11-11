class_name PlayerOverlay
extends Node3D
## Unlit markers on the floor for one player, so they stay readable in the
## dark and behind rock: a pulsing ring while downed, and the revive progress
## ring while the partner is reviving them (dimmer while the revive is
## interrupted: paused or decaying). Drawn over rock.

@export var player: Player

@export_group("Downed")
@export var downed_color: Color = Color(1.0, 0.3, 0.25)
@export var downed_energy: float = 2.0
@export var downed_radius: float = 0.6
@export var downed_width: float = 0.04
## Pulses per second of the downed ring.
@export var downed_pulse_speed: float = 1.2

@export_group("Revive")
@export var revive_color: Color = Color(0.6, 1.0, 0.7)
@export var revive_energy: float = 1.4
@export var revive_radius: float = 0.76
@export var revive_width: float = 0.08
## Opacity of the ring while the revive is interrupted (paused or decaying).
@export_range(0.0, 1.0) var revive_interrupted_alpha: float = 0.45

var _time: float = 0.0
var _downed_ring: GlowLines
var _revive_ring: GlowLines


func _ready() -> void:
	_downed_ring = _add_lines("DownedRing", downed_energy)
	_revive_ring = _add_lines("ReviveRing", revive_energy)


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	_downed_ring.clear()
	_revive_ring.clear()
	if player.health.is_downed:
		var center: Vector3 = player.get_global_transform_interpolated().origin
		var pulse: float = 0.5 + 0.5 * sin(_time * TAU * downed_pulse_speed)
		_downed_ring.add_ring(center, downed_radius * lerpf(0.9, 1.1, pulse), downed_width, Color(downed_color, lerpf(0.35, 0.9, pulse)))
		var reviver: ReviveHelper = _find_reviver()
		if reviver and reviver.progress > 0.0:
			var alpha: float = revive_interrupted_alpha if reviver.is_interrupted() else 1.0
			# From the top of the ring on the screen (away from the camera), clockwise.
			var start: float = _screen_up_angle()
			_revive_ring.add_arc(center, revive_radius, start, start + TAU * reviver.get_progress_ratio(),
				revive_width, Color(revive_color, alpha))
	_downed_ring.commit()
	_revive_ring.commit()


## True while the revive ring shows (tests).
func is_showing_revive() -> bool:
	var reviver: ReviveHelper = _find_reviver()
	return player != null and player.health.is_downed and reviver != null and reviver.progress > 0.0


## The floor angle that points up on the screen (away from the camera).
func _screen_up_angle() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return -PI * 0.5
	var away: Vector3 = -camera.global_basis.z
	return atan2(away.z, away.x)


## The partner's ReviveHelper (its progress on this player is kept while
## interrupted, so the ring shows even when the partner stepped away).
func _find_reviver() -> ReviveHelper:
	var partner: Player = player.get_partner()
	if partner == null:
		return null
	return partner.get_node_or_null("Revive") as ReviveHelper


func _add_lines(node_name: String, line_energy: float) -> GlowLines:
	var lines := GlowLines.new()
	lines.name = node_name
	lines.energy = line_energy
	add_child(lines)
	return lines
