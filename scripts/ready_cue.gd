class_name ReadyCue
extends Node2D
## A short "ready again" cue on the character in the world, so players notice
## a recharged ability without looking at the HUD: a soft ring grows out of
## the character and fades, with a soft chime. Played by ActiveSkill and the
## Echo's PulseAbility when their cooldown ends. Must live on a CanvasLayer
## with follow_viewport_enabled (drawn unlit); follows its player.

@export var player: Player
@export var color: Color = Color(0.45, 0.95, 1.0)
## HDR brightness multiplier (above 1.0 = blooms).
@export var energy: float = 2.2
@export var start_radius: float = 16.0
@export var end_radius: float = 44.0
@export var width: float = 2.5
## Seconds the ring grows and fades.
@export var time: float = 0.45
## AudioDirector sound name (empty = silent, e.g. the Echo's pulse) and its volume offset.
@export var sound: String = "skill_ready"
@export var volume_offset_db: float = 0.0

## Times played (tests).
var plays: int = 0
var _age: float = -1.0


func play() -> void:
	plays += 1
	_age = 0.0
	if player:
		global_position = player.global_position
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and sound != "":
		audio.play(sound, global_position, volume_offset_db)
	queue_redraw()


func is_playing() -> bool:
	return _age >= 0.0 and _age < time


func _process(delta: float) -> void:
	if _age < 0.0:
		return
	if player:
		global_position = player.global_position
	_age += delta
	if _age >= time:
		_age = -1.0
	queue_redraw()


func _draw() -> void:
	if not is_playing():
		return
	var t: float = _age / time
	var glow := Color(color.r * energy, color.g * energy, color.b * energy, (1.0 - t) * 0.9)
	draw_arc(Vector2.ZERO, lerpf(start_radius, end_radius, 1.0 - (1.0 - t) * (1.0 - t)), 0.0, TAU, 40, glow, width * (1.0 - t * 0.5), true)
