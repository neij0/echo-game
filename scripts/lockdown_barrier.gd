class_name LockdownBarrier
extends RockGate
## The rock that seals one doorway of the lockdown room. It starts open (sunk
## into the floor: no collision, hidden). close() makes it solid at once and
## the rock rises into view; open() lets it sink again with a warm light and
## a glowing seam along the doorway (the "you made it" light cue). The
## LockdownRoom creates one per connected doorway (the shape of a seal).

@export var close_time: float = 0.35
@export var open_time: float = 1.0

@export_group("Open Light")
@export var light_color: Color = Color(1.0, 0.85, 0.5)
@export var light_energy: float = 4.0
## World units.
@export var light_radius: float = 6.4
@export var light_height: float = 1.0
## Glowing seam along the doorway while it opens.
@export var seam_energy: float = 3.0
@export var seam_width: float = 0.08

var is_closed: bool = false
var _open_glow_left: float = 0.0
var _light: OmniLight3D
var _seam: GlowLines


func _ready() -> void:
	rise_time = close_time
	sink_time = open_time
	super()
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.light_energy = 0.0
	_light.omni_range = light_radius
	_light.shadow_enabled = false
	_light.position = center + Vector3.UP * light_height
	_light.visible = false
	add_child(_light)
	_seam = GlowLines.new()
	_seam.energy = seam_energy
	add_child(_seam)


func close() -> void:
	if is_closed:
		return
	is_closed = true
	set_solid(true)


func open() -> void:
	if not is_closed:
		return
	is_closed = false
	set_solid(false)
	_open_glow_left = open_time


func _process(delta: float) -> void:
	animate(delta)
	var showing: bool = _open_glow_left > 0.0
	_open_glow_left = maxf(_open_glow_left - delta, 0.0)
	var glow: float = _open_glow_left / maxf(open_time, 0.01)
	_light.visible = glow > 0.0
	_light.light_energy = light_energy * glow
	if showing or glow > 0.0:
		_seam.clear()
		if glow > 0.0:
			_seam.add_polyline(PackedVector3Array([center - along * half_length, center + along * half_length]),
				seam_width, Color(light_color, glow), 0.02)
		_seam.commit()
