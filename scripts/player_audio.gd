class_name PlayerAudio
extends Node
## A player's own sounds (positional, AudioDirector): a soft swish now and then
## while swimming, hurt, downed and revived.

@export var player: Player
@export var move_sound: String = "player_move"
@export var hurt_sound: String = "player_hurt"
@export var downed_sound: String = "player_downed"
@export var revive_sound: String = "player_revive"
## Swishes while faster than this share of max_speed, one every this many seconds.
@export_range(0.0, 1.0) var move_speed_ratio: float = 0.45
@export var stroke_interval_min: float = 0.45
@export var stroke_interval_max: float = 0.8

var _stroke_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# The Player's @onready health is not set yet (children are ready first).
	var health := player.get_node_or_null("Health") as PlayerHealth if player else null
	if health:
		health.hurt.connect(_play.bind(hurt_sound))
		health.downed.connect(func(_cause: PlayerHealth.Cause) -> void: _play(downed_sound))
		health.revived.connect(_play.bind(revive_sound))


func _process(delta: float) -> void:
	if player == null or player.health.is_downed:
		return
	if player.velocity.length() < player.max_speed * move_speed_ratio:
		_stroke_left = minf(_stroke_left, stroke_interval_min * 0.5)
		return
	_stroke_left -= delta
	if _stroke_left <= 0.0:
		_stroke_left = _rng.randf_range(stroke_interval_min, stroke_interval_max)
		_play(move_sound)


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and player:
		audio.play(sound_name, player.global_position)
