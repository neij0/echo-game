class_name LockdownRoom
extends Node2D
## The lockdown event of one level. When every player is inside the lockdown
## room (deeper than trigger_inset from its edges, so nobody stands in a
## doorway), each connected doorway is sealed with a LockdownBarrier (rumble,
## slam, camera shake) and after wake_delay a wave of creatures wakes on the
## room's Creature markers, hunting the nearest player. The doorways open again
## once every wave creature is dead (a chord, a warm light in each doorway).
## Happens once per attempt (a retry rebuilds the level). The creatures'
## navigation is rebaked when the doorways close and open (navigation_changed,
## LevelBuilder), behind the camera shake. Wave sizes come from the
## LevelDefinition per mode; the StageManager sets the mode ("mode_listeners").
## Built and set up by the LevelBuilder (all positions in its space).

signal locked
signal wave_spawned(creature: Creature)
signal cleared
## The doorways closed or opened: the LevelBuilder rebakes the navigation.
signal navigation_changed

enum Phase { WAITING, LOCKED, CLEARED }

## Players must be at least this far inside the room's edges to trigger it.
@export var trigger_inset: float = 260.0
## Seconds between the doorways closing and the wave waking.
@export var wake_delay: float = 0.8

@export_group("Feedback")
@export var close_shake_strength: float = 9.0
@export var close_shake_time: float = 0.6
@export var open_shake_strength: float = 4.0
@export var open_shake_time: float = 0.35
@export var rumble_stream: AudioStream
@export var rumble_volume_db: float = -2.0
@export var slam_stream: AudioStream
@export var slam_volume_db: float = 0.0
@export var clear_stream: AudioStream
@export var clear_volume_db: float = -3.0

## Set by the LevelBuilder before the node enters the tree.
var room_rect := Rect2()
var barrier_polygons: Array[PackedVector2Array] = []
var barrier_color: Color = Color(0.3, 0.3, 0.3)
var spawn_points: Array[Vector2] = []
var creature_scene: PackedScene
var wave_calm: int = 2
var wave_challenge: int = 3

## Off = never triggers (tests, or the collapse escape broke it open).
var enabled: bool = true
var phase: Phase = Phase.WAITING
var challenge_mode: bool = false
var _barriers: Array[LockdownBarrier] = []
var _wave: Array[Creature] = []
var _wake_left: float = -1.0
var _rumble: AudioStreamPlayer
var _slam: AudioStreamPlayer
var _clear: AudioStreamPlayer


func _ready() -> void:
	add_to_group("mode_listeners")
	add_to_group("lockdown_rooms")
	for polygon: PackedVector2Array in barrier_polygons:
		var barrier := LockdownBarrier.new()
		barrier.name = "Barrier"
		barrier.polygon = polygon
		barrier.color = barrier_color
		add_child(barrier)
		_barriers.append(barrier)
	_rumble = _make_player(rumble_stream, rumble_volume_db)
	_slam = _make_player(slam_stream, slam_volume_db)
	_clear = _make_player(clear_stream, clear_volume_db)


## Called (via the "mode_listeners" group) by StageManager.
func set_challenge_mode(enabled_value: bool) -> void:
	challenge_mode = enabled_value


func get_wave_size() -> int:
	return wave_challenge if challenge_mode else wave_calm


func is_locked() -> bool:
	return phase == Phase.LOCKED


## Doorway rocks that block the navigation right now (closed barriers).
func get_obstacles() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for barrier: LockdownBarrier in _barriers:
		if barrier.is_closed:
			result.append(barrier.polygon)
	return result


## True when the point (this node's space) is deep enough inside the room.
func contains(point: Vector2) -> bool:
	return room_rect.grow(-trigger_inset).has_point(point)


func _physics_process(delta: float) -> void:
	match phase:
		Phase.WAITING:
			if enabled and get_wave_size() > 0 and _everyone_inside():
				lock()
		Phase.LOCKED:
			if _wake_left >= 0.0:
				_wake_left -= delta
				if _wake_left < 0.0:
					_spawn_wave()
			elif _wave_dead():
				unlock()


func _everyone_inside() -> bool:
	var players: Array[Player] = Players.all(get_tree())
	if players.is_empty():
		return false
	for player: Player in players:
		if not contains(to_local(player.global_position)):
			return false
	return true


## Seals the doorways; the wave wakes after wake_delay.
func lock() -> void:
	if phase != Phase.WAITING:
		return
	phase = Phase.LOCKED
	for barrier: LockdownBarrier in _barriers:
		barrier.close()
	_play(_rumble)
	_play(_slam)
	_shake(close_shake_strength, close_shake_time)
	_wake_left = wake_delay
	get_tree().call_group("sonar_overlay", "rebuild_samples")
	navigation_changed.emit()
	locked.emit()


## Opens the doorways again (the wave is dead, or the collapse broke them).
func unlock() -> void:
	if phase != Phase.LOCKED:
		return
	phase = Phase.CLEARED
	_wake_left = -1.0
	for barrier: LockdownBarrier in _barriers:
		barrier.open()
	_play(_clear)
	_shake(open_shake_strength, open_shake_time)
	get_tree().call_group("sonar_overlay", "rebuild_samples")
	navigation_changed.emit()
	cleared.emit()


## The collapse escape: never trigger any more, and break open if locked.
func cancel() -> void:
	enabled = false
	if phase == Phase.LOCKED:
		unlock()


func _spawn_wave() -> void:
	if creature_scene == null or spawn_points.is_empty():
		unlock()
		return
	# Markers farthest from the players first, so nothing wakes on top of them.
	var points: Array[Vector2] = spawn_points.duplicate()
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _player_distance(a) > _player_distance(b))
	for i: int in get_wave_size():
		var creature := creature_scene.instantiate() as Creature
		if creature == null:
			continue
		var at: Vector2 = points[i % points.size()]
		# Several on one marker: spread them a little.
		creature.position = at + Vector2.from_angle(TAU * i / maxf(get_wave_size(), 1.0)) * 40.0 * floorf(float(i) / points.size())
		get_parent().add_child(creature)
		creature.set_challenge_mode(challenge_mode)
		var prey: Player = Players.nearest(get_tree(), creature.global_position)
		if prey:
			creature.hunt(prey)
		_wave.append(creature)
		wave_spawned.emit(creature)


func _player_distance(point: Vector2) -> float:
	var best: float = INF
	for player: Player in Players.all(get_tree()):
		best = minf(best, to_global(point).distance_to(player.global_position))
	return best


func _wave_dead() -> bool:
	for creature: Creature in _wave:
		if is_instance_valid(creature) and not creature.is_dying():
			return false
	return true


func get_wave() -> Array[Creature]:
	return _wave


func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _play(player: AudioStreamPlayer) -> void:
	if player.stream:
		player.play()


func _shake(strength: float, duration: float) -> void:
	get_tree().call_group("shared_camera", "shake_with", strength, duration)
