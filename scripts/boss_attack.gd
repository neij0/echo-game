class_name BossAttack
extends Resource
## One attack of a boss (Boss): a telegraph (the warning the players read),
## the attack itself, and a recovery (the boss stands open: the vulnerable
## window). What the attack does is the boss script's own (_on_attack_*); this
## holds its numbers. Values per mode: Calm gives longer warnings and
## recoveries and hits softer.

## Used by the boss script to tell its attacks apart (e.g. "charge", "bite").
@export var id: StringName = &""
## The first phase (1-based) that uses it.
@export var min_phase: int = 1
## Chance against the other attacks that fit (in range, off cooldown).
@export var weight: float = 1.0
## Picked only when the target is this far (Boss._attack_distance).
@export var min_range: float = 0.0
@export var max_range: float = 600.0

@export_group("Timing")
## Seconds of warning (telegraph) before it strikes.
@export var calm_telegraph: float = 1.1
@export var challenge_telegraph: float = 0.9
## Seconds the attack lasts at most (the boss script may end it earlier).
@export var active_time: float = 0.5
## Seconds it stands open afterwards (the vulnerable window).
@export var calm_recovery: float = 1.5
@export var challenge_recovery: float = 1.1
## Seconds before it can use this attack again (counted after the recovery).
@export var cooldown: float = 3.0

@export_group("Hit")
## Health segments a player loses when it lands (once per attack and player).
@export var calm_damage: float = 1.0
@export var challenge_damage: float = 1.5
## A short push away from the boss (the player is invulnerable after it).
@export var knockback_speed: float = 360.0


func get_telegraph(challenge: bool) -> float:
	return challenge_telegraph if challenge else calm_telegraph


func get_recovery(challenge: bool) -> float:
	return challenge_recovery if challenge else calm_recovery


func get_damage(challenge: bool) -> float:
	return challenge_damage if challenge else calm_damage
