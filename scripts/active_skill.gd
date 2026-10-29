class_name ActiveSkill
extends Node2D
## Base of an active skill (Lure Pulse, Shield, Dash...): one per character
## (PlayerSkills adds it to the player's UnlitLayer, so it draws unlit in world
## coordinates and follows the player). Used with the player's skill button
## (Player.try_skill_pressed / is_skill_held). Its numbers come from the
## SkillDefinition's values at the owned rank (value(key)); the look and the
## sounds are this node's own exports. The HUD reads get_cooldown_ratio().
## When the cooldown ends it plays a ReadyCue (ring on the character + chime).
## Aiming (Player.get_aim_direction / get_stick_aim / uses_gamepad): the
## subclasses decide how (right stick, or hold + move keys on the keyboard).

signal used
## Emitted once when the cooldown has run out.
signal became_ready

var player: Player
var definition: SkillDefinition
var rank: int = 1
var cooldown_left: float = 0.0
var ready_cue: ReadyCue


func setup(target_player: Player, skill: SkillDefinition, skill_rank: int) -> void:
	player = target_player
	definition = skill
	rank = skill_rank


func _ready() -> void:
	ready_cue = ReadyCue.new()
	ready_cue.player = player
	if definition:
		ready_cue.color = definition.icon_color
	add_child(ready_cue)


func value(key: String, default_value: float = 0.0) -> float:
	return definition.get_value(key, rank, default_value) if definition else default_value


func get_cooldown() -> float:
	return value("cooldown")


func is_ready() -> bool:
	return cooldown_left <= 0.0


## 0 = ready, 1 = just used.
func get_cooldown_ratio() -> float:
	var cooldown: float = get_cooldown()
	return clampf(cooldown_left / cooldown, 0.0, 1.0) if cooldown > 0.0 else 0.0


## True while it is being used (held / in progress): the HUD lights it up.
func is_in_use() -> bool:
	return false


## True while the player's action button must not trigger the normal ability
## (e.g. no sword swings behind a raised shield).
func blocks_actions() -> bool:
	return false


func _process(delta: float) -> void:
	if player == null:
		return
	var was_cooling: bool = cooldown_left > 0.0
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if was_cooling and cooldown_left <= 0.0:
		_on_ready_again()
	global_position = player.global_position
	_update(delta)
	queue_redraw()


## Override: called every frame (input, effect, timers).
func _update(_delta: float) -> void:
	pass


func _on_ready_again() -> void:
	if ready_cue:
		ready_cue.play()
	became_ready.emit()


## Starts the cooldown and tells the HUD / sounds.
func _mark_used() -> void:
	cooldown_left = get_cooldown()
	used.emit()


func _play(sound_name: String, at: Vector2) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and sound_name != "":
		audio.play(sound_name, at)


static func _hdr(color: Color, energy: float, alpha: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, alpha)
