class_name CreatureStuckWatch
extends Node
## Watches one creature for getting stuck: in CHASE / INVESTIGATE / SEARCH,
## far from its target, it moves less than stuck_distance in check_time.
## Each stuck check emits stuck (with what the creature was doing, for the
## logs and the tests) and, when log_enabled, prints it. Safety net: stuck for
## repath_after windows in a row = a fresh path; for nudge_after windows = it is
## moved off the wall / onto its navigation mesh (Creature.nudge_unstuck).
## Standing at the end of a path that stops short of the target (the target
## is somewhere it cannot fit) is not counted.

signal stuck(info: Dictionary)

## Print every stuck check (debug; the tests switch it on).
static var log_enabled: bool = false

@export var creature: Creature
## Seconds per check window.
@export var check_time: float = 0.75
## Moving less than this in one window (while it should move) = stuck.
@export var stuck_distance: float = 10.0
## Not stuck when the target is this close (it has arrived, or is next to the
## player it chases).
@export var target_margin: float = 60.0
## Safety net (in check windows: 2 x 0.75 s = stuck for 1.5 s).
@export var recover_enabled: bool = true
@export var repath_after: int = 2
@export var nudge_after: int = 3
## Repaths / nudges done so far (debug, tests).
var repaths_done: int = 0
var nudges_done: int = 0

## Stuck windows in a row (0 = moving fine).
var stuck_windows: int = 0
var total_stuck_windows: int = 0
var _window_left: float = 0.0
var _window_start: Vector2
var _repaths_at_start: int = 0
var _state_changes_at_start: int = 0
var _lunges_at_start: int = 0


func _ready() -> void:
	_window_left = check_time
	if creature:
		_window_start = creature.global_position


func _physics_process(delta: float) -> void:
	if creature == null or creature.is_dying():
		return
	_window_left -= delta
	if _window_left > 0.0:
		return
	var moved: float = creature.global_position.distance_to(_window_start)
	if _should_move() and moved < stuck_distance:
		stuck_windows += 1
		total_stuck_windows += 1
		var info: Dictionary = _describe(moved)
		if log_enabled:
			print("STUCK %s" % info)
		stuck.emit(info)
		_recover()
	else:
		stuck_windows = 0
	_window_left = check_time
	_window_start = creature.global_position
	_repaths_at_start = creature.path_requests
	_state_changes_at_start = creature.state_changes
	_lunges_at_start = creature.lunges_started


func _recover() -> void:
	if not recover_enabled:
		return
	if stuck_windows >= nudge_after:
		nudges_done += 1
		creature.nudge_unstuck()
	elif stuck_windows >= repath_after:
		repaths_done += 1
		creature.force_repath()


## Only these states move towards a target; staggered moves are knockback.
func _should_move() -> bool:
	if creature.state == Creature.State.WANDER or creature.is_staggered():
		return false
	if creature.is_at_path_end():
		return false
	return creature.global_position.distance_to(creature.target) > creature.body_radius + target_margin


## Distance to the nearest lit coral and its safe radius (-1 = none lit).
func _nearest_lit_coral() -> String:
	var best: float = INF
	var radius: float = -1.0
	var lit: int = 0
	for node: Node in creature.get_tree().get_nodes_in_group("corals"):
		var coral := node as Coral
		if coral == null or not coral.is_lit():
			continue
		lit += 1
		var distance: float = coral.global_position.distance_to(creature.global_position)
		if distance < best:
			best = distance
			radius = coral.safe_radius
	return "none" if lit == 0 else "%d px (safe %d), %d lit" % [roundi(best), roundi(radius), lit]


func _describe(moved: float) -> Dictionary:
	return {
		"creature": creature.name,
		"state": creature.get_state_name(),
		"position": creature.global_position.round(),
		"velocity": creature.velocity.round(),
		"target": creature.target.round(),
		"next_point": creature.get_next_path_point().round(),
		"path_points": creature.get_path_size(),
		"moved": snappedf(moved, 0.1),
		"repaths": creature.path_requests - _repaths_at_start,
		"state_changes": creature.state_changes - _state_changes_at_start,
		"lunges": creature.lunges_started - _lunges_at_start,
		"blocked_time": snappedf(creature.get_blocked_time(), 0.01),
		"radius": creature.body_radius,
		"lit_coral": _nearest_lit_coral(),
		"windows_in_a_row": stuck_windows,
	}
