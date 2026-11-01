class_name AnglerVoice
extends Node
## The Angler's sounds, played through the AudioDirector at its position when
## its AnglerVisual signals a moment: the roar (phase change, reveal), the
## charge rush, the bite snap, the death moan. All procedural
## (tools/generate_sounds.py, "boss_angler_*").

@export var visual: AnglerVisual
@export var roar_sound: String = "boss_angler_roar"
@export var charge_sound: String = "boss_angler_charge"
@export var bite_sound: String = "boss_angler_bite"
@export var death_sound: String = "boss_angler_death"


func _ready() -> void:
	if visual == null:
		return
	visual.roared.connect(_play.bind(roar_sound))
	visual.revealed.connect(_play.bind(roar_sound))
	visual.charge_started.connect(_play.bind(charge_sound))
	visual.bitten.connect(_play.bind(bite_sound))
	visual.died.connect(_play.bind(death_sound))


func _play(sound_name: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio and visual:
		audio.play(sound_name, visual.global_position)
